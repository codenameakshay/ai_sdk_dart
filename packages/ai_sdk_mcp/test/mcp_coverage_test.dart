import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/fake_streamable_http_server.dart';

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
  void enqueueRaw({
    required int status,
    required String body,
    String? contentType,
  }) => _responseQueue.add(
    _CannedResponse(status: status, rawBody: body, contentType: contentType),
  );

  void enqueueInitialize() {
    enqueueJson({
      'jsonrpc': '2.0',
      'result': {
        'protocolVersion': '2025-06-18',
        'capabilities': {'tools': {}},
        'serverInfo': {'name': 'test', 'version': '1.0.0'},
      },
    });
    enqueueJson({'jsonrpc': '2.0', 'result': {}});
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      if (request.method == 'GET' || request.method == 'DELETE') {
        request.response.statusCode = 405;
        await request.response.close();
        continue;
      }

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
  _CannedResponse({
    this.jsonBody,
    this.status = 200,
    this.rawBody,
    this.contentType,
  });

  final Map<String, dynamic>? jsonBody;
  final int status;
  final String? rawBody;
  final String? contentType;

  void write(HttpResponse res, Object? id) {
    res.statusCode = status;
    if (jsonBody != null) {
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode(Map.of(jsonBody!)..['id'] = id));
    } else {
      if (contentType != null) {
        res.headers.set('Content-Type', contentType!);
      }
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
  final sentNotifications = <JsonRpcNotification>[];
  int sendCount = 0;
  int closeCount = 0;
  bool closed = false;

  void pushNotification(Map<String, dynamic> message) =>
      _notifications.add(message);

  void pushError(Object error) {
    if (_notifications.isClosed) {
      return;
    }
    _notifications.addError(error);
  }

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    sendCount++;
    return _handler(request);
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {
    sentNotifications.add(notification);
  }

  @override
  Future<void> close() async {
    closeCount++;
    closed = true;
    if (!_notifications.isClosed) await _notifications.close();
  }
}

/// A transport that does NOT override [notifications], so the abstract default
/// (`json_rpc.dart`) getter is exercised.
class _DefaultNotificationsTransport extends MCPTransport {
  final sentNotifications = <JsonRpcNotification>[];

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    if (request.method == 'initialize') {
      return _initResult(request);
    }
    return const JsonRpcResponse(result: {});
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {
    sentNotifications.add(notification);
  }

  @override
  Future<void> close() async {}
}

JsonRpcResponse _ok(JsonRpcRequest req, Map<String, dynamic> result) =>
    JsonRpcResponse(result: result, id: req.id);

JsonRpcResponse _err(JsonRpcRequest req, String message) =>
    JsonRpcResponse(error: {'code': -32000, 'message': message}, id: req.id);

JsonRpcResponse _initResult(JsonRpcRequest req) => _ok(req, {
  'protocolVersion': '2025-06-18',
  'capabilities': {'tools': {}},
  'serverInfo': {'name': 'fake', 'version': '1.0.0'},
});

class _TrackingClient extends http.BaseClient {
  _TrackingClient(this._inner);

  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request);
  }

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

class _StreamedResponseClient extends http.BaseClient {
  _StreamedResponseClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }

  @override
  void close() {
    closed = true;
  }
}

class _FakeProcess implements Process {
  _FakeProcess({
    IOSink? stdin,
    Stream<List<int>>? stdout,
    Stream<List<int>>? stderr,
    Future<int>? exitCode,
  }) : stdin = stdin ?? IOSink(StreamController<List<int>>().sink),
       stdout = stdout ?? const Stream<List<int>>.empty(),
       stderr = stderr ?? const Stream<List<int>>.empty(),
       _exitCode = exitCode ?? Completer<int>().future;

  final Future<int> _exitCode;
  bool killed = false;

  @override
  final IOSink stdin;

  @override
  final Stream<List<int>> stdout;

  @override
  final Stream<List<int>> stderr;

  @override
  Future<int> get exitCode => _exitCode;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }
}

class _ThrowingStreamConsumer implements StreamConsumer<List<int>> {
  _ThrowingStreamConsumer(this.error);

  final Object error;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
    throw error;
  }

  @override
  Future<void> close() async {}
}

