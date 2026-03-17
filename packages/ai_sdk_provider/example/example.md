# ai_sdk_provider examples

`ai_sdk_provider` defines the low-level interfaces every provider must implement.
You do not normally import it directly — it is a transitive dependency of
`ai_sdk_dart` and all provider packages.

---

## Building a custom provider

Implement `LanguageModelV3` to wire any HTTP API into the AI SDK:

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

class MyCustomModel implements LanguageModelV3 {
  const MyCustomModel({required this.modelId});

  @override
  final String modelId;

  @override
  String get provider => 'my-provider';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    // Extract the user prompt from the last message.
    final prompt = options.prompt
        .whereType<LanguageModelV3UserMessage>()
        .lastOrNull
        ?.content
        .whereType<LanguageModelV3TextPart>()
        .map((p) => p.text)
        .join() ?? '';

    // Call your API here and return the result.
    final text = await _callMyApi(prompt);

    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: text)],
      finishReason: LanguageModelV3FinishReason.stop,
      usage: const LanguageModelV3Usage(
        inputTokens: 10,
        outputTokens: 5,
        totalTokens: 15,
      ),
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    // For streaming, return a stream of LanguageModelV3StreamPart events.
    final result = await doGenerate(options);
    final text = result.content.whereType<LanguageModelV3TextPart>().first.text;

    return LanguageModelV3StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(
            finishReason: LanguageModelV3FinishReason.stop,
            usage: result.usage,
          ),
        ],
      ),
    );
  }

  Future<String> _callMyApi(String prompt) async {
    // Replace with your actual HTTP call.
    return 'Response to: $prompt';
  }
}
```

Use it with any `ai_sdk_dart` core API:

```dart
final model = MyCustomModel(modelId: 'my-model-v1');

final result = await generateText(
  model: model,
  prompt: 'Hello from my custom provider!',
);
print(result.text);
```

---

## Available interfaces

| Interface | Use case |
|-----------|----------|
| `LanguageModelV3` | Text generation and streaming |
| `EmbeddingModelV2<VALUE>` | Text / multimodal embeddings |
| `ImageModelV3` | Image generation |
| `SpeechModelV1` | Text-to-speech synthesis |
| `TranscriptionModelV1` | Speech-to-text transcription |
| `RerankModelV1` | Document reranking |

---

## Runnable examples

See the full working examples in the monorepo:

- **[`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)** — Dart CLI using real providers
- **[`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)** — Flutter app with all providers
