# ai_sdk_openai examples

## Installation

```sh
dart pub add ai_sdk_dart ai_sdk_openai
```

The top-level `openai` factory reads
`const String.fromEnvironment('OPENAI_API_KEY')`. Use it with
`fvm dart run --define=OPENAI_API_KEY=sk-... bin/app.dart`, or read
`Platform.environment['OPENAI_API_KEY']` yourself and pass `apiKey:` to
`OpenAIProvider` in server and CLI apps.

---

## Text generation

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'Say hello from AI SDK Dart!',
);
print(result.text);
print('tokens used: ${result.usage}');
```

---

## Responses API

`openai.responses(modelId)` returns a `LanguageModelV4` backed by the OpenAI
Responses API instead of Chat Completions. It works with `generateText` and
`streamText` exactly like `openai(modelId)`:

```dart
final result = await generateText(
  model: openai.responses('gpt-4.1-mini'),
  prompt: 'Say hello from AI SDK Dart!',
);
print(result.text);
```

---

## Hosted tools (Responses API)

The Responses API exposes server-side tools as
`LanguageModelV4ProviderDefinedTool` subclasses, passed via
`providerDefinedTools:` (a `List`, separate from the `tools:` map) — they
require `openai.responses(...)`, not `openai(...)`:

```dart
final result = await generateText(
  model: openai.responses('gpt-4.1-mini'),
  prompt: 'What happened in the news today?',
  providerDefinedTools: [OpenAIWebSearchTool()],
);
print(result.text);
```

| Tool | Purpose |
|------|---------|
| `OpenAIWebSearchTool({userLocation, searchContextSize})` | Web search grounding |
| `OpenAIFileSearchTool({required vectorStoreIds, maxNumResults})` | Search over uploaded vector stores |
| `OpenAICodeInterpreterTool({container})` | Runs model-written code in an OpenAI container |
| `OpenAIMcpTool({required serverLabel, required serverUrl, allowedTools, requireApproval, headers})` | Connects to a remote MCP server |

```dart
final result = await generateText(
  model: openai.responses('gpt-4.1-mini'),
  prompt: 'Search our docs and summarize the onboarding steps.',
  providerDefinedTools: [
    OpenAIFileSearchTool(vectorStoreIds: ['vs_123']),
    OpenAICodeInterpreterTool(),
    OpenAIMcpTool(serverLabel: 'docs', serverUrl: 'https://mcp.example.com'),
  ],
);
```

---

## Streaming

```dart
import 'dart:io';

final result = await streamText(
  model: openai('gpt-4.1-mini'),
  prompt: 'Count from 1 to 5.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

---

## Structured output

```dart
final result = await generateText<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  prompt: 'Return the capital and currency of Japan as JSON.',
  output: Output.object(
    schema: Schema<Map<String, dynamic>>(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'capital': {'type': 'string'},
          'currency': {'type': 'string'},
        },
      },
      fromJson: (json) => json,
    ),
  ),
);
print(result.output); // {capital: Tokyo, currency: JPY}
```

---

## Tools (multi-step agent)

```dart
final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'What is the weather in Paris?',
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
      execute: (input, _) async => 'Sunny, 18°C in ${input['city']}',
    ),
  },
);
print(result.text);
```

---

## Embeddings

```dart
final a = await embed(
  model: openai.embedding('text-embedding-3-small'),
  value: 'Hello, world!',
);
final b = await embed(
  model: openai.embedding('text-embedding-3-small'),
  value: 'Hi there!',
);
print('similarity: ${cosineSimilarity(a.embedding, b.embedding)}');
```

---

## Image generation (DALL-E 3)

```dart
final result = await generateImage(
  model: openai.image('dall-e-3'),
  prompt: 'A futuristic city skyline at sunset, digital art.',
);
print('${result.image.bytes.length} bytes of ${result.image.mediaType}');
```

---

## Speech synthesis (TTS)

```dart
final result = await generateSpeech(
  model: openai.speech('tts-1'),
  text: 'Hello from AI SDK Dart!',
);
// result.audio is a Uint8List of MP3 audio bytes
await File('output.mp3').writeAsBytes(result.audio);
```

---

## Transcription (Whisper)

```dart
import 'dart:io';
import 'dart:typed_data';

final audioBytes = await File('recording.mp3').readAsBytes();
final result = await transcribe(
  model: openai.transcription('whisper-1'),
  audio: audioBytes,
  audioMediaType: 'audio/mpeg',
);
print(result.text);
```

---

## Custom base URL (Azure / compatible endpoint)

```dart
final azureModel = OpenAIProvider(
  apiKey: 'your-azure-key',
  baseUrl: 'https://my-resource.openai.azure.com/openai/deployments/gpt-4/v1',
).call('gpt-4');

final result = await generateText(
  model: azureModel,
  prompt: 'Hello from Azure OpenAI!',
);
```

---

## File and batch lifecycle

- **[files_lifecycle.dart](files_lifecycle.dart)** — uploads a file through `provider.files()`, downloads its content, and explicitly deletes it.
- **[batch_lifecycle.dart](batch_lifecycle.dart)** — creates a Responses batch through `provider.batches()`, checks its status, and reads the result file once it reaches a terminal state.

---

## Runnable example apps

- **[`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)** — Dart CLI covering all core APIs
- **[`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)** — Flutter app with OpenAI image gen, TTS, STT, embeddings
