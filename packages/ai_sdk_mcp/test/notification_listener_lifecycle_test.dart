import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'delayed old listener cancellation preserves the replacement listener',
    () async {
      final cancelling = Completer<void>();
      final releaseCancellation = Completer<void>();
      final replacementStarted = Completer<void>();
      var replacementCancelled = false;
      var gets = 0;
      var initializes = 0;
      final oldBody = StreamController<List<int>>(
        onCancel: () {
          cancelling.complete();
          return releaseCancellation.future;
        },
      );
      final newBody = StreamController<List<int>>(
        onCancel: () => replacementCancelled = true,
      );
      final transport = StreamableHttpClientTransport(
        url: Uri.https('mcp.test', '/'),
        client: _Client((request) async {
          if (request.method == 'GET') {
            gets++;
            if (gets == 1) return _sse(oldBody.stream);
            replacementStarted.complete();
            return _sse(newBody.stream);
          }
          if (request.method == 'DELETE') {
            return http.StreamedResponse(const Stream.empty(), 204);
          }
          return _initialized(++initializes);
        }),
      );
      addTearDown(transport.close);
      await _start(transport, 1);
      await Future<void>.delayed(Duration.zero);
      final reset = transport.resetHandshakeState();
      await cancelling.future;
      await _start(transport, 2);
      await replacementStarted.future;
      await Future<void>.delayed(Duration.zero);
      releaseCancellation.complete();
      await reset;
      await Future<void>.delayed(Duration.zero);
      expect(replacementCancelled, isFalse);
      await transport.close();
      await oldBody.close();
      await newBody.close();
    },
  );

  test(
    'resetting the handshake rejects a late listener from the old session',
    () async {
      final firstGet = Completer<void>();
      final lateResponse = Completer<http.StreamedResponse>();
      final currentGet = Completer<void>();
      var cancelled = false;
      final staleBody = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      final currentBody = StreamController<List<int>>();
      final getSessions = <String?>[];
      var initializes = 0;
      final transport = StreamableHttpClientTransport(
        url: Uri.https('mcp.test', '/'),
        client: _Client((request) async {
          if (request.method == 'GET') {
            getSessions.add(request.headers['Mcp-Session-Id']);
            if (getSessions.length == 1) {
              firstGet.complete();
              return lateResponse.future;
            }
            currentGet.complete();
            return _sse(currentBody.stream);
          }
          if (request.method == 'DELETE') {
            return http.StreamedResponse(const Stream.empty(), 204);
          }
          initializes++;
          return _initialized(initializes);
        }),
      );
      addTearDown(transport.close);
      await _start(transport, 1);
      await firstGet.future;
      await transport.resetHandshakeState();
      await _start(transport, 2);
      lateResponse.complete(_sse(staleBody.stream));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await currentGet.future.timeout(const Duration(seconds: 1));
      expect(getSessions, ['session-1', 'session-2']);
      await transport.close();
      await staleBody.close();
      await currentBody.close();
    },
  );

  test('an error cancels the old listener before reconnecting', () async {
    final firstGet = Completer<void>();
    final secondGet = Completer<void>();
    var cancelled = false;
    var gets = 0;
    final oldBody = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final newBody = StreamController<List<int>>();
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      listenerReconnectDelay: Duration.zero,
      client: _Client((request) async {
        if (request.method == 'GET') {
          gets++;
          if (gets == 1) {
            firstGet.complete();
            return _sse(oldBody.stream);
          }
          secondGet.complete();
          return _sse(newBody.stream);
        }
        if (request.method == 'DELETE') {
          return http.StreamedResponse(const Stream.empty(), 204);
        }
        return _initialized(1);
      }),
    );
    addTearDown(transport.close);
    final seen = <String>[];
    final subscription = transport.notifications.listen(
      (message) => seen.add((message['params'] as Map)['value'] as String),
    );
    addTearDown(subscription.cancel);
    await _start(transport, 1);
    await firstGet.future;
    oldBody.addError(StateError('listener failed'));
    await secondGet.future.timeout(const Duration(seconds: 1));
    expect(cancelled, isTrue);
    oldBody.add(_event('stale'));
    newBody.add(_event('current'));
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['current']);
    await transport.close();
    await oldBody.close();
    await newBody.close();
  });
}

Future<void> _start(StreamableHttpClientTransport transport, int id) async {
  await transport.send(JsonRpcRequest(method: 'initialize', id: id));
  transport.setProtocolVersion('2025-06-18');
  await transport.startNotificationListener();
}

http.StreamedResponse _initialized(int session) => http.StreamedResponse(
  Stream.value(
    utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': session, 'result': {}})),
  ),
  200,
  headers: {
    'content-type': 'application/json',
    'mcp-session-id': 'session-$session',
  },
);

http.StreamedResponse _sse(Stream<List<int>> stream) => http.StreamedResponse(
  stream,
  200,
  headers: {'content-type': 'text/event-stream'},
);

List<int> _event(String value) => utf8.encode(
  'data: ${jsonEncode({
    'jsonrpc': '2.0',
    'method': 'notifications/message',
    'params': {'value': value},
  })}\n\n',
);

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
