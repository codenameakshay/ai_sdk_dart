import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('ObjectStreamController', () {
    test('starts with initial value and idle state', () {
      final controller = ObjectStreamController<Map<String, dynamic>>(
        initialValue: const {'seed': true},
      );
      expect(controller.value, const {'seed': true});
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('bind streams partial values and toggles loading/streaming', () async {
      final controller = ObjectStreamController<int>();
      var sawLoading = false;
      var sawStreaming = false;
      controller.addListener(() {
        if (controller.isLoading) sawLoading = true;
        if (controller.isStreaming) sawStreaming = true;
      });

      await controller.bind(Stream<int>.fromIterable([1, 2, 3]));
      await pumpUntil(() => !controller.isLoading);

      expect(sawLoading, isTrue);
      expect(sawStreaming, isTrue);
      expect(controller.value, 3); // last partial wins
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('bind onFinish fires with the final value', () async {
      int? finished;
      final controller = ObjectStreamController<int>(
        onFinish: (v) => finished = v,
      );
      await controller.bind(Stream<int>.fromIterable([10, 20]));
      await pumpUntil(() => finished != null);
      expect(finished, 20);
      controller.dispose();
    });

    test('bind onError fires and sets error', () async {
      Object? captured;
      final failure = StateError('boom');
      final controller = ObjectStreamController<int>(
        onError: (e) => captured = e,
      );
      await controller.bind(Stream<int>.error(failure));
      await pumpUntil(() => controller.error != null);
      expect(controller.error, same(failure));
      expect(captured, same(failure));
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('clear / reset wipe value and error', () async {
      final controller = ObjectStreamController<int>();
      await controller.bind(Stream<int>.value(42));
      await pumpUntil(() => controller.value == 42);
      expect(controller.value, 42);

      controller.clear();
      expect(controller.value, isNull);

      await controller.bind(Stream<int>.value(7));
      await pumpUntil(() => controller.value == 7);
      controller.reset();
      expect(controller.value, isNull);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('submit throws StateError when model/schema not provided', () {
      final controller = ObjectStreamController<Map<String, dynamic>>();
      expect(() => controller.submit('hi'), throwsA(isA<StateError>()));
      controller.dispose();
    });

    test(
      'submit runs streamText(output: object) and streams the parsed object',
      () async {
        final controller = ObjectStreamController<Map<String, dynamic>>(
          model: MockLanguageModelV3(response: [mockText('{"title":"Hi"}')]),
          schema: mapSchema,
        );

        await controller.submit('Give me a title');
        await pumpUntil(
          () => !controller.isLoading && controller.value != null,
        );

        expect(controller.value, isNotNull);
        expect(controller.value!['title'], 'Hi');
        expect(controller.isStreaming, isFalse);
        expect(controller.isLoading, isFalse);
        controller.dispose();
      },
    );

    test('submit binds via bind() so a later bind still works', () async {
      final controller = ObjectStreamController<Map<String, dynamic>>(
        model: MockLanguageModelV3(response: [mockText('{"title":"A"}')]),
        schema: mapSchema,
      );
      await controller.submit('a');
      await pumpUntil(() => controller.value != null && !controller.isLoading);
      expect(controller.value!['title'], 'A');

      // bind still works independently afterwards.
      await controller.bind(
        Stream<Map<String, dynamic>>.value(const {'title': 'B'}),
      );
      await pumpUntil(() => controller.value?['title'] == 'B');
      expect(controller.value!['title'], 'B');
      controller.dispose();
    });
  });
}
