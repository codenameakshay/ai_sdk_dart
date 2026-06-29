import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
// JsonRpcRequest is internal (not re-exported by the barrel); the failure-path
// tests drive the transport directly, so import it from src.
import 'package:ai_sdk_mcp/src/json_rpc.dart' show JsonRpcRequest;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock MCP HTTP server
// ---------------------------------------------------------------------------

/// A local HTTP server that responds to JSON-RPC MCP requests from queued responses.
class _MockMCPServer {
  _MockMCPServer._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> _requestLog = [];
  final _responseQueue = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> get requestLog => List.unmodifiable(_requestLog);

  static Future<_MockMCPServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockMCPServer._(server);
    unawaited(mock._serve());
    return mock;
  }

  void enqueue(Map<String, dynamic> response) {
    _responseQueue.add(response);
  }

  /// Queue the standard initialize success + an empty response for the
  /// `notifications/initialized` fire-and-forget call.
  void enqueueInitialize() {
    enqueue({
      'jsonrpc': '2.0',
      'result': {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'test-server', 'version': '1.0.0'},
      },
    });
    // notifications/initialized may get a response — provide one so the client
    // doesn't hang, even though errors from it are silently ignored.
    enqueue({'jsonrpc': '2.0', 'result': {}});
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      final bodyText = await utf8.decoder.bind(request).join();
      try {
        final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
        _requestLog.add(body);
        final id = body['id'];

        Map<String, dynamic> responseBody;
        if (_responseQueue.isNotEmpty) {
          responseBody = Map.of(_responseQueue.removeAt(0))..['id'] = id;
        } else {
          responseBody = {'jsonrpc': '2.0', 'id': id, 'result': {}};
        }

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(responseBody));
      } catch (e) {
        request.response.statusCode = 500;
        request.response.write('{"error":"$e"}');
      }
      await request.response.close();
    }
  }

  Uri get uri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/mcp');

  Future<void> close() => _server.close(force: true);
}

// ---------------------------------------------------------------------------
// Mock MCP HTTP+SSE server (protocol 2024-11-05)
// ---------------------------------------------------------------------------

/// A local server implementing the MCP HTTP+SSE transport:
///   - `GET /sse`     → opens a long-lived `text/event-stream`, emits an
///                      `endpoint` event pointing at `/messages`, then keeps
///                      the connection open and writes server→client messages.
///   - `POST /messages` → accepts a JSON-RPC request, logs it, and pushes the
///                      matching response (from the queue) back over the SSE
///                      stream. Replies `202 Accepted` to the POST itself.
class _MockSseServer {
  _MockSseServer._(this._server);

  final HttpServer _server;
  final List<Map<String, dynamic>> _requestLog = [];
  final _responseQueue = <Map<String, dynamic>>[];

  HttpResponse? _sseResponse;
  final _sseReady = Completer<void>();

  List<Map<String, dynamic>> get requestLog => List.unmodifiable(_requestLog);

