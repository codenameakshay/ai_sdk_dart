# ai_sdk_dart examples

## In this directory

### `example.dart`

A self-contained runnable example covering every core API — no API key or network
connection required. Uses minimal in-memory fake models so you can run it instantly:

```sh
dart run example/example.dart
```

Demonstrates:

| Section | API |
|---------|-----|
| Text generation | `generateText` — text, finishReason, usage, steps |
| Streaming | `streamText` — live token-by-token output |
| Structured output | `Output.object` with a typed JSON schema |
| Tool use (multi-step) | `tool<INPUT, OUTPUT>` + `maxSteps` agent loop |
| Embeddings | `embed` + `cosineSimilarity` |
| Middleware | `wrapLanguageModel` + `extractReasoningMiddleware` |

---

## Runnable example apps

The repository contains three full example apps. Set your API keys, then run:

```sh
export OPENAI_API_KEY=sk-...
export ANTHROPIC_API_KEY=sk-ant-...   # advanced app only
export GOOGLE_API_KEY=AIza...         # advanced app only
```

### 1. Dart CLI — [`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)

A pure-Dart command-line program that exercises the full SDK against real providers.

```sh
cd examples/basic && dart run lib/main.dart
```

Covers: `generateText`, `streamText`, structured output (`Output.object` / `array` /
`choice` / `json`), type-safe tools, multi-step agent loops, `embed` +
`cosineSimilarity`, and the middleware system.

---

### 2. Flutter chat app — [`examples/flutter_chat`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/flutter_chat)

A Material 3 Flutter app showcasing all three `ai_sdk_flutter_ui` controllers.

```sh
cd examples/flutter_chat && fvm flutter run --dart-define=OPENAI_API_KEY=sk-...
# or: make run / make run-web
```

| Screen | Controller |
|--------|------------|
| Multi-turn streaming chat | `ChatController` |
| Single-turn completion with presets | `CompletionController` |
| Live structured JSON stream | `ObjectStreamController` |

---

### 3. Advanced app — [`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)

A comprehensive Flutter demo of every SDK feature across all three providers.

```sh
cd examples/advanced_app && fvm flutter run --dart-define=OPENAI_API_KEY=sk-...
# or: make run-advanced / make run-advanced-web
```

| Feature | Provider |
|---------|----------|
| Provider switcher (OpenAI / Anthropic / Google) | All |
| Tools chat (weather + calculator) | OpenAI |
| Image generation (DALL-E 3) | OpenAI |
| Multimodal (image + text input) | OpenAI / Google |
| Embeddings + cosine similarity | OpenAI / Google |
| Text-to-speech | OpenAI |
| Speech-to-text | OpenAI |
| Completion | All |
| Object stream | All |
