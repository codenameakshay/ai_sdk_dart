## 1.1.0

### New APIs

- **`embedMany()`** — batch embedding that fans out to the provider's `doEmbed` in configurable chunks, with merged usage stats.
- **`wrapEmbeddingModel()`** — middleware pipeline for embedding models, mirroring `wrapLanguageModel` for language models.
- **`customProvider()`** — on-the-fly provider construction from plain model-factory maps without a full `createProviderRegistry` setup.
- **`onAbort` callback in `streamText`** — fires synchronously when the caller's `CancellationToken` is cancelled, enabling graceful cleanup.
- **`timeout` parameter** — `Duration?` timeout added to `generateText`, `streamText`, `generateObject`, `streamObject`, `embed`, `embedMany`, `generateImage`, `generateSpeech`, `transcribe`, `rerank`. Wraps each underlying model call with `Future.timeout`.
- **`smoothStream` `delayInMs` option** — `smoothStream(delayInMs: 20)` adds per-chunk delay; `experimentalTransform` type is now `Stream<String> Function(Stream<String>)` (async), enabling arbitrary async transforms.
- **`generateObject` / `streamObject` pass `outputSchema`** — `LanguageModelV3CallOptions.outputSchema` is now set to `schema.jsonSchema` so providers that support native structured output (e.g. OpenAI `response_format: json_schema`) use it automatically.

### New Error Types

- `AiToolCallRepairError` — thrown when a tool-call repair attempt fails.
- `AiNoImageGeneratedError` — thrown when `generateImage` receives no image content.
- `AiNoVideoGeneratedError` — thrown when `generateVideo` receives no video content.
- `AiNoSpeechGeneratedError` — thrown when `generateSpeech` receives no speech content.
- `AiNoTranscriptGeneratedError` — thrown when `transcribe` receives no transcript.
- `AiRetryError` — wraps the list of errors from all exhausted retry attempts.
- `AiDownloadError` — thrown when an attachment download fails.

### Registry Expansion

- `createProviderRegistry` now supports 6 model categories: language, embedding, image, speech, transcription, and rerank models (previously language + embedding only).
- `RegistrableProvider` exposes `imageModelFactory`, `speechModelFactory`, `transcriptionModelFactory`, and `rerankModelFactory` factories.

### Testing Utilities

- `MockEmbeddingModelV3` — fake embedding model for conformance tests, mirroring `MockLanguageModelV2`.

### Bug Fixes

- **`pruneMessages`** — removed duplicate messages that were incorrectly appended in multi-step loops when `messages` was pre-populated; semantics now match Vercel AI SDK v6.

### New Provider Packages

- **`ai_sdk_azure`** — Azure OpenAI provider (`AzureOpenAIProvider`). Language models and embeddings via Azure-hosted deployments; configurable `endpoint`, `apiKey`, and `apiVersion`.
- **`ai_sdk_cohere`** — Cohere provider (`cohere`). Language models, text embeddings, and reranking (Command R, Command R+, embed-english-v3.0, rerank-english-v3.0).
- **`ai_sdk_groq`** — Groq provider (`groq`). Ultra-low latency inference for Llama, Mixtral, Gemma, and other Groq-hosted models.
- **`ai_sdk_mistral`** — Mistral AI provider (`mistral`). Language models and embeddings (Mistral Large, Mistral Small, Codestral, mistral-embed).
- **`ai_sdk_ollama`** — Ollama provider (`ollama`). Local inference for any model pulled via Ollama; no API key required.

### Test Count

- 562+ tests covering all public APIs, conformance cases, and new features.

---

## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Package renamed from `ai` → `ai_sdk_dart` to avoid conflicts with existing pub.dev packages.

### Core APIs
- `generateText` / `streamText` with full v6 result parity — text, finishReason, usage, steps, toolCalls, toolResults, reasoning, sources, files, providerMetadata, request/response envelopes.
- `generateObject` / `streamObject` with `Output.text/object/array/choice/json` API.
- `embed` / `embedMany` with `cosineSimilarity`.
- `generateImage`, `generateSpeech`, `transcribe`, `rerank`.

### Agentic Tools
- Multi-step tool loop with `maxSteps`, `stopConditions`, and `prepareStep`.
- Typed tool definitions (`tool<INPUT, OUTPUT>`, `dynamicTool`, `Schema<T>`).
- Tool choice controls (`ToolChoiceAuto`, `ToolChoiceRequired`, `ToolChoiceNone`, `ToolChoiceSpecific`).
- Tool approval flow (`needsApproval`) and `ToolLoopAgent` for autonomous agentic loops.

### Middleware & Registry
- Middleware system: `wrapLanguageModel`, `extractReasoningMiddleware`, `extractJsonMiddleware`, `simulateStreamingMiddleware`, `defaultSettingsMiddleware`, `addToolInputExamplesMiddleware`.
- `createProviderRegistry` — resolve models by `'provider:modelId'` string at runtime.

### Streaming
- `smoothStream` / `experimentalTransform` stream transform hooks.
- Full `fullStream` event taxonomy — 22 typed `StreamTextEvent` subtypes.
- Lifecycle callbacks: `onFinish`, `onStepFinish`, `onChunk`, `onError`, `experimentalOnStart`, `experimentalOnStepStart`.

### Other
- Complete `AiSdkError` sealed class hierarchy.
- Utilities: `generateId`, `createIdGenerator`, `simulateReadableStream`.
- 230-test conformance suite covering all public APIs and provider wire formats.

---

## 0.2.0

- Initial release.
- `generateText` / `streamText` with full v6 result parity (text, finishReason, usage, steps, toolCalls, toolResults, reasoning, sources, files, providerMetadata, request/response envelopes).
- `generateObject` / `streamObject` with `Output.text/object/array/choice/json` API.
- Multi-step tool loop with `maxSteps`, `stopWhen`, and `prepareStep`.
- Typed tool definitions (`tool<INPUT, OUTPUT>`, `dynamicTool`, `Schema<T>`).
- Tool choice controls (`ToolChoiceAuto`, `ToolChoiceRequired`, `ToolChoiceNone`, `ToolChoiceSpecific`).
- Tool approval flow (`needsApproval`).
- `ToolLoopAgent` for autonomous agentic loops.
- Middleware system (`wrapLanguageModel`, `extractReasoningMiddleware`, `extractJsonMiddleware`, `simulateStreamingMiddleware`, `defaultSettingsMiddleware`, `addToolInputExamplesMiddleware`).
- `embed` / `embedMany` with `cosineSimilarity`.
- `generateImage`, `generateSpeech`, `transcribe`, `rerank` interfaces.
- `createProviderRegistry` for multi-provider model lookup.
- `smoothStream` / `experimentalTransform` stream transform hooks.
- Full `fullStream` event taxonomy (`StreamTextEvent` hierarchy).
- Lifecycle callbacks: `onFinish`, `onStepFinish`, `onChunk`, `onError`, `experimentalOnStart`, `experimentalOnStepStart`, `experimentalOnToolCallStart`, `experimentalOnToolCallFinish`.
- Complete error type hierarchy (`AiSdkError` subclasses).
- Utility functions: `generateId`, `createIdGenerator`, `simulateReadableStream`.