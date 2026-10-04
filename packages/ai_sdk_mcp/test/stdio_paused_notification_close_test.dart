import 'dart:async';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('close completes while a notification listener is paused', () async {
    final transport = StdioMCPTransport(command: 'unused');
    final notifications = transport.notifications.listen((_) {});
    notifications.pause();
    var completed = false;
    final closing = transport.close().then((_) => completed = true);

    try {
      await Future<void>.delayed(Duration.zero);
      expect(completed, isTrue);
      await closing;
    } finally {
      await notifications.cancel();
      await closing;
    }
  });
}
