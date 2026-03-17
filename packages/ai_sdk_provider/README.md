# ai_sdk_provider

Provider interface specification for the [AI SDK Dart](https://github.com/codenameakshay/ai_sdk_dart) — defines the contracts that all provider packages must implement.

This package is an implementation detail. **You do not need to add it as a direct dependency** — it is a transitive dependency of `ai` and all provider packages.

## Interfaces

| Interface | Description |
|-----------|-------------|
| `LanguageModelV3` | Text generation and streaming |
| `EmbeddingModelV2<VALUE>` | Text / multimodal embeddings |
| `ImageModelV3` | Image generation |
| `SpeechModelV1` | Text-to-speech |
| `TranscriptionModelV1` | Speech-to-text |
| `RerankModelV1` | Document reranking |

## Implementing a custom provider

```dart
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

class MyProvider implements LanguageModelV3 {
  @override
  String get provider => 'my-provider';

  @override
  String get modelId => 'my-model';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    // Call your API here...
    return LanguageModelV3GenerateResult(
      content: [LanguageModelV3TextPart(text: 'Hello from my provider!')],
      finishReason: LanguageModelV3FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    // Return a stream of LanguageModelV3StreamPart events...
    throw UnimplementedError();
  }
}
```

## License

MIT
