# ai_sdk_ollama

Ollama provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Run open-source models locally via [Ollama](https://ollama.com) — no API key required.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_ollama: ^1.1.0
```

## Prerequisites

Install and start Ollama, then pull a model:

```sh
# Install: https://ollama.com/download
ollama pull llama3
ollama pull nomic-embed-text  # for embeddings
```

Ollama runs on `http://localhost:11434` by default.

## Usage

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';

final result = await generateText(
  model: ollama('llama3'),
  prompt: 'What is the Dart programming language?',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: ollama('llama3'),
  prompt: 'Write a short poem about local AI.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Embeddings

```dart
final result = await embed(
  model: ollama.embedding('nomic-embed-text'),
  value: 'Hello, world!',
);
print(result.embedding); // List<double>
```

### Tool use

Models that support function calling (e.g. `llama3.1`, `mistral`):

```dart
final result = await generateText(
  model: ollama('llama3.1'),
  prompt: 'What is 42 * 17?',
  maxSteps: 3,
  tools: {
    'calculate': tool<Map<String, dynamic>, String>(
      description: 'Evaluate a math expression.',
      inputSchema: Schema(
        jsonSchema: const {
          'type': 'object',
          'properties': {'expression': {'type': 'string'}},
        },
        fromJson: (json) => json,
      ),
      execute: (input, _) async {
        // evaluate input['expression']
        return '714';
      },
    ),
  },
);
print(result.text);
```

### Custom base URL

```dart
final myOllama = OllamaProvider(baseUrl: 'http://192.168.1.100:11434/api');
final result = await generateText(
  model: myOllama('llama3'),
  prompt: 'Hello from a remote Ollama instance!',
);
```

### With provider registry

```dart
final registry = createProviderRegistry({
  'ollama': RegistrableProvider(
    languageModelFactory: ollama.call,
    embeddingModelFactory: ollama.embedding,
  ),
});

final model = registry.languageModel('ollama:llama3');
```

## License

MIT
