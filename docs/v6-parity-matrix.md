# AI SDK v6 Parity Matrix

This matrix tracks one-to-one feature parity against AI SDK v6 docs.

Primary local docs source: `AI-SDK.md` (composite export of docs pages).

Legend:

- `[x]` implemented and covered by tests
- `[~]` partially implemented
- `[ ]` not implemented yet

## Core Text APIs

- [x] `generateText`
- [x] `streamText`
- [x] full text result parity (warnings, sources, provider metadata surfaced in core)
- [x] rich result object parity (`content`, `reasoning`, `reasoningText`, `files`, `sources`, `toolCalls`, `toolResults`, `finishReason`, `rawFinishReason`, `totalUsage`, `request`, `response`, `providerMetadata`, `steps`, `output`)
- [x] callback parity (`onFinish`, `onStepFinish`, `onChunk`, `onError`)
- [x] lifecycle callback parity (`experimental_onStart`, `experimental_onStepStart`, `experimental_onToolCallStart`, `experimental_onToolCallFinish`)
- [x] multi-step generation (`maxSteps`, stop conditions, tool loop execution)
- [x] `prepareStep` parity (step-wise model/tool/options/message overrides)
- [x] `fullStream` event parity (`start`, `start-step`, `text-*`, `reasoning-*`, `source`, `file`, `tool-*`, `finish-step`, `finish`, `error`, `raw`)
- [x] stream transform parity (`experimental_transform`, `smoothStream`)

## Structured Object APIs

- [x] `generateObject` helper (Dart-specific convenience)
- [x] `streamObject` helper (Dart-specific convenience)
- [x] v6-style Output API parity in `generateText`/`streamText` (`Output.text/object/array/choice/json`)
- [x] stream structured outputs parity (`partialOutputStream`, `elementStream`)
- [x] strict schema-guided generation controls per provider
- [x] object stream patch/event parity vs JS hooks
- [x] structured output error parity (`NoObjectGeneratedError` surface)

## Tools and Agents

- [x] typed tool definitions (`Schema<T>`, `Tool<INPUT, OUTPUT>`)
- [x] tool call execution loop in `ToolLoopAgent`
- [x] tool result roundtrip message serialization in OpenAI / Anthropic / Google
- [x] agent-level streaming with tool execution between stream steps
- [x] provider-defined tools parity in core agent pipeline
- [x] strict tools parity (`strict: true`) end-to-end
- [x] tool input examples parity (`inputExamples`, Anthropic-specific forwarding)
- [~] approval flow parity (`needsApproval`, `tool-approval-request`, `tool-approval-response`)
- [x] dynamic tool parity (`dynamicTool`, runtime unknown input/output)
- [~] tool execution context parity (`toolCallId`, `messages`, `abortSignal`, `experimental_context`)
- [x] tool input lifecycle hooks parity (`onInputStart`, `onInputDelta`, `onInputAvailable`)
- [x] preliminary tool results parity (async iterable tool output)
- [x] tool choice parity (`auto`, `required`, `none`, specific tool)

## Message and Content Parity

- [x] text parts
- [x] image parts
- [x] file parts
- [x] tool call parts
- [x] tool result parts including multipart + error flag
- [x] source parts fully surfaced through core APIs
- [x] reasoning/redacted reasoning parity in core helpers
- [x] tool approval parts (`tool-approval-request`, `tool-approval-response`)

## Streaming Parity

- [x] SSE parsing for OpenAI / Anthropic / Google
- [x] text/tool/reasoning stream parts
- [x] finish part
- [x] usage metadata in stream finish (provider-dependent)
- [x] response metadata/warnings forwarding in stream finish (provider-dependent)
- [x] mid-stream usage chunks surfaced as dedicated events in core wrappers
- [x] step boundary events surfaced in core (`start-step`, `finish-step`)
- [x] structured output streaming channels (`partialOutputStream`, `elementStream`)

## Provider Packages

- [x] OpenAI language + embedding + image
- [x] Anthropic language
- [x] Google language + embedding
- [~] exhaustive provider option parity with AI SDK docs examples
- [~] exhaustive finish-reason mapping and raw metadata parity edge cases
- [x] provider-level strict/approval/tool-example feature matrix coverage

