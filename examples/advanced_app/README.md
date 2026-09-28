# AI SDK Dart — Advanced Example

A comprehensive Flutter app demonstrating all major AI SDK capabilities: multiple providers, tool calling, image generation, multimodal input, embeddings, text-to-speech, and speech-to-text. Chat-style screens are built from the **prebuilt widgets** in `ai_sdk_flutter_ui` rather than hand-rolled UI.

## Features

| Feature | API | Prebuilt widgets | Provider(s) |
|---------|-----|------------------|-------------|
| Provider Chat | `ChatController` + `createProviderRegistry` + `instructions` | `AiChatScaffold`, `PromptSuggestions` | OpenAI, Anthropic, Google |
| Tools Chat | `ToolLoopAgent` + `toolWithContext` + `maxToolConcurrency` + request-level `approvalPolicyFor` | `ChatComposer`, `ChatMessageBubble`, `ToolCallCard`, `ReasoningView`, `SourceCitations`, `ToolApprovalCard`, `UsageView` | OpenAI |
| Image Generation | `generateImage` | — | OpenAI (`gpt-image-1`) |
| Multimodal | `streamText` + `LanguageModelV4ImagePart` | `StreamingTextView` | OpenAI |
| Embeddings | `embed`, `cosineSimilarity`, `embedMany` (`maxEmbeddingsPerCall`/`maxParallelCalls`) | — | OpenAI, Google |
| Text-to-Speech | `generateSpeech` | — | OpenAI |
| Speech-to-Text | `transcribe` | — | OpenAI |
| Completion | `CompletionController` | `StreamingTextView` | OpenAI |
| Object Stream | `streamObject` — `partialObjectStream`, `patchStream`, `validatedJsonSchema` | — | OpenAI |
| Conversation | `ConversationController` + `LocalConversationBackend` + `ConversationCodec` + `ConversationRetryInfo` | `AiChatScaffold.conversation`, `AiSdkUiStrings` (+ RTL) | OpenAI |
| Responses | `OpenAIProvider.responses` + `OpenAIWebSearchTool` + `reasoning:` | `ReasoningView`, `SourceCitations`, `StreamingTextView` | OpenAI, Anthropic, Google |
| Widget Gallery | — (sample data) | All prebuilt widgets | None (offline) |

### Widget Gallery

A live catalogue of every prebuilt widget in `ai_sdk_flutter_ui`, driven by
sample data and a synthetic stream — so it renders and reacts **without an API
key or a network call**. Open it from the navigation drawer to see:

- **`AssistantMessageView`** — a whole assistant turn (reasoning + text + tool
  call with its result + a source) from one `ModelMessage.parts`.
- **`ToolApprovalCard`** — a human-in-the-loop approve/deny gate.
- **`ObjectStreamView`** — partial structured output streaming in live.
- **`PromptSuggestions`**, **`TypingIndicator`**, **`MessageActionsBar`**,
  **`UsageView`**, **`ChatErrorView`**, **`ScrollToBottomButton`**,
  **`MessageImage`** / **`MessageAttachment`**, and **`ToolCallCard`**.

### Tools Chat

The Tools Chat screen drives a `ToolLoopAgent` directly (instead of
`ChatController`) so it can read tool-call, tool-result, reasoning, and source
events off the canonical `stream` and render the full agentic turn:

- **`ToolCallCard`** — each tool call with its pretty-printed input and result.
- **`ReasoningView`** — the model's `<think>…</think>` reasoning, surfaced via
  `extractReasoningMiddleware`.
- **`ChatMessageBubble`** / **`ChatComposer`** — the conversation text and input.
- **`SourceCitations`** — rendered when the model returns sources.
- **`ToolApprovalCard`** — the `deleteFile` tool is defined with
  `toolWithContext` (a typed, bound workspace context) and always requires
  approval via a request-level `approvalPolicyFor` selector; approving or
  denying resumes the agent with `ToolLoopAgent.resume`.
- **`UsageView`** — shown twice per turn: the final step's own usage
  (`finalStep.usage`, from the canonical `onStepEnd` callback) and the
  aggregate across every step (`result.usage`, from `onEnd`).

### Conversation

Persisted, resumable chat built on `ConversationController` +
`LocalConversationBackend`, rendered through `AiChatScaffold.conversation`:

- **Save / Restore** — `ConversationCodec.encode`/`decode` round-trip an
  in-memory snapshot; restoring only decodes state and never re-executes tools
  or calls a provider.
- **Retry** — `ConversationRetryInfo` reports whether the last turn can be
  safely retried; the app bar's retry action surfaces the reason when it can't.
- **Approval** — the same `deleteFile` tool as Tools Chat, gated by an
  agent-level approval policy, rendered by the scaffold's built-in
  `ToolApprovalCard` flow.
- **Localization** — `AiSdkUiStrings` + `AiSdkUiStringsScope` swap every label
  for an Arabic set with an RTL toggle (`Directionality`).

### Responses

Drives the OpenAI Responses API (`OpenAIProvider.responses`) with a hosted
`OpenAIWebSearchTool` toggle — citations come back as ordinary
`LanguageModelV4SourcePart`s and render with `SourceCitations`. A provider
selector lets Anthropic and Google join in through the shared top-level
`reasoning:` option; any reasoning text renders with `ReasoningView`.

## Tests

A smoke widget test (`test/widget_test.dart`) boots the app and verifies the
prebuilt chat surface and navigation render without a network call:

```bash
fvm flutter test examples/advanced_app
```

## Setup

### API Keys

Pass API keys at build/run time via `--dart-define`:

```bash
cd examples/advanced_app
fvm flutter run \
  --dart-define=OPENAI_API_KEY=sk-... \
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
  --dart-define=GOOGLE_API_KEY=...
```

> These `--dart-define` values are compiled into the client app. Use them for
> local demos only. Production apps should call a trusted backend or fetch
> short-lived provider credentials instead of embedding long-lived secrets.

- **OPENAI_API_KEY** — Required for: Chat, Tools, Image Gen, Multimodal, Embeddings, TTS, STT, Completion, Object Stream, Conversation, Responses
- **ANTHROPIC_API_KEY** — Required for: Provider Chat (Anthropic), Responses (Anthropic)
- **GOOGLE_API_KEY** — Required for: Provider Chat (Google), Embeddings (Google), Responses (Google)

### Run

```bash
fvm flutter run --dart-define=OPENAI_API_KEY=sk-...
```

Or from the workspace root:

```bash
fvm dart pub get
cd examples/advanced_app && \
  fvm flutter run --dart-define=OPENAI_API_KEY=sk-...
```

## Platform Permissions

- **Android**: `RECORD_AUDIO`, `CAMERA`, `READ_EXTERNAL_STORAGE` (for STT and Multimodal)
- **iOS**: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`
