import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('ChatController', () {
    test('starts ready and empty (or with initial messages)', () {
      final controller = ChatController();
      expect(controller.status, ChatStatus.ready);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.messages, isEmpty);
      expect(controller.streamingContent, isEmpty);
      controller.dispose();

      final seeded = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.system, content: 'sys'),
        ],
      );
      expect(seeded.messages, hasLength(1));
      seeded.dispose();
    });

    test('append adds a message without generating', () {
      final controller = ChatController();
      controller.append(
        const ModelMessage(role: ModelMessageRole.user, content: 'hi'),
      );
      expect(controller.messages, hasLength(1));
      expect(controller.status, ChatStatus.ready);
      controller.dispose();
    });

    test(
      'sendMessage runs ready -> submitted -> streaming -> ready and appends '
      'the assistant reply',
      () async {
        final controller = ChatController();
        final statuses = <ChatStatus>[];
        controller.addListener(() => statuses.add(controller.status));

        await controller.sendMessage(
          agent: textAgent('Hello world'),
          text: 'Hi',
        );
        await pumpUntil(() => controller.status == ChatStatus.ready);

        expect(statuses, contains(ChatStatus.submitted));
        expect(statuses, contains(ChatStatus.streaming));
        expect(controller.status, ChatStatus.ready);
        expect(controller.isStreaming, isFalse);
        expect(controller.isLoading, isFalse);

        // user message + assistant reply
        expect(controller.messages, hasLength(2));
        expect(controller.messages.first.role, ModelMessageRole.user);
        expect(controller.messages.last.role, ModelMessageRole.assistant);
        expect(controller.messages.last.content, 'Hello world');

        // streaming buffer is cleared once the turn completes
        expect(controller.streamingContent, isEmpty);
        controller.dispose();
      },
    );

    test('isStreaming mirrors status == streaming during the stream', () async {
      final controller = ChatController();
      var sawStreamingTrue = false;
      controller.addListener(() {
        if (controller.status == ChatStatus.streaming) {
          // Whenever status is streaming, isStreaming must agree.
          expect(controller.isStreaming, isTrue);
          sawStreamingTrue = true;
        }
      });

      await controller.sendMessage(agent: textAgent('streamed'), text: 'go');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(sawStreamingTrue, isTrue);
      controller.dispose();
    });

    test('onFinish fires with the assistant message', () async {
      ModelMessage? finished;
      final controller = ChatController(onFinish: (m) => finished = m);
      await controller.sendMessage(agent: textAgent('done'), text: 'x');
      await pumpUntil(() => finished != null);
      expect(finished, isNotNull);
      expect(finished!.content, 'done');
      expect(finished!.role, ModelMessageRole.assistant);
      controller.dispose();
    });

    test('onError fires and status becomes error on stream failure', () async {
      Object? captured;
      final controller = ChatController(onError: (e) => captured = e);
      final failure = StateError('boom');

      await controller.sendMessage(agent: erroringAgent(failure), text: 'x');
      await pumpUntil(() => controller.status == ChatStatus.error);

      expect(controller.status, ChatStatus.error);
      expect(controller.error, isNotNull);
      expect(captured, isNotNull);
      // user message remains, no assistant message appended
      expect(controller.messages, hasLength(1));
      controller.dispose();
    });

    test('clearError resets error status to ready', () async {
      final controller = ChatController();
      await controller.sendMessage(
        agent: erroringAgent(StateError('x')),
        text: 'x',
      );
      await pumpUntil(() => controller.status == ChatStatus.error);
      expect(controller.status, ChatStatus.error);

      controller.clearError();
      expect(controller.status, ChatStatus.ready);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('reload removes the last assistant message and regenerates', () async {
      final controller = ChatController();
      await controller.sendMessage(agent: textAgent('first'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(controller.messages.last.content, 'first');

      // reload uses the cached agent.
      await controller.reload();
      await pumpUntil(() => controller.status == ChatStatus.ready);
      // still 2 messages: user + freshly-generated assistant
      expect(controller.messages, hasLength(2));
      expect(controller.messages.last.role, ModelMessageRole.assistant);
      expect(controller.messages.last.content, 'first');
      controller.dispose();
    });

    test('regenerate is an alias of reload', () async {
      final controller = ChatController();
      await controller.sendMessage(agent: textAgent('a'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      await controller.regenerate();
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(controller.messages, hasLength(2));
      controller.dispose();
    });

    test('clear resets to initial messages', () async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.system, content: 'sys'),
        ],
      );
      await controller.sendMessage(agent: textAgent('a'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      expect(controller.messages.length, greaterThan(1));

      controller.clear();
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.content, 'sys');
      expect(controller.status, ChatStatus.ready);
      controller.dispose();
    });

    test(
      'addToolApprovalResponse records a pending approval without error',
      () {
        final controller = ChatController();
        controller.addToolApprovalResponse(approvalId: 'a1', approved: true);
        // No public getter; assert it simply notified and stayed ready.
        expect(controller.status, ChatStatus.ready);
        controller.dispose();
      },
    );

    test('stop leaves the controller ready', () async {
      final controller = ChatController();
      // With the mock the stream completes quickly; stop after completion must
      // be a no-op that leaves us ready.
      await controller.sendMessage(agent: textAgent('x'), text: 'q');
      await pumpUntil(() => controller.status == ChatStatus.ready);
      await controller.stop();
      expect(controller.status, ChatStatus.ready);
      controller.dispose();
    });

    test('stop mid-stream flushes the partial buffer as an assistant message',
        () async {
      final controller = ChatController();
      final model = HoldingTextModel('partial answer');

      // Don't await: the holding model keeps the stream open so we can stop
      // while content is buffered but the turn hasn't finished.
      unawaited(
        controller.sendMessage(
          agent: ToolLoopAgent(model: model),
          text: 'q',
        ),
      );
      await pumpUntil(() => controller.streamingContent.isNotEmpty);
      expect(controller.streamingContent, 'partial answer');

      await controller.stop();

      // The buffered text is committed as a trailing assistant message and the
      // buffer is cleared.
      expect(controller.status, ChatStatus.ready);
      expect(controller.streamingContent, isEmpty);
      expect(controller.messages.last.role, ModelMessageRole.assistant);
      expect(controller.messages.last.content, 'partial answer');

      model.finish();
      controller.dispose();
    });

    test(
      'a pending tool approval is consumed by the next generation',
      () async {
        final controller = ChatController();
        controller.addToolApprovalResponse(approvalId: 'a1', approved: true);

        // sendMessage runs _runGeneration, which consumes pending approvals.
        // We only need the generation to start and finish cleanly.
        await controller.sendMessage(agent: textAgent('ok'), text: 'go');
        await pumpUntil(() => controller.status == ChatStatus.ready);
        expect(controller.messages.last.content, 'ok');

        // A second generation with no pending approvals still works (the buffer
        // was cleared by the first consume).
        await controller.reload();
        await pumpUntil(() => controller.status == ChatStatus.ready);
        expect(controller.status, ChatStatus.ready);
        controller.dispose();
      },
    );

    test(
      'a synchronous failure from agent.stream() is caught and reported',
      () async {
        Object? captured;
        final controller = ChatController(onError: (e) => captured = e);
        final failure = StateError('sync boom');

        // throwOnStream makes doStream throw synchronously, so the
        // `await agent.stream(...)` itself rejects and is handled by the
        // try/catch in _runGeneration (not the stream error listener).
        await controller.sendMessage(
          agent: syncThrowingAgent(failure),
          text: 'x',
        );
        await pumpUntil(() => controller.status == ChatStatus.error);

        expect(controller.status, ChatStatus.error);
        expect(controller.error, same(failure));
        expect(captured, same(failure));
        controller.dispose();
      },
    );
  });
}
