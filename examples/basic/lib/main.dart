/// AI SDK Dart — Comprehensive Example
///
/// Demonstrates the major features of the AI SDK Dart package:
///
///   1. generateText   — single-turn text generation
///   2. streamText     — streaming text with onChunk callback
///   3. structured output — typed JSON via Output.object()
///   4. tools          — single tool call + multi-step loop
///   5. embeddings     — embed + cosineSimilarity
///   6. middleware     — extractReasoningMiddleware + defaultSettingsMiddleware
///   7. registry       — multi-provider model lookup
///
/// Prerequisites:
///   Set the OPENAI_API_KEY environment variable before running.
///
/// Run:
///   dart run lib/main.dart
///
import 'dart:io';

import 'package:ai/ai.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

void header(String title) {
  final bar = '─' * (title.length + 4);
  print('\n┌$bar┐');
  print('│  $title  │');
  print('└$bar┘');
}

// ─── 1. generateText ────────────────────────────────────────────────────────

Future<void> demo1GenerateText() async {
  header('1 · generateText');

  final result = await generateText(
    model: openai('gpt-4.1-mini'),
    prompt: 'Name three planets in our solar system. Be concise.',
  );

  print('Text    : ${result.text}');
  print('Reason  : ${result.finishReason}');
  print(
    'Usage   : ${result.usage?.inputTokens} in / ${result.usage?.outputTokens} out',
  );
}

// ─── 2. streamText ──────────────────────────────────────────────────────────

Future<void> demo2StreamText() async {
  header('2 · streamText (streaming)');

  final result = await streamText(
    model: openai('gpt-4.1-mini'),
    prompt: 'Count from 1 to 5, one number per line.',
    onChunk: (chunk) {
      if (chunk is StreamTextTextChunk) {
        stdout.write(chunk.text);
      }
    },
  );

  // Drain the stream so the onChunk callbacks fire.
  await result.text;
  print('\n[stream complete]');
}

// ─── 3. Structured output ───────────────────────────────────────────────────

Future<void> demo3StructuredOutput() async {
  header('3 · Structured output (Output.object)');

  final result = await generateText<Map<String, dynamic>>(
    model: openai('gpt-4.1-mini'),
    prompt: 'Give me the capital, population (approx), and currency of France.',
    output: Output.object(
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {
          'type': 'object',
          'properties': {
            'capital': {'type': 'string'},
            'population': {'type': 'number'},
            'currency': {'type': 'string'},
          },
          'required': ['capital', 'population', 'currency'],
        },
        fromJson: (json) => json,
      ),
    ),
  );

  final obj = result.output;
  print('Capital    : ${obj['capital']}');
  print('Population : ${obj['population']}');
  print('Currency   : ${obj['currency']}');
}

// ─── 4. Tools — single call + multi-step loop ───────────────────────────────

Future<void> demo4Tools() async {
  header('4 · Tools (weather lookup + multi-step)');

  // Fake weather database.
  Map<String, String> fakeWeather(String city) => switch (city.toLowerCase()) {
        'london' => {'condition': 'Rainy', 'tempC': '12'},
        'tokyo' => {'condition': 'Sunny', 'tempC': '22'},
        _ => {'condition': 'Unknown', 'tempC': '?'},
      };

  final result = await generateText(
    model: openai('gpt-4.1-mini'),
    prompt: 'What is the weather in London and Tokyo?',
    maxSteps: 5,
    tools: {
      'getWeather': tool<Map<String, dynamic>, String>(
        description: 'Get current weather for a city.',
        inputSchema: Schema<Map<String, dynamic>>(
          jsonSchema: const {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'description': 'City name'},
            },
            'required': ['city'],
          },
          fromJson: (json) => json,
        ),
        execute: (input, _) async {
          final city = input['city'] as String;
          final w = fakeWeather(city);
          return '${w['condition']}, ${w['tempC']}°C';
        },
      ),
    },
    onStepFinish: (step) {
      print(
        '  [step ${step.stepNumber}] finish=${step.finishReason} '
        'toolCalls=${step.toolCalls.length}',
      );
    },
  );

  print('Answer  : ${result.text}');
  print('Steps   : ${result.steps.length}');
}

// ─── 5. Embeddings + cosineSimilarity ───────────────────────────────────────

Future<void> demo5Embeddings() async {
  header('5 · Embeddings + cosineSimilarity');

  final embeddingModel = openai.embedding('text-embedding-3-small');

  final catResult = await embed(
    model: embeddingModel,
    value: 'a cat sitting on a mat',
  );
  final dogResult = await embed(
    model: embeddingModel,
    value: 'a dog running in a park',
  );
  final catFriendResult = await embed(
    model: embeddingModel,
    value: 'a cat playing with yarn',
  );

  final catDog = cosineSimilarity(catResult.embedding, dogResult.embedding);
  final catFriend =
      cosineSimilarity(catResult.embedding, catFriendResult.embedding);

  print('cat ↔ dog       similarity: ${catDog.toStringAsFixed(4)}');
  print('cat ↔ cat-friend similarity: ${catFriend.toStringAsFixed(4)}');
  print('(Higher = more similar)');
}

// ─── 6. Middleware ───────────────────────────────────────────────────────────

Future<void> demo6Middleware() async {
  header('6 · Middleware (defaultSettings + extractReasoning)');

  // defaultSettingsMiddleware injects a low temperature.
  // extractReasoningMiddleware strips <think>…</think> blocks emitted by
  // reasoning-capable models (e.g. claude-3-7-sonnet, o1).
  final model = wrapLanguageModel(
    openai('gpt-4.1-mini'),
    [
      defaultSettingsMiddleware(temperature: 0.2),
      extractReasoningMiddleware(tagName: 'think'),
    ],
  );

  final result = await generateText(
    model: model,
    prompt: 'What is 17 × 23? Show your work briefly.',
  );

  print('Text      : ${result.text}');
  if (result.reasoning.isNotEmpty) {
    print('Reasoning : ${result.reasoning.map((r) => r.text).join()}');
  }
}

// ─── 7. Provider registry ───────────────────────────────────────────────────

Future<void> demo7Registry() async {
  header('7 · Provider registry');

  // Register providers under string aliases.
  // RegistrableProvider wraps a language-model factory + embedding factory.
  final registry = createProviderRegistry({
    'openai': RegistrableProvider(
      languageModelFactory: openai.call,
      embeddingModelFactory: openai.embedding,
    ),
  });

  // Look up a model by "provider:modelId" — useful in config-driven apps.
  final model = registry.languageModel('openai:gpt-4.1-mini');

  final result = await generateText(
    model: model,
    prompt: 'Say "registry works!" in exactly three words.',
  );

  print('Response : ${result.text}');
}

// ─── entry point ────────────────────────────────────────────────────────────

Future<void> main() async {
  final key = Platform.environment['OPENAI_API_KEY'];
  if (key == null || key.isEmpty) {
    print(
      'Error: OPENAI_API_KEY environment variable is not set.\n'
      'Export it and re-run:\n'
      '  export OPENAI_API_KEY=sk-...',
    );
    exit(1);
  }

  try {
    await demo1GenerateText();
    await demo2StreamText();
    await demo3StructuredOutput();
    await demo4Tools();
    await demo5Embeddings();
    await demo6Middleware();
    await demo7Registry();
  } on AiApiCallError catch (e) {
    print('\nAPI error: ${e.message}');
    exit(1);
  }

  print('\nAll demos complete.');
}
