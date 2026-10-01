# ai_sdk_anthropic

Anthropic provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Supports Claude language models including extended thinking.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^3.0.0
  ai_sdk_anthropic: ^3.0.0
```

## Usage

The top-level `anthropic` factory reads
`const String.fromEnvironment('ANTHROPIC_API_KEY')`. Use it with
`fvm dart run --define=ANTHROPIC_API_KEY=sk-ant-... bin/app.dart`, or read
`Platform.environment['ANTHROPIC_API_KEY']` yourself and pass `apiKey:` to
`AnthropicProvider` in server and CLI apps.

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';

final result = await generateText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'Explain quantum entanglement simply.',
);
print(result.text);
```

### Streaming

```dart
import 'dart:io';

final result = await streamText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'Write a haiku about Dart.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Extended thinking (reasoning)

Claude's native thinking blocks become `LanguageModelV4ReasoningPart`s without
middleware. Enable thinking and give the output more tokens than the thinking
budget:

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';

final result = await generateText(
  model: anthropic('claude-sonnet-4-5'),
  maxOutputTokens: 8192,
  providerOptions: {
    'anthropic': AnthropicThinkingOptions(budgetTokens: 5000).toMap(),
  },
  prompt: 'Solve: if 3x + 5 = 20, what is x?',
);
print('Answer   : ${result.text}');
print('Reasoning: ${result.reasoning.map((r) => r.text).join()}');
```

### Thinking options (`AnthropicThinkingOptions`)

For Claude models that support the native `thinking` API block:

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';

// Enable thinking with a 5000-token budget
final result = await generateText(
  model: anthropic('claude-opus-4-5'),
  maxOutputTokens: 8192,
  prompt: 'Prove that √2 is irrational.',
  providerOptions: {
    'anthropic': AnthropicThinkingOptions(
      budgetTokens: 5000,
    ).toMap(),
  },
);
print(result.text);

// Disable thinking for fast, low-latency responses
final fast = await generateText(
  model: anthropic('claude-sonnet-4-5'),
  prompt: 'What is 2 + 2?',
  providerOptions: {
    'anthropic': AnthropicThinkingOptions(speed: 'fast').toMap(),
  },
);
print(fast.text);
```

Extended-thinking blocks carry a `signature` on `LanguageModelV4ReasoningPart`
so Claude can verify its own prior reasoning in a follow-up turn. Don't read
or reconstruct it yourself — reuse `result.responseMessages.map(ModelMessage.fromProvider)`
as history in the next call and it round-trips automatically.

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
