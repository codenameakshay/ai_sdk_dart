import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/retry_helper.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  setUp(debugResetRetryHooksForTests);
  tearDown(debugResetRetryHooksForTests);

  test('embedMany rejects non-positive parallelism before chunking', () async {
    final model = FakeEmbeddingModel(const [1]);

    await expectLater(
      embedMany(model: model, values: ['a'], maxParallelCalls: 0),
      throwsArgumentError,
    );
    await expectLater(
      embedMany(model: model, values: ['a'], maxParallelCalls: -1),
      throwsArgumentError,
    );
  });

  for (final value in ['NaN', 'Infinity', '1e308']) {
    test('invalid Retry-After $value uses bounded backoff', () async {
      final slept = <Duration>[];
      var calls = 0;
      debugConfigureRetryHooksForTests(
        randomDouble: () => 0.5,
        sleep: (duration) async => slept.add(duration),
      );

      final result = await withRetry<String>(
        maxRetries: 1,
        totalTimeout: null,
        stepTimeout: null,
        fn: (_) async {
          calls++;
          if (calls == 1) {
            throw AiApiCallError(
              'retryable',
              isRetryable: true,
              responseHeaders: {'Retry-After': value},
            );
          }
          return 'ok';
        },
      );

      expect(result, 'ok');
      expect(slept, [const Duration(milliseconds: 50)]);
    });
  }

  test('Retry-After accepts the largest web-safe duration', () async {
    final slept = <Duration>[];
    debugConfigureRetryHooksForTests(
      sleep: (duration) async => slept.add(duration),
    );

    final result = await withRetry<String>(
      maxRetries: 1,
      totalTimeout: null,
      stepTimeout: null,
      fn: (_) async {
        if (slept.isEmpty) {
          throw const AiApiCallError(
            'retryable',
            isRetryable: true,
            responseHeaders: {'Retry-After': '9007199254.74'},
          );
        }
        return 'ok';
      },
    );

    expect(result, 'ok');
    expect(slept, [const Duration(milliseconds: 9007199254740)]);
  });

  test('retry backoff stays bounded for large retry counts', () async {
    final slept = <Duration>[];
    debugConfigureRetryHooksForTests(
      randomDouble: () => 0.5,
      sleep: (duration) async => slept.add(duration),
    );

    await expectLater(
      withRetry<String>(
        maxRetries: 65,
        totalTimeout: null,
        stepTimeout: null,
        fn: (_) async =>
            throw const AiApiCallError('retryable', isRetryable: true),
      ),
      throwsA(isA<AiApiCallError>()),
    );

    expect(slept, hasLength(65));
    expect(slept.take(3), [
      const Duration(milliseconds: 50),
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 200),
    ]);
    expect(
      slept
          .skip(3)
          .every((duration) => duration == const Duration(milliseconds: 250)),
      isTrue,
    );
  });
}
