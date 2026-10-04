import 'dart:async';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('close shuts down transport with a paused progress listener', () async {
    final transport = _CloseAwareTransport();
    final client = MCPClient(transport: transport);
    final progress = client.progress.listen((_) {});
    progress.pause();

    final closing = client.close();
    try {
      await Future<void>.delayed(Duration.zero);
      expect(transport.closed, isTrue);
      await closing;
    } finally {
      await progress.cancel();
      await closing;
    }
  });

  test('close shuts down transport with a paused resource listener', () async {
    final transport = _CloseAwareTransport();
    final client = MCPClient(transport: transport);
    final resource = client.subscribeResource('file:///paused').listen((_) {});
    resource.pause();
    await transport.subscribed.future;

    final closing = client.close();
    try {
      await Future<void>.delayed(Duration.zero);
      expect(transport.closed, isTrue);
      await closing;
    } finally {
      await resource.cancel();
      await closing;
    }
  });
}

class _CloseAwareTransport extends MCPTransport {
  final notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();
  final subscribed = Completer<void>();
  bool closed = false;

  @override
  Stream<Map<String, dynamic>> get notifications =>
      notificationsController.stream;

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    if (request.method == 'initialize') {
      return const JsonRpcResponse(
        result: {'protocolVersion': '2025-06-18', 'capabilities': {}},
      );
    }
    if (request.method == 'resources/subscribe' && !subscribed.isCompleted) {
      subscribed.complete();
    }
    return const JsonRpcResponse(result: {});
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {}

  @override
  Future<void> close() async {
    closed = true;
    await notificationsController.close();
  }
}
