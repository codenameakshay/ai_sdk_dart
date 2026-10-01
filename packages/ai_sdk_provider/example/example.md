# ai_sdk_provider examples

`ai_sdk_provider` defines the low-level interfaces every provider must implement.
You do not normally import it directly — it is a transitive dependency of
`ai_sdk_dart` and all provider packages.

---

## Building a custom provider

Implement `LanguageModelV4` to wire any HTTP API into the AI SDK:

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

class MyCustomModel extends LanguageModelV4 {
  const MyCustomModel({required this.modelId});

  @override
  final String modelId;

  @override
  String get provider => 'my-provider';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    // Extract the user prompt from the last message.
    final prompt = options.prompt.messages
        .where((m) => m.role == LanguageModelV4Role.user)
        .lastOrNull
        ?.content
        .whereType<LanguageModelV4TextPart>()
        .map((p) => p.text)
        .join() ?? '';

    // Call your API here and return the result.
    final text = await _callMyApi(prompt);

    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: text)],
      finishReason: LanguageModelV4FinishReason.stop,
      usage: const LanguageModelV4Usage(
        inputTokens: LanguageModelV4InputTokenUsage(total: 10),
        outputTokens: LanguageModelV4OutputTokenUsage(total: 5),
      ),
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    // For streaming, return a stream of LanguageModelV4StreamPart events.
    final result = await doGenerate(options);
    final text = result.content.whereType<LanguageModelV4TextPart>().first.text;

    return LanguageModelV4StreamResult(
      stream: simulateReadableStream(
        parts: [
          StreamPartTextStart(id: 'text-1'),
          StreamPartTextDelta(id: 'text-1', delta: text),
          StreamPartTextEnd(id: 'text-1'),
          StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
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

## Cancellation with `AbortSignal`

Every call options type (`LanguageModelV4CallOptions`, `EmbeddingModelV2CallOptions`,
etc.) carries an `abortSignal` of type `AbortSignal?`:

```dart
abstract interface class AbortSignal {
  bool get isCancelled;
  Future<void> get onCancelled;
}
```

A custom provider should check `options.abortSignal?.isCancelled` before starting
expensive work. For prompt cancellation of in-flight work, attach an observer with
`AbortSignalObservation.attach` instead of only checking once at the start — it fires
`callback` immediately if the signal is already cancelled, or on the next cancellation
event otherwise:

```dart
@override
Future<LanguageModelV4GenerateResult> doGenerate(
  LanguageModelV4CallOptions options,
) async {
  if (options.abortSignal?.isCancelled ?? false) {
    throw const AiOperationCancelledError();
  }

  final observation = options.abortSignal == null
      ? null
      : AbortSignalObservation.attach(options.abortSignal!, () {
          // Cancel the in-flight HTTP call here.
        });
  try {
    final prompt = options.prompt.messages
        .where((m) => m.role == LanguageModelV4Role.user)
        .lastOrNull
        ?.content
        .whereType<LanguageModelV4TextPart>()
        .map((p) => p.text)
        .join() ?? '';
    final text = await _callMyApi(prompt);
    return LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: text)],
      finishReason: LanguageModelV4FinishReason.stop,
      usage: const LanguageModelV4Usage(),
    );
  } finally {
    await observation?.dispose();
  }
}
```

Call `dispose()` once the request settles so the observer doesn't outlive it.

---

## Cancellation for Dio-based providers

Providers built on `package:dio` should use `DioCancellationScope` to wire Dio's own
cancellation to the shared `AbortSignal`, so a caller-driven cancellation
(`CancellationToken.cancel()` from `ai_sdk_dart`, or a `timeout`) actually aborts the
live HTTP request instead of just abandoning the Future:

```dart
Future<LanguageModelV4GenerateResult> doGenerate(
  LanguageModelV4CallOptions options,
) async {
  final scope = DioCancellationScope(options.abortSignal);
  try {
    final response = await scope.run(
      () => _dio.post('/generate', data: _toBody(options), cancelToken: scope.token),
    );
    return _parseResponse(response.data);
  } finally {
    await scope.dispose();
  }
}
```

`scope.run` disposes the scope and rethrows on failure, and throws
`AiOperationCancelledError` if the signal fired while the request was in flight.

---

## Embedding model capability getters

`EmbeddingModelV2<VALUE>` implementations report two capabilities used by `embedMany`
in `ai_sdk_dart`. See
[`example/custom_embedding_model.dart`](custom_embedding_model.dart) in this directory
for a full working implementation:

```dart
@override
int get maxEmbeddingsPerCall => 16;

@override
bool get supportsParallelCalls => false;
```

`maxEmbeddingsPerCall` may also return `null`, meaning the adapter supplies no limit
(not "known unlimited"). `embedMany` batches by whichever is smaller: the caller's
explicit `maxEmbeddingsPerCall` argument or this getter. `supportsParallelCalls` gates
whether `embedMany`'s `maxParallelCalls` is allowed to run concurrent requests against
this model at all — when `false`, `embedMany` always runs batches one at a time.

---

## Provider-owned file references

`LanguageModelV4DataContent` has four variants: `DataContentBytes` (raw bytes),
`DataContentBase64` (a base64 string), `DataContentUrl` (a plain URL), and
`DataContentProviderReference` — an opaque, provider-owned file handle:

```dart
class DataContentProviderReference extends LanguageModelV4DataContent {
  const DataContentProviderReference({required this.namespace, required this.id});
  final String namespace;
  final String id;
}
```

It's used inside a `LanguageModelV4FilePart`, for example to reference a file already
uploaded to a provider:

```dart
const file = LanguageModelV4FilePart(
  data: DataContentProviderReference(namespace: 'openai', id: 'file-1'),
  mediaType: 'application/pdf',
  filename: 'contract.pdf',
);
```

A custom provider implementation must check `namespace` and reject a reference it
doesn't own, rather than reinterpreting an unrelated provider's file ID as a URL or
downloadable resource — this keeps one provider's opaque handle from leaking into
another provider's request.

---

## Available interfaces

| Interface | Use case |
|-----------|----------|
| `LanguageModelV4` | Text generation and streaming |
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
