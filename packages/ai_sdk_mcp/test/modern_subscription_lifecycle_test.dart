import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test(
    'modern subscription reconnects after EOF and delivers later updates',
    () async {
      final client = _SubscriptionClient();
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('https://mcp.test/'),
        client: client,
        requestTimeout: const Duration(seconds: 1),
        listenerReconnectDelay: const Duration(milliseconds: 20),
      );
      final mcp = MCPClient(
        transport: transport,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(mcp.close);
      addTearDown(client.close);

      final updated = Completer<MCPResourceContent>();
      final updates = mcp.subscribeResource('file:///tmp/a').listen((value) {
        if (!updated.isCompleted) updated.complete(value);
      });

      final value = await updated.future.timeout(const Duration(seconds: 2));
      expect(client.listenRequests, 2);
      expect(value.uri, 'file:///tmp/a');
      expect(value.text, 'recovered');

      await updates.cancel();
      await client.activeSubscriptionCancelled.future.timeout(
        const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(client.listenRequests, 2, reason: 'cancel must stop reconnects');
    },
  );

  test(
    'repeated acknowledged EOF uses backoff instead of a hot loop',
    () async {
      final client = _SubscriptionClient(emitRecovery: false);
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('https://mcp.test/'),
        client: client,
        requestTimeout: const Duration(seconds: 1),
        listenerReconnectDelay: const Duration(milliseconds: 40),
      );
      final mcp = MCPClient(
        transport: transport,
        protocolMode: MCPProtocolMode.modern,
      );
      addTearDown(mcp.close);
      addTearDown(client.close);

      final updates = mcp.subscribeResource('file:///tmp/a').listen((_) {});
      await client.secondListenRequest.future.timeout(
        const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(client.listenRequests, 2);
      await client.thirdListenRequest.future.timeout(
        const Duration(seconds: 1),
      );
      expect(client.listenRequests, 3);
      await updates.cancel();
    },
  );

  test(
    'cancel during reconnect startup prevents late acknowledgement resurrection',
    () async {
      final client = _SubscriptionClient(
        emitRecovery: false,
        holdSecondRequest: true,
      );
      final transport = StreamableHttpClientTransport(
        url: Uri.parse('https://mcp.test/'),
        client: client,
        requestTimeout: const Duration(seconds: 1),
        listenerReconnectDelay: const Duration(milliseconds: 10),
      )..setProtocolVersion('2026-07-28');
      final request = JsonRpcRequest(
        method: 'subscriptions/listen',
        id: 77,
        params: const {
          'notifications': {
            'resourceSubscriptions': ['file:///tmp/a'],
          },
        },
      );
      addTearDown(transport.close);

      await transport.send(request);
      await client.secondListenRequest.future.timeout(
        const Duration(seconds: 1),
      );
      await transport.cancelSubscription(77);
      client.releaseSecondRequest();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(client.listenRequests, 2);
      await transport.send(request);
      expect(client.listenRequests, 3);
      await transport.cancelSubscription(77);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(client.listenRequests, 3, reason: 'the reused ID is cancelled');
    },
  );

  test('cancel aborts a request still waiting for its HTTP response', () async {
    final client = _SubscriptionClient(holdFirstRequest: true);
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: client,
      requestTimeout: const Duration(seconds: 1),
    )..setProtocolVersion('2026-07-28');
    addTearDown(transport.close);
    addTearDown(client.close);

    final request = JsonRpcRequest(
      method: 'subscriptions/listen',
      id: 88,
      params: const {
        'notifications': {
          'resourceSubscriptions': ['file:///tmp/a'],
        },
      },
    );
    final pending = expectLater(
      transport.send(request),
      throwsA(
        isA<MCPTransportException>().having(
          (error) => error.context,
          'context',
          'subscription cancelled',
        ),
      ),
    );
    await client.firstListenRequest.future.timeout(const Duration(seconds: 1));
    await transport.cancelSubscription(88);
    await pending;

    client.releaseFirstRequest();
    await transport.send(request);
    expect(client.listenRequests, 2);
    await transport.cancelSubscription(88);
  });

  test('a pre-ack stream error retires the response before retrying', () async {
    final client = _SubscriptionClient(holdFirstStream: true);
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: client,
      requestTimeout: const Duration(seconds: 1),
    )..setProtocolVersion('2026-07-28');
    addTearDown(transport.close);
    addTearDown(client.close);

    final request = JsonRpcRequest(
      method: 'subscriptions/listen',
      id: 99,
      params: const {
        'notifications': {
          'resourceSubscriptions': ['file:///tmp/a'],
        },
      },
    );
    final failedAttempt = expectLater(
      transport.send(request),
      throwsA(isA<MCPException>()),
    );
    await client.firstListenRequest.future.timeout(const Duration(seconds: 1));
    client.failFirstRequestStream();
    await failedAttempt;
    await client.firstPendingStreamCancelled.future.timeout(
      const Duration(seconds: 1),
    );

    await transport.send(request);
    expect(client.listenRequests, 2);
    await transport.cancelSubscription(99);
  });

  test(
    'terminal JSON and SSE responses stop subscription reconnects',
    () async {
      for (final terminalSse in [false, true]) {
        final client = _SubscriptionClient(
          terminalJson: !terminalSse,
          terminalSse: terminalSse,
        );
        final transport = StreamableHttpClientTransport(
          url: Uri.parse('https://mcp.test/'),
          client: client,
          listenerReconnectDelay: const Duration(milliseconds: 20),
        )..setProtocolVersion('2026-07-28');
        addTearDown(transport.close);
        addTearDown(client.close);

        final request = JsonRpcRequest(
          method: 'subscriptions/listen',
          id: terminalSse ? 101 : 100,
          params: const {
            'notifications': {
              'resourceSubscriptions': ['file:///tmp/a'],
            },
          },
        );
        final result = await transport.send(request);
        if (terminalSse) {
          expect(
            result.isError,
            isFalse,
            reason: 'the acknowledgement resolves send',
          );
          await client.terminalStreamCancelled.future.timeout(
            const Duration(seconds: 1),
          );
        } else {
          expect(result.isError, isTrue);
        }
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(client.listenRequests, 1);
      }
    },
  );

  test('reconnect survives HTTP 408 and 503 before recovering', () async {
    final client = _SubscriptionClient(reconnectHttpStatuses: [408, 503]);
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: client,
      listenerReconnectDelay: const Duration(milliseconds: 5),
    )..setProtocolVersion('2026-07-28');
    addTearDown(transport.close);
    addTearDown(client.close);

    final updated = Completer<void>();
    final notifications = transport.notifications.listen((message) {
      if (message['method'] == 'notifications/resources/updated' &&
          !updated.isCompleted) {
        updated.complete();
      }
    });
    addTearDown(notifications.cancel);

    final request = JsonRpcRequest(
      method: 'subscriptions/listen',
      id: 102,
      params: const {
        'notifications': {
          'resourceSubscriptions': ['file:///tmp/a'],
        },
      },
    );
    await transport.send(request);
    await updated.future.timeout(const Duration(seconds: 2));

    expect(client.listenRequests, 4);
    expect(client.reconnectStatuses, [408, 503]);
    await transport.cancelSubscription(102);
  });

  test('replacing an in-flight subscription ignores the old stream', () async {
    final client = _SubscriptionClient(holdFirstStream: true);
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: client,
    )..setProtocolVersion('2026-07-28');
    addTearDown(transport.close);
    addTearDown(client.close);

    var updateCount = 0;
    final updated = Completer<void>();
    final notifications = transport.notifications.listen((message) {
      if (message['method'] == 'notifications/resources/updated') {
        updateCount++;
        if (!updated.isCompleted) updated.complete();
      }
    });
    addTearDown(notifications.cancel);

    final oldRequest = JsonRpcRequest(
      method: 'subscriptions/listen',
      id: 103,
      params: const {
        'notifications': {
          'resourceSubscriptions': ['file:///tmp/old'],
        },
      },
    );
    final oldAttempt = expectLater(
      transport.send(oldRequest),
      throwsA(isA<MCPException>()),
    );
    await client.firstListenRequest.future.timeout(const Duration(seconds: 1));
    final replacement = JsonRpcRequest(
      method: 'subscriptions/listen',
      id: 103,
      params: const {
        'notifications': {
          'resourceSubscriptions': ['file:///tmp/new'],
        },
      },
    );
    await transport.send(replacement);
    await oldAttempt;
    await client.firstPendingStreamCancelled.future.timeout(
      const Duration(seconds: 1),
    );
    await updated.future.timeout(const Duration(seconds: 1));

    client.emitLateOldUpdate();
    await Future<void>.delayed(Duration.zero);
    expect(updateCount, 1);
    await transport.cancelSubscription(103);
  });

  test('close aborts a subscription while HTTP headers are pending', () async {
    final client = _SubscriptionClient(holdFirstRequest: true);
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: client,
    )..setProtocolVersion('2026-07-28');
    addTearDown(client.close);

    final request = JsonRpcRequest(
      method: 'subscriptions/listen',
      id: 104,
      params: const {
        'notifications': {
          'resourceSubscriptions': ['file:///tmp/a'],
        },
      },
    );
    final pending = expectLater(
      transport.send(request),
      throwsA(isA<MCPTransportException>()),
    );
    await client.firstListenRequest.future.timeout(const Duration(seconds: 1));
    await transport.close();
    await pending;
    client.releaseFirstRequest();
    expect(client.listenRequests, 1);
  });

  test('closing during reconnect backoff cancels the pending reopen', () async {
    final client = _SubscriptionClient(emitRecovery: false);
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.test/'),
      client: client,
      requestTimeout: const Duration(seconds: 1),
      listenerReconnectDelay: const Duration(milliseconds: 100),
    );
    final mcp = MCPClient(
      transport: transport,
      protocolMode: MCPProtocolMode.modern,
    );
    addTearDown(client.close);

    final updates = mcp.subscribeResource('file:///tmp/a').listen((_) {});
    await client.firstListenRequest.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await mcp.close();
    await updates.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(client.listenRequests, 1);
  });
}

