import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

String Function() _ids() {
  var next = 0;
  return () => 'id-${++next}';
}

ToolLoopAgent _responseAgent(String text, String provider, String modelId) =>
    ToolLoopAgent(
      model: MockLanguageModelV4(
        response: [mockText(text)],
        provider: provider,
        modelId: modelId,
      ),
    );

void main() {
  group('ChatController message lifecycle regressions', () {
    test(
      'synchronous sends keep only the newest model answer and metadata',
      () async {
        final controller = ChatController(generateId: _ids());
        addTearDown(controller.dispose);
        final slow = _responseAgent('stale', 'provider-old', 'model-old');
        final fast = _responseAgent('current', 'provider-new', 'model-new');

        final oldSend = controller.sendMessage(agent: slow, text: 'first');
        final newSend = controller.sendMessage(agent: fast, text: 'second');
        await Future.wait([oldSend, newSend]);
        await pumpUntil(
          () =>
              controller.status == ChatStatus.ready &&
              controller.chatMessages.length == 3,
        );

        expect(controller.chatMessages.map((entry) => entry.id), [
          'id-1',
          'id-2',
          'id-3',
        ]);
        expect(controller.chatMessages.last.message.content, 'current');
        expect(controller.chatMessages.last.provider, 'provider-new');
        expect(controller.chatMessages.last.modelId, 'model-new');
        expect(
          controller.chatMessages.last.status,
          ConversationMessageStatus.complete,
        );
      },
    );

    test(
      'a reentrant newer send is not superseded by the outer send',
      () async {
        final controller = ChatController(generateId: _ids());
        addTearDown(controller.dispose);
        final outerAgent = RecordingStreamAgent();
        final newerAgent = _responseAgent(
          'newer answer',
          'new-provider',
          'new-model',
        );
        var startedNewerSend = false;
        controller.addListener(() {
          if (!startedNewerSend &&
              controller.messages.any(
                (message) =>
                    message.role == ModelMessageRole.user &&
                    message.content == 'outer question',
              )) {
            startedNewerSend = true;
            unawaited(
              controller.sendMessage(agent: newerAgent, text: 'newer question'),
            );
          }
        });

        await controller.sendMessage(agent: outerAgent, text: 'outer question');
        await pumpUntil(
          () =>
              controller.status == ChatStatus.ready &&
              controller.chatMessages.any(
                (entry) => entry.message.content == 'newer answer',
              ),
        );

        expect(startedNewerSend, isTrue);
        expect(outerAgent.invocations, isEmpty);
        expect(controller.chatMessages.last.message.content, 'newer answer');
        expect(controller.chatMessages.last.provider, 'new-provider');
        expect(controller.chatMessages.last.modelId, 'new-model');
      },
    );

    test('stop in the first append notification prevents generation', () async {
      final controller = ChatController(generateId: _ids());
      addTearDown(controller.dispose);
      final agent = RecordingStreamAgent();
      var stopStarted = false;
      controller.addListener(() {
        if (!stopStarted && controller.messages.isNotEmpty) {
          stopStarted = true;
          unawaited(controller.stop());
        }
      });

      await controller.sendMessage(agent: agent, text: 'question');
      await pumpUntil(() => controller.status == ChatStatus.ready);

      expect(stopStarted, isTrue);
      expect(agent.invocations, isEmpty);
      expect(controller.chatMessages, hasLength(1));
      expect(controller.chatMessages.single.id, 'id-1');
      expect(controller.chatMessages.single.message.content, 'question');
    });

    test(
      'clear in the first append notification prevents generation',
      () async {
        final controller = ChatController(generateId: _ids());
        addTearDown(controller.dispose);
        final agent = RecordingStreamAgent();
        var clearStarted = false;
        controller.addListener(() {
          if (!clearStarted && controller.messages.isNotEmpty) {
            clearStarted = true;
            controller.clear();
          }
        });

        await controller.sendMessage(agent: agent, text: 'question');
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(clearStarted, isTrue);
        expect(agent.invocations, isEmpty);
        expect(controller.chatMessages, isEmpty);
        expect(controller.messages, isEmpty);
      },
    );

    test(
      'late stream events after stop cannot create or change a message',
      () async {
        final controller = ChatController(generateId: _ids());
        addTearDown(controller.dispose);
        final agent = RecordingStreamAgent();

        final sending = controller.sendMessage(agent: agent, text: 'question');
        await sending;
        await pumpUntil(() => agent.invocations.length == 1);
        final invocation = agent.invocations.single;
        invocation.emitText('partial');
        await pumpUntil(() => controller.streamingContent == 'partial');
        await controller.stop();

        expect(controller.chatMessages, hasLength(2));
        expect(controller.chatMessages.last.message.content, 'partial');
        expect(
          controller.chatMessages.last.status,
          ConversationMessageStatus.interrupted,
        );

        invocation.emitText('late');
        await invocation.finish(finalText: 'partial late');
        await pumpUntil(() => false, tries: 20);

        expect(controller.status, ChatStatus.ready);
        expect(controller.chatMessages, hasLength(2));
        expect(controller.chatMessages.last.message.content, 'partial');
        expect(controller.chatMessages.last.provider, 'mock');
        expect(controller.chatMessages.last.modelId, 'mock-language-model');
        expect(controller.chatMessages.last.finishReason, isNull);
      },
    );

    test(
      'stop from the streaming notification cancels the newly opened stream',
      () async {
        final controller = ChatController(generateId: _ids());
        addTearDown(controller.dispose);
        final agent = RecordingStreamAgent();
        var stopStarted = false;
        controller.addListener(() {
          if (!stopStarted && controller.status == ChatStatus.streaming) {
            stopStarted = true;
            unawaited(controller.stop());
          }
        });

        await controller.sendMessage(agent: agent, text: 'question');
        await pumpUntil(() => agent.invocations.length == 1);
        final invocation = agent.invocations.single;
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(stopStarted, isTrue);
        expect(invocation.textSubscriptionCancelled, isTrue);
        expect(invocation.fullStreamSubscriptionCancelled, isTrue);
        expect(controller.chatMessages, hasLength(1));
      },
    );

    test(
      'a late stopped stream cannot cancel a newer stream subscriptions',
      () async {
        final controller = ChatController(generateId: _ids());
        addTearDown(controller.dispose);
        final firstAgent = RecordingStreamAgent();
        final secondAgent = RecordingStreamAgent();
        var replaced = false;
        controller.addListener(() {
          if (!replaced && controller.status == ChatStatus.streaming) {
            replaced = true;
            unawaited(controller.stop());
            unawaited(
              controller.sendMessage(agent: secondAgent, text: 'second'),
            );
          }
        });

        await controller.sendMessage(agent: firstAgent, text: 'first');
        await pumpUntil(
          () =>
              firstAgent.invocations.length == 1 &&
              secondAgent.invocations.length == 1 &&
              controller.status == ChatStatus.streaming,
        );
        final firstInvocation = firstAgent.invocations.single;
        final secondInvocation = secondAgent.invocations.single;

        await firstInvocation.finish(finalText: 'late first answer');
        secondInvocation.emitReasoning('newer reasoning');
        await pumpUntil(
          () => controller.streamingReasoning == 'newer reasoning',
        );
        expect(secondInvocation.fullStreamSubscriptionCancelled, isFalse);
        expect(secondInvocation.textSubscriptionCancelled, isFalse);
        secondInvocation.emitText('second answer');
        await secondInvocation.finish(
          finalText: 'second answer',
          reasoningText: 'newer reasoning',
        );
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(controller.status, ChatStatus.ready);
        expect(controller.chatMessages.last.message.content, 'second answer');
        expect(controller.chatMessages.last.provider, 'mock');
        expect(controller.chatMessages.last.modelId, 'mock-language-model');
        expect(
          controller.chatMessages.last.status,
          ConversationMessageStatus.complete,
        );
        expect(controller.reasoningText, 'newer reasoning');
      },
    );

    test(
      'disposing midstream prevents late events from committing an answer',
      () async {
        final controller = ChatController(generateId: _ids());
        final agent = RecordingStreamAgent();

        final sending = controller.sendMessage(agent: agent, text: 'question');
        await sending;
        await pumpUntil(() => agent.invocations.length == 1);
        final invocation = agent.invocations.single;
        invocation.emitText('partial');
        await pumpUntil(() => controller.streamingContent == 'partial');

        controller.dispose();
        invocation.emitText('late');
        await invocation.finish(finalText: 'partial late');
        await pumpUntil(() => false, tries: 20);

        expect(controller.chatMessages, hasLength(1));
        expect(controller.chatMessages.single.message.content, 'question');
      },
    );
  });
}
