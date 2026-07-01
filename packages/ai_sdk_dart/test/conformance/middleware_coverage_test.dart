import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

/// Targets the less-exercised branches of the language/image/embedding
/// middleware: wrong-type ArgumentError, wrapped-model getters, the
/// extractReasoning streaming state machine, simulateStreaming over every
/// content-part type, and the wrapStream overrides of the settings/examples
/// middleware.
void main() {
  group('wrapLanguageModel argument validation', () {
    test('throws ArgumentError for an unsupported middleware type', () {
      expect(
        () => wrapLanguageModel(model: FakeTextModel('x'), middleware: 42),
        throwsArgumentError,
      );
    });

    test('wrapped model proxies provider/modelId/specificationVersion', () {
      final inner = FakeTextModel('x', provider: 'p', modelId: 'm');
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: defaultSettingsMiddleware(temperature: 0.1),
      );
      expect(wrapped.provider, 'p');
      expect(wrapped.modelId, 'm');
      expect(wrapped.specificationVersion, 'v3');
    });
  });

  group('extractReasoningMiddleware streaming', () {
    test('emits text before tag, reasoning inside, and trailing text',
        () async {
      final inner = FakeStreamModel([
        const StreamPartTextStart(id: 't1'),
        // Emit in pieces so the partial-tag buffering logic runs.
        const StreamPartTextDelta(id: 't1', delta: 'before '),
        const StreamPartTextDelta(id: 't1', delta: '<think>'),
        const StreamPartTextDelta(id: 't1', delta: 'secret'),
        const StreamPartTextDelta(id: 't1', delta: '</think>'),
        const StreamPartTextDelta(id: 't1', delta: ' after'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]);
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: extractReasoningMiddleware(tagName: 'think'),
      );
      final result = await streamText(model: wrapped, prompt: 'go');
      final textPieces = await result.textStream.toList();
      final joined = textPieces.join();
      final reasoning = await result.reasoning;
      expect(reasoning.map((r) => r.text).join(), contains('secret'));
      expect(joined, contains('before'));
      expect(joined, contains('after'));
      expect(joined, isNot(contains('secret')));
    });

    test('flushes buffered reasoning when a non-text part interrupts',
        () async {
      const source = LanguageModelV3SourcePart(
        id: 's1',
        url: 'https://example.com',
      );
      final inner = FakeStreamModel([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: '<think>partial'),
        // A non-text part arrives while still inside reasoning → flush.
        const StreamPartSource(source: source),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]);
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: extractReasoningMiddleware(tagName: 'think'),
      );
      final result = await streamText(model: wrapped, prompt: 'go');
      await result.text;
      final reasoning = await result.reasoning;
      expect(reasoning.map((r) => r.text).join(), contains('partial'));
    });

    test('flushes buffered text at end of stream when no tag seen', () async {
      // A short delta (< openTag length) leaves residual buffered text that
      // must be flushed at end-of-stream.
      final inner = FakeStreamModel([
        const StreamPartTextStart(id: 't1'),
        const StreamPartTextDelta(id: 't1', delta: 'hi'),
        const StreamPartTextEnd(id: 't1'),
        StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
      ]);
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: extractReasoningMiddleware(tagName: 'thinking'),
      );
      final result = await streamText(model: wrapped, prompt: 'go');
      final joined = (await result.textStream.toList()).join();
      expect(joined, contains('hi'));
    });

    test('flushes buffered reasoning at end of stream (no close tag)',
        () async {
      // Stream ends (no terminal parts) while still inside <think> with
      // residual buffered text → the end-of-stream flush emits it as
      // reasoning.
      final inner = FakeStreamModel([
        const StreamPartTextDelta(id: 't1', delta: '<think>dangling'),
      ]);
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: extractReasoningMiddleware(tagName: 'think'),
      );
      final transformed = await wrapped.doStream(
        const LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(messages: []),
        ),
      );
      final parts = await transformed.stream.toList();
      final reasoning =
          parts.whereType<StreamPartReasoningDelta>().map((p) => p.delta).join();
      expect(reasoning, contains('dangling'));
    });

    test('flushes buffered text at end of stream (no terminal parts)',
        () async {
      // Only short text deltas (< tag length) and nothing to trigger an
      // in-loop flush → the end-of-stream flush emits the buffered text.
      final inner = FakeStreamModel([
        const StreamPartTextDelta(id: 't1', delta: 'hi'),
      ]);
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: extractReasoningMiddleware(tagName: 'thinking'),
      );
      final transformed = await wrapped.doStream(
        const LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(messages: []),
        ),
      );
      final parts = await transformed.stream.toList();
      final text =
          parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join();
      expect(text, contains('hi'));
    });

    test('non-text content parts pass through wrapGenerate unchanged',
        () async {
      final inner = _MultiPartGenerateModel();
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: extractReasoningMiddleware(tagName: 'think'),
      );
      final result = await generateText(model: wrapped, prompt: 'go');
      // The source part survived the wrapGenerate transform.
      expect(result.sources, isNotEmpty);
    });
  });

  group('simulateStreamingMiddleware over content types', () {
    test('fans out reasoning, tool call, source, and file parts', () async {
      final inner = _RichGenerateModel();
      final wrapped = wrapLanguageModel(
        model: inner,
        middleware: simulateStreamingMiddleware(),
      );
      final result = await wrapped.doStream(
        LanguageModelV3CallOptions(
          prompt: const LanguageModelV3Prompt(messages: []),
        ),
      );
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartReasoningDelta>(), isNotEmpty);
      expect(parts.whereType<StreamPartToolCallStart>(), isNotEmpty);
      expect(parts.whereType<StreamPartToolCallDelta>(), isNotEmpty);
      expect(parts.whereType<StreamPartToolCallEnd>(), isNotEmpty);
      expect(parts.whereType<StreamPartSource>(), isNotEmpty);
      expect(parts.whereType<StreamPartFile>(), isNotEmpty);
      expect(parts.whereType<StreamPartFinish>(), hasLength(1));
    });

    test('propagates a doGenerate error from doStream', () async {
      final wrapped = wrapLanguageModel(
        model: FakeErrorModel(StateError('gen failed')),
        middleware: simulateStreamingMiddleware(),
      );
      await expectLater(
        wrapped.doStream(
          LanguageModelV3CallOptions(
            prompt: const LanguageModelV3Prompt(messages: []),
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('settings/examples middleware wrapStream', () {
    test('defaultSettingsMiddleware applies defaults on the stream path',
        () async {
      final capturing = FakeCapturingModel();
      final wrapped = wrapLanguageModel(
        model: capturing,
        middleware: defaultSettingsMiddleware(temperature: 0.42),
      );
      final result = await streamText(model: wrapped, prompt: 'go');
      await result.text;
      expect(capturing.capturedOptions.single.temperature, 0.42);
    });

    test('addToolInputExamplesMiddleware enriches tools on the stream path',
        () async {
      final capturing = FakeCapturingModel();
      final wrapped = wrapLanguageModel(
        model: capturing,
        middleware: addToolInputExamplesMiddleware(),
      );
      final result = await streamText(
        model: wrapped,
        prompt: 'go',
        tools: {
          'echo': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            description: 'Echo',
            execute: (_, __) async => 'ok',
            inputExamples: const [ToolInputExample(input: {'msg': 'hi'})],
          ),
        },
      );
      await result.text;
      final sentTool = capturing.capturedOptions.single.tools.single;
      expect(sentTool.description, contains('Examples:'));
    });
  });

  group('wrapImageModel', () {
    test('throws ArgumentError for an unsupported middleware type', () {
      expect(
        () => wrapImageModel(model: _FakeImageModel(), middleware: 'nope'),
        throwsArgumentError,
      );
    });

    test('proxies metadata and transformParams runs', () async {
      final inner = _FakeImageModel();
      final wrapped = wrapImageModel(
        model: inner,
        middleware: _NoopImageMiddleware(),
      );
      expect(wrapped.provider, 'fake');
      expect(wrapped.modelId, 'fake-image');
      expect(wrapped.specificationVersion, 'v3');
      final result = await wrapped.doGenerate(
        const ImageModelV3CallOptions(prompt: 'a cat'),
      );
      expect(result.images, isEmpty);
    });
  });

  group('wrapEmbeddingModel', () {
    test('throws ArgumentError for an unsupported middleware type', () {
      expect(
        () => wrapEmbeddingModel<String>(
          model: FakeEmbeddingModel([0.1]),
          middleware: 99,
        ),
        throwsArgumentError,
      );
    });

    test('proxies metadata and embeds via transformParams default', () async {
      final inner = FakeEmbeddingModel([0.1, 0.2]);
      final wrapped = wrapEmbeddingModel<String>(
        model: inner,
        middleware: _NoopEmbeddingMiddleware(),
      );
      expect(wrapped.provider, 'fake');
      expect(wrapped.modelId, 'fake-embedding-model');
      expect(wrapped.specificationVersion, 'v2');
      final result = await wrapped.doEmbed(
        const EmbeddingModelV2CallOptions(values: ['hi']),
      );
      expect(result.embeddings.single.embedding, [0.1, 0.2]);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// doGenerate returns text + a source part (a non-text part for wrapGenerate).
class _MultiPartGenerateModel implements LanguageModelV3 {
  @override
  String get provider => 'fake';
  @override
  String get modelId => 'multi-part';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return const LanguageModelV3GenerateResult(
      content: [
        LanguageModelV3TextPart(text: 'plain text'),
        LanguageModelV3SourcePart(id: 's1', url: 'https://example.com'),
      ],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async =>
      throw UnimplementedError();
}

/// doGenerate returns reasoning, tool-call, source, and file parts.
class _RichGenerateModel implements LanguageModelV3 {
  @override
  String get provider => 'fake';
  @override
  String get modelId => 'rich';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    return const LanguageModelV3GenerateResult(
      content: [
        LanguageModelV3TextPart(text: 'hello'),
        LanguageModelV3ReasoningPart(text: 'thinking'),
        LanguageModelV3ToolCallPart(
          toolCallId: 'tc-1',
          toolName: 'search',
          input: {'q': 'x'},
        ),
        LanguageModelV3SourcePart(id: 's1', url: 'https://example.com'),
        LanguageModelV3FilePart(
          mediaType: 'text/plain',
          data: DataContentBase64('aGk='),
        ),
      ],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async =>
      throw UnimplementedError();
}

class _FakeImageModel implements ImageModelV3 {
  @override
  String get provider => 'fake';
  @override
  String get modelId => 'fake-image';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<ImageModelV3GenerateResult> doGenerate(
    ImageModelV3CallOptions options,
  ) async =>
      const ImageModelV3GenerateResult(images: []);
}

class _NoopImageMiddleware extends ImageModelMiddlewareBase {
  const _NoopImageMiddleware();
}

class _NoopEmbeddingMiddleware extends EmbeddingModelMiddlewareBase<String> {
  const _NoopEmbeddingMiddleware();
}