## Flutter API Parity

- [x] `ChatController` baseline behavior
- [x] `CompletionController` baseline behavior
- [x] `ObjectStreamController` baseline behavior
- [x] full hook parity (`append`, `reload`, `clear`/`reset`, optimistic streaming content, `onFinish`/`onError` callbacks, `isStreaming` status)

## MCP

- [x] transport/client scaffolding (SSE + Stdio)
- [x] tool discovery (`tools/list` → `ToolSet`)
- [x] tool invocation (`tools/call` with structured result extraction)
- [x] initialize handshake (MCP protocol 2024-11-05)
- [~] streaming tool outputs / reconnection (basic; no live SSE event streaming yet)

## Multimodal Model APIs

- [~] `experimental_generateSpeech` (interface + provider)
- [~] `experimental_transcribe` (interface + provider)
- [ ] `experimental_generateVideo`
- [~] `rerank` (interface + core; no provider yet)

## Middleware System

- [x] `wrapLanguageModel()` — language model middleware wrapper
- [x] `extractReasoningMiddleware` — extracts reasoning from delimited text
- [x] `simulateStreamingMiddleware` — wraps non-streaming models with streaming interface
- [x] `extractJsonMiddleware` — strips markdown code fences from JSON output
- [x] `defaultSettingsMiddleware` — applies default call option overrides
- [x] `addToolInputExamplesMiddleware` — enriches tool descriptions with examples

## Utility Functions

- [x] `cosineSimilarity()` — vector similarity for embeddings
- [x] `simulateReadableStream()` — test utility for simulating streams
- [x] `generateId()` / `createIdGenerator()` — ID generation utilities
- [x] `createProviderRegistry()` — multi-provider registry
- [x] `smoothStream()` (already tracked above)

## Provider Registry

- [x] `createProviderRegistry` — lookup model by `provider:modelId` string

## Streaming Enhancements

- [x] mid-stream usage chunks surfaced as `StreamTextUsageEvent` in `fullStream`

## Testing and Conformance

- [x] provider contract fixture suite for multimodal + tool-result serialization
- [x] provider endpoint tests for generate + stream + providerOptions
- [x] core tests for object APIs and tool loop agent
- [x] dedicated `fullStream` conformance snapshot suite
- [x] docs-to-tests traceability seeded from `AI-SDK.md`
- [x] golden compatibility fixtures mirroring official v6 examples

## Docs-to-Tests Traceability (AI-SDK.md Seed)