void main() {
  // =========================================================================
  // StreamableHttpClientTransport edge paths
  // =========================================================================

  group('StreamableHttpClientTransport', () {
    test(
      'throws a typed transport error on non-2xx HTTP status without leaking the response body',
      () async {
        final mock = await _MockHttpServer.start();
        addTearDown(mock.close);
        final secretUri = Uri(
          scheme: mock.uri.scheme,
          userInfo: 'alice:super-secret',
          host: mock.uri.host,
          port: mock.uri.port,
          path: mock.uri.path,
          queryParameters: {'token': 'query-secret'},
          fragment: 'frag-secret',
        );
        final safeUri = Uri(
          scheme: mock.uri.scheme,
          host: mock.uri.host,
          port: mock.uri.port,
          path: mock.uri.path,
        );
        mock.enqueueRaw(
          status: 503,
          body: 'service unavailable token=super-secret body=${'x' * 256}',
        );
        mock.enqueueRaw(
          status: 503,
          body: 'service unavailable token=super-secret body=${'x' * 256}',
        );

        final transport = StreamableHttpClientTransport(url: secretUri);
        addTearDown(transport.close);

        final future = transport.send(JsonRpcRequest(method: 'ping', id: 1));

        await expectLater(
          future,
          throwsA(
            isA<MCPTransportException>()
                .having((e) => e.statusCode, 'statusCode', 503)
                .having((e) => e.method, 'method', 'POST')
                .having((e) => e.uri, 'uri', safeUri),
          ),
        );

        MCPTransportException? error;
        try {
          await transport.send(JsonRpcRequest(method: 'ping', id: 2));
          fail('Expected MCPTransportException');
        } on MCPTransportException catch (caught) {
          error = caught;
        }

        expect(error, isNotNull);
        expect(error.toString(), contains('HTTP 503'));
        expect(error.toString(), contains('POST'));
        expect(error.toString(), contains(safeUri.toString()));
        expect(error.toString(), isNot(contains('super-secret')));
        expect(error.toString(), isNot(contains('service unavailable')));
        expect(error.toString(), isNot(contains('token=')));
        expect(error.toString(), isNot(contains('query-secret')));
        expect(error.toString(), isNot(contains('frag-secret')));
        expect(error.toString(), isNot(contains('alice:')));
        expect(error.uri, safeUri);
        expect(error.uri.userInfo, isEmpty);
        expect(error.uri.query, isEmpty);
        expect(error.uri.fragment, isEmpty);
        expect(error.uri.toString(), contains(safeUri.toString()));
        expect(error.uri.toString(), isNot(contains('super-secret')));
        expect(error.uri.toString(), isNot(contains('query-secret')));
        expect(error.uri.toString(), isNot(contains('frag-secret')));
        expect(error.message, isNot(contains('?')));
        expect(error.message, isNot(contains('#')));
        expect(error.message, isNot(contains('@')));
        expect(error.toString().length, lessThan(220));
      },
    );

    test('sendNotification redacts transport errors the same way', () async {
      final mock = await _MockHttpServer.start();
      addTearDown(mock.close);
      final secretUri = Uri(
        scheme: mock.uri.scheme,
        userInfo: 'notify:top-secret',
        host: mock.uri.host,
        port: mock.uri.port,
        path: mock.uri.path,
        queryParameters: {'apiKey': 'notify-query-secret'},
        fragment: 'notify-frag-secret',
      );
      final safeUri = Uri(
        scheme: mock.uri.scheme,
        host: mock.uri.host,
        port: mock.uri.port,
        path: mock.uri.path,
      );
      mock.enqueueRaw(status: 401, body: 'Bearer top-secret should never leak');
      mock.enqueueRaw(status: 401, body: 'Bearer top-secret should never leak');

      final transport = StreamableHttpClientTransport(url: secretUri);
      addTearDown(transport.close);

      final future = transport.sendNotification(
        JsonRpcNotification(method: 'notifications/initialized'),
      );

      await expectLater(
        future,
        throwsA(
          isA<MCPTransportException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.method, 'method', 'POST')
              .having((e) => e.uri, 'uri', safeUri),
        ),
      );

      MCPTransportException? error;
      try {
        await transport.sendNotification(
          JsonRpcNotification(method: 'notifications/initialized'),
        );
        fail('Expected MCPTransportException');
      } on MCPTransportException catch (caught) {
        error = caught;
      }

      expect(error, isNotNull);
      expect(error.toString(), contains(safeUri.toString()));
      expect(error.toString(), isNot(contains('top-secret')));
      expect(error.toString(), isNot(contains('Bearer')));
      expect(error.toString(), isNot(contains('notify:')));
      expect(error.toString(), isNot(contains('notify-query-secret')));
      expect(error.toString(), isNot(contains('notify-frag-secret')));
      expect(error.uri, safeUri);
      expect(error.uri.userInfo, isEmpty);
      expect(error.uri.query, isEmpty);
      expect(error.uri.fragment, isEmpty);
      expect(error.uri.toString(), isNot(contains('top-secret')));
      expect(error.uri.toString(), isNot(contains('notify-query-secret')));
      expect(error.uri.toString(), isNot(contains('notify-frag-secret')));
    });

    test('throws MCPException when body is not a JSON object', () async {
      final mock = await _MockHttpServer.start();
      addTearDown(mock.close);
      mock.enqueueRaw(
        status: 200,
        body: '["not", "an", "object"]',
        contentType: 'application/json',
      );

      final transport = StreamableHttpClientTransport(url: mock.uri);
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

    test('bounds buffered JSON response bodies at 1 MiB', () async {
      final mock = await _MockHttpServer.start();
      addTearDown(mock.close);
      final oversizedValue = 'x' * ((1024 * 1024) + 1);
      mock.enqueueRaw(
        status: 200,
        body: '{"jsonrpc":"2.0","id":1,"result":{"value":"$oversizedValue"}}',
        contentType: 'application/json',
      );

      final transport = StreamableHttpClientTransport(url: mock.uri);
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPTransportException>()
              .having((e) => e.message, 'message', contains('response body'))
              .having(
                (e) => e.message,
                'message',
                contains('exceeded 1048576 characters'),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains(oversizedValue.substring(0, 64))),
              ),
        ),
      );
    });

    test('bounds buffered SSE lines at 1 MiB', () async {
      final oversizedValue = 'x' * ((1024 * 1024) + 1);
      final responseBody = 'data: $oversizedValue\n\n';
      final client = _StreamedResponseClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(responseBody)),
          200,
          headers: const {'content-type': 'text/event-stream'},
        ),
      );
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('http://example.com/mcp'),
        client: client,
      );
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>()
              .having((e) => e.message, 'message', contains('SSE line'))
              .having(
                (e) => e.message,
                'message',
                contains('exceeded 1048576 characters'),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains(oversizedValue.substring(0, 64))),
              ),
        ),
      );
    });

    test('bounds buffered SSE events at 1 MiB across data lines', () async {
      final dataLine = 'x' * (64 * 1024);
      final responseBody =
          '${List.filled(17, 'data: $dataLine').join('\n')}\n\n';
      final client = _StreamedResponseClient(
        (_) async => http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode(responseBody)),
          200,
          headers: const {'content-type': 'text/event-stream'},
        ),
      );
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('http://example.com/mcp'),
        client: client,
      );
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'ping', id: 1)),
        throwsA(
          isA<MCPException>()
              .having((e) => e.message, 'message', contains('SSE event'))
              .having(
                (e) => e.message,
                'message',
                contains('exceeded 1048576 characters'),
              ),
        ),
      );
    });

    test('sends custom headers with every request', () async {
      final mock = await _MockHttpServer.start();
      addTearDown(mock.close);
      mock.enqueueJson({'jsonrpc': '2.0', 'result': {}});

      final transport = StreamableHttpClientTransport(
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

    test(
      'sendNotification posts JSON-RPC without an id and ignores 202 body',
      () async {
        final mock = await _MockHttpServer.start();
        addTearDown(mock.close);
        mock.enqueueRaw(status: 202, body: '');

        final transport = StreamableHttpClientTransport(url: mock.uri);
        addTearDown(transport.close);

        await transport.sendNotification(
          JsonRpcNotification(method: 'notifications/initialized'),
        );

        expect(mock.requestLog, hasLength(1));
        final sent = mock.requestLog.single;
        expect(sent['method'], 'notifications/initialized');
        expect(sent.containsKey('id'), isFalse);
      },
    );
    test(
      'request timeout sends notifications/cancelled and returns promptly',
      () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.queueInitializeResponse(sessionId: 'session-1');
        server.queueSseResponse(const [], closeStream: false);

        final client = MCPClient(
          transport: StreamableHttpClientTransport(
            url: server.uri,
            requestTimeout: const Duration(milliseconds: 80),
          ),
        );
        addTearDown(client.close);

        await expectLater(
          client.tools(),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('timed out'),
            ),
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(server.cancelNotificationCount, 1);
        final cancelled = server.requestLog.lastWhere(
          (request) => request.body?['method'] == 'notifications/cancelled',
        );
        expect((cancelled.body?['params'] as Map)['requestId'], isA<int>());
        expect((cancelled.body?['params'] as Map)['reason'], isNotEmpty);
      },
    );

    test(
      'rejects JSON responses whose id does not match the request id',
      () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.queueJsonResponse({
          'jsonrpc': '2.0',
          'id': 999,
          'result': {'ok': true},
        }, injectRequestId: false);

        final transport = StreamableHttpClientTransport(url: server.uri);
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 1)),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Unexpected JSON-RPC response id'),
            ),
          ),
        );
      },
    );

    test(
      'rejects SSE responses whose id does not match the request id',
      () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.queueSseResponse([
          FakeSseFrame.json({
            'jsonrpc': '2.0',
            'id': 999,
            'result': {'ok': true},
          }, id: 'evt-1'),
        ], injectRequestId: false);

        final transport = StreamableHttpClientTransport(
          url: server.uri,
          requestTimeout: const Duration(milliseconds: 200),
        );
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 1)),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Unexpected JSON-RPC response id'),
            ),
          ),
        );
      },
    );

    test(
      'close sends DELETE, accepts 405, and does not close an injected client',
      () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.deleteStatusCode = 405;
        server.queueInitializeResponse(sessionId: 'session-1');

        final trackingClient = _TrackingClient(http.Client());
        final transport = StreamableHttpClientTransport(
          url: server.uri,
          client: trackingClient,
        );
        final client = MCPClient(transport: transport);

        await client.initialize();
        await client.close();
        await client.close();

        expect(server.deleteRequestCount, 1);
        expect(trackingClient.closed, isFalse);
      },
    );

    test('rejects invalid Mcp-Session-Id values from initialize', () async {
      final server = await FakeStreamableHttpServer.start();
      addTearDown(server.close);
      server.queueInitializeResponse(sessionId: 'bad session');

      final client = MCPClient(
        transport: StreamableHttpClientTransport(url: server.uri),
      );
      addTearDown(client.close);

      await expectLater(
        client.initialize(),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('Mcp-Session-Id'),
          ),
        ),
      );
    });

    test(
      'throws a typed session-expired error on a 404 for an active session',
      () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.queueInitializeResponse(sessionId: 'session-1');

        final transport = StreamableHttpClientTransport(url: server.uri);
        addTearDown(transport.close);

        final initResp = await transport.send(
          JsonRpcRequest(method: 'initialize', id: 1),
        );
        expect((initResp.result as Map)['protocolVersion'], '2025-06-18');

        transport.setProtocolVersion('2025-06-18');
        server.expireCurrentSession();

        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 2)),
          throwsA(isA<MCPSessionExpiredException>()),
        );
      },
    );

    test(
      'sendNotification marks the session expired on a 404 and later calls fail before the network',
      () async {
        final server = await FakeStreamableHttpServer.start();
        addTearDown(server.close);
        server.queueInitializeResponse(sessionId: 'session-1');

        final transport = StreamableHttpClientTransport(url: server.uri);
        addTearDown(transport.close);

        final initResp = await transport.send(
          JsonRpcRequest(method: 'initialize', id: 1),
        );
        expect((initResp.result as Map)['protocolVersion'], '2025-06-18');

        transport.setProtocolVersion('2025-06-18');
        server.expireCurrentSession();

        await expectLater(
          transport.sendNotification(
            JsonRpcNotification(method: 'notifications/ping'),
          ),
          throwsA(isA<MCPSessionExpiredException>()),
        );

        final requestCountAfter404 = server.requestLog.length;
        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 2)),
          throwsA(isA<MCPSessionExpiredException>()),
        );
        expect(server.requestLog, hasLength(requestCountAfter404));
      },
    );

    test(
      'throws when a 2xx response uses an unexpected Content-Type',
      () async {
        final mock = await _MockHttpServer.start();
        addTearDown(mock.close);
        mock.enqueueRaw(
          status: 200,
          body: '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}',
          contentType: 'text/plain',
        );

        final transport = StreamableHttpClientTransport(url: mock.uri);
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 1)),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Unexpected MCP response Content-Type'),
            ),
          ),
        );
      },
    );

    test(
      'rejects JSON-RPC payloads with an unexpected jsonrpc version',
      () async {
        final mock = await _MockHttpServer.start();
        addTearDown(mock.close);
        mock.enqueueJson({
          'jsonrpc': '1.0',
          'result': {'ok': true},
        });

        final transport = StreamableHttpClientTransport(url: mock.uri);
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 1)),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Unexpected JSON-RPC response format'),
            ),
          ),
        );
      },
    );

    test(
      'rejects JSON-RPC payloads that contain both result and error',
      () async {
        final mock = await _MockHttpServer.start();
        addTearDown(mock.close);
        mock.enqueueJson({
          'jsonrpc': '2.0',
          'result': {'ok': true},
          'error': {'code': -1, 'message': 'boom'},
        });

        final transport = StreamableHttpClientTransport(url: mock.uri);
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 1)),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Unexpected JSON-RPC response format'),
            ),
          ),
        );
      },
    );

    test(
      'surfaces SSE notifications before failing when the stream closes without a response',
      () async {
        final client = _StreamedResponseClient((request) async {
          expect(request.method, 'POST');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable([
              utf8.encode(
                'data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"step":1}}\n\n',
              ),
            ]),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        });
        final transport = StreamableHttpClientTransport(
          url: Uri.parse('http://example.com/mcp'),
          client: client,
          requestTimeout: const Duration(milliseconds: 200),
        );
        addTearDown(transport.close);

        final notifications = <Map<String, dynamic>>[];
        final sub = transport.notifications.listen(notifications.add);
        addTearDown(sub.cancel);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'ping', id: 1)),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('closed before responding'),
            ),
          ),
        );

        expect(
          notifications.single,
          containsPair('method', 'notifications/progress'),
        );
      },
    );

    test('surfaces SSE byte-stream errors as MCPException', () async {
      final controller = StreamController<List<int>>();
      final client = _StreamedResponseClient((request) async {
        expect(request.method, 'POST');
        return http.StreamedResponse(
          controller.stream,
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      });
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('http://example.com/mcp'),
        client: client,
        requestTimeout: const Duration(milliseconds: 200),
      );
      addTearDown(() async {
        await controller.close();
        await transport.close();
      });

      final future = transport.send(JsonRpcRequest(method: 'ping', id: 1));
      controller.add(
        utf8.encode(
          'data: {"jsonrpc":"2.0","method":"notifications/progress"}\n\n',
        ),
      );
      controller.addError(StateError('sse boom'));

      await expectLater(
        future,
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('SSE response stream error'),
          ),
        ),
      );
    });
  });

  // =========================================================================
  // MCPClient error branches & reconnect (mcp_client.dart)
  // =========================================================================

  group('MCPClient error branches', () {
    test('close is idempotent for custom transports', () async {
      final transport = _ScriptedTransport(
        (_) async => const JsonRpcResponse(),
      );
      final client = MCPClient(transport: transport);

      await client.close();
      await client.close();

      expect(transport.closeCount, 1);
    });

    test('default-notifications transport drives the abstract getter', () async {
      // _DefaultNotificationsTransport does not override `notifications`, so the
      // abstract default getter in json_rpc.dart runs when the client wires up
      // its notification subscription.
      final transport = _DefaultNotificationsTransport();
      final client = MCPClient(transport: transport);
      addTearDown(client.close);
      await client.initialize();
      // A second initialize is a no-op (already initialized).
      await client.initialize();
      expect(transport.sentNotifications, hasLength(1));
      expect(
        transport.sentNotifications.single.method,
        'notifications/initialized',
      );
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

      // Exercise the dynamicTool execute closure.
      final tool = toolSet['echo']!;
      final result = await tool.execute!({
        'value': 'hi',
      }, const ToolExecutionOptions());
      expect(result, 'got: hi');
    });

    test('callTool JSON-RPC error (not isError) throws MCPException', () async {
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

    test(
      'readResource returns octet-stream fallback when result is not a Map',
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
      },
    );

    test('readResource returns octet-stream fallback when result has no '
        'usable contents', () async {
      // result is a Map but `contents` is missing/empty → fallback.
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
      // `first is! Map` fallback.
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

    test(
      'subscribeResource reuses the existing controller on second call',
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

        client.subscribeResource('file:///dup');
        // Let the first subscribe round-trip settle.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        client.subscribeResource('file:///dup'); // existing path

        await Future<void>.delayed(const Duration(milliseconds: 30));
        // The existing-controller branch must NOT issue a second subscribe.
        expect(subscribeRequests, 1);
      },
    );

    test(
      'subscribeResource swallows a resources/subscribe server error',
      () async {
        // The server returns an error for resources/subscribe; the client must
        // surface it through _subscribeResourceOnServer but swallow it via the
        // .catchError so subscribeResource itself succeeds.
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
        final sub = client.subscribeResource('file:///err').listen(updates.add);
        addTearDown(sub.cancel);

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(subscribeErrored, isTrue);
        // No crash; subscription is still live.
        expect(updates, isEmpty);
      },
    );

    test('transport notification error is swallowed by the client', () async {
      // Pushing an error onto the transport notifications stream must be caught
      // by the onError handler in _listenToTransport.
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

    test(
      'resource update bursts coalesce per URI while distinct URIs refresh independently',
      () async {
        final readA1 = Completer<JsonRpcResponse>();
        final readA2 = Completer<JsonRpcResponse>();
        final readB1 = Completer<JsonRpcResponse>();
        var readARequests = 0;
        var readBRequests = 0;

        final transport = _ScriptedTransport((req) {
          if (req.method == 'initialize') return _initResult(req);
          if (req.method == 'notifications/initialized') return _ok(req, {});
          if (req.method == 'resources/subscribe') return _ok(req, {});
          if (req.method != 'resources/read') return _ok(req, {});

          final uri = req.params?['uri'];
          if (uri == 'file:///a') {
            readARequests++;
            if (readARequests == 1) return readA1.future;
            if (readARequests == 2) return readA2.future;
          }
          if (uri == 'file:///b') {
            readBRequests++;
            if (readBRequests == 1) return readB1.future;
          }
          fail(
            'Unexpected resources/read for $uri (#${uri == 'file:///a' ? readARequests : readBRequests})',
          );
        });

        final client = MCPClient(transport: transport);
        addTearDown(client.close);

        final updatesA = <MCPResourceContent>[];
        final updatesB = <MCPResourceContent>[];
        final subA = client.subscribeResource('file:///a').listen(updatesA.add);
        final subB = client.subscribeResource('file:///b').listen(updatesB.add);
        addTearDown(subA.cancel);
        addTearDown(subB.cancel);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///a'},
        });
        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///a'},
        });
        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///a'},
        });
        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///b'},
        });

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(readARequests, 1);
        expect(readBRequests, 1);

        readB1.complete(
          JsonRpcResponse(
            id: 100,
            result: {
              'contents': [
                {'uri': 'file:///b', 'mimeType': 'text/plain', 'text': 'b-1'},
              ],
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(updatesB.map((it) => it.text), ['b-1']);

        readA1.complete(
          JsonRpcResponse(
            id: 101,
            result: {
              'contents': [
                {'uri': 'file:///a', 'mimeType': 'text/plain', 'text': 'a-1'},
              ],
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(readARequests, 2);
        expect(updatesA.map((it) => it.text), ['a-1']);

        readA2.complete(
          JsonRpcResponse(
            id: 102,
            result: {
              'contents': [
                {'uri': 'file:///a', 'mimeType': 'text/plain', 'text': 'a-2'},
              ],
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(readARequests, 2);
        expect(updatesA.map((it) => it.text), ['a-1', 'a-2']);
      },
    );

    test('close prevents a queued trailing refresh from starting', () async {
      final firstRead = Completer<JsonRpcResponse>();
      var readRequests = 0;

      final transport = _ScriptedTransport((req) {
        if (req.method == 'initialize') return _initResult(req);
        if (req.method == 'notifications/initialized') return _ok(req, {});
        if (req.method == 'resources/subscribe') return _ok(req, {});
        if (req.method == 'resources/read') {
          readRequests++;
          if (readRequests == 1) return firstRead.future;
        }
        fail('Unexpected ${req.method} request #$readRequests');
      });

      final client = MCPClient(transport: transport);

      final updates = <MCPResourceContent>[];
      final sub = client.subscribeResource('file:///close').listen(updates.add);
      addTearDown(sub.cancel);

      await Future<void>.delayed(const Duration(milliseconds: 30));

      transport.pushNotification({
        'jsonrpc': '2.0',
        'method': 'notifications/resources/updated',
        'params': {'uri': 'file:///close'},
      });
      transport.pushNotification({
        'jsonrpc': '2.0',
        'method': 'notifications/resources/updated',
        'params': {'uri': 'file:///close'},
      });

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(readRequests, 1);

      final closeFuture = client.close();
      firstRead.complete(
        JsonRpcResponse(
          id: 103,
          result: {
            'contents': [
              {
                'uri': 'file:///close',
                'mimeType': 'text/plain',
                'text': 'stale',
              },
            ],
          },
        ),
      );

      await closeFuture;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(readRequests, 1);
      expect(updates, isEmpty);
    });

    test(
      'unsubscribe and resubscribe do not deliver stale in-flight reads to the new controller',
      () async {
        final staleRead = Completer<JsonRpcResponse>();
        final freshRead = Completer<JsonRpcResponse>();
        var readRequests = 0;

        final transport = _ScriptedTransport((req) {
          if (req.method == 'initialize') return _initResult(req);
          if (req.method == 'notifications/initialized') return _ok(req, {});
          if (req.method == 'resources/subscribe') return _ok(req, {});
          if (req.method == 'resources/unsubscribe') return _ok(req, {});
          if (req.method != 'resources/read') return _ok(req, {});

          readRequests++;
          if (readRequests == 1) return staleRead.future;
          if (readRequests == 2) return freshRead.future;
          fail('Unexpected resources/read #$readRequests');
        });

        final client = MCPClient(transport: transport);
        addTearDown(client.close);

        final firstUpdates = <MCPResourceContent>[];
        final secondUpdates = <MCPResourceContent>[];

        final sub1 = client
            .subscribeResource('file:///swap')
            .listen(firstUpdates.add);

        await Future<void>.delayed(const Duration(milliseconds: 30));

        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///swap'},
        });
        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///swap'},
        });

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(readRequests, 1);

        await sub1.cancel();

        final sub2 = client
            .subscribeResource('file:///swap')
            .listen(secondUpdates.add);
        addTearDown(sub2.cancel);

        staleRead.complete(
          JsonRpcResponse(
            id: 200,
            result: {
              'contents': [
                {
                  'uri': 'file:///swap',
                  'mimeType': 'text/plain',
                  'text': 'stale',
                },
              ],
            },
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(readRequests, 1);
        expect(firstUpdates, isEmpty);
        expect(secondUpdates, isEmpty);

        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///swap'},
        });

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(readRequests, 2);

        freshRead.complete(
          JsonRpcResponse(
            id: 201,
            result: {
              'contents': [
                {
                  'uri': 'file:///swap',
                  'mimeType': 'text/plain',
                  'text': 'fresh',
                },
              ],
            },
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(secondUpdates.map((it) => it.text), ['fresh']);
      },
    );
  });

  // =========================================================================
  // Reconnect loop (mcp_client.dart)
  // =========================================================================

  group('MCPClient reconnect', () {
    test(
      'reconnects via the transport factory and succeeds after a failure',
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
      },
    );

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

    test(
      'resource refresh queues a trailing replay when a second update lands mid-read',
      () async {
        final readRelease = Completer<void>();
        var readCount = 0;
        final transport = _ScriptedTransport((req) async {
          switch (req.method) {
            case 'initialize':
              return _initResult(req);
            case 'notifications/initialized':
              return _ok(req, {});
            case 'resources/subscribe':
              return _ok(req, {});
            case 'resources/read':
              readCount++;
              if (readCount == 1) {
                await readRelease.future;
              }
              return _ok(req, {
                'contents': [
                  {
                    'uri': 'memory://doc',
                    'mimeType': 'text/plain',
                    'text': 'value-$readCount',
                  },
                ],
              });
            default:
              return _ok(req, {});
          }
        });
        final client = MCPClient(transport: transport);
        addTearDown(client.close);

        final updates = <MCPResourceContent>[];
        final sub = client
            .subscribeResource('memory://doc')
            .listen(updates.add);
        addTearDown(sub.cancel);

        await Future<void>.delayed(Duration.zero);
        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'memory://doc'},
        });
        await Future<void>.delayed(Duration.zero);
        transport.pushNotification({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'memory://doc'},
        });

        readRelease.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(readCount, 2);
        expect(updates.map((update) => update.text).toList(), [
          'value-1',
          'value-2',
        ]);
      },
    );

    test('policy retries reinitialize after session expiry', () async {
      var initializeCalls = 0;
      var toolsListCalls = 0;
      final transport = _ScriptedTransport((req) {
        switch (req.method) {
          case 'initialize':
            initializeCalls++;
            return _initResult(req);
          case 'notifications/initialized':
            return _ok(req, {});
          case 'tools/list':
            toolsListCalls++;
            if (toolsListCalls == 1) {
              throw MCPSessionExpiredException(
                method: 'POST',
                uri: Uri(),
                statusCode: 404,
                context: 'session expired',
              );
            }
            return _ok(req, {'tools': []});
          default:
            return _ok(req, {});
        }
      });
      final client = MCPClient(
        transport: transport,
        reconnectPolicy: const MCPReconnectPolicy(
          maxAttempts: 1,
          initialDelayMs: 1,
          maxDelayMs: 1,
        ),
      );
      addTearDown(client.close);

      final tools = await client.tools();
      expect(tools, isEmpty);
      expect(initializeCalls, 2);
      expect(toolsListCalls, 2);
    });
  });

  // =========================================================================
  // StdioMCPTransport (real subprocess)
  // =========================================================================

  group('StdioMCPTransport (subprocess)', () {
    final dartExe = Platform.resolvedExecutable;
    final fixture = 'packages/ai_sdk_mcp/test/fixtures/echo_stdio_server.dart';

    test(
      'concurrent cold-start operations spawn exactly one child process',
      () async {
        var startCalls = 0;
        final startGate = Completer<void>();

        final transport = StdioMCPTransport(
          command: dartExe,
          args: [fixture],
          processStarter: (command, args) async {
            startCalls++;
            await startGate.future;
            return Process.start(command, args);
          },
        );
        addTearDown(transport.close);

        final notificationFuture = transport.sendNotification(
          JsonRpcNotification(method: 'notifications/ping'),
        );
        final initializeFuture = transport.send(
          JsonRpcRequest(method: 'initialize', id: 1),
        );

        startGate.complete();

        await notificationFuture;
        final response = await initializeFuture.timeout(
          const Duration(seconds: 20),
        );
        expect(startCalls, 1);
        expect(response.isError, isFalse);
      },
    );

    test(
      'starts a subprocess, sends a request, and receives the response',
      () async {
        final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
        addTearDown(transport.close);

        final initResp = await transport
            .send(JsonRpcRequest(method: 'initialize', id: 1))
            .timeout(const Duration(seconds: 20));
        expect(initResp.isError, isFalse);
        expect((initResp.result as Map)['protocolVersion'], '2025-06-18');

        // A second send reuses the already-started process (early return).
        final toolsResp = await transport
            .send(JsonRpcRequest(method: 'tools/list', id: 2))
            .timeout(const Duration(seconds: 20));
        final tools = (toolsResp.result as Map)['tools'] as List;
        expect(tools, hasLength(1));
        expect((tools.first as Map)['name'], 'echo');
      },
    );

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

    test(
      'client initialize does not wait for a stdio notification response',
      () async {
        final client = MCPClient(
          transport: StdioMCPTransport(command: dartExe, args: [fixture]),
        );
        addTearDown(client.close);

        await client.initialize().timeout(const Duration(seconds: 20));
      },
    );

    test(
      'surfaces server-initiated notifications (with split-line framing)',
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
      },
    );

    test('returns a JSON-RPC error response for an unknown method', () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      addTearDown(transport.close);

      final resp = await transport
          .send(JsonRpcRequest(method: 'does/not/exist', id: 7))
          .timeout(const Duration(seconds: 20));
      expect(resp.isError, isTrue);
      expect(resp.error!['message'], contains('Method not found'));
    });

    test(
      'close during cold start rejects the pending caller and later sends',
      () async {
        var startCalls = 0;
        final startGate = Completer<void>();

        final transport = StdioMCPTransport(
          command: dartExe,
          args: [fixture],
          processStarter: (command, args) async {
            startCalls++;
            await startGate.future;
            return Process.start(command, args);
          },
        );

        final pending = transport.send(
          JsonRpcRequest(method: 'initialize', id: 1),
        );
        final closeMatcher = throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('Stdio transport closed'),
          ),
        );

        final pendingExpectation = expectLater(pending, closeMatcher);

        final closeFuture = transport.close();
        startGate.complete();

        await pendingExpectation;
        await closeFuture;
        expect(startCalls, 1);
        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 2)),
          closeMatcher,
        );
      },
    );

    test(
      'process exit fails each pending request once and rejects later sends',
      () async {
        final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
        addTearDown(transport.close);

        final first = transport.send(
          JsonRpcRequest(method: 'exit_after_delay', id: 1),
        );
        final second = transport.send(
          JsonRpcRequest(method: 'exit_after_delay', id: 2),
        );

        final exitMatcher = throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('Stdio MCP process exited with code 17'),
          ),
        );

        await expectLater(first, exitMatcher);
        await expectLater(second, exitMatcher);
        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 3)),
          exitMatcher,
        );
        await expectLater(
          transport.sendNotification(
            JsonRpcNotification(method: 'notifications/ping'),
          ),
          exitMatcher,
        );
      },
    );

    test(
      'close() fails deterministically stalled pending requests and rejects later sends',
      () async {
        final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
        addTearDown(transport.close);

        final ackReady = Completer<void>();
        final sub = transport.notifications.listen((message) {
          if (message['method'] != 'notifications/message') return;
          final params = message['params'];
          if (params is Map && params['ack'] == 'close-stall-ready') {
            if (!ackReady.isCompleted) ackReady.complete();
          }
        });
        addTearDown(sub.cancel);

        await transport
            .send(JsonRpcRequest(method: 'initialize', id: 0))
            .timeout(const Duration(seconds: 20));

        final first = transport.send(
          JsonRpcRequest(
            method: 'ack_then_stall',
            id: 1,
            params: {'ack': 'close-stall-ready'},
          ),
        );
        final second = transport.send(JsonRpcRequest(method: 'stall', id: 2));

        final closeMatcher = throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('Stdio transport closed'),
          ),
        );

        final firstExpectation = expectLater(first, closeMatcher);
        final secondExpectation = expectLater(second, closeMatcher);

        await ackReady.future.timeout(const Duration(seconds: 20));
        await transport.close();

        await firstExpectation;
        await secondExpectation;
        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 3)),
          closeMatcher,
        );
        await expectLater(
          transport.sendNotification(
            JsonRpcNotification(method: 'notifications/ping'),
          ),
          closeMatcher,
        );
      },
    );

    test('process exit reports only a sanitized stderr summary', () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      addTearDown(transport.close);

      await expectLater(
        transport.send(JsonRpcRequest(method: 'exit_with_stderr', id: 1)),
        throwsA(
          isA<MCPException>()
              .having(
                (e) => e.message,
                'message',
                contains('Stdio MCP process exited with code 23'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('stderr characters'),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('stderr-tail-marker')),
              )
              .having((e) => e.message, 'message', isNot(contains('AAAAA'))),
        ),
      );
    });

    test('process exit errors do not expose secret stderr content', () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      addTearDown(transport.close);

      await expectLater(
        transport.send(
          JsonRpcRequest(method: 'exit_with_secret_stderr', id: 1),
        ),
        throwsA(
          isA<MCPException>()
              .having(
                (e) => e.message,
                'message',
                contains('Stdio MCP process exited with code 29'),
              )
              .having(
                (e) => e.message,
                'message',
                contains('stderr characters'),
              )
              .having(
                (e) => e.message,
                'message',
                isNot(contains('Authorization')),
              )
              .having((e) => e.message, 'message', isNot(contains('Bearer')))
              .having(
                (e) => e.message,
                'message',
                isNot(contains('sk-live-stdio-token')),
              ),
        ),
      );
    });

    test('close() is idempotent and tears down the process', () async {
      final transport = StdioMCPTransport(command: dartExe, args: [fixture]);
      await transport
          .send(JsonRpcRequest(method: 'initialize', id: 1))
          .timeout(const Duration(seconds: 20));
      await transport.close();
      // Second close is a no-op (process already null, controller closed).
      await transport.close();
      expect(await transport.notifications.isEmpty, isTrue);
    });

    test('wraps non-MCP startup failures with process context', () async {
      final transport = StdioMCPTransport(
        command: 'missing-command',
        processStarter: (command, args) async {
          throw StateError('spawn failed');
        },
      );

      await expectLater(
        transport.send(JsonRpcRequest(method: 'initialize', id: 1)),
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('Failed to start stdio MCP process'),
          ),
        ),
      );
    });

    test(
      'stdout decoding errors terminate pending calls and future writes',
      () async {
        final process = _FakeProcess(
          stdout: Stream<List<int>>.error(StateError('stdout blew up')),
          stderr: const Stream<List<int>>.empty(),
        );
        final transport = StdioMCPTransport(
          command: 'fake',
          processStarter: (command, args) async => process,
        );
        addTearDown(transport.close);

        final pending = transport.send(
          JsonRpcRequest(method: 'initialize', id: 1),
        );

        final matcher = throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('stdout stream error'),
          ),
        );
        await expectLater(pending, matcher);
        await expectLater(
          transport.sendNotification(
            JsonRpcNotification(method: 'notifications/ping'),
          ),
          matcher,
        );
        expect(process.killed, isTrue);
      },
    );

    test('process exits without stderr and surfaces the exit code', () async {
      final exitCode = Completer<int>();
      final process = _FakeProcess(exitCode: exitCode.future);
      final transport = StdioMCPTransport(
        command: 'fake',
        processStarter: (command, args) async => process,
      );
      addTearDown(transport.close);

      final pending = transport.send(
        JsonRpcRequest(method: 'initialize', id: 1),
      );
      exitCode.complete(9);

      await expectLater(
        pending,
        throwsA(
          isA<MCPException>().having(
            (e) => e.message,
            'message',
            contains('exited with code 9'),
          ),
        ),
      );
    });

    test(
      'write failures surface for both requests and notifications',
      () async {
        final writeError = StateError('stdin flush failed');
        final process = _FakeProcess(
          stdin: IOSink(_ThrowingStreamConsumer(writeError)),
        );
        final transport = StdioMCPTransport(
          command: 'fake',
          processStarter: (command, args) async => process,
        );
        addTearDown(transport.close);

        await expectLater(
          transport.send(JsonRpcRequest(method: 'initialize', id: 1)),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Failed to write to stdio MCP process'),
            ),
          ),
        );
        await expectLater(
          transport.sendNotification(
            JsonRpcNotification(method: 'notifications/initialized'),
          ),
          throwsA(
            isA<MCPException>().having(
              (e) => e.message,
              'message',
              contains('Failed to write notification to stdio MCP process'),
            ),
          ),
        );
      },
    );

    test(
      'partial JSON over 1 MiB terminates without leaking buffered frame contents',
      () async {
        final overflowFragment = '{' * ((1024 * 1024) + 1);
        final process = _FakeProcess(
          stdout: Stream<List<int>>.fromIterable([
            utf8.encode('$overflowFragment\n'),
          ]),
        );
        final transport = StdioMCPTransport(
          command: 'fake',
          processStarter: (command, args) async => process,
        );
        addTearDown(transport.close);

        final pending = transport
            .send(JsonRpcRequest(method: 'initialize', id: 1))
            .timeout(const Duration(seconds: 2));

        final matcher = throwsA(
          isA<MCPException>()
              .having((e) => e.message, 'message', contains('frame exceeded'))
              .having(
                (e) => e.message,
                'message',
                isNot(contains(overflowFragment.substring(0, 64))),
              ),
        );
        await expectLater(pending, matcher);
        await expectLater(
          transport.sendNotification(
            JsonRpcNotification(method: 'notifications/initialized'),
          ),
          matcher,
        );
        expect(process.killed, isTrue);
      },
    );
  });
}
