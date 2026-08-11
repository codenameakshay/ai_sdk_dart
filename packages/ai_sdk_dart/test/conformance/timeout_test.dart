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
          timeout: const TimeoutConfiguration(total: Duration(seconds: 5)),
        );
        expect(result.text, 'ok');
      });

      test('throws TimeoutException when model is too slow', () async {
        final model = _SlowModel(delay: const Duration(seconds: 10));
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            timeout: const TimeoutConfiguration(
              total: Duration(milliseconds: 50),
            ),
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
              return LanguageModelV4GenerateResult(
                content: [LanguageModelV4TextPart(text: 'ok')],
                finishReason: LanguageModelV4FinishReason.stop,
              );
            },
          );

          final result = await generateText(
            model: model,
            prompt: 'hi',
            timeout: const TimeoutConfiguration(
              total: Duration(milliseconds: 500),
              step: Duration(milliseconds: 150),
            ),
            maxRetries: 1,
          );

          expect(result.text, 'ok');
          expect(callCount, 2);
          expect(slept, [const Duration(milliseconds: 50)]);
          expect(attemptTimeouts, [
            const Duration(milliseconds: 150),
            const Duration(milliseconds: 50),
          ]);
        },
      );

      test('tool timeout applies to tool execution', () async {
        final model = _ToolCallingGenerateModel();
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            maxSteps: 2,
            timeout: const TimeoutConfiguration(
              tool: Duration(milliseconds: 10),
            ),
            tools: {
              'slow': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                execute: (_, _) async {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  return 'ok';
                },
              ),
            },
          ),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('per-tool timeout overrides the default tool timeout', () async {
        final model = _ToolCallingGenerateModel();
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            maxSteps: 2,
            timeout: const TimeoutConfiguration(
              tool: Duration(milliseconds: 100),
              tools: {'slow': Duration(milliseconds: 10)},
            ),
            tools: {
              'slow': tool<Map<String, dynamic>, String>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                execute: (_, _) async {
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  return 'ok';
                },
              ),
            },
          ),
          throwsA(isA<TimeoutException>()),
        );
      });

      test('streaming tool output timeout applies between chunks', () async {
        final model = _ToolCallingGenerateModel();
        expect(
          () => generateText(
            model: model,
            prompt: 'hi',
            maxSteps: 2,
            timeout: const TimeoutConfiguration(
              tool: Duration(milliseconds: 10),
            ),
            tools: {
              'slow': tool<Map<String, dynamic>, Object?>(
                inputSchema: Schema<Map<String, dynamic>>(
                  jsonSchema: const {'type': 'object'},
                  fromJson: (json) => json,
                ),
                execute: (_, _) async => _DelayedToolValueStream(),
              ),
            },
          ),
          throwsA(isA<TimeoutException>()),
        );
      });
    });

    // ── streamText ───────────────────────────────────────────────────────

    group('streamText', () {
      test('completes normally when model responds within timeout', () async {
        final model = _SlowStreamModel(delay: Duration.zero);
        final result = await streamText(
          model: model,
          prompt: 'hi',
          timeout: const TimeoutConfiguration(total: Duration(seconds: 5)),
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
            timeout: const TimeoutConfiguration(
              step: Duration(milliseconds: 50),
            ),
            maxRetries: 0,
          );
          final outputExpectation = expectLater(
            result.output,
            throwsA(isA<TimeoutException>()),
          );
          await expectLater(
            result.fullStream.toList(),
            throwsA(isA<TimeoutException>()),
          );
          await outputExpectation;
        },
      );

      test(
        'firstChunk timeout fires when the stream stalls before output',
        () async {
          final result = await streamText(
            model: _DelayedChunkStreamModel(
              firstDelay: const Duration(milliseconds: 50),
            ),
            prompt: 'hi',
            timeout: const TimeoutConfiguration(
              firstChunk: Duration(milliseconds: 10),
            ),
            maxRetries: 0,
          );

          final outputExpectation = expectLater(
            result.output,
            throwsA(isA<TimeoutException>()),
          );
          await expectLater(
            result.fullStream.toList(),
            throwsA(isA<TimeoutException>()),
          );
          await outputExpectation;
        },
      );

      test('chunk timeout fires between streamed parts', () async {
        final result = await streamText(
          model: _DelayedChunkStreamModel(
            firstDelay: Duration.zero,
            secondDelay: const Duration(milliseconds: 50),
          ),
          prompt: 'hi',
          timeout: const TimeoutConfiguration(
            chunk: Duration(milliseconds: 10),
          ),
          maxRetries: 0,
        );

        final outputExpectation = expectLater(
          result.output,
          throwsA(isA<TimeoutException>()),
        );
        await expectLater(
          result.fullStream.toList(),
          throwsA(isA<TimeoutException>()),
        );
        await outputExpectation;
      });
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

  group('withRetry helper', () {
    test(
      'throws retry budget exhausted before a zero-time retry attempt',
      () async {
        var elapsed = Duration.zero;
        debugConfigureRetryHooksForTests(elapsed: () => elapsed);

        await expectLater(
          withRetry<String>(
            maxRetries: 1,
            totalTimeout: const Duration(milliseconds: 10),
            stepTimeout: const Duration(milliseconds: 10),
            fn: (attemptTimeout) async {
              elapsed += attemptTimeout!;
              throw const AiApiCallError(
                'retry me',
                statusCode: 503,
                isRetryable: true,
              );
            },
          ),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test(
      'throws retry budget exhausted after a retryable failure uses the budget',
      () async {
        var elapsed = Duration.zero;
        debugConfigureRetryHooksForTests(
          elapsed: () => elapsed,
          sleep: (_) async {},
          randomDouble: () => 1,
        );

        await expectLater(
          withRetry<String>(
            maxRetries: 1,
            totalTimeout: const Duration(milliseconds: 10),
            stepTimeout: const Duration(milliseconds: 10),
            fn: (_) async {
              elapsed = const Duration(milliseconds: 10);
              throw const AiApiCallError(
                'retry me',
                statusCode: 503,
                isRetryable: true,
              );
            },
          ),
          throwsA(isA<TimeoutException>()),
        );
      },
    );
  });
}

// ── Fake models with configurable delay ──────────────────────────────────────

class _SlowModel extends LanguageModelV4 {
  _SlowModel({required this.delay});
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-model';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'ok')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _SlowStreamModel extends LanguageModelV4 {
  _SlowStreamModel({required this.delay});
  final Duration delay;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'slow-stream-model';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    if (delay > Duration.zero) await Future.delayed(delay);
    final controller = StreamController<LanguageModelV4StreamPart>();
    controller.add(const StreamPartTextStart(id: 'text-0'));
    controller.add(const StreamPartTextDelta(id: 'text-0', delta: 'streamed'));
    controller.add(const StreamPartTextEnd(id: 'text-0'));
    controller.add(
      StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    );
    unawaited(controller.close());
    return LanguageModelV4StreamResult(stream: controller.stream);
  }
}

class _ToolCallingGenerateModel extends LanguageModelV4 {
  int _callCount = 0;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'tool-calling-generate-model';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    if (_callCount++ == 0) {
      return const LanguageModelV4GenerateResult(
        content: [
          LanguageModelV4ToolCallPart(
            toolCallId: 'tool-1',
            toolName: 'slow',
            input: {},
          ),
        ],
        finishReason: LanguageModelV4FinishReason.toolCalls,
      );
    }

    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'done')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}

class _DelayedChunkStreamModel extends LanguageModelV4 {
  _DelayedChunkStreamModel({
    required this.firstDelay,
    this.secondDelay = Duration.zero,
  });

  final Duration firstDelay;
  final Duration secondDelay;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'delayed-chunk-stream-model';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final controller = StreamController<LanguageModelV4StreamPart>();
    unawaited(() async {
      await Future<void>.delayed(firstDelay);
      controller.add(const StreamPartTextStart(id: 'text-0'));
      controller.add(const StreamPartTextDelta(id: 'text-0', delta: 'a'));
      if (secondDelay > Duration.zero) {
        await Future<void>.delayed(secondDelay);
      }
      controller.add(const StreamPartTextDelta(id: 'text-0', delta: 'b'));
      controller.add(const StreamPartTextEnd(id: 'text-0'));
      controller.add(
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      );
      await controller.close();
    }());
    return LanguageModelV4StreamResult(stream: controller.stream);
  }
}

class _DelayedToolValueStream extends Stream<Object?> {
  @override
  StreamSubscription<Object?> listen(
    void Function(Object? event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final controller = StreamController<Object?>();
    unawaited(() async {
      controller.add('first');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.add('second');
      await controller.close();
    }());
    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
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

class _BudgetAwareRetryModel extends LanguageModelV4 {
  _BudgetAwareRetryModel({required this.onGenerate});

  final Future<LanguageModelV4GenerateResult> Function() onGenerate;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'budget-aware-retry-model';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) {
    return onGenerate();
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    throw UnimplementedError();
  }
}
