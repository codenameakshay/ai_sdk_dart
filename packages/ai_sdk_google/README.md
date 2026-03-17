# ai_sdk_google

Google Generative AI provider for [AI SDK Dart](https://pub.dev/packages/ai). Supports Gemini language models and text embeddings.

## Installation

```yaml
dependencies:
  ai: ^0.1.0
  ai_sdk_google: ^0.1.0
```

## Usage

Set your API key via environment variable:

```sh
export GOOGLE_GENERATIVE_AI_API_KEY=AIza...
```

### Language model

```dart
import 'package:ai/ai.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';

final result = await generateText(
  model: google('gemini-2.0-flash'),
  prompt: 'What is the speed of light?',
);
print(result.text);
```

### Streaming

```dart
final result = await streamText(
  model: google('gemini-2.0-flash'),
  prompt: 'Tell me about the history of the internet.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Embeddings

```dart
final result = await embed(
  model: google.embedding('text-embedding-004'),
  value: 'Hello, world!',
);
print(result.embedding); // List<double>
```

### Custom API key

```dart
final myGoogle = GoogleProvider(apiKey: 'AIza...');
final result = await generateText(
  model: myGoogle('gemini-2.0-flash'),
  prompt: 'Hello!',
);
```

## License

MIT
