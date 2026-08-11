import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

class _PublicApiTransport implements MCPTransport {
  JsonRpcRequest? lastRequest;
  JsonRpcNotification? lastNotification;

  @override
  Stream<Map<String, dynamic>> get notifications => const Stream.empty();

  @override
  Future<JsonRpcResponse> send(JsonRpcRequest request) async {
    lastRequest = request;
    return JsonRpcResponse(result: {'ok': true}, id: request.id);
  }

  @override
  Future<void> sendNotification(JsonRpcNotification notification) async {
    lastNotification = notification;
  }

  @override
  Future<void> close() async {}
}

void main() {
  test(
    'barrel exports transport extension primitives for custom transports',
    () async {
      final transport = _PublicApiTransport();

      final response = await transport.send(
        JsonRpcRequest(method: 'ping', id: 7),
      );
      await transport.sendNotification(
        JsonRpcNotification(method: 'notifications/initialized'),
      );

      expect(response.id, 7);
      expect(response.result, {'ok': true});
      expect(transport.lastRequest?.method, 'ping');
      expect(transport.lastNotification?.method, 'notifications/initialized');
    },
  );
}
