# ai_sdk_dart examples

## In this directory

### `example.dart`

The v3 public-contract showcase — runs real requests against OpenAI, so it
needs a key:

```sh
dart run --define=OPENAI_API_KEY=sk-... example/example.dart
```

Demonstrates:

| Section | API |
|---------|-----|
| Instructions | `instructions` — the canonical top-level instruction |
| Canonical stream | `result.stream` — the exhaustive typed event stream |
| Lifecycle callbacks | `onStart`, `onStepStart`, `onToolExecutionStart`, `onToolExecutionEnd`, `onStepEnd`, `onEnd` |
| Aggregate vs. final step | `result.usage`/`result.text` (aggregate) vs. `result.finalStep` |
| History reuse | `responseMessages` + `ModelMessage.fromProvider` |
| Context + approval | `toolWithContext` + `approvalPolicy` |
| Bounded concurrency | `maxToolConcurrency` |
| Cancellation & deadlines | `CancellationToken` + `TimeoutConfiguration` |
| Payload retention | `BodyInclusionPolicy` |

For a keyless, offline walk-through of the same contracts — useful when you
just want to read compiling code without a provider key — see
[`example/migration/v3_contracts.dart`](migration/v3_contracts.dart) and
[`example/migration/v3_generation.dart`](migration/v3_generation.dart), which
run against `MockLanguageModelV4` and are covered by
`test/v3_contracts_example_test.dart` and `test/migration_examples_test.dart`.

---

## Runnable example apps

The repository contains three full example apps.

### 1. Dart CLI — [`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)

A pure-Dart command-line program that exercises the full SDK against real providers.

```sh
OPENAI_API_KEY=sk-... make run-basic
```

A 15-demo tour of the v3 contracts, selectable by number (`dart run lib/main.dart 5`).

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
cd examples/advanced_app && fvm flutter run \
  --dart-define=OPENAI_API_KEY=sk-... \
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
  --dart-define=GOOGLE_API_KEY=AIza...
# or: make run-advanced / make run-advanced-web
```

| Feature | Provider |
|---------|----------|
| Provider switcher (OpenAI / Anthropic / Google) | All |
| Tools chat (weather + calculator) | OpenAI |
| Image generation (DALL-E 3) | OpenAI |
| Multimodal (image + text input) | OpenAI |
| Embeddings + cosine similarity | OpenAI / Google |
| Text-to-speech | OpenAI |
| Speech-to-text | OpenAI |
| Completion | OpenAI |
| Object stream | OpenAI |
