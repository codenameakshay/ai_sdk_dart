// ignore_for_file: avoid_print
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Demonstrates the core ai_sdk_dart APIs using minimal fake in-memory models
/// so the example runs without any network calls or API keys.
///
/// In a real app, replace [_FakeModel] with a real provider:
///   ```dart
///   import 'package:ai_sdk_openai/ai_sdk_openai.dart';
///   final model = openai('gpt-4.1-mini'); // needs OPENAI_API_KEY
///   ```
void main() async {
  await _textGeneration();
  await _streaming();
  await _structuredOutput();
  await _toolUse();
  await _embeddings();
  await _middleware();
}

// ---------------------------------------------------------------------------
// 1. Text generation
// ---------------------------------------------------------------------------

Future<void> _textGeneration() async {
  print('── generateText ──────────────────────────────────────────');

  final result = await generateText(
    model: _FakeModel('Hello from AI SDK Dart!'),
    prompt: 'Say hello.',
  );

  print('text        : ${result.text}');
  print('finishReason: ${result.finishReason}');
  print('steps       : ${result.steps.length}');
  print('');
}

// ---------------------------------------------------------------------------
// 2. Streaming
// ---------------------------------------------------------------------------

Future<void> _streaming() async {
  print('── streamText ────────────────────────────────────────────');

  final result = await streamText(
    model: _FakeModel('Hello, streaming world!'),
    prompt: 'Count to three.',
  );

  stdout.write('text: ');
  await for (final chunk in result.textStream) {
    stdout.write(chunk);
  }
  print('');
  print('');
}

// ---------------------------------------------------------------------------
// 3. Structured output
// ---------------------------------------------------------------------------

Future<void> _structuredOutput() async {
  print('── structured output ─────────────────────────────────────');

  final result = await generateText<Map<String, dynamic>>(
    model: _FakeModel('{"capital":"Tokyo","currency":"JPY"}'),
    prompt: 'Capital and currency of Japan.',
    output: Output.object(
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {
          'type': 'object',
          'properties': {
            'capital': {'type': 'string'},
            'currency': {'type': 'string'},
          },
        },
        fromJson: (json) => json,
      ),
    ),
  );

  print('output: ${result.output}');
  print('');
}

// ---------------------------------------------------------------------------
// 4. Tool use (multi-step)
// ---------------------------------------------------------------------------

Future<void> _toolUse() async {
  print('── tool use ──────────────────────────────────────────────');

  int _calls = 0;
  final result = await generateText(
    model: _FakeStepModel(
      onStep: (_) {
        _calls++;
        if (_calls == 1) {
          return const LanguageModelV3GenerateResult(
            content: [
              LanguageModelV3ToolCallPart(
                toolCallId: 'c1',
                toolName: 'getWeather',
                input: {'city': 'Paris'},
              ),
            ],
            finishReason: LanguageModelV3FinishReason.toolCalls,
          );
        }
        return const LanguageModelV3GenerateResult(
          content: [
            LanguageModelV3TextPart(text: 'It is sunny in Paris (23°C).'),
          ],
          finishReason: LanguageModelV3FinishReason.stop,
        );
      },
    ),
    prompt: 'What is the weather in Paris?',
    maxSteps: 3,
    tools: {
      'getWeather': tool<Map<String, dynamic>, String>(
        description: 'Get current weather for a city.',
        inputSchema: Schema<Map<String, dynamic>>(
          jsonSchema: const {
            'type': 'object',
            'properties': {'city': {'type': 'string'}},
            'required': ['city'],
          },
          fromJson: (json) => json,
        ),
        execute: (input, _) async => 'Sunny, 23°C',
      ),
    },
  );

  print('text : ${result.text}');
  print('steps: ${result.steps.length}');
  print('');
}

// ---------------------------------------------------------------------------
// 5. Embeddings + cosine similarity
// ---------------------------------------------------------------------------

Future<void> _embeddings() async {
  print('── embed + cosineSimilarity ──────────────────────────────');

  final model = _FakeEmbeddingModel([1.0, 0.0, 0.0]);

  final a = await embed(model: model, value: 'Hello');
  final b = await embed(model: model, value: 'World');

  final similarity = cosineSimilarity(a.embedding, b.embedding);
  print('cosine similarity: $similarity');
  print('');
}

// ---------------------------------------------------------------------------
// 6. Middleware — extract reasoning
// ---------------------------------------------------------------------------

Future<void> _middleware() async {
  print('── wrapLanguageModel + extractReasoningMiddleware ─────────');

  final model = wrapLanguageModel(
    _FakeModel('<think>Let me think…</think>The answer is 42.'),
    [extractReasoningMiddleware(tagName: 'think')],
  );

  final result = await generateText(model: model, prompt: 'What is 6 × 7?');

  print('text     : ${result.text}');
  print('reasoning: ${result.reasoningText}');
  print('');
}

// ---------------------------------------------------------------------------
// Minimal fake models (no network calls needed)
// ---------------------------------------------------------------------------

class _FakeModel implements LanguageModelV3 {
  const _FakeModel(this._text);
  final String _text;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'fake-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async =>
      LanguageModelV3GenerateResult(
        content: [LanguageModelV3TextPart(text: _text)],
        finishReason: LanguageModelV3FinishReason.stop,
      );

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async =>
      LanguageModelV3StreamResult(
        stream: simulateReadableStream(
          parts: [
            StreamPartTextStart(id: 'text-1'),
            StreamPartTextDelta(id: 'text-1', delta: _text),
            StreamPartTextEnd(id: 'text-1'),
            StreamPartFinish(finishReason: LanguageModelV3FinishReason.stop),
          ],
        ),
      );
}

class _FakeStepModel implements LanguageModelV3 {
  _FakeStepModel({required this.onStep});
  final LanguageModelV3GenerateResult Function(LanguageModelV3CallOptions) onStep;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'fake-step-model';
  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async =>
      onStep(options);

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async =>
      throw UnimplementedError();
}

class _FakeEmbeddingModel implements EmbeddingModelV2<String> {
  const _FakeEmbeddingModel(this._embedding);
  final List<double> _embedding;

  @override
  String get provider => 'fake';
  @override
  String get modelId => 'fake-embedding';
  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async =>
      EmbeddingModelV2GenerateResult(
        embeddings: options.values
            .map(
              (v) => EmbeddingModelV2Embedding(value: v, embedding: _embedding),
            )
            .toList(),
      );
}
