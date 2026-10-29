import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('middleware conformance', () {
    // ── wrapLanguageModel() identity ──────────────────────────────────────

    group('wrapLanguageModel() identity', () {
      test('preserves provider from inner model', () {
        final inner = FakeTextModel('hi', provider: 'test-provider');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: <LanguageModelMiddleware>[],
        );
        expect(wrapped.provider, 'test-provider');
      });

      test('preserves modelId from inner model', () {
        final inner = FakeTextModel('hi', modelId: 'gpt-4o');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: <LanguageModelMiddleware>[],
        );
        expect(wrapped.modelId, 'gpt-4o');
      });

      test('preserves specificationVersion from inner model', () {
        final inner = FakeTextModel('hi');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: <LanguageModelMiddleware>[],
        );
        expect(wrapped.specificationVersion, 'v4');
      });

      test('empty middleware list returns model with same behavior', () async {
        final inner = FakeTextModel('hello from inner');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: <LanguageModelMiddleware>[],
        );
        final result = await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );
        final text = result.content.whereType<LanguageModelV4TextPart>().first;
        expect(text.text, 'hello from inner');
      });
    });

    // ── transformParams hook ──────────────────────────────────────────────

    group('transformParams', () {
      test(
        'transformParams can modify temperature before doGenerate',
        () async {
          final capturingModel = FakeCapturingModel();
          final mw = _TransformParamsMiddleware(temperature: 0.42);
          final wrapped = wrapLanguageModel(
            model: capturingModel,
            middleware: mw,
          );
          await wrapped.doGenerate(
            LanguageModelV4CallOptions(
              prompt: const LanguageModelV4Prompt(messages: []),
              temperature: 0.9,
            ),
          );
          expect(capturingModel.capturedOptions.first.temperature, 0.42);
        },
      );

      test('transformParams can modify temperature before doStream', () async {
        final capturingModel = FakeCapturingModel();
        final mw = _TransformParamsMiddleware(temperature: 0.1);
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: mw,
        );
        await wrapped.doStream(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            temperature: 0.9,
          ),
        );
        expect(capturingModel.capturedOptions.first.temperature, 0.1);
      });

      test('transformParams runs before wrapGenerate', () async {
        final log = <String>[];
        final mw = _LoggingTransformMiddleware(log);
        final model = FakeTextModel('hi');
        final wrapped = wrapLanguageModel(model: model, middleware: mw);
        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );
        expect(log, ['transformParams', 'wrapGenerate']);
      });

      test('default transformParams is a no-op', () async {
        final capturingModel = FakeCapturingModel();
        final mw = _NoOpMiddleware();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: mw,
        );
        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            temperature: 0.7,
          ),
        );
        expect(capturingModel.capturedOptions.first.temperature, 0.7);
      });
    });

    // ── Middleware chaining order ──────────────────────────────────────────

    group('middleware chaining', () {
      test('middleware applied left-to-right; first is outermost', () async {
        final callOrder = <String>[];

        final outerMw = _TrackingMiddleware('outer', callOrder);
        final innerMw = _TrackingMiddleware('inner', callOrder);

        final model = FakeTextModel('result');
        final wrapped = wrapLanguageModel(
          model: model,
          middleware: [outerMw, innerMw],
        );

        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        // outer is invoked first (before inner), so it appears first
        expect(callOrder, ['outer', 'inner']);
      });
    });

    // ── extractReasoningMiddleware ─────────────────────────────────────────

    group('extractReasoningMiddleware', () {
      test(
        'strips <think>...</think> and creates ReasoningPart in generate',
        () async {
          final inner = FakeTextModel('<think>reasoning</think>answer');
          final wrapped = wrapLanguageModel(
            model: inner,
            middleware: extractReasoningMiddleware(tagName: 'think'),
          );

          final result = await wrapped.doGenerate(
            LanguageModelV4CallOptions(
              prompt: const LanguageModelV4Prompt(messages: []),
            ),
          );

          final reasoningParts = result.content
              .whereType<LanguageModelV4ReasoningPart>()
              .toList();
          final textParts = result.content
              .whereType<LanguageModelV4TextPart>()
              .toList();

          expect(reasoningParts.length, 1);
          expect(reasoningParts[0].text, 'reasoning');
          expect(textParts.any((p) => p.text.contains('answer')), isTrue);
          expect(textParts.any((p) => p.text.contains('<think>')), isFalse);
        },
      );

      test('custom tagName is respected', () async {
        final inner = FakeTextModel('<reasoning>think here</reasoning>output');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: extractReasoningMiddleware(tagName: 'reasoning'),
        );

        final result = await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        final reasoningParts = result.content
            .whereType<LanguageModelV4ReasoningPart>()
            .toList();
        expect(reasoningParts.length, 1);
        expect(reasoningParts[0].text, 'think here');
      });

      test(
        'converts <think> text deltas to StreamPartReasoningDelta in stream',
        () async {
          // Use separate deltas so the middleware can properly split on tag boundaries
          final inner = FakeStreamModel([
            const StreamPartTextStart(id: 't1'),
            const StreamPartTextDelta(id: 't1', delta: '<think>'),
            const StreamPartTextDelta(id: 't1', delta: 'reasoning'),
            const StreamPartTextDelta(id: 't1', delta: '</think>'),
            const StreamPartTextDelta(id: 't1', delta: 'answer'),
            const StreamPartTextEnd(id: 't1'),
            StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
          ]);

          final wrapped = wrapLanguageModel(
            model: inner,
            middleware: extractReasoningMiddleware(tagName: 'think'),
          );

          final streamResult = await wrapped.doStream(
            LanguageModelV4CallOptions(
              prompt: const LanguageModelV4Prompt(messages: []),
            ),
          );

          final parts = await streamResult.stream.toList();
          final reasoningParts = parts.whereType<StreamPartReasoningDelta>();
          expect(reasoningParts.isNotEmpty, isTrue);
          // All reasoning text should combine to contain 'reasoning'
          final combined = reasoningParts.map((p) => p.delta).join();
          expect(combined, contains('reasoning'));
        },
      );

      group('stream tag parsing', () {
        Future<List<LanguageModelV4StreamPart>> transformParts(
          List<LanguageModelV4StreamPart> sourceParts, {
          String tagName = 'think',
        }) async {
          final wrapped = wrapLanguageModel(
            model: FakeStreamModel(sourceParts),
            middleware: extractReasoningMiddleware(tagName: tagName),
          );
          final result = await wrapped.doStream(
            LanguageModelV4CallOptions(
              prompt: const LanguageModelV4Prompt(messages: []),
            ),
          );
          return result.stream.toList();
        }

        Object event(LanguageModelV4StreamPart part) => switch (part) {
          StreamPartReasoningStart(:final id) => ('reasoning-start', id),
          StreamPartReasoningDelta(:final id, :final delta) => (
            'reasoning-delta',
            id,
            delta,
          ),
          StreamPartReasoningEnd(:final id) => ('reasoning-end', id),
          StreamPartTextDelta(:final id, :final delta) => (
            'text-delta',
            id,
            delta,
          ),
          StreamPartTextStart(:final id) => ('text-start', id),
          StreamPartTextEnd(:final id) => ('text-end', id),
          StreamPartSource(:final source) => ('source', source.id),
          StreamPartFinish() => ('finish',),
          _ => part.runtimeType,
        };

        Object streamTextEvent(StreamTextEvent part) => switch (part) {
          StreamTextReasoningStartEvent(:final id) => ('reasoning-start', id),
          StreamTextReasoningDeltaEvent(:final id, :final delta) => (
            'reasoning-delta',
            id,
            delta,
          ),
          StreamTextReasoningEndEvent(:final id) => ('reasoning-end', id),
          _ => part.runtimeType,
        };

        Future<({List<String> reasoning, String text})> extract(
          List<String> deltas,
        ) async {
          final wrapped = wrapLanguageModel(
            model: textDeltaStream(deltas),
            middleware: extractReasoningMiddleware(tagName: 'think'),
          );
          final streamResult = await wrapped.doStream(
            LanguageModelV4CallOptions(
              prompt: const LanguageModelV4Prompt(messages: []),
            ),
          );
          final reasoning = <String>[];
          final text = StringBuffer();
          StringBuffer? block;
          await for (final part in streamResult.stream) {
            switch (part) {
              case StreamPartReasoningStart():
                expect(block, isNull, reason: 'nested reasoning start');
                block = StringBuffer();
              case StreamPartReasoningDelta(:final delta):
                expect(block, isNotNull, reason: 'delta outside reasoning');
                block!.write(delta);
              case StreamPartReasoningEnd():
                expect(block, isNotNull, reason: 'end outside reasoning');
                reasoning.add(block!.toString());
                block = null;
              case StreamPartTextDelta(:final delta):
                expect(block, isNull, reason: 'text inside reasoning');
                text.write(delta);
              default:
            }
          }
          expect(block, isNull, reason: 'unclosed reasoning block');
          return (reasoning: reasoning, text: text.toString());
        }

        test('one delta holds a whole block and the answer', () async {
          final result = await extract(['<think>plan</think>Done.']);
          expect(result.reasoning, ['plan']);
          expect(result.text, 'Done.');
        });

        test('one delta holds two blocks', () async {
          final result = await extract([
            'A<think>one</think>B<think>two</think>C',
          ]);
          expect(result.reasoning, ['one', 'two']);
          expect(result.text, 'ABC');
        });

        test('one delta holds the close tag and the following text', () async {
          final result = await extract([
            '<think>plan',
            ' more</think>The answer is long enough.',
          ]);
          expect(result.reasoning, ['plan more']);
          expect(result.text, 'The answer is long enough.');
        });

        test('one delta holds a close tag and a new open tag', () async {
          final result = await extract([
            '<think>one',
            '</think>mid<think>two',
            '</think>end',
          ]);
          expect(result.reasoning, ['one', 'two']);
          expect(result.text, 'midend');
        });

        test('tags split across delta boundaries', () async {
          final result = await extract([
            'Hi <th',
            'ink>pl',
            'an</thi',
            'nk>Done.',
          ]);
          expect(result.reasoning, ['plan']);
          expect(result.text, 'Hi Done.');
        });

        test('per-character stream', () async {
          final result = await extract(
            'a<think>x</think>b<think>y</think>c'.split(''),
          );
          expect(result.reasoning, ['x', 'y']);
          expect(result.text, 'abc');
        });

        test(
          'ends unmatched reasoning at raw EOF after flushing content',
          () async {
            final parts = await transformParts([
              const StreamPartTextStart(id: 'source-text'),
              const StreamPartTextDelta(id: 'source-text', delta: '<think>'),
              const StreamPartTextDelta(id: 'source-text', delta: 'x'),
            ]);
            expect(parts.map(event), [
              ('text-start', 'source-text'),
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-delta', 'mw-reasoning', 'x'),
              ('reasoning-end', 'mw-reasoning'),
            ]);
          },
        );

        const source = LanguageModelV4SourcePart(
          id: 'source-1',
          url: 'https://example.com',
        );
        for (final testCase in [
          (
            name: 'empty active reasoning buffer',
            sourceParts: <LanguageModelV4StreamPart>[
              const StreamPartTextDelta(id: 'source-text', delta: '<think>'),
            ],
            expected: <Object>[
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-end', 'mw-reasoning'),
            ],
          ),
          (
            name: 'reasoning buffer flushed by a non-text part',
            sourceParts: <LanguageModelV4StreamPart>[
              const StreamPartTextDelta(id: 'source-text', delta: '<think>x'),
              const StreamPartSource(source: source),
            ],
            expected: <Object>[
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-delta', 'mw-reasoning', 'x'),
              ('source', 'source-1'),
              ('reasoning-end', 'mw-reasoning'),
            ],
          ),
        ]) {
          test('closes ${testCase.name} at raw EOF', () async {
            final parts = await transformParts(testCase.sourceParts);
            expect(parts.map(event), testCase.expected);
          });
        }

        test('closes unmatched reasoning before terminal finish', () async {
          final parts = await transformParts([
            const StreamPartTextDelta(id: 'source-text', delta: '<think>x'),
            StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
          ]);
          expect(parts.map(event), [
            ('reasoning-start', 'mw-reasoning'),
            ('reasoning-delta', 'mw-reasoning', 'x'),
            ('reasoning-end', 'mw-reasoning'),
            ('finish',),
          ]);
        });

        test(
          'flushes reasoning before a source and continues through close tag',
          () async {
            const source = LanguageModelV4SourcePart(
              id: 'source-1',
              url: 'https://example.com',
            );
            final parts = await transformParts([
              const StreamPartTextDelta(id: 'source-text', delta: '<think>x'),
              const StreamPartSource(source: source),
              const StreamPartTextDelta(id: 'source-text', delta: '</think>'),
            ]);
            expect(parts.map(event), [
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-delta', 'mw-reasoning', 'x'),
              ('source', 'source-1'),
              ('reasoning-end', 'mw-reasoning'),
            ]);
          },
        );

        test(
          'empty tag name handles empty delimiters and flushes following text',
          () async {
            final parts = await transformParts([
              const StreamPartTextDelta(id: 'source-text', delta: ''),
              const StreamPartTextDelta(id: 'source-text', delta: '<>x</>ok'),
              const StreamPartTextDelta(id: 'source-text', delta: ''),
            ], tagName: '');
            expect(parts.map(event), [
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-delta', 'mw-reasoning', 'x'),
              ('reasoning-end', 'mw-reasoning'),
              ('text-delta', 'source-text', 'o'),
              ('text-delta', 'mw-text', 'k'),
            ]);
          },
        );

        test(
          'empty deltas and blocks preserve start/end order with custom tags',
          () async {
            final parts = await transformParts([
              const StreamPartTextDelta(id: 'text-custom', delta: ''),
              const StreamPartTextDelta(
                id: 'text-custom',
                delta: '<reasoning>',
              ),
              const StreamPartTextDelta(id: 'text-custom', delta: ''),
              const StreamPartTextDelta(
                id: 'text-custom',
                delta: '</reasoning>',
              ),
            ], tagName: 'reasoning');
            expect(parts.map(event), [
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-end', 'mw-reasoning'),
            ]);
          },
        );

        test(
          'streamText reports separate blocks sharing middleware reasoning ID',
          () async {
            final result = await streamText(
              model: wrapLanguageModel(
                model: textDeltaStream([
                  '<think>one</think>middle<think>two</think>end',
                ]),
                middleware: extractReasoningMiddleware(tagName: 'think'),
              ),
              prompt: 'think',
            );
            final reasoningEvents = await result.fullStream
                .where(
                  (part) =>
                      part is StreamTextReasoningStartEvent ||
                      part is StreamTextReasoningDeltaEvent ||
                      part is StreamTextReasoningEndEvent,
                )
                .toList();
            expect(reasoningEvents.map(streamTextEvent), [
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-delta', 'mw-reasoning', 'one'),
              ('reasoning-end', 'mw-reasoning'),
              ('reasoning-start', 'mw-reasoning'),
              ('reasoning-delta', 'mw-reasoning', 'two'),
              ('reasoning-end', 'mw-reasoning'),
            ]);
            expect((await result.reasoning).map((part) => part.text), [
              'one',
              'two',
            ]);
            expect(await result.reasoningText, 'onetwo');
          },
        );

        test('streamText reports reasoning and textStream', () async {
          final result = await streamText(
            model: wrapLanguageModel(
              model: textDeltaStream(['<think>plan</think>Done.']),
              middleware: extractReasoningMiddleware(tagName: 'think'),
            ),
            prompt: 'think',
          );
          final text = await result.textStream.join();
          expect(text, 'Done.');
          expect(await result.reasoningText, 'plan');
        });
      });

      test('text without tags passes through unchanged', () async {
        final inner = FakeTextModel('plain text without tags');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: extractReasoningMiddleware(),
        );

        final result = await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        final reasoningParts = result.content
            .whereType<LanguageModelV4ReasoningPart>()
            .toList();
        final textParts = result.content
            .whereType<LanguageModelV4TextPart>()
            .toList();

        expect(reasoningParts, isEmpty);
        expect(textParts.any((p) => p.text.contains('plain text')), isTrue);
      });
    });

    // ── extractJsonMiddleware ─────────────────────────────────────────────

    group('extractJsonMiddleware', () {
      test('strips ```json ... ``` code fences from generate output', () async {
        final inner = FakeTextModel('```json\n{"ok":true}\n```');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: extractJsonMiddleware(),
        );

        final result = await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        final textPart = result.content
            .whereType<LanguageModelV4TextPart>()
            .first;
        expect(textPart.text.contains('```'), isFalse);
        expect(textPart.text.trim(), '{"ok":true}');
      });

      test('passes through text without code fences unchanged', () async {
        final inner = FakeTextModel('{"already":"clean"}');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: extractJsonMiddleware(),
        );

        final result = await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        final textPart = result.content
            .whereType<LanguageModelV4TextPart>()
            .first;
        expect(textPart.text.trim(), '{"already":"clean"}');
      });
    });

    // ── simulateStreamingMiddleware ────────────────────────────────────────

    group('simulateStreamingMiddleware', () {
      test('calls doGenerate and fans out result as stream parts', () async {
        final inner = FakeTextModel(
          'streamed text',
          finishReason: LanguageModelV4FinishReason.stop,
        );
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: simulateStreamingMiddleware(),
        );

        final streamResult = await wrapped.doStream(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        final parts = await streamResult.stream.toList();
        expect(parts.whereType<StreamPartTextDelta>().isNotEmpty, isTrue);
        expect(parts.whereType<StreamPartFinish>().isNotEmpty, isTrue);

        final text = parts
            .whereType<StreamPartTextDelta>()
            .map((p) => p.delta)
            .join();
        expect(text, 'streamed text');
      });

      test('finish part has correct finishReason', () async {
        final inner = FakeTextModel(
          'done',
          finishReason: LanguageModelV4FinishReason.stop,
        );
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: simulateStreamingMiddleware(),
        );

        final streamResult = await wrapped.doStream(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        final parts = await streamResult.stream.toList();
        final finish = parts.whereType<StreamPartFinish>().first;
        expect(finish.finishReason, LanguageModelV4FinishReason.stop);
      });
    });

    // ── defaultSettingsMiddleware ─────────────────────────────────────────

    group('defaultSettingsMiddleware', () {
      test('applies temperature default when not set at call time', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: defaultSettingsMiddleware(temperature: 0.5),
        );

        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        expect(capturingModel.capturedOptions.first.temperature, 0.5);
      });

      test('call-time temperature overrides the default', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: defaultSettingsMiddleware(temperature: 0.5),
        );

        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            temperature: 0.9,
          ),
        );

        expect(capturingModel.capturedOptions.first.temperature, 0.9);
      });

      test('applies maxOutputTokens default', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: defaultSettingsMiddleware(maxOutputTokens: 200),
        );

        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        expect(capturingModel.capturedOptions.first.maxOutputTokens, 200);
      });

      test('applies topP default when not overridden', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: defaultSettingsMiddleware(topP: 0.95),
        );

        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
          ),
        );

        expect(capturingModel.capturedOptions.first.topP, 0.95);
      });

      test('generateText forwards topK through to call options', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: defaultSettingsMiddleware(),
        );

        await generateText(model: wrapped, prompt: 'hi', topK: 7);

        expect(capturingModel.capturedOptions.single.topK, 7);
      });
    });

    // ── addToolInputExamplesMiddleware ────────────────────────────────────

    group('addToolInputExamplesMiddleware', () {
      test('appends Examples section to tool description', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: addToolInputExamplesMiddleware(),
        );

        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            tools: [
              const LanguageModelV4FunctionTool(
                name: 'search',
                inputSchema: {'type': 'object'},
                description: 'Search the web',
                inputExamples: [
                  {'query': 'Dart async programming'},
                ],
              ),
            ],
          ),
        );

        final tool = capturingModel.capturedOptions.first.tools.first;
        expect(tool.description, contains('Examples:'));
        expect(tool.description, contains('Dart async programming'));
      });

      test('tools without inputExamples are left unchanged', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(
          model: capturingModel,
          middleware: addToolInputExamplesMiddleware(),
        );

        await wrapped.doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            tools: [
              const LanguageModelV4FunctionTool(
                name: 'simple',
                inputSchema: {'type': 'object'},
                description: 'A simple tool',
              ),
            ],
          ),
        );

        final tool = capturingModel.capturedOptions.first.tools.first;
        expect(tool.description, 'A simple tool');
      });
    });
  });
}

