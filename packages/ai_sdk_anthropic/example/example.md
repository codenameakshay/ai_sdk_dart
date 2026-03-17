# ai_sdk_anthropic examples

## Installation

```sh
dart pub add ai_sdk_dart ai_sdk_anthropic
export ANTHROPIC_API_KEY=sk-ant-...
```

---

## Text generation

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';

final result = await generateText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'Explain quantum entanglement in one sentence.',
);
print(result.text);
print('tokens used: ${result.usage?.totalTokens}');
```

---

## Streaming

```dart
import 'dart:io';

final result = await streamText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'Write a short poem about Dart.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

---

## System prompt

```dart
final result = await generateText(
  model: anthropic('claude-sonnet-4-5'),
  system: 'You are a concise assistant. Reply in at most two sentences.',
  prompt: 'What is the Dart programming language?',
);
print(result.text);
```

---

## Extended thinking (reasoning)

Claude's native `thinking` content blocks are surfaced as `ReasoningPart` via
`extractReasoningMiddleware`:

```dart
final model = wrapLanguageModel(
  anthropic('claude-sonnet-4-5'),
  [extractReasoningMiddleware(tagName: 'think')],
);

final result = await generateText(
  model: model,
  prompt: 'Solve step by step: if 3x + 5 = 20, what is x?',
);
print('Answer   : ${result.text}');
print('Reasoning: ${result.reasoningText}');
```

---

## Tools (multi-step agent)

```dart
final result = await generateText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'What is the weather in London?',
  maxSteps: 5,
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
      execute: (input, _) async => 'Cloudy, 14°C in ${input['city']}',
    ),
  },
);
print(result.text);
```

---

## Structured output

```dart
final result = await generateText<Map<String, dynamic>>(
  model: anthropic('claude-haiku-4-5'),
  prompt: 'Give me the capital and population of France as JSON.',
  output: Output.object(
    schema: Schema<Map<String, dynamic>>(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'capital': {'type': 'string'},
          'population': {'type': 'number'},
        },
      },
      fromJson: (json) => json,
    ),
  ),
);
print(result.output); // {capital: Paris, population: 68000000}
```

---

## Middleware — default settings

```dart
final model = wrapLanguageModel(
  anthropic('claude-sonnet-4-5'),
  [defaultSettingsMiddleware(temperature: 0.3, maxTokens: 512)],
);

final result = await generateText(
  model: model,
  prompt: 'Summarise the Dart language in three bullet points.',
);
print(result.text);
```

---

## Runnable example apps

- **[`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)** — Dart CLI
- **[`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)** — Flutter app with Anthropic provider switcher
