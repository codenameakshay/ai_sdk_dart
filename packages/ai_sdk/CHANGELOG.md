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
