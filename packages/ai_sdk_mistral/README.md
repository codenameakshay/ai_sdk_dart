# ai_sdk_mistral

Mistral AI provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Supports Mistral language models and text embeddings.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_mistral: ^1.1.0
```

## Usage

Set your API key via environment variable:

```sh
export MISTRAL_API_KEY=...
```

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mistral/ai_sdk_mistral.dart';

final result = await generateText(
  model: mistral('mistral-large-latest'),
  prompt: 'Explain the difference between supervised and unsupervised learning.',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: mistral('mistral-small-latest'),
  prompt: 'Write a limerick about Dart.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Embeddings

```dart
final result = await embed(
  model: mistral.embedding('mistral-embed'),
  value: 'Hello, world!',
);
print(result.embedding); // List<double>
```

### Structured output

```dart
final result = await generateText<Map<String, dynamic>>(
  model: mistral('mistral-large-latest'),
  prompt: 'Return the capital and population of France as JSON.',
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
print(result.output);
```

### Custom API key

```dart
final myMistral = MistralProvider(apiKey: 'my-key');
final result = await generateText(
  model: myMistral('codestral-latest'),
  prompt: 'Write a Dart function that reverses a string.',
);
```

### With provider registry

```dart
final registry = createProviderRegistry({
  'mistral': RegistrableProvider(
    languageModelFactory: mistral.call,
    embeddingModelFactory: mistral.embedding,
  ),
});

final model = registry.languageModel('mistral:mistral-large-latest');
```

## License

MIT
