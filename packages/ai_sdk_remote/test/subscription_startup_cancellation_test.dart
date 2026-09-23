import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('subscription cancellation interrupts unresolved auth', () async {
    final authStarted = Completer<void>();
    final auth = Completer<Map<String, String>>();
    final client = _CountingClient();
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://example.test/chat'),
      client: client,
      authHeaders: () {
        authStarted.complete();
        return auth.future;
      },
    );
    final subscription = transport
        .send(Conversation(id: 'c1', messages: const []))
        .listen((_) {});
    await authStarted.future;
    final cancelled = subscription.cancel();
    Object? cancellationError;
    try {
      await cancelled.timeout(const Duration(seconds: 1));
    } catch (error) {
      cancellationError = error;
    } finally {
      transport.dispose();
      auth.complete(const {});
      try {
        await cancelled;
      } catch (_) {}
      client.close();
    }
    expect(cancellationError, isNull);
    expect(client.requests, 0);
  });
}

class _CountingClient extends http.BaseClient {
  var requests = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    throw StateError('Cancelled authentication must not dispatch HTTP.');
  }
}
