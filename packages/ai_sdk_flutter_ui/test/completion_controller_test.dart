import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('CompletionController', () {
    test('starts empty and idle', () {
      final controller = CompletionController(agent: textAgent('x'));
      expect(controller.completion, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('complete accumulates text and toggles loading/streaming', () async {
      final controller = CompletionController(agent: textAgent('Hello there'));
      var sawLoading = false;
      var sawStreaming = false;
      controller.addListener(() {
        if (controller.isLoading) sawLoading = true;
        if (controller.isStreaming) sawStreaming = true;
      });

      await controller.complete('Hi');
      await pumpUntil(() => !controller.isLoading);

      expect(sawLoading, isTrue);
      expect(sawStreaming, isTrue);
      expect(controller.completion, 'Hello there');
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('onFinish fires with the full text', () async {
      String? finished;
      final controller = CompletionController(
        agent: textAgent('done'),
        onFinish: (t) => finished = t,
      );
      await controller.complete('go');
      await pumpUntil(() => finished != null);
      expect(finished, 'done');
      controller.dispose();
    });

    test('onError fires and error is set on failure', () async {
      Object? captured;
      final failure = StateError('boom');
      final controller = CompletionController(
        agent: erroringAgent(failure),
        onError: (e) => captured = e,
      );
      await controller.complete('go');
      await pumpUntil(() => controller.error != null);
      expect(controller.error, isNotNull);
      expect(captured, isNotNull);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('complete resets prior state on a new call', () async {
      final controller = CompletionController(agent: textAgent('first'));
      await controller.complete('a');
      await pumpUntil(() => !controller.isLoading);
      expect(controller.completion, 'first');

      // Second completion reuses the same agent/model -> same text, but the
      // buffer must have been reset (not appended).
      await controller.complete('b');
      await pumpUntil(() => !controller.isLoading);
      expect(controller.completion, 'first');
      controller.dispose();
    });

    test('clear resets all state', () async {
      final controller = CompletionController(agent: textAgent('x'));
      await controller.complete('a');
      await pumpUntil(() => !controller.isLoading);
      controller.clear();
      expect(controller.completion, isEmpty);
      expect(controller.error, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('stop is a safe no-op after completion', () async {
      final controller = CompletionController(agent: textAgent('x'));
      await controller.complete('a');
      await pumpUntil(() => !controller.isLoading);
      await controller.stop();
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('stop cancels an in-flight stream and resets flags', () async {
      final controller = CompletionController(
        agent: ToolLoopAgent(model: HoldingTextModel('partial')),
      );

      // Don't await: the holding model keeps the stream open so stop() runs
      // while a subscription is genuinely active.
      unawaited(controller.complete('q'));
      await pumpUntil(() => controller.completion.isNotEmpty);
      expect(controller.isStreaming, isTrue);

      await controller.stop();
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test(
      'a synchronous failure from agent.stream() is caught and reported',
      () async {
        Object? captured;
        final failure = StateError('sync boom');
        final controller = CompletionController(
          agent: syncThrowingAgent(failure),
          onError: (e) => captured = e,
        );

        await controller.complete('go');
        await pumpUntil(() => controller.error != null);

        expect(controller.error, same(failure));
        expect(captured, same(failure));
        expect(controller.isLoading, isFalse);
        expect(controller.isStreaming, isFalse);
        controller.dispose();
      },
    );

    test('an agent.stream() that throws synchronously is caught', () async {
      Object? captured;
      final failure = StateError('stream() threw');
      final controller = CompletionController(
        agent: ThrowingStreamAgent(failure),
        onError: (e) => captured = e,
      );

      await controller.complete('go');
      await pumpUntil(() => controller.error != null);

      expect(controller.error, same(failure));
      expect(captured, same(failure));
      controller.dispose();
    });

    test('captures the last usage after completing', () async {
      const usage = LanguageModelV3Usage(
        inputTokens: 3,
        outputTokens: 5,
        totalTokens: 8,
      );
      final controller = CompletionController(
        agent: textAgentWithUsage('done', usage),
      );

      await controller.complete('go');
      await pumpUntil(() => !controller.isStreaming && !controller.isLoading);

      expect(controller.lastUsage?.totalTokens, 8);
      controller.dispose();
    });
  });
}
