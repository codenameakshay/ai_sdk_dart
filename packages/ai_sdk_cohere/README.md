# ai_sdk_cohere

Cohere provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Supports language models, text embeddings, and reranking via the Cohere API.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^2.0.0
  ai_sdk_cohere: ^2.0.0
```

## Usage

The top-level `cohere` factory reads
`const String.fromEnvironment('COHERE_API_KEY')`. Use it with
`fvm dart run --define=COHERE_API_KEY=... bin/app.dart`, or read
`Platform.environment['COHERE_API_KEY']` yourself and pass `apiKey:` to
`CohereProvider` in server and CLI apps.

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
import 'dart:io';

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
