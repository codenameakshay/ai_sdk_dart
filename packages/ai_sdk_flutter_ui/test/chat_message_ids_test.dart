import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

String Function() sequentialIds() {
  var n = 0;
  return () => 'm${++n}';
}

List<String> idsOf(ChatController c) => [for (final m in c.chatMessages) m.id];

ToolLoopAgent _textAgent({
  required String text,
  String provider = 'mock',
  String modelId = 'mock-language-model',
  LanguageModelV4FinishReason finishReason = LanguageModelV4FinishReason.stop,
}) {
  return ToolLoopAgent(
    model: MockLanguageModelV4(
      response: [mockText(text)],
      provider: provider,
      modelId: modelId,
      finishReason: finishReason,
    ),
  );
}

void main() {
  group('ChatController.chatMessages', () {
    test(
      'send assigns fresh ids and records the assistant turn metadata',
      () async {
        final c = ChatController(generateId: sequentialIds());
        addTearDown(c.dispose);

        await c.sendMessage(
          agent: _textAgent(
            text: 'hi',
            provider: 'anthropic',
            modelId: 'claude-opus',
          ),
          text: 'hello',
        );
        await pumpUntil(
          () => c.status == ChatStatus.ready && c.messages.length == 2,
        );

        expect(idsOf(c), ['m1', 'm2']);
        expect(c.chatMessages[0].message.role, ModelMessageRole.user);
        expect(c.chatMessages[0].status, ConversationMessageStatus.complete);
        expect(c.chatMessages[0].provider, isNull);
        expect(c.chatMessages[0].modelId, isNull);
        expect(c.chatMessages[0].finishReason, isNull);
        expect(c.chatMessages[1].message.content, 'hi');
        expect(c.chatMessages[1].provider, 'anthropic');
        expect(c.chatMessages[1].modelId, 'claude-opus');
        expect(
          c.chatMessages[1].finishReason,
          LanguageModelV4FinishReason.stop,
        );
        expect(c.chatMessages[1].status, ConversationMessageStatus.complete);
        expect(identical(c.chatMessages[1].message, c.messages[1]), isTrue);
      },
    );

    test('finishReason length is reported on the assistant turn', () async {
      final c = ChatController(generateId: sequentialIds());
      addTearDown(c.dispose);

      await c.sendMessage(
        agent: _textAgent(
          text: 'cut off',
          finishReason: LanguageModelV4FinishReason.length,
        ),
        text: 'long',
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 2,
      );

      expect(idsOf(c), ['m1', 'm2']);
      expect(
        c.chatMessages[1].finishReason,
        LanguageModelV4FinishReason.length,
      );
    });

    test('initial messages and append get ids without metadata', () async {
      final c = ChatController(
        initialMessages: [
          ModelMessage(role: ModelMessageRole.user, content: 'earlier'),
        ],
        generateId: sequentialIds(),
      );
      addTearDown(c.dispose);

      expect(idsOf(c), ['m1']);

      c.append(ModelMessage(role: ModelMessageRole.user, content: 'note'));
      expect(idsOf(c), ['m1', 'm2']);
      expect(c.chatMessages[1].provider, isNull);
      expect(c.chatMessages[1].modelId, isNull);

      await c.sendMessage(
        agent: _textAgent(text: 'ok', provider: 'openai', modelId: 'gpt-x'),
        text: 'next',
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 4,
      );

      expect(idsOf(c), ['m1', 'm2', 'm3', 'm4']);
      expect(c.chatMessages[3].modelId, 'gpt-x');
    });

    test(
      'stop with partial text commits an interrupted assistant entry',
      () async {
        final c = ChatController(generateId: sequentialIds());
        addTearDown(c.dispose);
        final model = HoldingTextModel('partial');
        addTearDown(model.finish);

        unawaited(
          c.sendMessage(
            agent: ToolLoopAgent(model: model),
            text: 'q',
          ),
        );
        await pumpUntil(() => c.streamingContent.isNotEmpty);
        await c.stop();

        expect(idsOf(c), ['m1', 'm2']);
        expect(c.chatMessages[1].message.content, 'partial');
        expect(c.chatMessages[1].status, ConversationMessageStatus.interrupted);
        expect(c.chatMessages[1].provider, 'mock');
        expect(c.chatMessages[1].modelId, 'holding-text');
        expect(c.chatMessages[1].finishReason, isNull);

        await c.sendMessage(
          agent: _textAgent(text: 'next', provider: 'openai', modelId: 'gpt-x'),
          text: 'again',
        );
        await pumpUntil(
          () => c.status == ChatStatus.ready && c.messages.length == 4,
        );

        expect(idsOf(c), ['m1', 'm2', 'm3', 'm4']);
        expect(c.chatMessages[1].status, ConversationMessageStatus.interrupted);
        expect(c.chatMessages[1].modelId, 'holding-text');
        expect(c.chatMessages[3].status, ConversationMessageStatus.complete);
        expect(c.chatMessages[3].modelId, 'gpt-x');
        expect(
          c.chatMessages[3].finishReason,
          LanguageModelV4FinishReason.stop,
        );
      },
    );

    test('stop with no buffered text commits nothing', () async {
      final c = ChatController(generateId: sequentialIds());
      addTearDown(c.dispose);
      final model = HoldingTextModel('late');
      addTearDown(model.finish);

      unawaited(
        c.sendMessage(
          agent: ToolLoopAgent(model: model),
          text: 'q',
        ),
      );
      await c.stop();
      await pumpUntil(() => false, tries: 20);

      expect(idsOf(c), ['m1']);
      expect(c.status, ChatStatus.ready);
      expect(
        c.chatMessages.any(
          (m) => m.status == ConversationMessageStatus.interrupted,
        ),
        isFalse,
      );

      await c.sendMessage(
        agent: _textAgent(text: 'next', provider: 'openai', modelId: 'gpt-x'),
        text: 'again',
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 3,
      );

      expect(idsOf(c), ['m1', 'm2', 'm3']);
      expect(c.chatMessages[2].status, ConversationMessageStatus.complete);
      expect(c.chatMessages[2].modelId, 'gpt-x');
      expect(
        c.chatMessages.any(
          (m) => m.status == ConversationMessageStatus.interrupted,
        ),
        isFalse,
      );
    });

    test('a superseded send never commits its answer', () async {
      final c = ChatController(generateId: sequentialIds());
      addTearDown(c.dispose);
      final slow = HoldingTextModel('stale');

      unawaited(
        c.sendMessage(
          agent: ToolLoopAgent(model: slow),
          text: 'q1',
        ),
      );
      await pumpUntil(() => c.streamingContent.isNotEmpty);
      await c.sendMessage(
        agent: _textAgent(text: 'fast', provider: 'openai', modelId: 'gpt-x'),
        text: 'q2',
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 3,
      );
      slow.finish();
      await pumpUntil(() => false, tries: 20);

      expect(idsOf(c), ['m1', 'm2', 'm3']);
      expect(c.chatMessages[2].message.content, 'fast');
      expect(c.chatMessages[2].modelId, 'gpt-x');
      expect(c.chatMessages[2].status, ConversationMessageStatus.complete);
    });

    test('reload and regenerate give the new answer a new id', () async {
      final c = ChatController(generateId: sequentialIds());
      addTearDown(c.dispose);

      await c.sendMessage(
        agent: _textAgent(text: 'from a', provider: 'a', modelId: 'a1'),
        text: 'q',
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 2,
      );
      expect(idsOf(c), ['m1', 'm2']);

      await c.reload(
        agent: _textAgent(text: 'from b', provider: 'b', modelId: 'b1'),
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 2,
      );
      expect(idsOf(c), ['m1', 'm3']);
      expect(c.chatMessages[1].modelId, 'b1');
      expect(c.chatMessages[1].provider, 'b');

      await c.regenerate();
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.chatMessages[1].id == 'm4',
      );
      expect(idsOf(c), ['m1', 'm4']);
      expect(c.chatMessages[1].modelId, 'a1');
    });

    test(
      'reload after an interrupted stop replaces the interrupted entry',
      () async {
        final c = ChatController(generateId: sequentialIds());
        addTearDown(c.dispose);
        final model = HoldingTextModel('partial');
        addTearDown(model.finish);

        unawaited(
          c.sendMessage(
            agent: ToolLoopAgent(model: model),
            text: 'q',
          ),
        );
        await pumpUntil(() => c.streamingContent.isNotEmpty);
        await c.stop();
        expect(idsOf(c), ['m1', 'm2']);

        await c.reload(
          agent: _textAgent(
            text: 'fresh',
            provider: 'openai',
            modelId: 'gpt-x',
          ),
        );
        await pumpUntil(
          () => c.status == ChatStatus.ready && c.messages.length == 2,
        );

        expect(idsOf(c), ['m1', 'm3']);
        expect(c.chatMessages[1].message.content, 'fresh');
        expect(c.chatMessages[1].status, ConversationMessageStatus.complete);
        expect(
          c.chatMessages[1].finishReason,
          LanguageModelV4FinishReason.stop,
        );
      },
    );

    test('clear restores initial ids and never reuses old ids', () async {
      final c = ChatController(
        initialMessages: [
          ModelMessage(role: ModelMessageRole.user, content: 'earlier'),
        ],
        generateId: sequentialIds(),
      );
      addTearDown(c.dispose);

      await c.sendMessage(
        agent: _textAgent(text: 'ok'),
        text: 'q',
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 3,
      );
      expect(idsOf(c), ['m1', 'm2', 'm3']);

      c.clear();
      expect(idsOf(c), ['m1']);

      await c.sendMessage(
        agent: _textAgent(text: 'again'),
        text: 'q2',
      );
      await pumpUntil(
        () => c.status == ChatStatus.ready && c.messages.length == 3,
      );
      expect(idsOf(c), ['m1', 'm4', 'm5']);
    });

    test(
      'error commits no assistant entry and retry after error succeeds',
      () async {
        final c = ChatController(generateId: sequentialIds());
        addTearDown(c.dispose);

        await c.sendMessage(
          agent: erroringAgent(StateError('boom')),
          text: 'q',
        );
        await pumpUntil(() => c.status == ChatStatus.error);
        expect(idsOf(c), ['m1']);

        await c.reload(
          agent: _textAgent(text: 'recovered', provider: 'p', modelId: 'ok'),
        );
        await pumpUntil(
          () => c.status == ChatStatus.ready && c.messages.length == 2,
        );

        expect(idsOf(c), ['m1', 'm2']);
        expect(c.chatMessages[1].message.content, 'recovered');
        expect(c.chatMessages[1].modelId, 'ok');
        expect(c.chatMessages[1].status, ConversationMessageStatus.complete);
        expect(
          c.chatMessages[1].finishReason,
          LanguageModelV4FinishReason.stop,
        );
      },
    );

    test(
      'approval resume commits the final answer with the model metadata',
      () async {
        final c = ChatController(generateId: sequentialIds());
        addTearDown(c.dispose);
        final agent = approvalAgent(
          finalText: 'final answer',
          repeatCallAfterApproval: false,
        );

        await c.sendMessage(agent: agent, text: 'delete it');
        await pumpUntil(() => c.status == ChatStatus.awaitingApproval);
        expect(idsOf(c), ['m1']);

        c.addToolApprovalResponse(
          approvalId: c.pendingApprovalRequests.single.approvalId,
          approved: true,
        );
        await pumpUntil(() => c.status == ChatStatus.ready);

        expect(idsOf(c), ['m1', 'm2']);
        expect(c.chatMessages[1].message.content, 'final answer');
        expect(c.chatMessages[1].provider, 'mock');
        expect(c.chatMessages[1].modelId, 'queued');
        expect(
          c.chatMessages[1].finishReason,
          LanguageModelV4FinishReason.stop,
        );
      },
    );

    test('default generator produces 16-character unique ids', () {
      final c = ChatController(
        initialMessages: [
          ModelMessage(role: ModelMessageRole.user, content: 'a'),
          ModelMessage(role: ModelMessageRole.user, content: 'b'),
        ],
      );
      addTearDown(c.dispose);

      final ids = idsOf(c);
      expect(ids, hasLength(2));
      expect(ids[0], hasLength(16));
      expect(ids[1], hasLength(16));
      expect(ids[0] == ids[1], isFalse);
    });

    test('chatMessages is read-only', () {
      final c = ChatController(
        initialMessages: [
          ModelMessage(role: ModelMessageRole.user, content: 'a'),
        ],
        generateId: sequentialIds(),
      );
      addTearDown(c.dispose);

      expect(
        () => c.chatMessages.add(c.chatMessages.first),
        throwsUnsupportedError,
      );
    });

    test('ConversationChatController uses snapshot ids and statuses', () async {
      final backend = FakeConversationBackend(
        initial: Conversation(
          id: 'chat-1',
          messages: [
            ConversationMessage(
              id: 'u-1',
              role: ConversationRole.user,
              parts: [TextPart(id: 'p1', text: 'hi')],
            ),
            ConversationMessage(
              id: 'a-1',
              role: ConversationRole.assistant,
              status: ConversationMessageStatus.interrupted,
              parts: [TextPart(id: 'p2', text: 'par')],
            ),
          ],
        ),
      );
      final chat = ConversationChatController(ConversationController(backend));
      addTearDown(chat.dispose);

      expect(idsOf(chat), ['u-1', 'a-1']);
      expect(chat.chatMessages.map((m) => m.status).toList(), [
        ConversationMessageStatus.complete,
        ConversationMessageStatus.interrupted,
      ]);
      expect(chat.chatMessages[0].provider, isNull);
      expect(chat.chatMessages[1].provider, isNull);
      expect(chat.chatMessages[1].message.role, ModelMessageRole.assistant);

      backend.publish(
        Conversation(
          id: 'chat-1',
          messages: [
            ConversationMessage(
              id: 'u-1',
              role: ConversationRole.user,
              parts: [TextPart(id: 'p1', text: 'hi')],
            ),
            ConversationMessage(
              id: 'a-1',
              role: ConversationRole.assistant,
              status: ConversationMessageStatus.interrupted,
              parts: [TextPart(id: 'p2', text: 'par')],
            ),
            ConversationMessage(
              id: 'a-2',
              role: ConversationRole.assistant,
              parts: [TextPart(id: 'p3', text: 'full')],
            ),
          ],
        ),
      );
      await pumpUntil(() => chat.chatMessages.length == 3);

      expect(idsOf(chat), ['u-1', 'a-1', 'a-2']);
    });
  });
}
