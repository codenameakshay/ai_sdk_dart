# ai_sdk_groq

Groq provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Run Llama, Mixtral, Gemma, and other models at ultra-low latency via the Groq API.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_groq: ^1.1.0
```

## Usage

Set your API key via environment variable:

```sh
export GROQ_API_KEY=gsk_...
```

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_groq/ai_sdk_groq.dart';

final result = await generateText(
  model: groq('llama3-8b-8192'),
  prompt: 'Say hello at lightning speed!',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: groq('llama-3.3-70b-versatile'),
  prompt: 'Explain recursion briefly.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Tool use

```dart
final result = await generateText(
  model: groq('llama3-groq-70b-8192-tool-use-preview'),
  prompt: 'What is the weather in Tokyo?',
  maxSteps: 3,
  tools: {
    'getWeather': tool<Map<String, dynamic>, String>(
      description: 'Get current weather for a city.',
      inputSchema: Schema(
        jsonSchema: const {
          'type': 'object',
          'properties': {'city': {'type': 'string'}},
        },
        fromJson: (json) => json,
      ),
      execute: (input, _) async => 'Sunny, 22°C',
    ),
  },
);
print(result.text);
```

### Custom API key / base URL

```dart
final myGroq = GroqProvider(
  apiKey: 'gsk_...',
  baseUrl: 'https://api.groq.com/openai/v1',
);

final result = await generateText(
  model: myGroq('llama3-8b-8192'),
  prompt: 'Hello!',
);
```

### With provider registry

```dart
final registry = createProviderRegistry({
  'groq': RegistrableProvider(
    languageModelFactory: groq.call,
  ),
});

final model = registry.languageModel('groq:llama3-8b-8192');
```

## License

MIT
