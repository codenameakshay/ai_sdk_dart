# ai_sdk_anthropic

Anthropic provider for [AI SDK Dart](https://pub.dev/packages/ai). Supports Claude language models including extended thinking.

## Installation

```yaml
dependencies:
  ai: ^0.1.0
  ai_sdk_anthropic: ^0.1.0
```

## Usage

Set your API key via environment variable:

```sh
export ANTHROPIC_API_KEY=sk-ant-...
```

### Language model

```dart
import 'package:ai/ai.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';

final result = await generateText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'Explain quantum entanglement simply.',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'Write a haiku about Dart.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Extended thinking (reasoning)

Use `extractReasoningMiddleware` to surface `<think>` blocks from reasoning models:

```dart
import 'package:ai/ai.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';

final model = wrapLanguageModel(
  anthropic('claude-sonnet-4-5'),
  [extractReasoningMiddleware(tagName: 'think')],
);

final result = await generateText(
  model: model,
  prompt: 'Solve: if 3x + 5 = 20, what is x?',
);
print('Answer   : ${result.text}');
print('Reasoning: ${result.reasoning.map((r) => r.text).join()}');
```

### Custom API key

```dart
final myAnthropic = AnthropicProvider(apiKey: 'sk-ant-...');
final result = await generateText(
  model: myAnthropic('claude-haiku-4-5'),
  prompt: 'Hello!',
);
```

## License

MIT
