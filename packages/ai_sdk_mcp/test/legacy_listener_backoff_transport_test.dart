import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'GET failures retry with transport-level capped exponential delays',
    () async {
      late Duration Function() elapsed;
      final attempts = <Duration>[];
      final client = _Client((request) async {
        if (request.method == 'GET') {
          attempts.add(elapsed());
          throw StateError('GET unavailable');
        }
        return _initialized();
      });
      final transport = StreamableHttpClientTransport(
        url: Uri.https('mcp.test', '/'),
        listenerReconnectDelay: const Duration(seconds: 10),
        client: client,
      );
      await _initialize(transport);
      fakeAsync((async) {
        elapsed = () => async.elapsed;
        unawaited(transport.startNotificationListener());
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        async.flushMicrotasks();
        expect(attempts, [Duration.zero]);

        for (final (delay, expectedCount, expectedLast) in [
          (const Duration(seconds: 10), 2, const Duration(seconds: 10)),
          (const Duration(seconds: 20), 3, const Duration(seconds: 30)),
          (const Duration(seconds: 30), 4, const Duration(seconds: 60)),
          (const Duration(seconds: 30), 5, const Duration(seconds: 90)),
        ]) {
          async.elapse(delay - const Duration(microseconds: 1));
          async.flushMicrotasks();
          async.elapse(Duration.zero);
          async.flushMicrotasks();
          expect(attempts, hasLength(expectedCount - 1));
          async.elapse(const Duration(microseconds: 1));
          async.flushMicrotasks();
          async.elapse(Duration.zero);
          async.flushMicrotasks();
          expect(attempts, hasLength(expectedCount));
          expect(attempts.last, expectedLast);
        }
      });
      await transport.close();
    },
  );

  test('an SSE notification resets transport retry delay', () async {
    final secondGet = Completer<void>();
    final thirdGet = Completer<void>();
    final receivedNotification = Completer<void>();
    final listener = StreamController<List<int>>();
    const reconnectDelay = Duration(seconds: 1);
    final reconnectDelays = <Duration>[];
    var gets = 0;
    final client = _Client((request) async {
      if (request.method == 'GET') {
        gets++;
        if (gets == 1) {
          throw StateError('GET unavailable');
        }
        if (gets == 3) {
          thirdGet.complete();
          throw StateError('GET unavailable');
        }
        secondGet.complete();
        return _response(listener.stream, 200, sse: true);
      }
      return _initialized();
    });
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      listenerReconnectDelay: reconnectDelay,
      client: client,
    );
    await _initialize(transport);
    await runZoned(
      () async {
        transport.notifications.listen((_) => receivedNotification.complete());
        await transport.startNotificationListener();
        await secondGet.future.timeout(const Duration(seconds: 5));
        listener.add(_event());
        await receivedNotification.future.timeout(const Duration(seconds: 5));
        await listener.close();
        await thirdGet.future.timeout(const Duration(seconds: 5));
        expect(reconnectDelays.take(2), [reconnectDelay, reconnectDelay]);
        await transport.close();
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          if (duration == reconnectDelay ||
              duration == const Duration(seconds: 2)) {
            reconnectDelays.add(duration);
            return parent.createTimer(zone, Duration.zero, callback);
          }
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
  });

  test('closing transport cancels its scheduled GET retry', () async {
    var gets = 0;
    final client = _Client((request) async {
      if (request.method == 'GET') {
        gets++;
        throw StateError('GET unavailable');
      }
      return _initialized();
    });
    final transport = StreamableHttpClientTransport(
      url: Uri.https('mcp.test', '/'),
      listenerReconnectDelay: const Duration(seconds: 10),
      client: client,
    );
    await _initialize(transport);
    fakeAsync((async) {
      unawaited(transport.startNotificationListener());
      async.flushMicrotasks();
      expect(gets, 1);
      unawaited(transport.close());
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(gets, 1);
    });
  });
}

Future<void> _initialize(StreamableHttpClientTransport transport) async {
  await transport.send(JsonRpcRequest(method: 'initialize', id: 1));
  transport.setProtocolVersion('2025-06-18');
}

http.StreamedResponse _initialized() => http.StreamedResponse(
  Stream.value(
    utf8.encode(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'protocolVersion': '2025-06-18'},
      }),
    ),
  ),
  200,
  headers: {'content-type': 'application/json', 'mcp-session-id': 'session-1'},
);

http.StreamedResponse _response(
  Stream<List<int>> body,
  int status, {
  bool sse = false,
}) => http.StreamedResponse(
  body,
  status,
  headers: {'content-type': sse ? 'text/event-stream' : 'application/json'},
);

List<int> _event() => utf8.encode(
  'data: ${jsonEncode({
    'jsonrpc': '2.0',
    'method': 'notifications/message',
    'params': {'value': 'activity'},
  })}\n\n',
);

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
