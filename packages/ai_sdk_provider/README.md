# ai_sdk_provider

Provider interface specification for the [AI SDK Dart](https://github.com/codenameakshay/ai_sdk_dart) — defines the contracts that all provider packages must implement.

This package is an implementation detail for most applications. **You do not need to add it as a direct dependency** unless you are building a custom provider; it is a transitive dependency of `ai_sdk_dart` and the provider packages.

Custom providers upgrading from 1.x should read the
[2.0 migration guide](https://github.com/codenameakshay/ai_sdk_dart/blob/main/docs/migration-2.0.md)
before adopting the V4 contract.

## Interfaces

| Interface | Description |
|-----------|-------------|
| `LanguageModelV4` | Text generation and streaming |
| `EmbeddingModelV2<VALUE>` | Text / multimodal embeddings |
| `ImageModelV3` | Image generation |
| `SpeechModelV1` | Text-to-speech |
| `TranscriptionModelV1` | Speech-to-text |
| `RerankModelV1` | Document reranking |

## Implementing a custom provider

```dart
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

class MyProvider extends LanguageModelV4 {
  @override
  String get provider => 'my-provider';

  @override
  String get modelId => 'my-model';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    // Call your API here...
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'Hello from my provider!')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    // Return a stream of LanguageModelV4StreamPart events...
    throw UnimplementedError();
  }
}
```

## License

MIT
