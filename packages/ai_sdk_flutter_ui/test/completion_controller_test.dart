import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
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
  });
}
