# ai_sdk_azure

Azure OpenAI provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Use Azure-hosted OpenAI deployments for text generation and embeddings.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_azure: ^1.1.0
```

## Usage

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_azure/ai_sdk_azure.dart';

final provider = AzureOpenAIProvider(
  endpoint: 'https://my-resource.openai.azure.com',
  apiKey: 'my-api-key',
);

final result = await generateText(
  model: provider('gpt-4o-deployment'),
  prompt: 'Say hello from Azure OpenAI!',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: provider('gpt-4o-deployment'),
  prompt: 'Count from 1 to 5.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Embeddings

```dart
final result = await embed(
  model: provider.embedding('text-embedding-3-small-deployment'),
  value: 'Hello, world!',
);
print(result.embedding); // List<double>
```

### Custom API version

The default API version is `2024-02-15-preview`. Override it with the `apiVersion` parameter:

```dart
final provider = AzureOpenAIProvider(
  endpoint: 'https://my-resource.openai.azure.com',
  apiKey: 'my-api-key',
  apiVersion: '2024-05-01-preview',
);
```

### With provider registry

```dart
final registry = createProviderRegistry({
  'azure': RegistrableProvider(
    languageModelFactory: provider.call,
    embeddingModelFactory: provider.embedding,
  ),
});

final model = registry.languageModel('azure:gpt-4o-deployment');
```

## License

MIT
