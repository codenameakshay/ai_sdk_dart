# ai_sdk_google

Google Generative AI provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Supports Gemini language models and text embeddings.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.2.0
  ai_sdk_google: ^1.2.0
```

## Usage

The top-level `google` factory reads
`const String.fromEnvironment('GOOGLE_API_KEY')`. Use it with
`fvm dart run --define=GOOGLE_API_KEY=AIza... bin/app.dart`, or read
`Platform.environment['GOOGLE_API_KEY']` yourself and pass `apiKey:` to
`GoogleGenerativeAIProvider` in server and CLI apps.

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';

final result = await generateText(
  model: google('gemini-2.0-flash'),
  prompt: 'What is the speed of light?',
);
print(result.text);
```

### Streaming

```dart
import 'dart:io';

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
final myGoogle = GoogleGenerativeAIProvider(apiKey: 'AIza...');
final result = await generateText(
  model: myGoogle('gemini-2.0-flash'),
  prompt: 'Hello!',
);
```

## License

MIT
