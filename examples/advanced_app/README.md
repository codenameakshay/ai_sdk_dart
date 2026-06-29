# AI SDK Dart — Advanced Example

A comprehensive Flutter app demonstrating all major AI SDK capabilities: multiple providers, tool calling, image generation, multimodal input, embeddings, text-to-speech, and speech-to-text. Chat-style screens are built from the **prebuilt widgets** in `ai_sdk_flutter_ui` rather than hand-rolled UI.

## Features

| Feature | API | Prebuilt widgets | Provider(s) |
|---------|-----|------------------|-------------|
| Provider Chat | `ChatController` + `createProviderRegistry` | `AiChatScaffold`, `PromptSuggestions` | OpenAI, Anthropic, Google |
| Tools Chat | `streamText` + `tools` + `extractReasoningMiddleware` | `ChatComposer`, `ChatMessageBubble`, `ToolCallCard`, `ReasoningView`, `SourceCitations` | OpenAI |
| Image Generation | `generateImage` | — | OpenAI (DALL-E 3) |
| Multimodal | `streamText` + `LanguageModelV3ImagePart` | `StreamingTextView` | OpenAI |
| Embeddings | `embed`, `cosineSimilarity` | — | OpenAI, Google |
| Text-to-Speech | `generateSpeech` | — | OpenAI |
| Speech-to-Text | `transcribe` | — | OpenAI |
| Completion | `CompletionController` | `StreamingTextView` | OpenAI |
| Object Stream | `ObjectStreamController.submit(model, schema)` | — | OpenAI |
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

The Tools Chat screen drives `streamText` directly (instead of `ChatController`)
so it can read tool-call, tool-result, reasoning, and source events off
`fullStream` and render the full agentic turn:

- **`ToolCallCard`** — each tool call with its pretty-printed input and result.
- **`ReasoningView`** — the model's `<think>…</think>` reasoning, surfaced via
  `extractReasoningMiddleware`.
- **`ChatMessageBubble`** / **`ChatComposer`** — the conversation text and input.
- **`SourceCitations`** — rendered when the model returns sources.

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
fvm flutter run \
  --dart-define=OPENAI_API_KEY=sk-... \
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
  --dart-define=GOOGLE_API_KEY=...
```

- **OPENAI_API_KEY** — Required for: Chat, Tools, Image Gen, Multimodal, Embeddings, TTS, STT, Completion, Object Stream
- **ANTHROPIC_API_KEY** — Required for: Provider Chat (Anthropic)
- **GOOGLE_API_KEY** — Required for: Provider Chat (Google), Embeddings (Google)

### Run

```bash
cd examples/advanced_app
fvm flutter pub get
fvm flutter run --dart-define=OPENAI_API_KEY=sk-...
```

Or from the workspace root:

```bash
melos get
fvm flutter run -C examples/advanced_app --dart-define=OPENAI_API_KEY=sk-...
```

## Platform Permissions

- **Android**: `RECORD_AUDIO`, `CAMERA`, `READ_EXTERNAL_STORAGE` (for STT and Multimodal)
- **iOS**: `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`
