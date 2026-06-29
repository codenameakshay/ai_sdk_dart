# flutter_chat

Flutter example app for [AI SDK Dart](https://pub.dev/packages/ai) — demonstrates the three `ai_sdk_flutter_ui` controllers wired to the package's **prebuilt widgets**, with a polished Material 3 UI.

## Screens

| Screen | Controller | Prebuilt widgets | What it shows |
|--------|-----------|------------------|---------------|
| **Chat** | `ChatController` | `AiChatScaffold` (→ `ChatMessageList`, `ChatMessageBubble`, `ChatComposer`) | Multi-turn streaming chat from a single drop-in widget — bubbles, auto-scroll, stop button, empty state, clear history |
| **Completion** | `CompletionController` | `StreamingTextView` | Single-turn generation with preset chips; output grows token-by-token with a blinking cursor |
| **Object** | `ObjectStreamController` | — | Streams a typed JSON object (country profile) via the `submit(prompt)` convenience — fields appear as they arrive |

## Run

The API key is injected at build/run time via `--dart-define` (works on all platforms — Android, iOS, web, desktop):

```sh
# From repo root
fvm flutter run --dart-define=OPENAI_API_KEY=sk-...

# Web
fvm flutter run -d chrome --dart-define=OPENAI_API_KEY=sk-...

# Release build
fvm flutter build apk --dart-define=OPENAI_API_KEY=sk-...
```

## Structure

```
lib/
  main.dart                  # App shell + bottom NavigationBar
  config.dart                # API key from environment
  pages/
    chat_page.dart           # ChatController demo
    completion_page.dart     # CompletionController demo
    object_stream_page.dart  # ObjectStreamController demo
```

## Key patterns

### Chat — one prebuilt widget

`AiChatScaffold` wires `ChatMessageList` + `ChatComposer` to a `ChatController`
and a `ToolLoopAgent`; no hand-rolled list or input row required.

```dart
final agent = ToolLoopAgent(
  model: OpenAIProvider(apiKey: apiKey)('gpt-4.1-mini'),
  instructions: 'You are a helpful assistant.',
  maxSteps: 5,
);
final chat = ChatController();

Scaffold(
  appBar: AppBar(title: const Text('Chat')),
  body: AiChatScaffold(controller: chat, agent: agent),
);
```

### Completion — `StreamingTextView`

```dart
final completion = CompletionController(
  agent: ToolLoopAgent(model: OpenAIProvider(apiKey: apiKey)('gpt-4.1-mini')),
);
await completion.complete('Explain async/await in Dart.');

// Renders the growing text with a blinking cursor while streaming:
StreamingTextView(
  text: completion.completion,
  isStreaming: completion.isStreaming,
);
```

### ObjectStreamController — `submit(prompt)`

The useObject-style convenience: pass the model + schema once, then just call
`submit` — it runs `streamText(output: Output.object(...))` and binds the
partial-output stream for you.

```dart
final controller = ObjectStreamController<Map<String, dynamic>>(
  model: OpenAIProvider(apiKey: apiKey)('gpt-4.1-mini'),
  schema: countryProfileSchema,
  onFinish: (value) => print('Final: $value'),
);

await controller.submit('Generate a country profile for Japan.');
// `controller.value` updates with each partial object as fields arrive.
```
