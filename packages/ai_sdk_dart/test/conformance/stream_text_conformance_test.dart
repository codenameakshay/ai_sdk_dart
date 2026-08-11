import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('streamText conformance', () {
    // ── Basic text streaming ───────────────────────────────────────────────

    group('basic text stream', () {
      test('textStream emits only text delta strings', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'Hello'),
          const StreamPartTextDelta(id: 't1', delta: ' world'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        final deltas = await result.textStream.toList();
        expect(deltas, ['Hello', ' world']);
      });

      test('text future resolves to joined text from all deltas', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'Hello'),
          const StreamPartTextDelta(id: 't1', delta: ', world'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        expect(await result.text, 'Hello, world');
      });

      test('finishReason future resolves to correct value', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'done'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        // Drain the stream so futures complete
        await result.text;
        expect(await result.finishReason, LanguageModelV4FinishReason.stop);
      });

      test('usage future resolves to usage from finish part', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'done'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
            usage: const LanguageModelV4Usage(
              inputTokens: LanguageModelV4InputTokenUsage(total: 10),
              outputTokens: LanguageModelV4OutputTokenUsage(total: 5),
            ),
          ),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        await result.text;
        final usage = await result.usage;
        expect(usage?.inputTokens.total, 10);
        expect(usage?.outputTokens.total, 5);
      });
    });

    // ── Full stream event taxonomy ─────────────────────────────────────────

    group('fullStream event taxonomy', () {
      test('fullStream starts with StreamTextStartEvent', () async {
        final model = FakeTextModel('hello');
        final result = await streamText(model: model, prompt: 'hi');
        final events = await result.fullStream.toList();
        final nonRaw = events.where((e) => e is! StreamTextRawEvent).toList();
        expect(nonRaw.first, isA<StreamTextStartEvent>());
      });

      test('fullStream ends with StreamTextFinishEvent', () async {
        final model = FakeTextModel('hello');
        final result = await streamText(model: model, prompt: 'hi');
        final events = await result.fullStream.toList();
        final nonRaw = events.where((e) => e is! StreamTextRawEvent).toList();
        expect(nonRaw.last, isA<StreamTextFinishEvent>());
      });

      test(
        'fullStream includes StreamTextStartStepEvent for each step',
        () async {
          final model = FakeTextModel('hello');
          final result = await streamText(model: model, prompt: 'hi');
          final events = await result.fullStream.toList();
          final startSteps = events
              .whereType<StreamTextStartStepEvent>()
              .toList();
          expect(startSteps.length, 1);
          expect(startSteps[0].stepNumber, 0);
        },
      );

      test('fullStream includes text start/delta/end events', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hi'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        final events = await result.fullStream.toList();
        expect(events.whereType<StreamTextTextStartEvent>().isNotEmpty, isTrue);
        expect(events.whereType<StreamTextTextDeltaEvent>().isNotEmpty, isTrue);
        expect(events.whereType<StreamTextTextEndEvent>().isNotEmpty, isTrue);
      });

      test('fullStream includes reasoning delta events', () async {
        final model = FakeStreamModel([
          const StreamPartReasoningDelta(
            id: 'reasoning-0',
            delta: 'thinking...',
          ),
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'answer'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        final events = await result.fullStream.toList();
        expect(
          events.whereType<StreamTextReasoningDeltaEvent>().isNotEmpty,
          isTrue,
        );
      });

      test('fullStream includes finish step event', () async {
        final model = FakeTextModel('hello');
        final result = await streamText(model: model, prompt: 'hi');
        final events = await result.fullStream.toList();
        expect(
          events.whereType<StreamTextFinishStepEvent>().isNotEmpty,
          isTrue,
        );
      });
    });

    // ── Smooth stream transform ────────────────────────────────────────────

    group('experimentalTransform', () {
      test('smoothStream chunks text deltas by chunkSize', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'Hello'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final result = await streamText(
          model: model,
          prompt: 'hi',
          experimentalTransform: smoothStream(chunkSize: 2),
        );

        final events = await result.fullStream.toList();
        final deltas = events
            .whereType<StreamTextTextDeltaEvent>()
            .map((e) => e.delta)
            .toList();

        // 'Hello' split into chunks of 2: ['He', 'll', 'o']
        expect(deltas, ['He', 'll', 'o']);
        expect(await result.text, 'Hello');
      });

      test(
        'experimentalTransform is applied before onChunk callback',
        () async {
          final model = FakeStreamModel([
            const StreamPartTextStart(id: 't1'),
            const StreamPartTextDelta(id: 't1', delta: 'Hi'),
            const StreamPartTextEnd(id: 't1'),
            StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
          ]);

          final onChunkTexts = <String>[];
          final result = await streamText(
            model: model,
            prompt: 'hi',
            experimentalTransform: smoothStream(chunkSize: 1),
            onChunk: (chunk) {
              if (chunk is StreamTextTextChunk) {
                onChunkTexts.add(chunk.text);
              }
            },
          );

          // Drain the stream so callbacks are fired
          await result.text;
          // 'Hi' split into ['H', 'i']
          expect(onChunkTexts, ['H', 'i']);
        },
      );
    });

    // ── onChunk callback ──────────────────────────────────────────────────

    group('onChunk', () {
      test('onChunk receives StreamTextTextChunk for text deltas', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'Hello'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final chunkTypes = <Type>[];
        final result = await streamText(
          model: model,
          prompt: 'hi',
          onChunk: (chunk) => chunkTypes.add(chunk.runtimeType),
        );

        await result.text;
        expect(chunkTypes, contains(StreamTextTextChunk));
      });

      test('onChunk receives StreamTextRawChunk for every raw part', () async {
        final model = FakeStreamModel([
          const StreamPartRaw(rawValue: {'type': 'provider-chunk'}),
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hi'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final chunkTypes = <Type>[];
        final result = await streamText(
          model: model,
          prompt: 'hi',
          onChunk: (chunk) => chunkTypes.add(chunk.runtimeType),
        );

        await result.text;
        expect(chunkTypes, contains(StreamTextRawChunk));
      });
    });

    // ── onError callback ──────────────────────────────────────────────────

    group('onError', () {
      test('onError is called and the raw stream fails', () async {
        final model = FakeErrorStreamModel('boom');

        Object? observed;
        final result = await streamText(
          model: model,
          prompt: 'hi',
          onError: (err) => observed = err,
        );

        await expectLater(result.stream.toList(), throwsA('boom'));
        expect(observed, 'boom');
      });
    });

    group('failure contracts', () {
      test(
        'textStream-only consumer sees stream failure without zone leak',
        () async {
          final zoneErrors = <Object>[];

          await runZonedGuarded(() async {
            final result = await streamText(
              model: _ErrorAfterTextModel(StateError('boom')),
              prompt: 'hi',
            );
            await expectLater(
              result.textStream.toList(),
              throwsA(isA<StateError>()),
            );
            await Future<void>.delayed(Duration.zero);
          }, (error, stackTrace) => zoneErrors.add(error));

          expect(zoneErrors, isEmpty);
        },
      );

      test(
        'text future-only consumer sees stream failure without zone leak',
        () async {
          final zoneErrors = <Object>[];

          await runZonedGuarded(() async {
            final result = await streamText(
              model: _ErrorAfterTextModel(StateError('boom')),
              prompt: 'hi',
            );
            await expectLater(result.text, throwsA(isA<StateError>()));
            await Future<void>.delayed(Duration.zero);
          }, (error, stackTrace) => zoneErrors.add(error));

          expect(zoneErrors, isEmpty);
        },
      );

      test('fullStream emits an error event before failing', () async {
        final result = await streamText(
          model: _ErrorAfterTextModel(StateError('boom')),
          prompt: 'hi',
        );

        final events = <StreamTextEvent>[];
        final done = Completer<void>();
        final sub = result.fullStream.listen(
          events.add,
          onError: (Object error, StackTrace stackTrace) {
            if (!done.isCompleted) {
              done.completeError(error, stackTrace);
            }
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );

        await expectLater(done.future, throwsA(isA<StateError>()));
        await sub.cancel();

        expect(events.whereType<StreamTextTextDeltaEvent>().single.delta, 'Hi');
        expect(events.last, isA<StreamTextErrorEvent>());
      });

      test(
        'late fullStream subscriber sees pre-cancelled terminal error',
        () async {
          final token = CancellationToken()..cancel();
          final result = await streamText(
            model: FakeTextModel('unused'),
            prompt: 'hi',
            abortSignal: token,
          );

          await Future<void>.delayed(Duration.zero);
          final events = await _collectFailingFullStream(
            result,
            isA<AiOperationCancelledError>(),
          );

          expect(events.single, isA<StreamTextErrorEvent>());
        },
      );

      test(
        'late fullStream subscriber sees startup-timeout terminal error',
        () async {
          final result = await streamText(
            model: _SlowStartEmptyStreamModel(const Duration(milliseconds: 50)),
            prompt: 'hi',
            timeout: const TimeoutConfiguration(
              step: Duration(milliseconds: 10),
            ),
            maxRetries: 0,
          );

          await Future<void>.delayed(const Duration(milliseconds: 30));
          final events = await _collectFailingFullStream(
            result,
            isA<TimeoutException>(),
          );

          expect(events.single, isA<StreamTextErrorEvent>());
        },
      );

      test(
        'late subscriber sees provider failure on raw and text streams',
        () async {
          final result = await streamText(
            model: FakeErrorModel(StateError('boom')),
            prompt: 'hi',
            maxRetries: 0,
          );

          await Future<void>.delayed(Duration.zero);
          await expectLater(result.stream.toList(), throwsA(isA<StateError>()));
          await expectLater(
            result.textStream.toList(),
            throwsA(isA<StateError>()),
          );
        },
      );
    });

    // ── Multi-step streaming ───────────────────────────────────────────────

    group('multi-step streaming', () {
      test('multi-step emits step start/finish events for each step', () async {
        final model = FakeMultiStepModel([
          LanguageModelV4GenerateResult(
            content: [
              const LanguageModelV4ToolCallPart(
                toolCallId: 'c1',
                toolName: 'noop',
                input: {},
              ),
            ],
            finishReason: LanguageModelV4FinishReason.toolCalls,
          ),
          const LanguageModelV4GenerateResult(
            content: [LanguageModelV4TextPart(text: 'Final answer')],
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ]);

        final result = await streamText(
          model: model,
          prompt: 'hi',
          maxSteps: 3,
          tools: {
            'noop': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ok',
            ),
          },
        );

        final events = await result.fullStream.toList();
        final startSteps = events
            .whereType<StreamTextStartStepEvent>()
            .toList();
        final finishSteps = events
            .whereType<StreamTextFinishStepEvent>()
            .toList();

        expect(startSteps.length, 2);
        expect(finishSteps.length, 2);
        expect(startSteps[0].stepNumber, 0);
        expect(startSteps[1].stepNumber, 1);
      });

      test('steps future resolves with all steps after completion', () async {
        final model = FakeMultiStepModel([
          LanguageModelV4GenerateResult(
            content: [
              const LanguageModelV4ToolCallPart(
                toolCallId: 'c1',
                toolName: 'noop',
                input: {},
              ),
            ],
            finishReason: LanguageModelV4FinishReason.toolCalls,
          ),
          const LanguageModelV4GenerateResult(
            content: [LanguageModelV4TextPart(text: 'done')],
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ]);

        final result = await streamText(
          model: model,
          prompt: 'hi',
          maxSteps: 3,
          tools: {
            'noop': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
              execute: (_, _) async => 'ok',
            ),
          },
        );

        final steps = await result.steps;
        expect(steps.length, 2);
      });
    });

    // ── onFinish callback ─────────────────────────────────────────────────

    group('onFinish', () {
      test('onFinish receives text, usage, and steps', () async {
        StreamTextFinishEvent<dynamic>? finishEvent;
        final model = FakeTextModel(
          'done',
          usage: const LanguageModelV4Usage(
            inputTokens: LanguageModelV4InputTokenUsage(total: 5),
            outputTokens: LanguageModelV4OutputTokenUsage(total: 3),
          ),
        );

        final result = await streamText(
          model: model,
          prompt: 'hi',
          onFinish: (event) => finishEvent = event,
        );

        await result.output;
        expect(finishEvent, isNotNull);
        expect(finishEvent!.text, 'done');
        expect(finishEvent!.usage?.inputTokens.total, 5);
        expect(finishEvent!.steps, isNotEmpty);
      });

      test(
        'onFinish receives structured warnings from stream result',
        () async {
          StreamTextFinishEvent<dynamic>? finishEvent;
          final model = _FakeStreamModelWithWarnings('done', [
            'provider-warning',
          ]);

          final result = await streamText(
            model: model,
            prompt: 'hi',
            onFinish: (event) => finishEvent = event,
          );

          await result.output;
          expect(finishEvent, isNotNull);
          expect(
            finishEvent!.warnings,
            contains(
              isA<LanguageModelV4OtherWarning>().having(
                (warning) => warning.message,
                'message',
                'provider-warning',
              ),
            ),
          );
        },
      );
    });

    // ── content and reasoning futures ─────────────────────────────────────

    group('content and reasoning futures', () {
      test('content future resolves with all content parts', () async {
        final model = FakeTextModel('Hello');
        final result = await streamText(model: model, prompt: 'hi');
        await result.text;
        final content = await result.content;
        expect(content, isNotEmpty);
        expect(content.whereType<LanguageModelV4TextPart>().isNotEmpty, isTrue);
      });

      test('reasoning future resolves with reasoning parts', () async {
        final model = FakeStreamModel([
          const StreamPartReasoningDelta(id: 'reasoning-0', delta: 'thinking'),
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'answer'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        await result.text;
        final reasoning = await result.reasoning;
        expect(reasoning, isNotEmpty);
        expect(reasoning[0].text, contains('thinking'));
      });
    });
  });
}

class _ErrorAfterTextModel extends LanguageModelV4 {
  const _ErrorAfterTextModel(this.error);

  final Object error;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'error-after-text-model';

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
    return LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.fromIterable([
        const StreamPartTextStart(id: 'text-1'),
        const StreamPartTextDelta(id: 'text-1', delta: 'Hi'),
        const StreamPartTextEnd(id: 'text-1'),
        StreamPartError(error: error),
      ]),
    );
  }
}