| Docs evidence (AI-SDK.md) | Parity target | Status | Current coverage |
| --- | --- | --- | --- |
| `AI-SDK.md:9308` (`generateText`) | Baseline non-stream text generation | [x] | `packages/ai/lib/src/core/generate_text.dart`, `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:9452` (`streamText`) | Baseline streaming text generation | [x] | `packages/ai/lib/src/core/stream_text.dart`, provider stream tests |
| `AI-SDK.md:9337` + `AI-SDK.md:9497` | Rich result object fields/promises | [x] | Added request/response envelopes plus response body/request body surfacing in `generateText`/`streamText` with core tests |
| `AI-SDK.md:9537` | `onChunk` typed chunk callback parity | [x] | Normalized stream chunk taxonomy (`source/file/tool-input-*` included) in `packages/ai/lib/src/core/stream_text.dart`; assertions in `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:9646` | `fullStream` event model parity | [x] | Core taxonomy implemented end-to-end in `packages/ai/lib/src/core/stream_text.dart`; ordering+payload tests in `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:10012` | Output API in `generateText`/`streamText` | [x] | Implemented for `Output.text/object/array/choice/json` |
| `AI-SDK.md:10075` | `partialOutputStream` parity | [x] | Robust partial parsing, fenced JSON handling, and malformed boundary coverage in `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:10202` | `elementStream` parity | [x] | Partial array emission + invalid element recovery in `packages/ai/lib/src/core/stream_text.dart` and `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:10552` | strict tool mode (`strict`) | [x] | Strict input failure-path conformance tests in `packages/ai_sdk_openai/test/openai_provider_test.dart`, `packages/ai_sdk_anthropic/test/anthropic_provider_test.dart`, `packages/ai_sdk_google/test/google_provider_test.dart` |
| `AI-SDK.md:10605` | tool approval flow (`needsApproval`) | [~] | Core approval request/response flow covered in `packages/ai/test/core_api_test.dart` (`streamText approval flow emits request then executes after approval`); richer UI/agent parity pending |
| `AI-SDK.md:10722` | multi-step tool calls (`stopWhen`) | [x] | `stopWhen` semantics verified in `packages/ai/test/core_api_test.dart` for both `generateText` and `streamText` |
| `AI-SDK.md:10590` + `AI-SDK.md:14000` | tool input examples (`inputExamples`) | [x] | Core tool-to-provider forwarding in `packages/ai/lib/src/core/generate_text.dart` and `packages/ai/lib/src/core/stream_text.dart`; Anthropic wire forwarding asserted in `packages/ai_sdk_anthropic/test/anthropic_provider_test.dart` |
| `AI-SDK.md:17581` + `AI-SDK.md:17619` | provider-native `source` / `file` content surfacing | [x] | OpenAI/Anthropic/Google extraction in provider impls with assertions in `packages/ai_sdk_openai/test/openai_provider_test.dart`, `packages/ai_sdk_anthropic/test/anthropic_provider_test.dart`, `packages/ai_sdk_google/test/google_provider_test.dart` |
| `AI-SDK.md:10757` | `prepareStep` step-level overrides | [x] | Model/toolChoice/activeTools/messages/providerOptions per-step overrides in `generateText` + `streamText` |
| `AI-SDK.md:10949` | dynamic tools (`dynamicTool`) | [x] | Core `dynamicTool` helper implemented; raw input passed through as-is in both `generateText` and `streamText` via `_parseToolInput` dynamic branch |
| `AI-SDK.md:10797` | `onStepFinish` callback parity | [x] | Step callbacks in `generateText` and `streamText` with step payload coverage in `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:10857` | `prepareStep` callback parity | [x] | Step preparation contract implemented and validated with forced tool choice + message compression test |
| `AI-SDK.md:10825` | tool execution lifecycle callbacks | [x] | `experimentalOnToolCallStart` / `experimentalOnToolCallFinish` with no-throw guards and tests |
| `AI-SDK.md:9590` | streaming lifecycle callbacks | [x] | `experimentalOnStart` / `experimentalOnStepStart` added to `streamText` with swallow-safe behavior |
| `AI-SDK.md:9766` | stream transforms (`experimental_transform`) | [x] | Transform hook applies before stream callbacks/output accumulation; verified in `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:9776` | `smoothStream` helper | [x] | `smoothStream(chunkSize)` implemented and tested in `packages/ai/test/core_api_test.dart` |
| `AI-SDK.md:11014` | preliminary tool results (async iterable) | [x] | Streaming preliminary tool-result events + canonical final tool result in `streamText` |
| `AI-SDK.md:11048` | tool choice controls | [x] | Enforced `auto` / `required` / `none` / specific tool semantics and invalid-name guards |
| `AI-SDK.md:10416` | `AI_NoObjectGeneratedError` parity | [x] | `AiNoObjectGeneratedError` wired with response metadata/body across structured helpers; tests in `packages/ai/test/core_api_test.dart` |

## Page-Level Core Feature Traceability