/// Middleware that overrides temperature via transformParams.
class _TransformParamsMiddleware extends LanguageModelMiddlewareBase {
  _TransformParamsMiddleware({required this.temperature});
  final double temperature;

  @override
  FutureOr<LanguageModelV4CallOptions> transformParams({
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) {
    return LanguageModelV4CallOptions(
      prompt: options.prompt,
      tools: options.tools,
      toolChoice: options.toolChoice,
      maxOutputTokens: options.maxOutputTokens,
      temperature: temperature,
      topP: options.topP,
      topK: options.topK,
      presencePenalty: options.presencePenalty,
      frequencyPenalty: options.frequencyPenalty,
      stopSequences: options.stopSequences,
      seed: options.seed,
      headers: options.headers,
      providerOptions: options.providerOptions,
    );
  }
}

/// Middleware that logs transformParams and wrapGenerate call order.
class _LoggingTransformMiddleware extends LanguageModelMiddlewareBase {
  _LoggingTransformMiddleware(this.log);
  final List<String> log;

  @override
  FutureOr<LanguageModelV4CallOptions> transformParams({
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) {
    log.add('transformParams');
    return options;
  }

  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    log.add('wrapGenerate');
    return doGenerate(options);
  }
}

/// Middleware that does nothing (inherits all pass-through defaults).
class _NoOpMiddleware extends LanguageModelMiddlewareBase {}

/// A middleware that records its name in a shared list when invoked.
class _TrackingMiddleware extends LanguageModelMiddlewareBase {
  _TrackingMiddleware(this.name, this.callOrder);

  final String name;
  final List<String> callOrder;

  @override
  Future<LanguageModelV4GenerateResult> wrapGenerate({
    required Future<LanguageModelV4GenerateResult> Function(
      LanguageModelV4CallOptions options,
    )
    doGenerate,
    required LanguageModelV4CallOptions options,
    required LanguageModelV4 model,
  }) async {
    callOrder.add(name);
    return doGenerate(options);
  }
}
