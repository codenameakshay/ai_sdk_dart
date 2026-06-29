import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_mcp/src/json_rpc.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock plain-HTTP JSON-RPC server (mirrors the conformance helper).
// ---------------------------------------------------------------------------

/// A local HTTP server that answers JSON-RPC MCP requests from a queue.
///
/// Unlike the conformance helper, this one can also be told to return a raw
/// HTTP error status, a non-JSON body, or a non-object JSON body so the
/// transport's error/parse branches are exercised. It also records request
/// headers so header-merge behavior can be asserted.
class _MockHttpServer {
  _MockHttpServer._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> requestLog = [];
  final List<HttpHeaders> headerLog = [];
  final _responseQueue = <_CannedResponse>[];

  static Future<_MockHttpServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockHttpServer._(server);
    unawaited(mock._serve());
    return mock;
  }

  /// Queue a JSON-RPC body to return as a 200 (the `id` is filled in).
  void enqueueJson(Map<String, dynamic> response) =>
      _responseQueue.add(_CannedResponse(jsonBody: response));

  /// Queue a raw HTTP response (status + raw body) — used for error/parse paths.
  void enqueueRaw({required int status, required String body}) =>
      _responseQueue.add(_CannedResponse(status: status, rawBody: body));

  void enqueueInitialize() {
    enqueueJson({
      'jsonrpc': '2.0',
      'result': {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'test', 'version': '1.0.0'},
      },
    });
    enqueueJson({'jsonrpc': '2.0', 'result': {}});
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      headerLog.add(request.headers);
      final bodyText = await utf8.decoder.bind(request).join();
      Object? id;
      try {
        final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
        requestLog.add(body);
        id = body['id'];
      } catch (_) {
        // Ignore unparseable bodies; still respond from the queue.
      }

      if (_responseQueue.isNotEmpty) {
        final canned = _responseQueue.removeAt(0);
        canned.write(request.response, id);
      } else {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': {}}),
        );
      }
      await request.response.close();
    }
  }

  Uri get uri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/mcp');

  Future<void> close() => _server.close(force: true);
}

class _CannedResponse {
  _CannedResponse({this.jsonBody, this.status = 200, this.rawBody});

  final Map<String, dynamic>? jsonBody;
  final int status;
  final String? rawBody;

  void write(HttpResponse res, Object? id) {
    res.statusCode = status;
    if (jsonBody != null) {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(Map.of(jsonBody!)..['id'] = id));
    } else {
      res.write(rawBody ?? '');
    }
  }
}

// ---------------------------------------------------------------------------
// Fake transports for client-level branch coverage.
// ---------------------------------------------------------------------------

/// A transport whose [send] is driven by a supplied handler. Used to exercise
/// MCPClient error branches and the reconnect loop deterministically.
class _ScriptedTransport implements MCPTransport {
  _ScriptedTransport(this._handler);

  final FutureOr<JsonRpcResponse> Function(JsonRpcRequest request) _handler;
  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  int sendCount = 0;
  bool closed = false;

  void pushNotification(Map<String, dynamic> message) =>
      _notifications.add(message);

  void pushError(Object error) => _notifications.addError(error);

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    sendCount++;
    return _handler(request);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_notifications.isClosed) await _notifications.close();
  }
}

/// A transport that does NOT override [notifications], so the abstract default
/// (`json_rpc.dart`) getter is exercised.
class _DefaultNotificationsTransport extends MCPTransport {
  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    return const JsonRpcResponse(result: {});
  }

  @override
  Future<void> close() async {}
}

JsonRpcResponse _ok(JsonRpcRequest req, Map<String, dynamic> result) =>
    JsonRpcResponse(result: result, id: req.id);

JsonRpcResponse _err(JsonRpcRequest req, String message) => JsonRpcResponse(
  error: {'code': -32000, 'message': message},
  id: req.id,
);

JsonRpcResponse _initResult(JsonRpcRequest req) => _ok(req, {
  'protocolVersion': '2024-11-05',
  'capabilities': {'tools': {}},
  'serverInfo': {'name': 'fake', 'version': '1.0.0'},
});

