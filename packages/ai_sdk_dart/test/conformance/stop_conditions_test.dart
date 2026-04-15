import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('StepSnapshot', () {
    test('has stepCount, toolCallNames, and finishReason fields', () {
      const snapshot = StepSnapshot(
        stepCount: 3,
        toolCallNames: ['search', 'read'],
        finishReason: LanguageModelV3FinishReason.stop,
      );
      expect(snapshot.stepCount, 3);
      expect(snapshot.toolCallNames, ['search', 'read']);
      expect(snapshot.finishReason, LanguageModelV3FinishReason.stop);
    });

    test('defaults toolCallNames to empty list', () {
      const snapshot = StepSnapshot(stepCount: 1);
      expect(snapshot.toolCallNames, isEmpty);
    });

    test('defaults finishReason to null', () {
      const snapshot = StepSnapshot(stepCount: 1);
      expect(snapshot.finishReason, isNull);
    });
  });

  group('never stop condition', () {
    test('always returns false', () {
      expect(never(const StepSnapshot(stepCount: 1)), isFalse);
      expect(never(const StepSnapshot(stepCount: 100)), isFalse);
      expect(
        never(
          const StepSnapshot(
            stepCount: 1,
            finishReason: LanguageModelV3FinishReason.stop,
          ),
        ),
        isFalse,
      );
    });
  });

  group('stepCountIs', () {
    test('returns false when count not reached', () {
      final cond = stepCountIs(5);
      expect(cond(const StepSnapshot(stepCount: 3)), isFalse);
    });

    test('returns true when count exactly reached', () {
      final cond = stepCountIs(5);
      expect(cond(const StepSnapshot(stepCount: 5)), isTrue);
    });

    test('returns true when count exceeded', () {
      final cond = stepCountIs(5);
      expect(cond(const StepSnapshot(stepCount: 7)), isTrue);
    });
  });

  group('hasToolCall', () {
    test('returns true when matching tool call present', () {
      final cond = hasToolCall('search');
      expect(
        cond(
          const StepSnapshot(
            stepCount: 1,
            toolCallNames: ['search', 'read'],
          ),
        ),
        isTrue,
      );
    });

    test('returns false when tool call not present', () {
      final cond = hasToolCall('write');
      expect(
        cond(
          const StepSnapshot(
            stepCount: 1,
            toolCallNames: ['search', 'read'],
          ),
        ),
        isFalse,
      );
    });

    test('returns false when toolCallNames is empty', () {
      final cond = hasToolCall('search');
      expect(cond(const StepSnapshot(stepCount: 1)), isFalse);
    });
  });

  group('hasFinishReason', () {
    test('returns true when finishReason matches', () {
      final cond = hasFinishReason(LanguageModelV3FinishReason.stop);
      expect(
        cond(
          const StepSnapshot(
            stepCount: 1,
            finishReason: LanguageModelV3FinishReason.stop,
          ),
        ),
        isTrue,
      );
    });

    test('returns false when finishReason does not match', () {
      final cond = hasFinishReason(LanguageModelV3FinishReason.stop);
      expect(
        cond(
          const StepSnapshot(
            stepCount: 1,
            finishReason: LanguageModelV3FinishReason.length,
          ),
        ),
        isFalse,
      );
    });

    test('returns false when finishReason is null', () {
      final cond = hasFinishReason(LanguageModelV3FinishReason.stop);
      expect(cond(const StepSnapshot(stepCount: 1)), isFalse);
    });
  });

  group('anyOf', () {
    test('returns true when any condition matches', () {
      final cond = stopWhenAny([stepCountIs(10), hasToolCall('done')]);
      expect(
        cond(
          const StepSnapshot(
            stepCount: 3,
            toolCallNames: ['done'],
          ),
        ),
        isTrue,
      );
    });

    test('returns false when no conditions match', () {
      final cond = stopWhenAny([stepCountIs(10), hasToolCall('done')]);
      expect(cond(const StepSnapshot(stepCount: 3)), isFalse);
    });

    test('returns false for empty conditions list', () {
      final cond = stopWhenAny([]);
      expect(cond(const StepSnapshot(stepCount: 1)), isFalse);
    });
  });

  group('allOf', () {
    test('returns true when all conditions match', () {
      final cond = stopWhenAll([
        stepCountIs(3),
        hasFinishReason(LanguageModelV3FinishReason.stop),
      ]);
      expect(
        cond(
          const StepSnapshot(
            stepCount: 3,
            finishReason: LanguageModelV3FinishReason.stop,
          ),
        ),
        isTrue,
      );
    });

    test('returns false when only some conditions match', () {
      final cond = stopWhenAll([
        stepCountIs(3),
        hasFinishReason(LanguageModelV3FinishReason.stop),
      ]);
      expect(
        cond(
          const StepSnapshot(
            stepCount: 3,
            finishReason: LanguageModelV3FinishReason.length,
          ),
        ),
        isFalse,
      );
    });

    test('returns true for empty conditions list', () {
      final cond = stopWhenAll([]);
      expect(cond(const StepSnapshot(stepCount: 1)), isTrue);
    });
  });

  group('generateText stopWhen parameter', () {
    test('accepts a single StopCondition', () async {
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await generateText(
        model: model,
        prompt: 'Hi',
        stopWhen: stepCountIs(1),
      );
      expect(result.text, 'Hello!');
    });

    test('accepts a list of StopConditions', () async {
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await generateText(
        model: model,
        prompt: 'Hi',
        stopWhen: [stepCountIs(1), never],
      );
      expect(result.text, 'Hello!');
    });

    test('null stopWhen falls back to maxSteps', () async {
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await generateText(
        model: model,
        prompt: 'Hi',
        maxSteps: 1,
        // stopWhen intentionally omitted
      );
      expect(result.text, 'Hello!');
    });
  });

  group('streamText stopWhen parameter', () {
    test('accepts a single StopCondition', () async {
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await streamText(
        model: model,
        prompt: 'Hi',
        stopWhen: stepCountIs(1),
      );
      expect(await result.text, 'Hello!');
    });

    test('accepts a list of StopConditions', () async {
      final model = MockLanguageModelV3(
        response: [mockText('Hello!')],
      );

      final result = await streamText(
        model: model,
        prompt: 'Hi',
        stopWhen: [stepCountIs(1), never],
      );
      expect(await result.text, 'Hello!');
    });
  });
}