| Feature | AI-SDK.md evidence | Implementation | Tests |
| --- | --- | --- | --- |
| `streamText` event taxonomy | `AI-SDK.md:9646-9763` | `packages/ai/lib/src/core/stream_text.dart` | `packages/ai/test/core_api_test.dart` (`streamText emits full event taxonomy in order`, `streamText onChunk includes source/file/tool-input chunks`) |
| `onStepFinish` | `AI-SDK.md:10797-10823` | `packages/ai/lib/src/core/generate_text.dart`, `packages/ai/lib/src/core/stream_text.dart` | `packages/ai/test/core_api_test.dart` (`onStepFinish works for multi-step...`) |
| `prepareStep` | `AI-SDK.md:10857-10920` | `packages/ai/lib/src/core/generate_text.dart`, `packages/ai/lib/src/core/stream_text.dart` | `packages/ai/test/core_api_test.dart` (`prepareStep supports...`) |
| Tool choice | `AI-SDK.md:11048-11080` | `packages/ai/lib/src/core/generate_text.dart`, `packages/ai/lib/src/core/stream_text.dart` | `packages/ai/test/core_api_test.dart` (`toolChoice enforces...`) |
| Tool input lifecycle hooks | `AI-SDK.md:9547-9549`, `AI-SDK.md:9721-9731` | `packages/ai/lib/src/core/stream_text.dart` | `packages/ai/test/core_api_test.dart` (`streamText tool input lifecycle hooks...`) |
| Preliminary tool results | `AI-SDK.md:11014-11046` | `packages/ai/lib/src/core/generate_text.dart`, `packages/ai/lib/src/core/stream_text.dart` | `packages/ai/test/core_api_test.dart` (`streamText emits preliminary tool results...`) |
| Experimental lifecycle callbacks | `AI-SDK.md:9590-9644`, `AI-SDK.md:10825-10855` | `packages/ai/lib/src/core/generate_text.dart`, `packages/ai/lib/src/core/stream_text.dart` | `packages/ai/test/core_api_test.dart` (`experimental lifecycle callbacks are swallow-safe`) |
| Structured output robustness | `AI-SDK.md:10075-10202` | `packages/ai/lib/src/core/stream_text.dart`, `packages/ai/lib/src/core/stream_object.dart` | `packages/ai/test/core_api_test.dart` (`partialOutputStream...`, `elementStream...`, `output fails...`, `streamObject patch stream supports nested json pointer operations`) |

## Provider-Level Traceability (Tool Choice / Strict)

| Provider | Feature | Implementation | Tests |
| --- | --- | --- | --- |
| OpenAI | `toolChoice` (`auto`/`none`/`required`/specific) | `packages/ai_sdk_openai/lib/src/openai_provider.dart` (`_toOpenAiToolChoice`) | `packages/ai_sdk_openai/test/openai_provider_test.dart` (`maps tool choice modes and strict tool schemas`) |
| OpenAI | strict tool schema forwarding | `packages/ai_sdk_openai/lib/src/openai_provider.dart` | `packages/ai_sdk_openai/test/openai_provider_test.dart` (`maps tool choice modes and strict tool schemas`) |
| OpenAI | strict invalid-argument failure shape | `packages/ai_sdk_openai/lib/src/openai_provider.dart` | `packages/ai_sdk_openai/test/openai_provider_test.dart` (`preserves invalid strict tool arguments for downstream failure handling`) |
| Anthropic | `toolChoice` (`auto`/`required`/specific; `none` mapped to provider auto) | `packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart` (`_toAnthropicToolChoice`) | `packages/ai_sdk_anthropic/test/anthropic_provider_test.dart` (`maps tool choice modes to anthropic wire format`) |
| Anthropic | strict invalid-argument failure shape | `packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart` | `packages/ai_sdk_anthropic/test/anthropic_provider_test.dart` (`preserves invalid strict tool arguments for downstream failure handling`) |
| Google | function tool declarations + tool choice config | `packages/ai_sdk_google/lib/src/google_provider.dart` (`_googleToolChoicePayload`) | `packages/ai_sdk_google/test/google_provider_test.dart` (`maps tool choice modes and tool declarations`) |
| Google | strict invalid-argument failure shape | `packages/ai_sdk_google/lib/src/google_provider.dart` | `packages/ai_sdk_google/test/google_provider_test.dart` (`preserves invalid strict tool arguments for downstream failure handling`) |

## Next Actions to Reach Full Parity

1. Expand MCP parity from scaffolding to full tool discovery/invocation and reconnection semantics.
2. Add a Cohere (or other) provider implementation for `rerank()`.
3. Add `experimental_generateVideo` support (new model type interface + provider).
4. Complete provider-defined tools pipeline integration.
5. Continue tracking edge-case provider metadata/finish-reason normalization as docs evolve.
