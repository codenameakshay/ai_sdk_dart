# ai_sdk_cohere

Cohere provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Supports language models, text embeddings, and reranking via the Cohere API.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_cohere: ^1.1.0
```

## Usage

Set your API key via environment variable:

```sh
export COHERE_API_KEY=...
```

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';

final result = await generateText(
  model: cohere('command-r-plus'),
  prompt: 'Explain large language models in one paragraph.',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: cohere('command-r-plus'),
  prompt: 'Write a haiku about the ocean.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Embeddings

```dart
final result = await embed(
  model: cohere.embedding('embed-english-v3.0'),
  value: 'Hello, world!',
);
print(result.embedding); // List<double>
```

### Reranking

```dart
final result = await rerank(
  model: cohere.rerank('rerank-english-v3.0'),
  query: 'What is the capital of France?',
  documents: [
    'Paris is the capital of France.',
    'Berlin is the capital of Germany.',
    'Rome is the capital of Italy.',
  ],
);
for (final item in result.rerankedDocuments) {
  print('${item.score}: ${item.document}');
}
```

### Custom API key

```dart
final myCohere = CohereProvider(apiKey: 'my-key');
final result = await generateText(
  model: myCohere('command-r'),
  prompt: 'Hello!',
);
```

### With provider registry

```dart
final registry = createProviderRegistry({
  'cohere': RegistrableProvider(
    languageModelFactory: cohere.call,
    embeddingModelFactory: cohere.embedding,
  ),
});

final model = registry.languageModel('cohere:command-r-plus');
```

## License

MIT