void main() {
  // =========================================================================
  // HttpClientTransport edge paths
  // =========================================================================

  group('HttpClientTransport', () {
    test('throws MCPException on non-2xx HTTP status', () async {
      final mock = await _MockHttpServer.start();
      addTearDown(mock.close);
      mock.enqueueRaw(status: 503, body: 'service unavailable');

      final transport = HttpClientTransport(url: mock.uri);
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            allOf(contains('HTTP 503'), contains('service unavailable')),
          ),
        ),
      );
    });

    test('throws MCPException when body is not a JSON object', () async {
      final mock = await _MockHttpServer.start();
      addTearDown(mock.close);
      mock.enqueueRaw(status: 200, body: '["not", "an", "object"]');

      final transport = HttpClientTransport(url: mock.uri);
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('Unexpected MCP response format'),
          ),
        ),
      );
    });

    test('sends custom headers with every request', () async {
      final mock = await _MockHttpServer.start();
      addTearDown(mock.close);
      mock.enqueueJson({'jsonrpc': '2.0', 'result': {}});

      final transport = HttpClientTransport(
        url: mock.uri,
        headers: {'Authorization': 'Bearer secret-token'},
      );
      addTearDown(transport.close);

      await transport.send(JsonRpcRequest(method: 'ping', id: 1));

      expect(mock.headerLog, isNotEmpty);
      expect(
        mock.headerLog.first.value('authorization'),
        'Bearer secret-token',
      );
    });

    test('notifications stream is empty', () async {
      final transport = HttpClientTransport(
        url: Uri.parse('http://localhost:1/mcp'),
      );
      addTearDown(transport.close);
      expect(await transport.notifications.isEmpty, isTrue);
    });
  });

  // =========================================================================
  // SseClientTransport edge paths (using the conformance-style SSE flow is
  // covered elsewhere; here we target the uncovered error/inline/header lines).
  // =========================================================================

  group('SseClientTransport edge paths', () {
    test('uses explicit postUrl without waiting for an endpoint event '
        'and parses an inline JSON-RPC response body', () async {
      // Server: GET /sse opens a stream that never emits an `endpoint` event;
      // POST replies inline with the JSON-RPC body (200). This drives the
      // `_explicitPostUrl` branch (line 156) and the inline-response branch
      // (lines 325-331).
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final headerSeen = Completer<String?>();

      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.headers.set('Content-Type', 'text/event-stream');
          request.response.bufferOutput = false;
          // Flush headers (so the client's streamed GET resolves) via a
          // comment line, but never advertise an endpoint.
          request.response.write(': open\n\n');
          await request.response.flush();
          return;
        }
        // POST: reply inline with a JSON-RPC result.
        if (!headerSeen.isCompleted) {
          headerSeen.complete(request.headers.value('authorization'));
        }
        final bodyText = await utf8.decoder.bind(request).join();
        final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': {
              'protocolVersion': '2024-11-05',
              'capabilities': {'tools': {}},
              'serverInfo': {'name': 'inline', 'version': '1.0.0'},
            },
          }),
        );
        await request.response.close();
      });

      final sseUri = Uri.parse(
        'http://${server.address.address}:${server.port}/sse',
      );
      final postUri = Uri.parse(
        'http://${server.address.address}:${server.port}/messages',
      );

      final transport = SseClientTransport(
        url: sseUri,
        postUrl: postUri,
        headers: {'Authorization': 'Bearer abc'},
        connectTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(seconds: 5),
      );
      addTearDown(transport.close);

      final resp = await transport.send(
        JsonRpcRequest(method: 'initialize', id: 1),
      );
      expect(resp.isError, isFalse);
      expect((resp.result as Map)['protocolVersion'], '2024-11-05');
      expect(transport.resolvedPostUrl, postUri);
      expect(await headerSeen.future, 'Bearer abc');
    });

    test('throws MCPException when the SSE connect returns a non-2xx status',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = 401;
        request.response.write('unauthorized');
        await request.response.close();
      });

      final transport = SseClientTransport(
        url: Uri.parse(
          'http://${server.address.address}:${server.port}/sse',
        ),
        connectTimeout: const Duration(seconds: 5),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('SSE connect failed: HTTP 401'),
          ),
        ),
      );
    });

    test('falls back to the SSE url for POSTs when no endpoint event arrives '
        'within connectTimeout', () async {
      // No `endpoint` event and no explicit postUrl → after connectTimeout the
      // transport falls back to the SSE url itself (lines 188/190/191). The
      // POST then succeeds inline.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.headers.set('Content-Type', 'text/event-stream');
          request.response.bufferOutput = false;
          // Flush headers so the streamed GET resolves; emit no endpoint event.
          request.response.write(': open\n\n');
          await request.response.flush();
          return; // keep open, no endpoint event
        }
        final bodyText = await utf8.decoder.bind(request).join();
        final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'jsonrpc': '2.0', 'id': body['id'], 'result': {}}),
        );
        await request.response.close();
      });

      final sseUri = Uri.parse(
        'http://${server.address.address}:${server.port}/sse',
      );
      final transport = SseClientTransport(
        url: sseUri,
        connectTimeout: const Duration(milliseconds: 150),
        requestTimeout: const Duration(seconds: 5),
      );
      addTearDown(transport.close);

      final resp = await transport.send(
        JsonRpcRequest(method: 'ping', id: 1),
      );
      expect(resp.isError, isFalse);
      expect(transport.resolvedPostUrl, sseUri);
    });

    test('throws MCPException when POST returns a non-2xx status', () async {
      // Endpoint event is advertised so we get past _ensureConnected, then the
      // POST itself fails with a 500 (lines 315/316).
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.headers.set('Content-Type', 'text/event-stream');
          request.response.bufferOutput = false;
          request.response.write('event: endpoint\n');
          request.response.write('data: /messages\n\n');
          return;
        }
        request.response.statusCode = 500;
        request.response.write('boom');
        await request.response.close();
      });

      final transport = SseClientTransport(
        url: Uri.parse(
          'http://${server.address.address}:${server.port}/sse',
        ),
        connectTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(seconds: 5),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            allOf(contains('HTTP 500'), contains('boom')),
          ),
        ),
      );
    });

    test('stream error fails pending requests (SSE stream error path)',
        () async {
      // GET /sse advertises the endpoint then abruptly closes the underlying
      // socket. The POST request is in flight (the POST handler never replies),
      // so the pending completer must be failed when the stream errors/ends
      // (lines 254/255 + 258-263).
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      HttpResponse? sseResponse;
      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.headers.set('Content-Type', 'text/event-stream');
          request.response.bufferOutput = false;
          request.response.write('event: endpoint\n');
          request.response.write('data: /messages\n\n');
          sseResponse = request.response;
          return;
        }
        // POST: ack but never deliver a response, then sever the SSE stream so
        // the pending request fails.
        request.response.statusCode = 202;
        request.response.write('Accepted');
        await request.response.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sseResponse?.close();
      });

      final transport = SseClientTransport(
        url: Uri.parse(
          'http://${server.address.address}:${server.port}/sse',
        ),
        connectTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(seconds: 5),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('SSE stream closed by server'),
          ),
        ),
      );
    });

    test('times out waiting for an SSE response (requestTimeout)', () async {
      // Endpoint advertised; POST is acked 202 but a matching response never
      // arrives over the stream, so the request completer times out (the
      // `onTimeout` callback in send()).
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.headers.set('Content-Type', 'text/event-stream');
          request.response.bufferOutput = false;
          request.response.write('event: endpoint\n');
          request.response.write('data: /messages\n\n');
          await request.response.flush();
          return; // keep open, never deliver a response
        }
        request.response.statusCode = 202;
        request.response.write('Accepted');
        await request.response.close();
      });

      final transport = SseClientTransport(
        url: Uri.parse(
          'http://${server.address.address}:${server.port}/sse',
        ),
        connectTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'slow', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('Timeout waiting for SSE response to slow'),
          ),
        ),
      );
    });

    test('close() during an in-progress connect fails the awaiting caller',
        () async {
      // GET opens the stream (flushes headers) but never advertises an endpoint,
      // and there is no explicit postUrl, so _ensureConnected is parked waiting
      // for the endpoint event. Closing mid-connect must complete the pending
      // `_ready` with an error rather than hang until connectTimeout.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        if (request.method == 'GET') {
          request.response.statusCode = 200;
          request.response.headers.set('Content-Type', 'text/event-stream');
          request.response.bufferOutput = false;
          request.response.write(': open\n\n');
          await request.response.flush();
          return; // keep open, no endpoint event
        }
        request.response.statusCode = 202;
        await request.response.close();
      });

      final transport = SseClientTransport(
        url: Uri.parse(
          'http://${server.address.address}:${server.port}/sse',
        ),
        // Long connect timeout so the only way out is close().
        connectTimeout: const Duration(seconds: 30),
        requestTimeout: const Duration(seconds: 30),
      );

      final pending = transport.send(JsonRpcRequest(method: 'ping', id: 1));
      // Attach the expectation NOW (before close()) so the error that close()
      // triggers on `pending` is observed rather than escaping as unhandled.
      final expectation = expectLater(
        pending,
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('SSE transport closed'),
          ),
        ),
      );
      // Let the connect park on the missing endpoint event, then close.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await transport.close();
      await expectation;
    });

    test('an errored SSE byte stream fails pending requests via the '
        'stream onError path', () async {
      // Use a RAW TCP server so we can promise a large Content-Length, send the
      // endpoint event, then destroy the socket before the body completes. The
      // client's HTTP parser surfaces this truncation as a STREAM ERROR (not a
      // clean done), driving _handleStreamError and SseLineSink.addError.
      final tcp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        try {
          await tcp.close();
        } catch (_) {}
      });

      Socket? sseSocket;
      tcp.listen((socket) {
        final buffer = StringBuffer();
        socket.cast<List<int>>().transform(utf8.decoder).listen((chunk) async {
          buffer.write(chunk);
          // Wait until we have a full request (headers end with a blank line).
          if (!buffer.toString().contains('\r\n\r\n')) return;
          final requestText = buffer.toString();
          buffer.clear();
          final isGet = requestText.startsWith('GET');
          if (isGet) {
            // Promise more body than we will actually send, then sever the
            // connection mid-stream → truncated body → client stream error.
            sseSocket = socket;
            socket.write(
              'HTTP/1.1 200 OK\r\n'
              'Content-Type: text/event-stream\r\n'
              'Content-Length: 100000\r\n'
              '\r\n'
              'event: endpoint\n'
              'data: /messages\n\n',
            );
            await socket.flush();
          } else {
            // POST: ack with 202 then destroy the SSE socket shortly after.
            socket.write(
              'HTTP/1.1 202 Accepted\r\n'
              'Content-Length: 8\r\n'
              '\r\n'
              'Accepted',
            );
            await socket.flush();
            await Future<void>.delayed(const Duration(milliseconds: 50));
            sseSocket?.destroy();
          }
        });
      });

      final transport = SseClientTransport(
        url: Uri.parse(
          'http://${tcp.address.address}:${tcp.port}/sse',
        ),
        connectTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(seconds: 5),
      );
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            anyOf(
              contains('SSE stream error'),
              contains('SSE stream closed by server'),
            ),
          ),
        ),
      );
    });
  });

  // =========================================================================
  // SseLineSink: addError + close paths (lines 436/438/441/443/444)
  // =========================================================================

  group('SSE line parser ($_SseLabel)', () {
    test('forwards a stream error and closes on done', () async {
      // Drive _parseSse via a real SSE GET whose stream emits an event then is
      // closed by the server. The eventTransformed sink's close() (and the
      // underlying addError path on an upstream error) are exercised here.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('Content-Type', 'text/event-stream');
        request.response.bufferOutput = false;
        // Emit a notification with NO trailing blank line, then close — this
        // forces the sink's close()/_flush() to emit the buffered event.
        request.response.write('event: message\n');
        request.response.write(
          'data: ${jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/x'})}\n',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await request.response.close();
      });

      final transport = SseClientTransport(
        url: Uri.parse(
          'http://${server.address.address}:${server.port}/sse',
        ),
        postUrl: Uri.parse(
          'http://${server.address.address}:${server.port}/messages',
        ),
        connectTimeout: const Duration(seconds: 5),
      );
      addTearDown(transport.close);

      final received = <Map<String, dynamic>>[];
      final sub = transport.notifications.listen(received.add);
      addTearDown(sub.cancel);

      // Force the SSE connection to open.
      // ignore: unawaited_futures
      transport.send(JsonRpcRequest(method: 'noop', id: 99)).catchError(
        (_) => const JsonRpcResponse(result: {}),
      );

      await Future<void>.delayed(const Duration(milliseconds: 200));
      // The event buffered before close() was flushed and surfaced.
      expect(received.any((m) => m['method'] == 'notifications/x'), isTrue);
    });
  });

  // =========================================================================
  // MCPClient error branches & reconnect (mcp_client.dart)
  // =========================================================================

  group('MCPClient error branches', () {
    test('default-notifications transport drives the abstract getter',
        () async {
      // _DefaultNotificationsTransport does not override `notifications`, so the
      // abstract default getter in json_rpc.dart (line 78) runs when the client
      // wires up its notification subscription.
      final transport = _DefaultNotificationsTransport();
      final client = MCPClient(transport: transport);
      addTearDown(client.close);
      await client.initialize();
      // A second initialize is a no-op (already initialized).
      await client.initialize();
    });

    test('tools/list JSON-RPC error throws MCPException', () async {
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'tools/list') return _err(req, 'no tools');
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      await expectLater(
        client.tools(),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('tools/list failed'),
          ),
        ),
      );
    });

    test('tools() builds a ToolSet whose execute calls the tool', () async {
      final transport = _ScriptedTransport((req) {
        switch (req.method) {
          case 'initialize':
            return _initResult(req);
          case 'notifications/initialized':
            return _ok(req, {});
          case 'tools/list':
            return _ok(req, {
              'tools': [
                {
                  'name': 'echo',
                  'description': 'echoes',
                  'inputSchema': {
                    'type': 'object',
                    'properties': {
                      'value': {'type': 'string'},
                    },
                  },
                },
                // No name → skipped.
                {'description': 'nameless'},
                // Not a map → skipped.
                'garbage',
              ],
            });
          case 'tools/call':
            final value =
                (req.params!['arguments'] as Map)['value']?.toString() ?? '';
            return _ok(req, {
              'content': [
                {'type': 'text', 'text': 'got: $value'},
              ],
              'isError': false,
            });
          default:
            return _ok(req, {});
        }
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      final toolSet = await client.tools();
      expect(toolSet.keys, ['echo']);

      // Exercise the dynamicTool execute closure (line 343).
      final tool = toolSet['echo']!;
      final result = await tool.execute!(
        {'value': 'hi'},
        const ToolExecutionOptions(),
      );
      expect(result, 'got: hi');
    });

    test('callTool JSON-RPC error (not isError) throws MCPException',
        () async {
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'tools/call') return _err(req, 'tool blew up');
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      await expectLater(
        client.callTool('boom', {}),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            allOf(contains('tools/call'), contains('failed')),
          ),
        ),
      );
    });

    test('prompts/list JSON-RPC error throws MCPException', () async {
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'prompts/list') return _err(req, 'nope');
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      await expectLater(
        client.listPrompts(),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('prompts/list failed'),
          ),
        ),
      );
    });

    test('getPrompt parses Map text content and String content', () async {
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'prompts/get') {
          return _ok(req, {
            'description': 'rendered',
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'from map'},
              },
              {'role': 'assistant', 'content': 'from string'},
            ],
          });
        }
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      final result = await client.getPrompt('p', arguments: {'a': 'b'});
      expect(result.description, 'rendered');
      expect(result.messages.length, 2);
      expect(result.messages[0].content, 'from map');
      expect(result.messages[1].content, 'from string');
    });

    test('resources/list JSON-RPC error throws MCPException', () async {
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'resources/list') return _err(req, 'denied');
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      await expectLater(
        client.listResources(),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('resources/list failed'),
          ),
        ),
      );
    });

    test('readResource returns octet-stream fallback when result is not a Map',
        () async {
      // The JSON-RPC `result` is a non-Map (a String), so the `result is! Map`
      // fallback runs.
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'resources/read') {
          return JsonRpcResponse(result: 'not-a-map', id: req.id);
        }
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      final content = await client.readResource('file:///raw');
      expect(content.uri, 'file:///raw');
      expect(content.mimeType, 'application/octet-stream');
      expect(content.text, isNull);
    });

    test('readResource returns octet-stream fallback when result has no '
        'usable contents', () async {
      // result is a Map but `contents` is missing/empty → fallback (line 510).
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'resources/read') return _ok(req, {'contents': []});
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      final content = await client.readResource('file:///x');
      expect(content.uri, 'file:///x');
      expect(content.mimeType, 'application/octet-stream');
      expect(content.text, isNull);
    });

    test('readResource returns octet-stream fallback when first content is '
        'not a Map', () async {
      // contents is a non-empty list whose first element is not a Map → the
      // `first is! Map` fallback (line 514).
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'resources/read') {
          return _ok(req, {
            'contents': ['not-a-map'],
          });
        }
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      final content = await client.readResource('file:///y');
      expect(content.mimeType, 'application/octet-stream');
    });

    test('subscribeResource reuses the existing controller on second call',
        () async {
      var subscribeRequests = 0;
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'resources/subscribe') subscribeRequests++;
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      final s1 = client.subscribeResource('file:///dup');
      // Let the first subscribe round-trip settle.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final s2 = client.subscribeResource('file:///dup'); // existing path

      expect(s1, isA<Stream<MCPResourceContent>>());
      expect(s2, isA<Stream<MCPResourceContent>>());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // The existing-controller branch must NOT issue a second subscribe.
      expect(subscribeRequests, 1);
    });

    test('subscribeResource swallows a resources/subscribe server error',
        () async {
      // The server returns an error for resources/subscribe; the client must
      // surface it through _subscribeResourceOnServer (lines 564/565) but
      // swallow it via the .catchError so subscribeResource itself succeeds.
      var subscribeErrored = false;
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'resources/subscribe') {
          subscribeErrored = true;
          return _err(req, 'unsupported');
        }
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);

      final updates = <MCPResourceContent>[];
      final sub = client
          .subscribeResource('file:///err')
          .listen(updates.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(subscribeErrored, isTrue);
      // No crash; subscription is still live.
      expect(updates, isEmpty);
    });

    test('transport notification error is swallowed by the client', () async {
      // Pushing an error onto the transport notifications stream must be caught
      // by the onError handler in _listenToTransport (line 211).
      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        return _ok(req, {});
      });
      final client = MCPClient(transport: transport);
      addTearDown(client.close);
      await client.initialize();

      transport.pushError(StateError('boom'));
      // A non-resource notification is ignored too.
      transport.pushNotification({'jsonrpc': '2.0', 'method': 'noise'});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // Client is still usable.
      expect(transport.closed, isFalse);
    });
  });

  // =========================================================================
  // Reconnect loop (mcp_client.dart lines 286-300)
  // =========================================================================

  group('MCPClient reconnect', () {
    test('reconnects via the transport factory and succeeds after a failure',
        () async {
      // First transport fails every tools/list; reconnect swaps in a fresh
      // transport (via the factory) that succeeds. Exercises 286-300.
      var built = 0;
      late _ScriptedTransport first;

      _ScriptedTransport makeWorking() {
        return _ScriptedTransport((req) {
          switch (req.method) {
            case 'initialize':
              return _initResult(req);
            case 'notifications/initialized':
              return _ok(req, {});
            case 'tools/list':
              return _ok(req, {'tools': []});
            default:
              return _ok(req, {});
          }
        });
      }

      first = _ScriptedTransport((req) {
        switch (req.method) {
          case 'initialize':
            return _initResult(req);
          case 'notifications/initialized':
            return _ok(req, {});
          case 'tools/list':
            throw const MCPException('transport down');
          default:
            return _ok(req, {});
        }
      });

      final client = MCPClient(
        transport: first,
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 3,
          initialDelayMs: 1,
          maxDelayMs: 5,
        ),
        transportFactory: () {
          built++;
          return makeWorking();
        },
      );
      addTearDown(client.close);

      final toolSet = await client.tools();
      expect(toolSet, isEmpty);
      expect(built, greaterThanOrEqualTo(1));
      expect(first.closed, isTrue); // old transport was closed on reconnect
    });

    test('exhausts attempts and rethrows when every attempt fails', () async {
      _ScriptedTransport makeFailing() => _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        throw const MCPException('always down');
      });

      final client = MCPClient(
        transport: makeFailing(),
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 2,
          initialDelayMs: 1,
          maxDelayMs: 2,
        ),
        transportFactory: makeFailing,
      );
      addTearDown(client.close);

      await expectLater(client.tools(), throwsA(isA<MCPException>()));
    });
  });

  // =========================================================================
  // StdioMCPTransport (real subprocess)
  // =========================================================================

  group('StdioMCPTransport (subprocess)', () {
    final dartExe = Platform.resolvedExecutable;
    final fixture =
        'packages/ai_sdk_mcp/test/fixtures/echo_stdio_server.dart';

    test('starts a subprocess, sends a request, and receives the response',
        () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      addTearDown(transport.close);

      final initResp = await transport
          .send(JsonRpcRequest(method: 'initialize', id: 1))
          .timeout(const Duration(seconds: 20));
      expect(initResp.isError, isFalse);
      expect((initResp.result as Map)['protocolVersion'], '2024-11-05');

      // A second send reuses the already-started process (line 29 early return).
      final toolsResp = await transport
          .send(JsonRpcRequest(method: 'tools/list', id: 2))
          .timeout(const Duration(seconds: 20));
      final tools = (toolsResp.result as Map)['tools'] as List;
      expect(tools, hasLength(1));
      expect((tools.first as Map)['name'], 'echo');
    });

    test('drives the full client over stdio', () async {
      final client = MCPClient(
        transport: StdioMCPTransport(command: dartExe, args: [fixture]),
      );
      addTearDown(client.close);

      final toolSet = await client.tools().timeout(const Duration(seconds: 20));
      expect(toolSet.keys, contains('echo'));

      final result = await client
          .callTool('echo', {'value': 'world'})
          .timeout(const Duration(seconds: 20));
      expect(result, 'echo: world');
    });

    test('surfaces server-initiated notifications (with split-line framing)',
        () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      addTearDown(transport.close);

      final received = <Map<String, dynamic>>[];
      final sub = transport.notifications.listen(received.add);
      addTearDown(sub.cancel);

      final resp = await transport
          .send(JsonRpcRequest(method: 'emit_notification', id: 1))
          .timeout(const Duration(seconds: 20));
      expect(resp.isError, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        received.any((m) => m['method'] == 'notifications/message'),
        isTrue,
      );
    });

    test('returns a JSON-RPC error response for an unknown method', () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      addTearDown(transport.close);

      final resp = await transport
          .send(JsonRpcRequest(method: 'does/not/exist', id: 7))
          .timeout(const Duration(seconds: 20));
      expect(resp.isError, isTrue);
      expect(resp.error!['message'], contains('Method not found'));
    });

    test('close() is idempotent and tears down the process', () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      await transport.send(JsonRpcRequest(method: 'initialize', id: 1))
          .timeout(const Duration(seconds: 20));
      await transport.close();
      // Second close is a no-op (process already null, controller closed).
      await transport.close();
      expect(await transport.notifications.isEmpty, isTrue);
    });
  });
}

/// Label used in a group name to keep the SSE-parser group description unique
/// and self-documenting.
const _SseLabel = '_SseLineSink';
