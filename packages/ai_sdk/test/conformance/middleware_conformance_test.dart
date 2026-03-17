import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('middleware conformance', () {
    // ── wrapLanguageModel() identity ──────────────────────────────────────

    group('wrapLanguageModel() identity', () {
      test('preserves provider from inner model', () {
        final inner = FakeTextModel('hi', provider: 'test-provider');
        final wrapped = wrapLanguageModel(inner, []);
        expect(wrapped.provider, 'test-provider');
      });

      test('preserves modelId from inner model', () {
        final inner = FakeTextModel('hi', modelId: 'gpt-4o');
        final wrapped = wrapLanguageModel(inner, []);
        expect(wrapped.modelId, 'gpt-4o');
      });

      test('preserves specificationVersion from inner model', () {
        final inner = FakeTextModel('hi');
        final wrapped = wrapLanguageModel(inner, []);
        expect(wrapped.specificationVersion, 'v3');
      });

      test('empty middleware list returns model with same behavior', () async {
        final inner = FakeTextModel('hello from inner');
        final wrapped = wrapLanguageModel(inner, []);
        final result = await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );
        final text = result.content.whereType<LanguageModelV3TextPart>().first;
        expect(text.text, 'hello from inner');
      });
    });

    // ── Middleware chaining order ──────────────────────────────────────────

    group('middleware chaining', () {
      test('middleware applied left-to-right; first is outermost', () async {
        final callOrder = <String>[];

        final outerMw = _TrackingMiddleware('outer', callOrder);
        final innerMw = _TrackingMiddleware('inner', callOrder);

        final model = FakeTextModel('result');
        final wrapped = wrapLanguageModel(model, [outerMw, innerMw]);

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
          final wrapped = wrapLanguageModel(inner, [
            extractReasoningMiddleware(tagName: 'think'),
          ]);

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
        final wrapped = wrapLanguageModel(inner, [
          extractReasoningMiddleware(tagName: 'reasoning'),
        ]);

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

          final wrapped = wrapLanguageModel(inner, [
            extractReasoningMiddleware(tagName: 'think'),
          ]);

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
        final wrapped = wrapLanguageModel(inner, [
          extractReasoningMiddleware(),
        ]);

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
        final wrapped = wrapLanguageModel(inner, [extractJsonMiddleware()]);

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
        final wrapped = wrapLanguageModel(inner, [extractJsonMiddleware()]);

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
        final wrapped = wrapLanguageModel(inner, [
          simulateStreamingMiddleware(),
        ]);

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
        final wrapped = wrapLanguageModel(inner, [
          simulateStreamingMiddleware(),
        ]);

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
        final wrapped = wrapLanguageModel(capturingModel, [
          defaultSettingsMiddleware(temperature: 0.5),
        ]);

        await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        expect(capturingModel.capturedOptions.first.temperature, 0.5);
      });

      test('call-time temperature overrides the default', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(capturingModel, [
          defaultSettingsMiddleware(temperature: 0.5),
        ]);

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
        final wrapped = wrapLanguageModel(capturingModel, [
          defaultSettingsMiddleware(maxOutputTokens: 200),
        ]);

        await wrapped.doGenerate(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        );

        expect(capturingModel.capturedOptions.first.maxOutputTokens, 200);
      });

      test('applies topP default when not overridden', () async {
        final capturingModel = FakeCapturingModel();
        final wrapped = wrapLanguageModel(capturingModel, [
          defaultSettingsMiddleware(topP: 0.95),
        ]);

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
        final wrapped = wrapLanguageModel(capturingModel, [
          addToolInputExamplesMiddleware(),
        ]);

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
        final wrapped = wrapLanguageModel(capturingModel, [
          addToolInputExamplesMiddleware(),
        ]);

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