  static Future<_MockSseServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _MockSseServer._(server);
    unawaited(mock._serve());
    return mock;
  }

  void enqueue(Map<String, dynamic> response) => _responseQueue.add(response);

  void enqueueInitialize() {
    enqueue({
      'jsonrpc': '2.0',
      'result': {
        'protocolVersion': '2024-11-05',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'sse-test-server', 'version': '1.0.0'},
      },
    });
    enqueue({'jsonrpc': '2.0', 'result': {}});
  }

  /// Push an arbitrary server-initiated message over the open SSE stream.
  Future<void> pushMessage(Map<String, dynamic> message) async {
    await _sseReady.future;
    _writeEvent('message', jsonEncode(message));
  }

  void _writeEvent(String event, String data) {
    final res = _sseResponse;
    if (res == null) return;
    res.write('event: $event\n');
    for (final line in const LineSplitter().convert(data)) {
      res.write('data: $line\n');
    }
    res.write('\n');
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.method == 'GET' && request.uri.path == '/sse') {
        request.response.statusCode = 200;
        request.response.headers.set('Content-Type', 'text/event-stream');
        request.response.headers.set('Cache-Control', 'no-cache');
        request.response.bufferOutput = false;
        _sseResponse = request.response;
        // Advertise the POST endpoint.
        _writeEvent('endpoint', '/messages');
        if (!_sseReady.isCompleted) _sseReady.complete();
        // Keep the response open; do not close it here.
        continue;
      }

      if (request.method == 'POST' && request.uri.path == '/messages') {
        final bodyText = await utf8.decoder.bind(request).join();
        try {
          final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
          _requestLog.add(body);
          final id = body['id'];
          // Acknowledge the POST.
          request.response.statusCode = 202;
          request.response.write('Accepted');
          await request.response.close();

          // Deliver the JSON-RPC response over the SSE stream.
          if (_responseQueue.isNotEmpty) {
            final responseBody = Map.of(_responseQueue.removeAt(0))
              ..['id'] = id;
            await pushMessage(responseBody);
          } else {
            await pushMessage({'jsonrpc': '2.0', 'id': id, 'result': {}});
          }
        } catch (e) {
          request.response.statusCode = 500;
          request.response.write('{"error":"$e"}');
          await request.response.close();
        }
        continue;
      }

      request.response.statusCode = 404;
      await request.response.close();
    }
  }

  Uri get sseUri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/sse');

  Future<void> close() async {
    try {
      await _sseResponse?.close();
    } catch (_) {}
    await _server.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

MCPClient _client(_MockMCPServer mock) => MCPClient(
  transport: HttpClientTransport(url: mock.uri, postUrl: mock.uri),
);

/// Bind then immediately release a port, returning a port number that is now
/// free — connecting to it yields "connection refused".
Future<int> _refusedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// A raw HTTP server for SSE failure-path tests. Handles the SSE `GET` with a
/// configurable status (optionally opening the stream and emitting an
/// `endpoint` event) and replies to client→server `POST`s with a configurable
/// status.
class _EdgeSseServer {
  _EdgeSseServer._(
    this._server,
    this._sseStatus,
    this._sendEndpoint,
    this._postStatus,
  );

  final HttpServer _server;
  final int _sseStatus;
  final bool _sendEndpoint;
  final int _postStatus;
  HttpResponse? _sse;

  static Future<_EdgeSseServer> start({
    int sseStatus = 200,
    bool sendEndpoint = false,
    int postStatus = 500,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mock = _EdgeSseServer._(server, sseStatus, sendEndpoint, postStatus);
    unawaited(mock._serve());
    return mock;
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.method == 'GET' && request.uri.path == '/sse') {
        request.response.statusCode = _sseStatus;
        if (_sseStatus >= 200 && _sseStatus < 300) {
          request.response.headers.set('Content-Type', 'text/event-stream');
          request.response.headers.set('Cache-Control', 'no-cache');
          request.response.bufferOutput = false;
          _sse = request.response;
          // Flush the response headers with an ignored SSE comment so the
          // client's streaming GET "connects" even when no endpoint event is
          // advertised (otherwise the GET would hang waiting for headers).
          request.response.write(': connected\n\n');
          if (_sendEndpoint) {
            request.response.write('event: endpoint\ndata: /post\n\n');
          }
          // Keep the stream open; do not close it here.
          continue;
        }
        await request.response.close();
        continue;
      }
      // Any POST (to /post or the fallback /sse) drains the body and replies
      // with the configured status.
      await utf8.decoder.bind(request).drain<void>();
      request.response.statusCode = _postStatus;
      request.response.write('nope');
      await request.response.close();
    }
  }

  Uri get sseUri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/sse');
  Uri get postUri =>
      Uri.parse('http://${_server.address.address}:${_server.port}/post');

  Future<void> close() async {
    try {
      await _sse?.close();
    } catch (_) {}
    await _server.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MCPClient conformance', () {
    // ── initialize() ────────────────────────────────────────────────────────

    group('initialize()', () {
      test(
        'sends protocol version "2024-11-05" and tools capability',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final client = _client(mock);
          addTearDown(client.close);

          await client.initialize();

          expect(mock.requestLog, isNotEmpty);
          final initReq = mock.requestLog.first;
          expect(initReq['method'], 'initialize');
          final params = initReq['params'] as Map<String, dynamic>;
          expect(params['protocolVersion'], '2024-11-05');
          final caps = params['capabilities'] as Map<String, dynamic>;
          expect(caps.keys, contains('tools'));
        },
      );

      test(
        'is idempotent — second call does not send another initialize',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final client = _client(mock);
          addTearDown(client.close);

          await client.initialize();
          await client.initialize(); // no-op

          final initCount = mock.requestLog
              .where((r) => r['method'] == 'initialize')
              .length;
          expect(initCount, 1);
        },
      );

      test(
        'throws MCPException when server returns a JSON-RPC error',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);

          mock.enqueue({
            'jsonrpc': '2.0',
            'error': {'code': -32600, 'message': 'Invalid Request'},
          });

          final client = _client(mock);
          addTearDown(client.close);

          await expectLater(
            client.initialize(),
            throwsA(
              isA<MCPException>().having(
                (e) => e.message,
                'message',
                contains('Initialize failed'),
              ),
            ),
          );
        },
      );
    });

    // ── tools() ─────────────────────────────────────────────────────────────

    group('tools()', () {
      test('returns a ToolSet with correct tool names from server', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'tools': [
              {
                'name': 'get_weather',
                'description': 'Get current weather',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                },
              },
              {
                'name': 'calculate',
                'description': 'Arithmetic',
                'inputSchema': {'type': 'object'},
              },
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final toolSet = await client.tools();
        expect(toolSet.length, 2);
        expect(toolSet.keys, containsAll(['get_weather', 'calculate']));
      });

      test('returns empty ToolSet when server returns no tools', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'tools': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        final toolSet = await client.tools();
        expect(toolSet, isEmpty);
      });
    });

    // ── callTool() ───────────────────────────────────────────────────────────

    group('callTool()', () {
      test('returns text content from MCP tool response', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'content': [
              {'type': 'text', 'text': 'Sunny, 18°C'},
            ],
            'isError': false,
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final result = await client.callTool('get_weather', {'city': 'Paris'});
        expect(result, 'Sunny, 18°C');
      });

      test('throws MCPException when isError is true', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'content': [
              {'type': 'text', 'text': 'Unknown city'},
            ],
            'isError': true,
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        await expectLater(
          client.callTool('get_weather', {'city': 'INVALID'}),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Unknown city'),
            ),
          ),
        );
      });

      test('sends tools/call with correct name and arguments', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'content': [
              {'type': 'text', 'text': '42'},
            ],
            'isError': false,
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.callTool('calculate', {'expression': '6*7'});

        final callReq = mock.requestLog.firstWhere(
          (r) => r['method'] == 'tools/call',
        );
        expect(callReq['params']['name'], 'calculate');
        expect((callReq['params']['arguments'] as Map)['expression'], '6*7');
      });
    });

    // ── listPrompts() ────────────────────────────────────────────────────────

    group('listPrompts()', () {
      test('returns prompt list from server', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'prompts': [
              {
                'name': 'summarize',
                'description': 'Summarizes a document',
                'arguments': [
                  {'name': 'document', 'required': true},
                  {'name': 'length', 'description': 'Target length'},
                ],
              },
              {'name': 'translate', 'description': 'Translate text'},
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final prompts = await client.listPrompts();
        expect(prompts.length, 2);
        expect(prompts.first.name, 'summarize');
        expect(prompts.first.description, 'Summarizes a document');
        expect(prompts.first.arguments.length, 2);
        expect(prompts.first.arguments.first.name, 'document');
        expect(prompts.first.arguments.first.required, isTrue);
        expect(prompts[1].name, 'translate');
      });

      test('returns empty list when server has no prompts', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'prompts': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        final prompts = await client.listPrompts();
        expect(prompts, isEmpty);
      });

      test('sends prompts/list method', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'prompts': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.listPrompts();

        expect(
          mock.requestLog.any((r) => r['method'] == 'prompts/list'),
          isTrue,
        );
      });
    });

    // ── getPrompt() ───────────────────────────────────────────────────────────

    group('getPrompt()', () {
      test('returns rendered prompt messages', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'description': 'Summarize this',
            'messages': [
              {
                'role': 'user',
                'content': {'type': 'text', 'text': 'Summarize: Hello world'},
              },
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final result = await client.getPrompt(
          'summarize',
          arguments: {'document': 'Hello world'},
        );
        expect(result.description, 'Summarize this');
        expect(result.messages.length, 1);
        expect(result.messages.first.role, 'user');
        expect(result.messages.first.content, 'Summarize: Hello world');
      });

      test('sends prompts/get with name and arguments', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'messages': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.getPrompt('summarize', arguments: {'doc': 'test'});

        final req = mock.requestLog.firstWhere(
          (r) => r['method'] == 'prompts/get',
        );
        expect(req['params']['name'], 'summarize');
        expect((req['params']['arguments'] as Map)['doc'], 'test');
      });

      test('throws MCPException on server error', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'error': {'code': -32601, 'message': 'Prompt not found'},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await expectLater(
          client.getPrompt('unknown'),
          throwsA(isA<MCPException>()),
        );
      });
    });

    // ── listResources() ───────────────────────────────────────────────────────

    group('listResources()', () {
      test('returns resource list from server', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'resources': [
              {
                'uri': 'file:///data/config.json',
                'name': 'config.json',
                'description': 'App configuration',
                'mimeType': 'application/json',
              },
              {'uri': 'file:///data/log.txt', 'name': 'log.txt'},
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final resources = await client.listResources();
        expect(resources.length, 2);
        expect(resources.first.uri, 'file:///data/config.json');
        expect(resources.first.name, 'config.json');
        expect(resources.first.mimeType, 'application/json');
        expect(resources[1].description, isNull);
      });

      test('returns empty list when server has no resources', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {'resources': []},
        });

        final client = _client(mock);
        addTearDown(client.close);

        final resources = await client.listResources();
        expect(resources, isEmpty);
      });
    });

    // ── readResource() ────────────────────────────────────────────────────────

    group('readResource()', () {
      test('returns resource content', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'contents': [
              {
                'uri': 'file:///data/config.json',
                'mimeType': 'application/json',
                'text': '{"debug": true}',
              },
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        final content = await client.readResource('file:///data/config.json');
        expect(content.uri, 'file:///data/config.json');
        expect(content.mimeType, 'application/json');
        expect(content.text, '{"debug": true}');
      });

      test('sends resources/read with correct uri', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'contents': [
              {'uri': 'file:///x', 'mimeType': 'text/plain', 'text': 'hello'},
            ],
          },
        });

        final client = _client(mock);
        addTearDown(client.close);

        await client.readResource('file:///x');

        final req = mock.requestLog.firstWhere(
          (r) => r['method'] == 'resources/read',
        );
        expect(req['params']['uri'], 'file:///x');
      });

      test('throws MCPException on server error', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'error': {'code': -32601, 'message': 'Resource not found'},
        });

        final client = _client(mock);
        addTearDown(client.close);

        await expectLater(
          client.readResource('file:///missing'),
          throwsA(isA<MCPException>()),
        );
      });
    });

    // ── subscribeResource / notifyResourceUpdated ─────────────────────────────

    group('resource subscriptions', () {
      test('subscribeResource returns a stream', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        // Server accepts subscribe silently
        mock.enqueue({'jsonrpc': '2.0', 'result': {}});

        final client = _client(mock);
        addTearDown(client.close);

        final stream = client.subscribeResource('file:///data/log.txt');
        expect(stream, isA<Stream<MCPResourceContent>>());
      });

      test('notifyResourceUpdated pushes to subscribers', () async {
        final mock = await _MockMCPServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({'jsonrpc': '2.0', 'result': {}});

        final client = _client(mock);
        addTearDown(client.close);

        final updates = <MCPResourceContent>[];
        final subscription = client
            .subscribeResource('file:///data/log.txt')
            .listen(updates.add);
        addTearDown(subscription.cancel);

        await Future<void>.delayed(Duration.zero); // let subscribe settle

        client.notifyResourceUpdated(
          'file:///data/log.txt',
          const MCPResourceContent(
            uri: 'file:///data/log.txt',
            mimeType: 'text/plain',
            text: 'new content',
          ),
        );

        await Future<void>.delayed(Duration.zero);
        expect(updates.length, 1);
        expect(updates.first.text, 'new content');
      });
    });

    // ── MCPReconnectPolicy ────────────────────────────────────────────────────

    group('MCPReconnectPolicy', () {
      test('delayFor returns increasing delays', () {
        const policy = MCPReconnectPolicy(
          initialDelayMs: 100,
          backoffFactor: 2.0,
          maxDelayMs: 5000,
        );
        final d0 = policy.delayFor(0);
        final d1 = policy.delayFor(1);
        final d2 = policy.delayFor(2);
        expect(d1.inMilliseconds, greaterThanOrEqualTo(d0.inMilliseconds));
        expect(d2.inMilliseconds, greaterThanOrEqualTo(d1.inMilliseconds));
      });

      test('delayFor caps at maxDelayMs', () {
        const policy = MCPReconnectPolicy(
          initialDelayMs: 1000,
          backoffFactor: 10.0,
          maxDelayMs: 3000,
        );
        final delay = policy.delayFor(10);
        expect(delay.inMilliseconds, lessThanOrEqualTo(3000));
      });

      test('MCPClient accepts reconnectPolicy constructor param', () {
        final mock_transport = HttpClientTransport(
          url: Uri.parse('http://localhost:9999/mcp'),
        );
        final client = MCPClient(
          transport: mock_transport,
          reconnectPolicy: const MCPReconnectPolicy(maxAttempts: 3),
        );
        expect(client.reconnectPolicy?.maxAttempts, 3);
        client.close();
      });
    });

    // ── capabilities advertised in initialize() ───────────────────────────────

    group('capabilities', () {
      test(
        'initialize advertises prompts and resources capabilities',
        () async {
          final mock = await _MockMCPServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final client = _client(mock);
          addTearDown(client.close);

          await client.initialize();

          final initReq = mock.requestLog.first;
          final caps =
              (initReq['params'] as Map)['capabilities']
                  as Map<String, dynamic>;
          expect(caps.keys, contains('prompts'));
          expect(caps.keys, contains('resources'));
          expect((caps['resources'] as Map)['subscribe'], isTrue);
        },
      );
    });

    // ── MCPException ─────────────────────────────────────────────────────────

    group('MCPException', () {
      test('has a message field', () {
        const e = MCPException('something went wrong');
        expect(e.message, 'something went wrong');
      });

      test('toString includes MCPException prefix and message', () {
        const e = MCPException('oops');
        expect(e.toString(), contains('MCPException'));
        expect(e.toString(), contains('oops'));
      });
    });

    // ── Transport types ──────────────────────────────────────────────────────

    group('transport types', () {
      test('HttpClientTransport accepts url and optional postUrl', () {
        final t = HttpClientTransport(
          url: Uri.parse('http://localhost:3000/sse'),
          postUrl: Uri.parse('http://localhost:3000/mcp'),
        );
        expect(t.url.path, '/sse');
        expect(t.postUrl.path, '/mcp');
      });

      test('HttpClientTransport defaults postUrl to url when omitted', () {
        final t = HttpClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
        );
        expect(t.url, t.postUrl);
      });

      test('SseClientTransport accepts url and headers', () {
        final t = SseClientTransport(
          url: Uri.parse('http://localhost:3000/sse'),
          headers: {'Authorization': 'Bearer token'},
        );
        expect(t.url.path, '/sse');
        expect(t.headers?['Authorization'], 'Bearer token');
        // No server push received yet, so no POST endpoint resolved.
        expect(t.resolvedPostUrl, isNull);
      });

      test('StdioMCPTransport accepts command and args', () {
        final t = StdioMCPTransport(
          command: 'npx',
          args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
        );
        expect(t.command, 'npx');
        expect(t.args, [
          '-y',
          '@modelcontextprotocol/server-filesystem',
          '/tmp',
        ]);
      });
    });

    // ── Real SSE transport (HTTP+SSE, 2024-11-05) ────────────────────────────

    group('SseClientTransport (real SSE)', () {
      test('opens SSE stream, POSTs to advertised endpoint, reads response '
          'over the stream', () async {
        final mock = await _MockSseServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        mock.enqueue({
          'jsonrpc': '2.0',
          'result': {
            'tools': [
              {
                'name': 'ping',
                'inputSchema': {'type': 'object'},
              },
            ],
          },
        });

        final client = MCPClient(
          transport: SseClientTransport(url: mock.sseUri),
        );
        addTearDown(client.close);

        final toolSet = await client.tools();
        expect(toolSet.keys, contains('ping'));

        // Requests were POSTed to the server-advertised /messages endpoint.
        expect(mock.requestLog, isNotEmpty);
        expect(mock.requestLog.first['method'], 'initialize');
      });

      test(
        'resolves the relative endpoint from the `endpoint` event',
        () async {
          final mock = await _MockSseServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final transport = SseClientTransport(url: mock.sseUri);
          final client = MCPClient(transport: transport);
          addTearDown(client.close);

          await client.initialize();

          expect(transport.resolvedPostUrl, isNotNull);
          expect(transport.resolvedPostUrl!.path, '/messages');
        },
      );

      test(
        'surfaces server-initiated notifications via notifications stream',
        () async {
          final mock = await _MockSseServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();

          final transport = SseClientTransport(url: mock.sseUri);
          final client = MCPClient(transport: transport);
          addTearDown(client.close);

          await client.initialize();

          final received = <Map<String, dynamic>>[];
          final sub = transport.notifications.listen(received.add);
          addTearDown(sub.cancel);

          await mock.pushMessage({
            'jsonrpc': '2.0',
            'method': 'notifications/message',
            'params': {'level': 'info', 'data': 'hello'},
          });

          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(received, isNotEmpty);
          expect(received.first['method'], 'notifications/message');
        },
      );

      test(
        'server-pushed resources/updated reaches resource subscribers',
        () async {
          final mock = await _MockSseServer.start();
          addTearDown(mock.close);
          mock.enqueueInitialize();
          // Response to resources/subscribe.
          mock.enqueue({'jsonrpc': '2.0', 'result': {}});
          // Response to the readResource triggered by the update notification.
          mock.enqueue({
            'jsonrpc': '2.0',
            'result': {
              'contents': [
                {
                  'uri': 'file:///watched.txt',
                  'mimeType': 'text/plain',
                  'text': 'updated body',
                },
              ],
            },
          });

          final client = MCPClient(
            transport: SseClientTransport(url: mock.sseUri),
          );
          addTearDown(client.close);

          final updates = <MCPResourceContent>[];
          final sub = client
              .subscribeResource('file:///watched.txt')
              .listen(updates.add);
          addTearDown(sub.cancel);

          // Let initialize + subscribe round-trips settle.
          await Future<void>.delayed(const Duration(milliseconds: 150));

          // Server pushes an update notification over the SSE stream.
          await mock.pushMessage({
            'jsonrpc': '2.0',
            'method': 'notifications/resources/updated',
            'params': {'uri': 'file:///watched.txt'},
          });

          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(updates, isNotEmpty);
          expect(updates.first.text, 'updated body');
        },
      );

      test('parses multi-line and named data events correctly', () async {
        final mock = await _MockSseServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();

        final transport = SseClientTransport(url: mock.sseUri);
        final client = MCPClient(transport: transport);
        addTearDown(client.close);

        await client.initialize();

        final received = <Map<String, dynamic>>[];
        final sub = transport.notifications.listen(received.add);
        addTearDown(sub.cancel);

        // JSON containing a newline-bearing value is split across two data:
        // lines by the mock and must be reassembled by the SSE parser.
        await mock.pushMessage({
          'jsonrpc': '2.0',
          'method': 'notifications/message',
          'params': {'text': 'line one\nline two'},
        });

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(received, isNotEmpty);
        expect((received.first['params'] as Map)['text'], 'line one\nline two');
      });

      test('operations after close throw MCPException', () async {
        final mock = await _MockSseServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();

        final client = MCPClient(
          transport: SseClientTransport(url: mock.sseUri),
        );
        await client.initialize();
        await client.close();

        // The transport is closed; a fresh request must fail rather than hang.
        await expectLater(client.listResources(), throwsA(isA<MCPException>()));
      });
    });

    // ── SSE transport failure paths (exactly one error, no leaks) ────────────
    //
    // Each scenario must surface exactly one observable MCPException via
    // send()/initialize(). A SECONDARY MCPException escaping unhandled (from the
    // internal connection future, the SSE GET stream, or the unlistened
    // notifications broadcast) would be reported by the test runner as an
    // unhandled async error and fail the test — so these tests guard against
    // that regression. The trailing delay gives any leaked async error a chance
    // to escape into the test's error zone.

    group('SseClientTransport failure paths', () {
      test('SSE GET returning 401 surfaces a single MCPException', () async {
        final server = await _EdgeSseServer.start(sseStatus: 401);
        addTearDown(server.close);

        final transport = SseClientTransport(url: server.sseUri);
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 1)),
          throwsA(isA<MCPException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      test('SSE connect to a refused port surfaces a single MCPException', () async {
        final port = await _refusedPort();
        final transport = SseClientTransport(
          url: Uri.parse('http://127.0.0.1:$port/sse'),
          connectTimeout: const Duration(seconds: 2),
        );
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 1)),
          throwsA(isA<MCPException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      test('explicit postUrl with no endpoint event surfaces one error on a '
          'failed POST', () async {
        final server = await _EdgeSseServer.start(postStatus: 500);
        addTearDown(server.close);

        final transport = SseClientTransport(
          url: server.sseUri,
          postUrl: server.postUri,
        );
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 1)),
          throwsA(isA<MCPException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      test('no-endpoint fallback to the SSE url surfaces one error', () async {
        final server = await _EdgeSseServer.start(postStatus: 405);
        addTearDown(server.close);

        final transport = SseClientTransport(
          url: server.sseUri,
          connectTimeout: const Duration(milliseconds: 150),
        );
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 1)),
          throwsA(isA<MCPException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      test('reconnect via transportFactory after a transport failure surfaces '
          'one error', () async {
        final mock = await _MockSseServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        final sseUri = mock.sseUri;

        final client = MCPClient(
          transport: SseClientTransport(
            url: sseUri,
            connectTimeout: const Duration(milliseconds: 200),
          ),
          reconnectPolicy: const MCPReconnectPolicy(
            maxAttempts: 2,
            initialDelayMs: 1,
            backoffFactor: 1.0,
            maxDelayMs: 5,
          ),
          transportFactory: () => SseClientTransport(
            url: sseUri,
            connectTimeout: const Duration(milliseconds: 200),
          ),
        );
        addTearDown(client.close);

        // First transport connects and initializes against the live server.
        await client.initialize();
        // Server dies; every subsequent send (and reconnect) now fails.
        await mock.close();

        await expectLater(client.tools(), throwsA(isA<MCPException>()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      test('give up after maxAttempts (no factory) surfaces one error', () async {
        final mock = await _MockSseServer.start();
        addTearDown(mock.close);
        mock.enqueueInitialize();
        final sseUri = mock.sseUri;

        final client = MCPClient(
          transport: SseClientTransport(
            url: sseUri,
            connectTimeout: const Duration(milliseconds: 200),
          ),
          reconnectPolicy: const MCPReconnectPolicy(
            maxAttempts: 2,
            initialDelayMs: 1,
            backoffFactor: 1.0,
            maxDelayMs: 5,
          ),
        );
        addTearDown(client.close);

        await client.initialize();
        await mock.close();

        await expectLater(client.tools(), throwsA(isA<MCPException>()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    });
  });
}
