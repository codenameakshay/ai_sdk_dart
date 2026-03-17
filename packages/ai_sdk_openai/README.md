# ai_sdk_openai

OpenAI provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Supports language models, embeddings, and image generation via the OpenAI API.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.0.0
  ai_sdk_openai: ^1.0.0
```

## Usage

Set your API key via environment variable:

```sh
export OPENAI_API_KEY=sk-...
```

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'Say hello!',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: openai('gpt-4.1'),
  prompt: 'Tell me a joke.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Embeddings

```dart
final result = await embed(
  model: openai.embedding('text-embedding-3-small'),
  value: 'Hello, world!',
);
print(result.embedding); // List<double>
```

### Image generation

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final result = await generateImage(
  model: openai.image('dall-e-3'),
  prompt: 'A futuristic city at sunset.',
);
```

### Custom API key / base URL

```dart
final myOpenAi = OpenAIProvider(
  apiKey: 'sk-...',
  baseUrl: 'https://my-proxy.example.com/v1',
);

final result = await generateText(
  model: myOpenAi('gpt-4.1-mini'),
  prompt: 'Hello!',
);
```

### With provider registry

```dart
final registry = createProviderRegistry({
  'openai': RegistrableProvider(
    languageModelFactory: openai.call,
    embeddingModelFactory: openai.embedding,
  ),
});

final model = registry.languageModel('openai:gpt-4.1-mini');
```

## License

MIT
