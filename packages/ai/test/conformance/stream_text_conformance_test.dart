import 'package:ai/ai.dart';
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
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
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
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        expect(await result.text, 'Hello, world');
      });

      test('finishReason future resolves to correct value', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'done'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        // Drain the stream so futures complete
        await result.text;
        expect(await result.finishReason, LanguageModelV3FinishReason.stop);
      });

      test('usage future resolves to usage from finish part', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'done'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(
            finishReason: LanguageModelV3FinishReason.stop,
            usage: const LanguageModelV3Usage(
              inputTokens: 10,
              outputTokens: 5,
              totalTokens: 15,
            ),
          ),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        await result.text;
        final usage = await result.usage;
        expect(usage?.inputTokens, 10);
        expect(usage?.outputTokens, 5);
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

      test('fullStream includes StreamTextStartStepEvent for each step', () async {
        final model = FakeTextModel('hello');
        final result = await streamText(model: model, prompt: 'hi');
        final events = await result.fullStream.toList();
        final startSteps = events.whereType<StreamTextStartStepEvent>().toList();
        expect(startSteps.length, 1);
        expect(startSteps[0].stepNumber, 0);
      });

      test('fullStream includes text start/delta/end events', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hi'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ]);

        final result = await streamText(model: model, prompt: 'hi');
        final events = await result.fullStream.toList();
        expect(events.whereType<StreamTextTextStartEvent>().isNotEmpty, isTrue);
        expect(events.whereType<StreamTextTextDeltaEvent>().isNotEmpty, isTrue);
        expect(events.whereType<StreamTextTextEndEvent>().isNotEmpty, isTrue);
      });

      test('fullStream includes reasoning delta events', () async {
        final model = FakeStreamModel([
          const StreamPartReasoningDelta(delta: 'thinking...'),
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'answer'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
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
        expect(events.whereType<StreamTextFinishStepEvent>().isNotEmpty, isTrue);
      });
    });

    // ── Smooth stream transform ────────────────────────────────────────────

    group('experimentalTransform', () {
      test('smoothStream chunks text deltas by chunkSize', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'Hello'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
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

      test('experimentalTransform is applied before onChunk callback', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'Hi'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
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
      });
    });

    // ── onChunk callback ──────────────────────────────────────────────────

    group('onChunk', () {
      test('onChunk receives StreamTextTextChunk for text deltas', () async {
        final model = FakeStreamModel([
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'Hello'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
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
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'hi'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
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
      test('onError is called and stream still completes', () async {
        final model = FakeErrorStreamModel('boom');

        Object? observed;
        final result = await streamText(
          model: model,
          prompt: 'hi',
          onError: (err) => observed = err,
        );

        // Drain the raw stream to ensure onError is invoked
        await result.stream.toList();
        expect(observed, 'boom');
      });
    });

    // ── Multi-step streaming ───────────────────────────────────────────────

    group('multi-step streaming', () {
      test('multi-step emits step start/finish events for each step', () async {
        final model = FakeMultiStepModel([
          LanguageModelV3GenerateResult(
            content: [
              const LanguageModelV3ToolCallPart(
                toolCallId: 'c1',
                toolName: 'noop',
                input: {},
              ),
            ],
            finishReason: LanguageModelV3FinishReason.toolCalls,
          ),
          const LanguageModelV3GenerateResult(
            content: [LanguageModelV3TextPart(text: 'Final answer')],
            finishReason: LanguageModelV3FinishReason.stop,
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
              execute: (_, __) async => 'ok',
            ),
          },
        );

        final events = await result.fullStream.toList();
        final startSteps = events.whereType<StreamTextStartStepEvent>().toList();
        final finishSteps =
            events.whereType<StreamTextFinishStepEvent>().toList();

        expect(startSteps.length, 2);
        expect(finishSteps.length, 2);
        expect(startSteps[0].stepNumber, 0);
        expect(startSteps[1].stepNumber, 1);
      });

      test('steps future resolves with all steps after completion', () async {
        final model = FakeMultiStepModel([
          LanguageModelV3GenerateResult(
            content: [
              const LanguageModelV3ToolCallPart(
                toolCallId: 'c1',
                toolName: 'noop',
                input: {},
              ),
            ],
            finishReason: LanguageModelV3FinishReason.toolCalls,
          ),
          const LanguageModelV3GenerateResult(
            content: [LanguageModelV3TextPart(text: 'done')],
            finishReason: LanguageModelV3FinishReason.stop,
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
              execute: (_, __) async => 'ok',
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
          usage: const LanguageModelV3Usage(
            inputTokens: 5,
            outputTokens: 3,
            totalTokens: 8,
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
        expect(finishEvent!.usage?.inputTokens, 5);
        expect(finishEvent!.steps, isNotEmpty);
      });

      test('onFinish receives warnings from rawResponse', () async {
        StreamTextFinishEvent<dynamic>? finishEvent;
        final model = _FakeStreamModelWithWarnings('done', ['provider-warning']);

        final result = await streamText(
          model: model,
          prompt: 'hi',
          onFinish: (event) => finishEvent = event,
        );

        await result.output;
        expect(finishEvent, isNotNull);
        expect(finishEvent!.warnings, contains('provider-warning'));
      });
    });

    // ── content and reasoning futures ─────────────────────────────────────

    group('content and reasoning futures', () {
      test('content future resolves with all content parts', () async {
        final model = FakeTextModel('Hello');
        final result = await streamText(model: model, prompt: 'hi');
        await result.text;
        final content = await result.content;
        expect(content, isNotEmpty);
        expect(content.whereType<LanguageModelV3TextPart>().isNotEmpty, isTrue);
      });

      test('reasoning future resolves with reasoning parts', () async {
        final model = FakeStreamModel([
          const StreamPartReasoningDelta(delta: 'thinking'),
          const StreamPartTextStart(id: 't1'),
          const StreamPartTextDelta(id: 't1', delta: 'answer'),
          const StreamPartTextEnd(id: 't1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
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

/// A fake model that includes warnings in rawResponse so streamText can read them.
class _FakeStreamModelWithWarnings implements LanguageModelV3 {
  _FakeStreamModelWithWarnings(this.text, this.warnings);

  final String text;
  final List<String> warnings;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'fake-warnings-model';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: LanguageModelV3FinishReason.stop,
      warnings: warnings,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
        ],
      ),
      rawResponse: <Object?, Object?>{'warnings': warnings},
    );
  }
}
