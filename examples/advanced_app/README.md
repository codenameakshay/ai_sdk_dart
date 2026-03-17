# AI SDK Dart — Advanced Example

A comprehensive Flutter app demonstrating all major AI SDK capabilities: multiple providers, tools, image generation, multimodal input, embeddings, text-to-speech, and speech-to-text.

## Features

| Feature | API | Provider(s) |
|---------|-----|-------------|
| Provider Chat | `ChatController` + `createProviderRegistry` | OpenAI, Anthropic, Google |
| Tools Chat | `ToolLoopAgent` with tools | OpenAI |
| Image Generation | `generateImage` | OpenAI (DALL-E 3) |
| Multimodal | `LanguageModelV3ImagePart` in messages | OpenAI |
| Embeddings | `embed`, `cosineSimilarity` | OpenAI, Google |
| Text-to-Speech | `generateSpeech` | OpenAI |
| Speech-to-Text | `transcribe` | OpenAI |
| Completion | `CompletionController` | OpenAI |
| Object Stream | `ObjectStreamController` + `streamObject` | OpenAI |

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