class _SlowStartEmptyStreamModel extends LanguageModelV4 {
  const _SlowStartEmptyStreamModel(this.delay);

  final Duration delay;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'slow-start-empty-stream';

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
    await Future<void>.delayed(delay);
    return const LanguageModelV4StreamResult(
      stream: Stream<LanguageModelV4StreamPart>.empty(),
    );
  }
}

Future<List<StreamTextEvent>> _collectFailingFullStream(
  StreamTextResult result,
  Matcher matcher,
) async {
  final events = <StreamTextEvent>[];
  final done = Completer<void>();
  final sub = result.fullStream.listen(
    events.add,
    onError: (Object error, StackTrace stackTrace) {
      if (!done.isCompleted) {
        done.completeError(error, stackTrace);
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
  );
  await expectLater(done.future, throwsA(matcher));
  await sub.cancel();
  return events;
}

/// A fake model that includes structured warnings on the stream result.
class _FakeStreamModelWithWarnings extends LanguageModelV4 {
  _FakeStreamModelWithWarnings(this.text, this.warnings);

  final String text;
  final List<String> warnings;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'fake-warnings-model';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: text)],
      finishReason: LanguageModelV4FinishReason.stop,
      warnings: structuredWarnings,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
        ],
      ),
      warnings: structuredWarnings,
    );
  }

  List<LanguageModelV4Warning> get structuredWarnings => warnings
      .map((warning) => LanguageModelV4OtherWarning(message: warning))
      .toList(growable: false);
}
