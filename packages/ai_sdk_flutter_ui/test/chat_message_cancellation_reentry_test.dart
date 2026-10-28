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
  test(
    'a send started by cancellation wins over the send that triggered it',
    () async {
      final controller = ChatController(generateId: _ids());
      addTearDown(controller.dispose);
      final cancelledAgent = RecordingStreamAgent();
      final newerAgent = _responseAgent(
        'newer answer',
        'new-provider',
        'new-model',
      );
      final outerAgent = _responseAgent(
        'outer answer',
        'outer-provider',
        'outer-model',
      );

      await controller.sendMessage(agent: cancelledAgent, text: 'first');
      await pumpUntil(() => cancelledAgent.invocations.length == 1);
      final cancellation = cancelledAgent
          .invocations
          .single
          .abortSignal!
          .cancellationEvents
          .listen((_) {
            unawaited(
              controller.sendMessage(agent: newerAgent, text: 'newer question'),
            );
          });
      addTearDown(cancellation.cancel);

      await controller.sendMessage(agent: outerAgent, text: 'outer question');
      await pumpUntil(
        () =>
            controller.status == ChatStatus.ready &&
            controller.chatMessages.any(
              (entry) =>
                  entry.message.content == 'outer answer' ||
                  entry.message.content == 'newer answer',
            ),
      );

      expect(controller.chatMessages.last.message.content, 'newer answer');
      expect(controller.chatMessages.last.provider, 'new-provider');
      expect(controller.chatMessages.last.modelId, 'new-model');
    },
  );

  test(
    'stop after partial text preserves its interruption and cancellation reentry',
    () async {
      final controller = ChatController(generateId: _ids());
      addTearDown(controller.dispose);
      final stoppedAgent = RecordingStreamAgent();
      final newerAgent = _responseAgent(
        'newer answer',
        'new-provider',
        'new-model',
      );

      await controller.sendMessage(agent: stoppedAgent, text: 'first');
      await pumpUntil(() => stoppedAgent.invocations.length == 1);
      final stoppedInvocation = stoppedAgent.invocations.single;
      stoppedInvocation.emitText('partial');
      await pumpUntil(() => controller.streamingContent == 'partial');
      final cancellation = stoppedInvocation.abortSignal!.cancellationEvents
          .listen((_) {
            unawaited(
              controller.sendMessage(agent: newerAgent, text: 'newer question'),
            );
          });
      addTearDown(cancellation.cancel);

      await controller.stop();
      await pumpUntil(
        () =>
            controller.status == ChatStatus.ready &&
            controller.chatMessages.any(
              (entry) => entry.message.content == 'newer answer',
            ),
      );

      expect(controller.chatMessages.map((entry) => entry.id), [
        'id-1',
        'id-2',
        'id-3',
        'id-4',
      ]);
      expect(controller.chatMessages[1].message.content, 'partial');
      expect(
        controller.chatMessages[1].status,
        ConversationMessageStatus.interrupted,
      );
      expect(controller.chatMessages[2].message.content, 'newer question');
      expect(controller.chatMessages.last.message.content, 'newer answer');
      expect(controller.chatMessages.last.provider, 'new-provider');
      expect(controller.chatMessages.last.modelId, 'new-model');
      expect(
        controller.chatMessages.last.status,
        ConversationMessageStatus.complete,
      );
    },
  );

  test(
    'clear during an active stream preserves a cancellation reentrant send',
    () async {
      final controller = ChatController(generateId: _ids());
      addTearDown(controller.dispose);
      final clearedAgent = RecordingStreamAgent();
      final newerAgent = _responseAgent(
        'newer answer',
        'new-provider',
        'new-model',
      );

      await controller.sendMessage(agent: clearedAgent, text: 'first');
      await pumpUntil(() => clearedAgent.invocations.length == 1);
      final clearedInvocation = clearedAgent.invocations.single;
      final cancellation = clearedInvocation.abortSignal!.cancellationEvents
          .listen((_) {
            unawaited(
              controller.sendMessage(agent: newerAgent, text: 'newer question'),
            );
          });
      addTearDown(cancellation.cancel);

      controller.clear();
      await pumpUntil(
        () =>
            controller.status == ChatStatus.ready &&
            controller.chatMessages.any(
              (entry) => entry.message.content == 'newer answer',
            ),
      );

      expect(controller.chatMessages.map((entry) => entry.id), [
        'id-1',
        'id-2',
        'id-3',
      ]);
      expect(controller.chatMessages.map((entry) => entry.message.content), [
        'first',
        'newer question',
        'newer answer',
      ]);
      expect(controller.chatMessages.last.message.content, 'newer answer');
      expect(controller.chatMessages.last.provider, 'new-provider');
      expect(controller.chatMessages.last.modelId, 'new-model');
      expect(
        controller.chatMessages.last.status,
        ConversationMessageStatus.complete,
      );
    },
  );
}
