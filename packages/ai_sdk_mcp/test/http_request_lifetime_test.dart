import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('malformed session headers cancel the unread response body', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      client: _Client(
        (_) async => http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json', 'mcp-session-id': ''},
        ),
      ),
    );
    addTearDown(transport.close);
    await expectLater(
      transport.send(JsonRpcRequest(method: 'initialize', id: 1)),
      throwsA(isA<MCPException>()),
    );
    expect(cancelled, isTrue);
    await body.close();
  });

  test('body cleanup failure preserves the source error', () async {
    final escaped = <Object>[];
    final finished = Completer<void>();
    final sourceError = StateError('source');
    Object? outcome;
    runZonedGuarded(() async {
      final body = StreamController<List<int>>(
        onListen: () {},
        onCancel: () => Future<void>.error(StateError('cleanup')),
      );
      final transport = StreamableHttpClientTransport(
        url: Uri.https('mcp.test', '/'),
        client: _Client((_) async {
          body.addError(sourceError);
          return http.StreamedResponse(
            body.stream,
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      try {
        outcome = await transport
            .send(JsonRpcRequest(method: 'tools/list', id: 1))
            .then<Object?>((value) => value, onError: (Object e) => e)
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () => 'still pending',
            );
        await transport.close();
        await Future<void>.delayed(Duration.zero);
      } finally {
        finished.complete();
      }
    }, (error, _) => escaped.add(error));
    await finished.future;
    expect(outcome, same(sourceError));
    expect(escaped, isEmpty);
  });

  test('closing during authentication rejects the waiting caller', () async {
    final authenticating = Completer<void>();
    final token = Completer<String?>();
    var sends = 0;
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      auth: MCPAuthConfiguration(
        resource: Uri.https('mcp.test', '/'),
        accessToken: () {
          authenticating.complete();
          return token.future;
        },
      ),
      client: _Client((_) async {
        sends++;
        return http.StreamedResponse(const Stream.empty(), 200);
      }),
    );
    final outcome = transport
        .send(JsonRpcRequest(method: 'tools/list', id: 1))
        .then<Object?>((value) => value, onError: (Object e) => e);
    await authenticating.future;
    await transport.close();
    expect(
      await outcome.timeout(
        const Duration(seconds: 1),
        onTimeout: () => 'still pending',
      ),
      isA<MCPTransportException>(),
    );
    token.complete('late');
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
  });

  test('header deadline aborts the HTTP connection', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final connected = Completer<void>();
    final disconnected = Completer<void>();
    server.listen((request) async {
      await request.drain<void>();
      final socket = await request.response.detachSocket(writeHeaders: false);
      socket.listen((_) {}, onDone: disconnected.complete);
      connected.complete();
    });
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('http://127.0.0.1:${server.port}/mcp'),
      requestTimeout: const Duration(seconds: 1),
    );
    addTearDown(transport.close);
    final result = expectLater(
      transport.send(JsonRpcRequest(method: 'tools/list', id: 1)),
      throwsA(isA<MCPTransportException>()),
    );
    await connected.future.timeout(const Duration(seconds: 5));
    await result;
    await disconnected.future.timeout(const Duration(seconds: 2));
  });

  test('JSON response deadline cancels a silent response body', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      requestTimeout: const Duration(milliseconds: 20),
      client: _Client(
        (_) async => http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(transport.close);
    final pending = transport.send(JsonRpcRequest(method: 'tools/list', id: 1));
    final outcome = pending.then<Object?>(
      (value) => value,
      onError: (Object e) => e,
    );
    expect(
      await outcome.timeout(
        const Duration(seconds: 1),
        onTimeout: () => 'still pending',
      ),
      isA<MCPTransportException>(),
    );
    expect(cancelled, isTrue);
    await body.close();
  });

  test('authentication deadline prevents late request dispatch', () async {
    final token = Completer<String?>();
    var sends = 0;
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      requestTimeout: const Duration(milliseconds: 20),
      auth: MCPAuthConfiguration(
        resource: Uri.https('mcp.test', '/'),
        accessToken: () => token.future,
      ),
      client: _Client((_) async {
        sends++;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': {}})),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(transport.close);
    final pending = transport.send(JsonRpcRequest(method: 'tools/list', id: 1));
    final outcome = pending.then<Object?>(
      (value) => value,
      onError: (Object e) => e,
    );
    expect(
      await outcome.timeout(
        const Duration(seconds: 1),
        onTimeout: () => 'still pending',
      ),
      isA<MCPTransportException>(),
    );
    token.complete('late');
    await Future<void>.delayed(Duration.zero);
    expect(sends, 0);
  });
}

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
