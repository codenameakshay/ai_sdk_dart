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