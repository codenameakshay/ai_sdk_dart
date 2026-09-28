# flutter_chat

Flutter example app for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart) — demonstrates the `ai_sdk_flutter_ui` controllers and conversation backends wired to the package's **prebuilt widgets**, with a polished Material 3 UI.

## Screens

| Screen | Controller | Prebuilt widgets | What it shows |
|--------|-----------|------------------|---------------|
| **Chat** | `ChatController` | `AiChatScaffold` (→ `ChatMessageList`, `ChatMessageBubble`, `ChatComposer`) | Multi-turn streaming chat from a single drop-in widget — bubbles, auto-scroll, stop button, empty state, clear history |
| **Completion** | `CompletionController` | `StreamingTextView` | Single-turn generation with preset chips; output grows token-by-token with a blinking cursor |
| **Object** | `ObjectStreamController` | — | Streams a typed JSON object (country profile) via the `submit(prompt)` convenience — fields appear as they arrive |
| **Conversation** | `ConversationController` + `LocalConversationBackend` | `AiChatScaffold.conversation` | A persisted, tool-approval conversation driven entirely locally by a `ToolLoopAgent`; the app bar has a language toggle that swaps in a demo Arabic `AiSdkUiStrings` set and flips the layout to RTL via `Directionality` |
| **Remote** | `ConversationController` + `RemoteConversationBackend` | `AiChatScaffold.conversation` | The same conversation UI backed by the `examples/remote_backend` reference server over `ai_sdk_remote`; shows a clear message with the endpoint and startup command when the backend is unreachable |

The Conversation and Remote screens are also reachable directly at the `/conversation` and `/remote` named routes (used by CI's browser and iOS Simulator smoke tests).

## Run

The API key is injected at build/run time via `--dart-define` (works on all
platforms — Android, iOS, web, desktop):

```sh
cd examples/flutter_chat
fvm flutter run --dart-define=OPENAI_API_KEY=sk-...

# Web
fvm flutter run -d chrome --dart-define=OPENAI_API_KEY=sk-...

# Release build
fvm flutter build apk --dart-define=OPENAI_API_KEY=sk-...
```

> `--dart-define` compiles the key into the client binary. Use it for local
> demos only. Production apps should call a trusted backend or use short-lived
> credentials instead of embedding long-lived provider secrets.

The Remote screen's backend URL is also configurable via `--dart-define`, and
defaults to the pinned reference server's loopback address:

```sh
fvm flutter run --dart-define=REMOTE_BACKEND_URL=http://127.0.0.1:8081/chat
```

Start the reference server first — see
[`examples/remote_backend`](../remote_backend/README.md).

## Structure

```
lib/
  main.dart                  # App shell + NavigationBar (5 tabs, same widgets as the named routes)
  config.dart                # compile-time key/URL from --dart-define
  pages/
    chat_page.dart           # ChatController demo
    completion_page.dart     # CompletionController demo
    object_stream_page.dart  # ObjectStreamController demo
    conversation_page.dart   # Local + remote ConversationController demos
```

## Key patterns

### Chat — one prebuilt widget

`AiChatScaffold` wires `ChatMessageList` + `ChatComposer` to a `ChatController`
and a `ToolLoopAgent`; no hand-rolled list or input row required.

```dart
final agent = ToolLoopAgent(
  model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
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
  agent: ToolLoopAgent(
    model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
  ),
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
  model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
  schema: countryProfileSchema,
  onFinish: (value) => print('Final: $value'),
);

await controller.submit('Generate a country profile for Japan.');
// `controller.value` updates with each partial object as fields arrive.
```
