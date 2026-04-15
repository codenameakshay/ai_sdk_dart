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
        final wrapped = wrapLanguageModel(model: inner, middleware: <LanguageModelMiddleware>[]);
        expect(wrapped.provider, 'test-provider');
      });

      test('preserves modelId from inner model', () {
        final inner = FakeTextModel('hi', modelId: 'gpt-4o');
        final wrapped = wrapLanguageModel(model: inner, middleware: <LanguageModelMiddleware>[]);
        expect(wrapped.modelId, 'gpt-4o');
      });

      test('preserves specificationVersion from inner model', () {
        final inner = FakeTextModel('hi');
        final wrapped = wrapLanguageModel(model: inner, middleware: <LanguageModelMiddleware>[]);
        expect(wrapped.specificationVersion, 'v3');
      });

      test('empty middleware list returns model with same behavior', () async {
        final inner = FakeTextModel('hello from inner');
        final wrapped = wrapLanguageModel(model: inner, middleware: <LanguageModelMiddleware>[]);
        final result = await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );
        final text = result.content.whereType<LanguageModelV3TextPart>().first;
        expect(text.text, 'hello from inner');
      });
    });

    // ── transformParams hook ──────────────────────────────────────────────

    group('transformParams', () {
      test('transformParams can modify temperature before doGenerate', () async {
        final capturingModel = FakeCapturingModel();
        final mw = _TransformParamsMiddleware(temperature: 0.42);
        final wrapped = wrapLanguageModel(model: capturingModel, middleware: mw);
        await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
            temperature: 0.9,
          ),
        );
        expect(capturingModel.capturedOptions.first.temperature, 0.42);
      });

      test('transformParams can modify temperature before doStream', () async {
        final capturingModel = FakeCapturingModel();
        final mw = _TransformParamsMiddleware(temperature: 0.1);
        final wrapped = wrapLanguageModel(model: capturingModel, middleware: mw);
        await wrapped.doStream(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );
        expect(log, ['transformParams', 'wrapGenerate']);
      });

      test('default transformParams is a no-op', () async {
        final capturingModel = FakeCapturingModel();
        final mw = _NoOpMiddleware();
        final wrapped = wrapLanguageModel(model: capturingModel, middleware: mw);
        await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
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
        final wrapped = wrapLanguageModel(model: model, middleware: [outerMw, innerMw]);

        await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
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
            LanguageModelV3CallOptions(
              prompt: const LanguageModelV3Prompt(messages: []),
            ),
          );

          final reasoningParts = result.content
              .whereType<LanguageModelV3ReasoningPart>()
              .toList();
          final textParts = result.content
              .whereType<LanguageModelV3TextPart>()
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        final reasoningParts = result.content
            .whereType<LanguageModelV3ReasoningPart>()
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
            StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
          ]);

          final wrapped = wrapLanguageModel(
            model: inner,
            middleware: extractReasoningMiddleware(tagName: 'think'),
          );

          final streamResult = await wrapped.doStream(
            LanguageModelV3CallOptions(
              prompt: const LanguageModelV3Prompt(messages: []),
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

      test('text without tags passes through unchanged', () async {
        final inner = FakeTextModel('plain text without tags');
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: extractReasoningMiddleware(),
        );

        final result = await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        final reasoningParts = result.content
            .whereType<LanguageModelV3ReasoningPart>()
            .toList();
        final textParts = result.content
            .whereType<LanguageModelV3TextPart>()
            .toList();

        expect(reasoningParts, isEmpty);
        expect(textParts.any((p) => p.text.contains('plain text')), isTrue);
      });
    });

    // ── extractJsonMiddleware ─────────────────────────────────────────────

    group('extractJsonMiddleware', () {
      test('strips ```json ... ``` code fences from generate output', () async {
        final inner = FakeTextModel('```json\n{"ok":true}\n```');
        final wrapped = wrapLanguageModel(model: inner, middleware: extractJsonMiddleware());

        final result = await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        final textPart = result.content
            .whereType<LanguageModelV3TextPart>()
            .first;
        expect(textPart.text.contains('```'), isFalse);
        expect(textPart.text.trim(), '{"ok":true}');
      });

      test('passes through text without code fences unchanged', () async {
        final inner = FakeTextModel('{"already":"clean"}');
        final wrapped = wrapLanguageModel(model: inner, middleware: extractJsonMiddleware());

        final result = await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        final textPart = result.content
            .whereType<LanguageModelV3TextPart>()
            .first;
        expect(textPart.text.trim(), '{"already":"clean"}');
      });
    });

    // ── simulateStreamingMiddleware ────────────────────────────────────────

    group('simulateStreamingMiddleware', () {
      test('calls doGenerate and fans out result as stream parts', () async {
        final inner = FakeTextModel(
          'streamed text',
          finishReason: LanguageModelV3FinishReason.stop,
        );
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: simulateStreamingMiddleware(),
        );

        final streamResult = await wrapped.doStream(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
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
          finishReason: LanguageModelV3FinishReason.stop,
        );
        final wrapped = wrapLanguageModel(
          model: inner,
          middleware: simulateStreamingMiddleware(),
        );

        final streamResult = await wrapped.doStream(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        final parts = await streamResult.stream.toList();
        final finish = parts.whereType<StreamPartFinish>().first;
        expect(finish.finishReason, LanguageModelV3FinishReason.stop);
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        expect(capturingModel.capturedOptions.first.topP, 0.95);
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
            tools: [
              const LanguageModelV3FunctionTool(
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
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
            tools: [
              const LanguageModelV3FunctionTool(
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
  FutureOr<LanguageModelV3CallOptions> transformParams({
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) {
    return LanguageModelV3CallOptions(
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
  FutureOr<LanguageModelV3CallOptions> transformParams({
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) {
    log.add('transformParams');
    return options;
  }

  @override
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
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
  Future<LanguageModelV3GenerateResult> wrapGenerate({
    required Future<LanguageModelV3GenerateResult> Function(
      LanguageModelV3CallOptions options,
    )
    doGenerate,
    required LanguageModelV3CallOptions options,
    required LanguageModelV3 model,
  }) async {
    callOrder.add(name);
    return doGenerate(options);
  }
}