class _SubscriptionClient extends http.BaseClient {
  _SubscriptionClient({
    this.emitRecovery = true,
    this.holdSecondRequest = false,
    this.holdFirstRequest = false,
    this.holdFirstStream = false,
    this.terminalJson = false,
    this.terminalSse = false,
    this.reconnectHttpStatuses = const [],
  });

  final bool emitRecovery;
  final bool holdSecondRequest;
  final bool holdFirstRequest;
  final bool holdFirstStream;
  final bool terminalJson;
  final bool terminalSse;
  final List<int> reconnectHttpStatuses;
  final firstListenRequest = Completer<void>();
  final secondListenRequest = Completer<void>();
  final thirdListenRequest = Completer<void>();
  final heldFirstResponse = Completer<http.StreamedResponse>();
  final heldSecondResponse = Completer<http.StreamedResponse>();
  final firstPendingStreamCancelled = Completer<void>();
  final terminalStreamCancelled = Completer<void>();
  final activeSubscriptionCancelled = Completer<void>();
  final reconnectStatuses = <int>[];
  StreamController<List<int>>? _firstPendingStream;
  var listenRequests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body =
        jsonDecode((request as http.Request).body) as Map<String, dynamic>;
    final id = body['id'] as int;
    final method = body['method'];
    if (method == 'server/discover') {
      return _jsonResponse(id, {
        'supportedVersions': ['2026-07-28'],
      });
    }
    if (method == 'subscriptions/listen') {
      listenRequests++;
      if (!firstListenRequest.isCompleted) firstListenRequest.complete();
      if (listenRequests == 2 && !secondListenRequest.isCompleted) {
        secondListenRequest.complete();
      }
      if (listenRequests == 3 && !thirdListenRequest.isCompleted) {
        thirdListenRequest.complete();
      }
      final ack = _sse({
        'jsonrpc': '2.0',
        'method': 'notifications/subscriptions/acknowledged',
        'params': {
          '_meta': {'io.modelcontextprotocol/subscriptionId': id},
        },
      });
      if (listenRequests > 1 &&
          listenRequests <= reconnectHttpStatuses.length + 1) {
        final status = reconnectHttpStatuses[listenRequests - 2];
        reconnectStatuses.add(status);
        return http.StreamedResponse(
          Stream<List<int>>.value(utf8.encode('temporary failure')),
          status,
          headers: {'content-type': 'text/plain'},
        );
      }
      if (terminalJson && listenRequests == 1) {
        return http.StreamedResponse(
          Stream<List<int>>.value(
            utf8.encode(
              jsonEncode({
                'jsonrpc': '2.0',
                'id': id,
                'error': {'code': -32600, 'message': 'subscription ended'},
              }),
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (terminalSse && listenRequests == 1) {
        final stream = StreamController<List<int>>(
          onCancel: () {
            if (!terminalStreamCancelled.isCompleted) {
              terminalStreamCancelled.complete();
            }
          },
        );
        scheduleMicrotask(() {
          stream
            ..add(utf8.encode(ack))
            ..add(
              utf8.encode(
                _sse({
                  'jsonrpc': '2.0',
                  'id': id,
                  'error': {'code': -32600, 'message': 'subscription ended'},
                }),
              ),
            );
        });
        return _sseResponse(stream.stream);
      }
      if (listenRequests == 1 || !emitRecovery) {
        if (holdFirstStream && listenRequests == 1) {
          _firstPendingStream = StreamController<List<int>>(
            onCancel: () {
              if (!firstPendingStreamCancelled.isCompleted) {
                firstPendingStreamCancelled.complete();
              }
            },
          );
          return _sseResponse(_firstPendingStream!.stream);
        }
        if (holdFirstRequest && listenRequests == 1) {
          return heldFirstResponse.future;
        }
        if (holdSecondRequest && listenRequests == 2) {
          return heldSecondResponse.future;
        }
        return _sseResponse(Stream<List<int>>.value(utf8.encode(ack)));
      }

      final stream = StreamController<List<int>>(
        onCancel: () {
          if (!activeSubscriptionCancelled.isCompleted) {
            activeSubscriptionCancelled.complete();
          }
        },
      );
      scheduleMicrotask(() {
        stream
          ..add(utf8.encode(ack))
          ..add(
            utf8.encode(
              _sse({
                'jsonrpc': '2.0',
                'method': 'notifications/resources/updated',
                'params': {'uri': 'file:///tmp/a'},
              }),
            ),
          );
      });
      return _sseResponse(stream.stream);
    }
    if (method == 'resources/read') {
      return _jsonResponse(id, {
        'resultType': 'complete',
        'contents': [
          {
            'uri': 'file:///tmp/a',
            'mimeType': 'text/plain',
            'text': 'recovered',
          },
        ],
      });
    }
    return _jsonResponse(id, {'resultType': 'complete'});
  }

  void releaseSecondRequest() {
    heldSecondResponse.complete(
      _sseResponse(
        Stream<List<int>>.value(
          utf8.encode(
            _sse({
              'jsonrpc': '2.0',
              'method': 'notifications/subscriptions/acknowledged',
              'params': {
                '_meta': {'io.modelcontextprotocol/subscriptionId': 77},
              },
            }),
          ),
        ),
      ),
    );
  }

  void releaseFirstRequest() {
    heldFirstResponse.complete(
      _sseResponse(
        Stream<List<int>>.value(
          utf8.encode(
            _sse({
              'jsonrpc': '2.0',
              'method': 'notifications/subscriptions/acknowledged',
              'params': {
                '_meta': {'io.modelcontextprotocol/subscriptionId': 88},
              },
            }),
          ),
        ),
      ),
    );
  }

  void failFirstRequestStream() {
    _firstPendingStream!.addError(StateError('response stream failed'));
  }

  void emitLateOldUpdate() {
    _firstPendingStream!.add(
      utf8.encode(
        _sse({
          'jsonrpc': '2.0',
          'method': 'notifications/resources/updated',
          'params': {'uri': 'file:///tmp/old'},
        }),
      ),
    );
  }

  @override
  void close() {}

  http.StreamedResponse _jsonResponse(int id, Map<String, dynamic> result) {
    return http.StreamedResponse(
      Stream<List<int>>.value(
        utf8.encode(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result})),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  http.StreamedResponse _sseResponse(Stream<List<int>> body) =>
      http.StreamedResponse(
        body,
        200,
        headers: {'content-type': 'text/event-stream'},
      );

  String _sse(Map<String, dynamic> message) =>
      'data: ${jsonEncode(message)}\n\n';
}
