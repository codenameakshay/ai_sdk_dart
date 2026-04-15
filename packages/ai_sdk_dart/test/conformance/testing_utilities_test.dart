import 'dart:async';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('testing utilities', () {
    // ── MockLanguageModelV3 ───────────────────────────────────────────────

    group('MockLanguageModelV3', () {
      test('returns configured text response from generateText', () async {
        final model = MockLanguageModelV3(
          response: [mockText('Hello, world!')],
        );
        final result = await generateText(model: model, prompt: 'hi');
        expect(result.text, 'Hello, world!');
      });

      test('records calls in generateCalls list', () async {
        final model = MockLanguageModelV3(response: [mockText('ok')]);
        await generateText(model: model, prompt: 'first');
        await generateText(model: model, prompt: 'second');
        expect(model.generateCalls.length, 2);
      });

      test('records calls in streamCalls list', () async {
        final model = MockLanguageModelV3(response: [mockText('ok')]);
        final result = await streamText(model: model, prompt: 'test');
        await result.text; // consume the stream
        expect(model.streamCalls.length, 1);
      });

      test('throws doGenerateError when configured', () async {
        final model = MockLanguageModelV3(
          response: [],
          doGenerateError: Exception('generate error'),
        );
        expect(
          () => generateText(model: model, prompt: 'hi'),
          throwsA(isA<Exception>()),
        );
      });

      test('returns reasoning from streamText', () async {
        final model = MockLanguageModelV3(
          response: [mockReasoning('thinking...'), mockText('done')],
        );
        final result = await streamText(model: model, prompt: 'hi');
        await result.text; // consume stream
        expect(result.reasoningText, completion(contains('thinking')));
      });

      test('returns correct finishReason', () async {
        final model = MockLanguageModelV3(
          response: [mockText('hi')],
          finishReason: LanguageModelV3FinishReason.stop,
        );
        final result = await generateText(model: model, prompt: 'test');
        expect(result.finishReason, LanguageModelV3FinishReason.stop);
      });

      test('reports usage when configured', () async {
        final model = MockLanguageModelV3(
          response: [mockText('hi')],
          usage: const LanguageModelV3Usage(inputTokens: 10, outputTokens: 5),
        );
        final result = await generateText(model: model, prompt: 'test');
        expect(result.usage?.inputTokens, 10);
        expect(result.usage?.outputTokens, 5);
      });

      test('mockText helper creates LanguageModelV3TextPart', () {
        final part = mockText('hello');
        expect(part, isA<LanguageModelV3TextPart>());
        expect(part.text, 'hello');
      });

      test('mockReasoning helper creates LanguageModelV3ReasoningPart', () {
        final part = mockReasoning('think');
        expect(part, isA<LanguageModelV3ReasoningPart>());
        expect(part.text, 'think');
      });

      test('mockToolCall helper creates LanguageModelV3ToolCallPart', () {
        final part = mockToolCall(toolName: 'search', input: {'q': 'test'});
        expect(part, isA<LanguageModelV3ToolCallPart>());
        expect(part.toolName, 'search');
        expect(part.input, {'q': 'test'});
      });
    });

    // ── MockEmbeddingModelV2 ──────────────────────────────────────────────

    group('MockEmbeddingModelV2', () {
      test('returns configured embedding vector', () async {
        final model = MockEmbeddingModelV2<String>(
          embedding: [0.1, 0.2, 0.3],
        );
        final result = await embed(model: model, value: 'hello');
        expect(result.embedding, [0.1, 0.2, 0.3]);
      });

      test('returns same vector for all inputs via doEmbed', () async {
        final model = MockEmbeddingModelV2<String>(embedding: [1.0, 0.0]);
        final raw = await model.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['a', 'b', 'c']),
        );
        expect(raw.embeddings.length, 3);
        for (final e in raw.embeddings) {
          expect(e.embedding, [1.0, 0.0]);
        }
      });

      test('records calls in embedCalls list', () async {
        final model = MockEmbeddingModelV2<String>(embedding: [0.5]);
        await embed(model: model, value: 'first');
        await embed(model: model, value: 'second');
        expect(model.embedCalls.length, 2);
      });

      test('throws doEmbedError when configured', () async {
        final model = MockEmbeddingModelV2<String>(
          embedding: [],
          doEmbedError: Exception('embed error'),
        );
        expect(
          () => embed(model: model, value: 'hi'),
          throwsA(isA<Exception>()),
        );
      });
    });

    // ── MockEmbeddingModelV3 ─────────────────────────────────────────────

    group('MockEmbeddingModelV3', () {
      test('returns configured embedding vector via embed()', () async {
        final model = MockEmbeddingModelV3<String>(
          embedding: [0.4, 0.5, 0.6],
        );
        final result = await embed(model: model, value: 'hello');
        expect(result.embedding, [0.4, 0.5, 0.6]);
      });

      test('specificationVersion is v2 (underlying spec)', () {
        final model = MockEmbeddingModelV3<String>(embedding: [0.1]);
        expect(model.specificationVersion, 'v2');
      });

      test('records calls in embedCalls list', () async {
        final model = MockEmbeddingModelV3<String>(embedding: [0.1, 0.2]);
        await embed(model: model, value: 'first');
        await embed(model: model, value: 'second');
        expect(model.embedCalls.length, 2);
      });

      test('throws doEmbedError when configured', () {
        final model = MockEmbeddingModelV3<String>(
          embedding: [],
          doEmbedError: Exception('v3 embed error'),
        );
        expect(
          () => embed(model: model, value: 'hi'),
          throwsA(isA<Exception>()),
        );
      });

      test('returns same vector for all inputs via doEmbed', () async {
        final model = MockEmbeddingModelV3<String>(embedding: [9.0, 8.0]);
        final raw = await model.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['x', 'y']),
        );
        expect(raw.embeddings.length, 2);
        for (final e in raw.embeddings) {
          expect(e.embedding, [9.0, 8.0]);
        }
      });

      test('works with embedMany()', () async {
        final model = MockEmbeddingModelV3<String>(embedding: [0.7, 0.8]);
        final result = await embedMany(
          model: model,
          values: ['a', 'b', 'c'],
        );
        expect(result.embeddings, hasLength(3));
        for (final e in result.embeddings) {
          expect(e.embedding, [0.7, 0.8]);
        }
      });
    });

    // ── MockImageModelV3 ─────────────────────────────────────────────────

    group('MockImageModelV3', () {
      test('returns configured image bytes', () async {
        final bytes = Uint8List.fromList([0, 1, 2, 3]);
        final model = MockImageModelV3(images: [bytes]);
        final result = await generateImage(model: model, prompt: 'a cat');
        expect(result.image.bytes, bytes);
      });

      test('records calls in generateCalls list', () async {
        final model = MockImageModelV3(
          images: [Uint8List.fromList([0])],
        );
        await generateImage(model: model, prompt: 'test 1');
        await generateImage(model: model, prompt: 'test 2');
        expect(model.generateCalls.length, 2);
      });

      test('throws doGenerateError when configured', () async {
        final model = MockImageModelV3(
          images: [],
          doGenerateError: Exception('image error'),
        );
        expect(
          () => generateImage(model: model, prompt: 'hi'),
          throwsA(isA<Exception>()),
        );
      });
    });

    // ── mockId() ─────────────────────────────────────────────────────────

    group('mockId()', () {
      test('starts at 0 and increments', () {
        final id = mockId();
        expect(id(), '0');
        expect(id(), '1');
        expect(id(), '2');
      });

      test('two independent generators are independent', () {
        final id1 = mockId();
        final id2 = mockId();
        expect(id1(), '0');
        expect(id1(), '1');
        expect(id2(), '0');
        expect(id1(), '2');
        expect(id2(), '1');
      });
    });

    // ── mockValues() ─────────────────────────────────────────────────────

    group('mockValues()', () {
      test('returns values in order', () {
        final next = mockValues(['a', 'b', 'c']);
        expect(next(), 'a');
        expect(next(), 'b');
        expect(next(), 'c');
      });

      test('stays at last value after exhausting list', () {
        final next = mockValues([1, 2]);
        expect(next(), 1);
        expect(next(), 2);
        expect(next(), 2);
        expect(next(), 2);
      });

      test('works with single element list', () {
        final next = mockValues(['only']);
        expect(next(), 'only');
        expect(next(), 'only');
      });

      test('throws for empty list', () {
        expect(() => mockValues<String>([]), throwsArgumentError);
      });
    });

    // ── wrapImageModel() ─────────────────────────────────────────────────

    group('wrapImageModel()', () {
      test('preserves provider, modelId, specificationVersion', () {
        final inner = MockImageModelV3(images: []);
        final wrapped = wrapImageModel(
          model: inner,
          middleware: <ImageModelMiddleware>[],
        );
        expect(wrapped.provider, inner.provider);
        expect(wrapped.modelId, inner.modelId);
        expect(wrapped.specificationVersion, inner.specificationVersion);
      });

      test('passes call through with empty middleware list', () async {
        final bytes = Uint8List.fromList([9, 8, 7]);
        final inner = MockImageModelV3(images: [bytes]);
        final wrapped = wrapImageModel(
          model: inner,
          middleware: <ImageModelMiddleware>[],
        );
        final result = await generateImage(
          model: wrapped,
          prompt: 'sunset',
        );
        expect(result.image.bytes, bytes);
      });

      test('transformParams can modify prompt', () async {
        final inner = MockImageModelV3(
          images: [Uint8List.fromList([1])],
        );
        final mw = _PrefixPromptMiddleware('detailed: ');
        final wrapped = wrapImageModel(model: inner, middleware: mw);

        await wrapped.doGenerate(
          const ImageModelV3CallOptions(prompt: 'cat'),
        );

        expect(inner.generateCalls.first.prompt, 'detailed: cat');
      });

      test('single middleware can be passed without a list', () async {
        final inner = MockImageModelV3(
          images: [Uint8List.fromList([1])],
        );
        // _ConcreteImageMiddleware is a no-op concrete subclass
        final mw = _ConcreteImageMiddleware();
        final wrapped = wrapImageModel(model: inner, middleware: mw);
        expect(wrapped, isA<ImageModelV3>());
      });

      test('throws ArgumentError for invalid middleware type', () {
        final inner = MockImageModelV3(images: []);
        expect(
          () => wrapImageModel(model: inner, middleware: 'invalid'),
          throwsArgumentError,
        );
      });
    });
  });
}

/// Concrete no-op image middleware for testing instantiation.
class _ConcreteImageMiddleware extends ImageModelMiddlewareBase {}

/// Middleware that prepends a prefix to the prompt.
class _PrefixPromptMiddleware extends ImageModelMiddlewareBase {
  _PrefixPromptMiddleware(this.prefix);
  final String prefix;

  @override
  FutureOr<ImageModelV3CallOptions> transformParams({
    required ImageModelV3CallOptions options,
    required ImageModelV3 model,
  }) {
    return ImageModelV3CallOptions(
      prompt: options.prompt != null ? '$prefix${options.prompt}' : null,
      n: options.n,
      size: options.size,
      aspectRatio: options.aspectRatio,
      seed: options.seed,
      headers: options.headers,
      providerOptions: options.providerOptions,
    );
  }
}
