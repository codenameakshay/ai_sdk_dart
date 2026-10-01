import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:flutter_test/flutter_test.dart';

class _SilentTransport extends RemoteConversationTransport {
  _SilentTransport() : super(endpoint: Uri.parse('http://127.0.0.1/chat'));
  final tokens = <RemoteCancellationToken>[];
  @override
  Stream<Conversation> send(
    Conversation conversation, {
    RemoteCancellationToken? cancellation,
  }) async* {
    tokens.add(cancellation!);
    await cancellation.whenCancelled;
  }

  @override
  void dispose() {
    for (final token in tokens) {
      token.cancel();
    }
    super.dispose();
  }
}

void main() {
  test(
    'simultaneous remote sends cannot leave a superseded request active',
    () async {
      final transport = _SilentTransport();
      final backend = RemoteConversationBackend(
        transport: transport,
        initial: Conversation(id: 'race', messages: const []),
      );
      final first = backend.send('first');
      final second = backend.send('second');
      addTearDown(() async {
        await backend.dispose();
        await Future.wait([first, second]);
      });
      await Future<void>.delayed(Duration.zero);
      expect(transport.tokens, hasLength(1));
      await backend.interrupt();
      await Future.wait([first, second]);
      expect(transport.tokens.single.isCancelled, isTrue);
    },
  );

  test(
    'simultaneous local sends cannot publish a superseded user turn',
    () async {
      final backend = LocalConversationBackend(
        agent: ToolLoopAgent(
          model: MockLanguageModelV4(response: [mockText('latest')]),
        ),
        initial: Conversation(id: 'race', messages: const []),
      );
      addTearDown(backend.dispose);
      await Future.wait([backend.send('first'), backend.send('second')]);
      expect(
        backend.conversation.messages
            .where((message) => message.role == ConversationRole.user)
            .map((message) => (message.parts.single as TextPart).text),
        ['second'],
      );
      expect(
        backend.conversation.messages.last.status,
        ConversationMessageStatus.complete,
      );
    },
  );
}
