# ai_sdk_flutter_ui

Flutter UI controllers for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart) — the
Dart/Flutter equivalent of the Vercel AI SDK React hooks (`useChat`, `useCompletion`,
`useObject`).

Each controller is a `ChangeNotifier`, so wrap it in a `ListenableBuilder` (or
`AnimatedBuilder`) and it rebuilds as tokens stream in.

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

> ChatController exposes streaming state via `status`/`isLoading`; `CompletionController` and
> `ObjectStreamController` expose a dedicated `isStreaming` bool.

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

`ObjectStreamController` adapts any `Stream<T>` of partial values into reactive state. Build the
stream yourself with `streamText(... output: Output.object(...))` and `bind` its
`partialOutputStream`:

```dart
final controller = ObjectStreamController<Map<String, dynamic>>();

final schema = Schema<Map<String, dynamic>>(
  jsonSchema: const {
    'type': 'object',
    'properties': {'title': {'type': 'string'}},
  },
  fromJson: (json) => json,
);

final streamResult = await streamText<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  prompt: 'Give me a book title as JSON.',
  output: Output.object(schema: schema),
);

await controller.bind(
  streamResult.partialOutputStream.map((v) => v as Map<String, dynamic>),
);
print(controller.value); // partial object, updated as it streams

controller.dispose();
```

**State:** `value` (`T?`), `isLoading`, `isStreaming`, `error`.
**Methods:** `bind(Stream<T>)`, `stop()`, `clear()` / `reset()`.

## License

MIT
