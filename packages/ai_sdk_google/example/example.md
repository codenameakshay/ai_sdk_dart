# ai_sdk_google examples

## Installation

```sh
dart pub add ai_sdk_dart ai_sdk_google
export GOOGLE_API_KEY=AIza...
```

---

## Text generation

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';

final result = await generateText(
  model: google('gemini-2.0-flash'),
  prompt: 'What is the speed of light?',
);
print(result.text);
print('tokens used: ${result.usage?.totalTokens}');
```

---

## Streaming

```dart
import 'dart:io';

final result = await streamText(
  model: google('gemini-2.0-flash'),
  prompt: 'Explain how neural networks learn.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

---

## System prompt

```dart
final result = await generateText(
  model: google('gemini-2.0-flash'),
  system: 'You are a helpful assistant that replies only in haiku.',
  prompt: 'Tell me about Flutter.',
);
print(result.text);
```

---

## Structured output

```dart
final result = await generateText<Map<String, dynamic>>(
  model: google('gemini-2.0-flash'),
  prompt: 'Return the capital and timezone of Japan as JSON.',
  output: Output.object(
    schema: Schema<Map<String, dynamic>>(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'capital': {'type': 'string'},
          'timezone': {'type': 'string'},
        },
      },
      fromJson: (json) => json,
    ),
  ),
);
print(result.output); // {capital: Tokyo, timezone: Asia/Tokyo}
```

---

## Tools (multi-step agent)

```dart
final result = await generateText(
  model: google('gemini-2.0-flash'),
  prompt: 'What is the weather in Tokyo?',
  maxSteps: 5,
  tools: {
    'getWeather': tool<Map<String, dynamic>, String>(
      description: 'Get current weather for a city.',
      inputSchema: Schema<Map<String, dynamic>>(
        jsonSchema: const {
          'type': 'object',
          'properties': {'city': {'type': 'string'}},
          'required': ['city'],
        },
        fromJson: (json) => json,
      ),
      execute: (input, _) async => 'Sunny, 28°C in ${input['city']}',
    ),
  },
);
print(result.text);
```

---

## Embeddings

```dart
final a = await embed(
  model: google.embedding('text-embedding-004'),
  value: 'Hello, world!',
);
final b = await embed(
  model: google.embedding('text-embedding-004'),
  value: 'Hi there!',
);
print('similarity: ${cosineSimilarity(a.embedding, b.embedding)}');
```

---

## Multimodal (image + text)

```dart
import 'dart:io';

final imageBytes = await File('photo.jpg').readAsBytes();

final result = await generateText(
  model: google('gemini-2.0-flash'),
  messages: [
    ModelMessage.user(
      content: [
        MessageContentImage.fromBytes(
          data: imageBytes,
          mimeType: 'image/jpeg',
        ),
        const MessageContentText('What is in this image?'),
      ],
    ),
  ],
);
print(result.text);
```

---

## Custom API key

```dart
final myGoogle = GoogleGenerativeAIProvider(apiKey: 'AIza...');
final result = await generateText(
  model: myGoogle('gemini-2.0-flash'),
  prompt: 'Hello!',
);
```

---

## Runnable example apps

- **[`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)** — Dart CLI covering all core APIs
- **[`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)** — Flutter app with Google provider, multimodal, and embeddings
