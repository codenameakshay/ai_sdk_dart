# ai_sdk_flutter_ui

A one-stop Flutter UI hub for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart): reactive
**controllers** (the Dart/Flutter equivalent of the Vercel AI SDK React hooks `useChat`,
`useCompletion`, `useObject`) plus a small library of prebuilt, themeable **Material widgets** to
render their state.

Each controller is a `ChangeNotifier`, so wrap it in a `ListenableBuilder` (or
`AnimatedBuilder`) and it rebuilds as tokens stream in. The widgets do this wiring for you.

No heavy platform dependencies: attachments and link-opening are exposed as callbacks rather than
pulling in `image_picker`/`file_selector`/`url_launcher`. Everything themes via
`Theme.of(context)`.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_flutter_ui: ^1.1.0
  ai_sdk_openai: ^1.1.0   # or another provider
```

## How it works

Controllers drive a [`ToolLoopAgent`](https://pub.dev/packages/ai_sdk_dart) — you build the
agent (which owns the model, tools, and step settings) and hand it to the controller. This keeps
the model/tool configuration in one place and lets a single agent back multiple controllers.

```dart
final agent = ToolLoopAgent(
  model: openai('gpt-4.1-mini'),
  instructions: 'You are a helpful assistant.',
  // tools: {...}, maxSteps: 5,  // optional
);
```

## Controllers

### ChatController — multi-turn streaming chat

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ToolLoopAgent _agent;
  late final ChatController _chat;

  @override
  void initState() {
    super.initState();
    _agent = ToolLoopAgent(model: openai('gpt-4.1-mini'));
    _chat = ChatController(
      onFinish: (message) => debugPrint('Done: ${message.content}'),
      onError: (error) => debugPrint('Error: $error'),
    );
  }

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _chat.messages.length,
                itemBuilder: (context, i) {
                  final msg = _chat.messages[i];
                  return ListTile(
                    title: Text(msg.role.name),
                    subtitle: Text(msg.content),
                  );
                },
              ),
            ),
            // Optimistic assistant bubble while the response streams in.
            if (_chat.streamingContent.isNotEmpty) Text(_chat.streamingContent),
            if (_chat.status == ChatStatus.streaming)
              const LinearProgressIndicator(),
            ElevatedButton(
              onPressed: () =>
                  _chat.sendMessage(agent: _agent, text: 'Tell me a joke'),
              child: const Text('Ask'),
            ),
          ],
        );
      },
    );
  }
}
```

**State:** `messages` (`List<ModelMessage>`), `status` (`ChatStatus.ready|submitted|streaming|error`),
`isLoading`, `error`, `streamingContent` (live buffer of the in-flight reply).

**Methods:** `sendMessage({agent, text})`, `append(ModelMessage)` (add without generating),
`reload({agent})` / `regenerate({agent})`, `stop()`, `clear()`, `clearError()`,
`addToolApprovalResponse({approvalId, approved, reason})` (for tools with `needsApproval`).

> All three controllers expose an `isStreaming` bool. `ChatController` additionally exposes the
> richer `status`/`isLoading` (`isStreaming` there is just `status == ChatStatus.streaming`).

### CompletionController — single-turn completion

```dart
final completion = CompletionController(
  agent: ToolLoopAgent(model: openai('gpt-4.1-mini')),
);

await completion.complete('Explain async/await in Dart.');
print(completion.completion); // accumulates as it streams

completion.dispose();
```

**State:** `completion` (`String`), `isLoading`, `isStreaming`, `error`.
**Methods:** `complete(prompt)`, `stop()`, `clear()`.

### ObjectStreamController — live structured output

Two ways to drive it.

**Ergonomic (`submit`)** — pass a `model` and `schema` up front, then call `submit(prompt)`. It
runs `streamText(... output: Output.object(schema:))` and binds the partial-output stream for you,
giving true `useObject`-style ergonomics:

```dart
final schema = Schema<Map<String, dynamic>>(
  jsonSchema: const {
    'type': 'object',
    'properties': {'title': {'type': 'string'}},
  },
  fromJson: (json) => json,
);

final controller = ObjectStreamController<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  schema: schema,
);

await controller.submit('Give me a book title as JSON.');
print(controller.value); // partial object, updated as it streams

controller.dispose();
```

`submit` throws a `StateError` if `model`/`schema` were not provided.

**Flexible (`bind`)** — adapt any `Stream<T>` of partial values yourself. Build the stream with
`streamText(... output: Output.object(...))` (or anything else) and `bind` its
`partialOutputStream`:

```dart
final streamResult = await streamText<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  prompt: 'Give me a book title as JSON.',
  output: Output.object(schema: schema),
);

await controller.bind(
  streamResult.partialOutputStream.map((v) => v as Map<String, dynamic>),
);
```

**State:** `value` (`T?`), `isLoading`, `isStreaming`, `error`.
**Methods:** `submit(prompt)` (requires `model`+`schema`), `bind(Stream<T>)`, `stop()`,
`clear()` / `reset()`.

## Prebuilt widgets

The package ships a small library of composable Material widgets that read only the controllers'
public state. Use them piecemeal, or drop in `AiChatScaffold` for a full chat screen.

| Widget | Purpose |
| --- | --- |
| `AiChatScaffold` | Drop-in chat body: `ChatMessageList` + `ChatComposer` wired to a `ChatController` + `ToolLoopAgent`. |
| `ChatMessageList` | Renders a controller's history + an optimistic streaming bubble; auto-scrolls; optional `messageBuilder`. |
| `ChatMessageBubble` | A single message styled by role (user/assistant/tool), with selectable text. |
| `ChatComposer` | Text field + send button; disabled while loading; optional `onStop` and `onAttach` callbacks. |
| `StreamingTextView` | Text that grows as it streams, with a subtle blinking cursor. |
| `ToolCallCard` | A tool call (name + pretty-printed JSON args) and its result/error. |
| `ReasoningView` | A collapsible panel for reasoning / "thinking" text. |
| `SourceCitations` | A wrap of citation chips for source parts (title + link), with an `onTap` callback. |

### Drop-in chat screen with `AiChatScaffold`

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _agent = ToolLoopAgent(
    model: openai('gpt-4.1-mini'),
    instructions: 'You are a helpful assistant.',
  );
  final _chat = ChatController();

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: AiChatScaffold(
        controller: _chat,
        agent: _agent,
        emptyState: const Center(child: Text('Ask me anything')),
        // onAttach: () => pickAndAttachFile(), // wire your own picker
      ),
    );
  }
}
```

Need more control? Compose the pieces yourself — e.g. `ChatMessageList` over your own scroll view
plus a custom `ChatComposer`, or a custom `messageBuilder` that renders `ToolCallCard`,
`ReasoningView`, and `SourceCitations` inline for richer turns.

## License

MIT
