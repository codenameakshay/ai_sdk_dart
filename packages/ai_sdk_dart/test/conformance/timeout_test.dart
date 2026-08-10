import 'dart:async';
import 'dart:typed_data';
// ignore_for_file: avoid_dynamic_calls

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/retry_helper.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  setUp(debugResetRetryHooksForTests);
  tearDown(debugResetRetryHooksForTests);

  group('timeout parameter', () {
    // ── generateText ─────────────────────────────────────────────────────

    group('generateText', () {
      test('completes normally when model responds within timeout', () async {
        final model = _SlowModel(delay: Duration.zero);
        final result = await generateText(
          model: model,
          prompt: 'hi',
          timeout: const Duration(seconds: 5),
        );
        expect(result.text, 'ok');
      });

      test('throws TimeoutException when model is too slow', () async {
        final model = _SlowModel(delay: const Duration(seconds: 10));
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('no timeout when timeout is null', () async {
        final model = _SlowModel(delay: const Duration(milliseconds: 10));
        // Should not throw
        await generateText(model: model, prompt: 'hi');
      });

      test(
        'retry backoff and attempt timeout stay within remaining budget',
        () async {
          final attemptTimeouts = <Duration?>[];
          final slept = <Duration>[];
          var elapsed = Duration.zero;

          debugConfigureRetryHooksForTests(
            elapsed: () => elapsed,
            randomDouble: () => 0.5,
            sleep: (duration) async {
              slept.add(duration);
              elapsed += duration;
            },
            onAttempt: (attempt) => attemptTimeouts.add(attempt.timeout),
          );

          var callCount = 0;
          final model = _BudgetAwareRetryModel(
            onGenerate: () async {
              callCount++;
              if (callCount == 1) {
                elapsed += const Duration(milliseconds: 50);
                throw const AiApiCallError(
                  'Transient upstream failure',
                  statusCode: 503,
                  isRetryable: true,
                );
              }
              return LanguageModelV3GenerateResult(
                content: [LanguageModelV3TextPart(text: 'ok')],
                finishReason: LanguageModelV3FinishReason.stop,
              );
            },
          );

          final result = await generateText(
            model: model,
            prompt: 'hi',
            timeout: const Duration(milliseconds: 200),
            maxRetries: 1,
          );

          expect(result.text, 'ok');
          expect(callCount, 2);
          expect(slept, [const Duration(milliseconds: 50)]);
          expect(attemptTimeouts, [
            const Duration(milliseconds: 200),
            const Duration(milliseconds: 100),
          ]);
        },
      );
    });

    // ── streamText ───────────────────────────────────────────────────────

    group('streamText', () {
      test('completes normally when model responds within timeout', () async {
        final model = _SlowStreamModel(delay: Duration.zero);
        final result = await streamText(
          model: model,
          prompt: 'hi',
          timeout: const Duration(seconds: 5),
        );
        expect(await result.text, 'streamed');
      });

      test(
        'output future completes with TimeoutException when model exceeds timeout',
        () async {
          final model = _SlowStreamModel(delay: const Duration(seconds: 10));
          final result = await streamText(
            model: model,
            prompt: 'hi',
            timeout: const Duration(milliseconds: 50),
            maxRetries: 0,
          );
          final outputExpectation = expectLater(
            result.output,
            throwsA(isA<TimeoutException>()),
          );
          await result.fullStream.toList();
          await outputExpectation;
        },
      );
    });

    // ── embed ─────────────────────────────────────────────────────────────

    group('embed', () {
      test('completes normally when model responds within timeout', () async {
        final model = _SlowEmbeddingModel(delay: Duration.zero);
        final result = await embed(
          model: model,
          value: 'hello',
          timeout: const Duration(seconds: 5),
        );
        expect(result.embedding, [1.0, 2.0]);
      });

      test('throws TimeoutException when model is too slow', () async {
        final model = _SlowEmbeddingModel(delay: const Duration(seconds: 10));
        expect(
          () => embed(
            model: model,
            value: 'hello',
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });
    });

    // ── embedMany ─────────────────────────────────────────────────────────

    group('embedMany', () {
      test('completes normally when model responds within timeout', () async {
        final model = _SlowEmbeddingModel(delay: Duration.zero);
        final result = await embedMany(
          model: model,
          values: ['a', 'b'],
          timeout: const Duration(seconds: 5),
        );
        expect(result.embeddings, hasLength(2));
      });

      test('throws TimeoutException when model is too slow', () async {
        final model = _SlowEmbeddingModel(delay: const Duration(seconds: 10));
        expect(
          () => embedMany(
            model: model,
            values: ['a', 'b'],
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });
    });

    // ── generateImage ─────────────────────────────────────────────────────

    group('generateImage', () {
      test('completes normally when model responds within timeout', () async {
        final model = _SlowImageModel(delay: Duration.zero);
        final result = await generateImage(
          model: model,
          prompt: 'a cat',
          timeout: const Duration(seconds: 5),
        );
        expect(result.images, hasLength(1));
      });

      test('throws TimeoutException when model is too slow', () async {
        final model = _SlowImageModel(delay: const Duration(seconds: 10));
        expect(
          () => generateImage(
            model: model,
            prompt: 'a cat',
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });
    });
  });
}

// ── Fake models with configurable delay ──────────────────────────────────────

class _SlowModel implements LanguageModelV3 {
  _SlowModel({required this.delay});
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: 'ok')],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _SlowStreamModel implements LanguageModelV3 {
  _SlowStreamModel({required this.delay});
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-stream-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async => throw UnimplementedError();

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    final controller = StreamController<LanguageModelV3StreamPart>();
    controller.add(const StreamPartTextStart(id: 'text-0'));
    controller.add(const StreamPartTextDelta(id: 'text-0', delta: 'streamed'));
    controller.add(const StreamPartTextEnd(id: 'text-0'));
    controller.add(
      StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
    );
    unawaited(controller.close());
    return LanguageModelV3StreamResult(stream: controller.stream);
  }
}

class _SlowEmbeddingModel implements EmbeddingModelV2<String> {
  _SlowEmbeddingModel({required this.delay});
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-embedding-model';
  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return EmbeddingModelV2GenerateResult(
      embeddings: options.values
          .map(
            (v) => EmbeddingModelV2Embedding(value: v, embedding: [1.0, 2.0]),
          )
          .toList(),
    );
  }
}

class _SlowImageModel implements ImageModelV3 {
  _SlowImageModel({required this.delay});
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-image-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return ImageModelV3GenerateResult(
      images: [GeneratedImage(bytes: Uint8List(4), mediaType: 'image/png')],
    );
  }
}

class _BudgetAwareRetryModel implements LanguageModelV3 {
  _BudgetAwareRetryModel({required this.onGenerate});

  final Future<LanguageModelV3GenerateResult> Function() onGenerate;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'budget-aware-retry-model';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) {
    return onGenerate();
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}
