# ai

Core AI SDK for Dart — a Dart/Flutter port of [Vercel AI SDK v6](https://sdk.vercel.ai).

Provider-agnostic APIs for text generation, streaming, structured output, tool use, embeddings, and more.

---

## Installation

You need this package **plus one provider**:

```sh
# OpenAI
dart pub add ai ai_sdk_openai

# Anthropic
dart pub add ai ai_sdk_anthropic

# Google Generative AI
dart pub add ai ai_sdk_google

# Flutter apps (adds UI controllers)
dart pub add ai ai_sdk_openai ai_sdk_flutter
```

---

## Quick start

```dart
import 'package:ai/ai.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

void main() async {
  final result = await generateText(
    model: openai('gpt-4.1-mini'),
    prompt: 'Say hello from AI SDK Dart.',
  );
  print(result.text);
}
```

---

## Features

### Streaming

```dart
final result = await streamText(
  model: openai('gpt-4.1-mini'),
  prompt: 'Tell me a short story.',
  onChunk: (chunk) {
    if (chunk is StreamTextTextChunk) stdout.write(chunk.text);
  },
);
await result.text; // wait for completion
```

### Structured output

```dart
final result = await generateText<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  prompt: 'Give me info about Paris.',
  output: Output.object(
    schema: Schema<Map<String, dynamic>>(
      jsonSchema: const {'type': 'object', 'properties': {
        'city': {'type': 'string'},
        'country': {'type': 'string'},
      }},
      fromJson: (json) => json,
    ),
  ),
);
print(result.output); // {city: Paris, country: France}
```

Output modes: `Output.text()`, `Output.object()`, `Output.array()`, `Output.choice()`, `Output.json()`

### Tools + multi-step

```dart
final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'What is the weather in Tokyo?',
  maxSteps: 5,
  tools: {
    'getWeather': tool<Map<String, dynamic>, String>(
      description: 'Get weather for a city.',
      inputSchema: Schema(
        jsonSchema: const {'type': 'object', 'properties': {
          'city': {'type': 'string'},
        }},
        fromJson: (json) => json,
      ),
      execute: (input, _) async => 'Sunny, 22°C',
    ),
  },
);
print(result.text); // "The weather in Tokyo is sunny, 22°C."
```

### Embeddings

```dart
final e1 = await embed(model: openai.embedding('text-embedding-3-small'), value: 'cat');
final e2 = await embed(model: openai.embedding('text-embedding-3-small'), value: 'kitten');

print(cosineSimilarity(e1.embedding, e2.embedding)); // ~0.9
```

### Middleware

```dart
final model = wrapLanguageModel(
  openai('gpt-4.1-mini'),
  [
    defaultSettingsMiddleware(temperature: 0.2),
    extractReasoningMiddleware(tagName: 'think'),
  ],
);
```

Built-in middleware: `extractReasoningMiddleware`, `extractJsonMiddleware`, `simulateStreamingMiddleware`, `defaultSettingsMiddleware`, `addToolInputExamplesMiddleware`

### Provider registry

```dart
final registry = createProviderRegistry({
  'openai': RegistrableProvider(
    languageModelFactory: openai.call,
    embeddingModelFactory: openai.embedding,
  ),
});

final model = registry.languageModel('openai:gpt-4.1-mini');
```

---

## Provider packages

| Package | Provider |
|---------|---------|
| [`ai_sdk_openai`](https://pub.dev/packages/ai_sdk_openai) | OpenAI |
| [`ai_sdk_anthropic`](https://pub.dev/packages/ai_sdk_anthropic) | Anthropic |
| [`ai_sdk_google`](https://pub.dev/packages/ai_sdk_google) | Google Generative AI |
| [`ai_sdk_flutter`](https://pub.dev/packages/ai_sdk_flutter) | Flutter UI controllers |
| [`ai_sdk_mcp`](https://pub.dev/packages/ai_sdk_mcp) | MCP client |

---

## License

MIT
