# ai_sdk_flutter_ui examples

Flutter UI controllers for AI SDK Dart — the Dart/Flutter equivalent of the
Vercel AI SDK React hooks (`useChat`, `useCompletion`, `useObject`).

## Installation

```sh
dart pub add ai_sdk_dart ai_sdk_openai ai_sdk_flutter_ui
```

In Flutter apps, resolve your provider key from a compile-time define like
`String.fromEnvironment('OPENAI_API_KEY')` or, for production, from a trusted
backend flow that returns short-lived credentials.

---

## ChatController — multi-turn streaming chat

The `ChatController` manages message history, streams assistant replies, and
implements `Listenable` for use with `ListenableBuilder`.

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
  late final ChatController _chat;
  late final ToolLoopAgent _agent;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _agent = ToolLoopAgent(model: openai('gpt-4.1-mini'));
    _chat = ChatController(onError: (e) => debugPrint('Error: $e'));
  }

  @override
  void dispose() {
    _chat.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: ListenableBuilder(
        listenable: _chat,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: _chat.messages.length,
                itemBuilder: (context, i) {
                  final msg = _chat.messages[i];
                  final isUser = msg.role == ModelMessageRole.user;
                  return Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser ? Colors.blue[100] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(msg.content ?? ''),
                    ),
                  );
                },
              ),
            ),
            if (_chat.isStreaming) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _chat.isLoading
                        ? null
                        : () {
                            final text = _controller.text.trim();
                            if (text.isEmpty) return;
                            _controller.clear();
                            _chat.sendMessage(agent: _agent, text: text);
                          },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## CompletionController — single-turn completion

```dart
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

class CompletionPage extends StatefulWidget {
  const CompletionPage({super.key});
  @override
  State<CompletionPage> createState() => _CompletionPageState();
}

class _CompletionPageState extends State<CompletionPage> {
  late final CompletionController _completion;

  @override
  void initState() {
    super.initState();
    _completion = CompletionController(
      agent: ToolLoopAgent(model: openai('gpt-4.1-mini')),
    );
  }

  @override
  void dispose() {
    _completion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completion')),
      body: ListenableBuilder(
        listenable: _completion,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton(
                onPressed: _completion.isStreaming
                    ? null
                    : () => _completion.complete('Write a haiku about Dart.'),
                child: const Text('Generate haiku'),
              ),
              const SizedBox(height: 16),
              Text(_completion.completion),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## ObjectStreamController — live structured JSON stream

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

class ObjectStreamPage extends StatefulWidget {
  const ObjectStreamPage({super.key});
  @override
  State<ObjectStreamPage> createState() => _ObjectStreamPageState();
}

class _ObjectStreamPageState extends State<ObjectStreamPage> {
  late final ObjectStreamController<Map<String, dynamic>> _controller;

  @override
  void initState() {
    super.initState();
    _controller = ObjectStreamController<Map<String, dynamic>>(
      model: openai('gpt-4.1-mini'),
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {
          'type': 'object',
          'properties': {
            'country': {'type': 'string'},
            'capital': {'type': 'string'},
            'population': {'type': 'number'},
            'languages': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
        },
        fromJson: (json) => json,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Object Stream')),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton(
                onPressed: _controller.isStreaming
                    ? null
                    : () => _controller.submit('Describe Japan as a JSON object.'),
                child: const Text('Describe Japan'),
              ),
              const SizedBox(height: 16),
              if (_controller.value != null)
                Text(_controller.value.toString()),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## ConversationController — persisted, replayable conversations

`ConversationController` wraps a `ConversationBackend` and exposes typed
`Conversation` snapshots instead of a plain message list, so a session can be
persisted, restored, and replayed across app restarts or between local and
remote execution.

### Basic wiring

```dart
import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key});
  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  late final ConversationController _conversation;

  @override
  void initState() {
    super.initState();
    _conversation = ConversationController(
      LocalConversationBackend(
        agent: ToolLoopAgent(model: openai('gpt-4.1-mini')),
        initial: Conversation(id: 'conversation-1', messages: const []),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // AiChatScaffold.conversation disposes the controller (and its backend)
    // by default, unlike the base AiChatScaffold constructor.
    return AiChatScaffold.conversation(conversationController: _conversation);
  }
}
```

`LocalConversationBackend` wraps a `ToolLoopAgent` and runs the tool loop
in-process. `RemoteConversationBackend` wraps a `RemoteConversationTransport`
(from `ai_sdk_remote`) for a trusted-backend flow instead — both take the
same `{required <agent|transport>, required Conversation initial}` shape:

```dart
LocalConversationBackend(
  agent: ToolLoopAgent(model: openai('gpt-4.1-mini')),
  initial: Conversation(id: 'conversation-1', messages: const []),
);

RemoteConversationBackend(
  transport: myRemoteConversationTransport,
  initial: Conversation(id: 'conversation-1', messages: const []),
);
```

### Persistence

Persist `ConversationCodec.encode(controller.conversation)`, and restore with
`backend.restore(encoded)` before attaching the screen. Restore only decodes
the snapshot — it never executes a tool or calls a provider.

```dart
final saved = ConversationCodec.encode(_conversation.conversation);
// ...persist `saved` (e.g. to local storage) and later:
await backend.restore(saved);
```

### Approvals

`AiChatScaffold`/`AiChatScaffold.conversation` render a pending
`LanguageModelV4ToolApprovalRequestPart` as an inline `ToolApprovalCard`
automatically, the same as the base `ChatController` flow for tools with
`needsApproval`. Pass `approvalBuilder` to render your own card instead:

```dart
AiChatScaffold.conversation(
  conversationController: _conversation,
  approvalBuilder: (context, controller, request) => ToolApprovalCard(
    request: request,
    onApprove: (reason) => controller.addToolApprovalResponse(
      approvalId: request.approvalId,
      approved: true,
      reason: reason,
    ),
    onDeny: (reason) => controller.addToolApprovalResponse(
      approvalId: request.approvalId,
      approved: false,
      reason: reason,
    ),
  ),
);
```

### Retry

`ConversationRetryBackend` (implemented by both `LocalConversationBackend`
and `RemoteConversationBackend`) exposes `retryInfo` and `retryLastTurn()`.
`ConversationController` forwards both, so callers don't need to cast the
backend:

```dart
ElevatedButton(
  onPressed: _conversation.retryInfo.isAvailable
      ? () => _conversation.retryLastTurn()
      : null,
  child: const Text('Retry'),
);
```

`ConversationRetryInfo.isAvailable` is only true when
`retryInfo.availability == ConversationRetryAvailability.available`. The
other values (`noFailedTurn`, `pendingApproval`, `unsafe`, `unsupported`)
explain why not — in particular, a turn that already executed a tool,
approval, or unknown part is reported `unsafe` rather than silently
replayed.

### Localizing/overriding UI copy

Every user-facing string in the prebuilt widgets (button labels, a11y
labels, status text) comes from `AiSdkUiStrings`. Override it by wrapping a
subtree in `AiSdkUiStringsScope`:

```dart
AiSdkUiStringsScope(
  strings: const AiSdkUiStrings(
    sendMessage: 'Envoyer',
    retry: 'Réessayer',
  ),
  child: AiChatScaffold.conversation(conversationController: _conversation),
);
```

### Framework lifecycle recipes

`example/recipes` has runnable patterns for wiring a `ConversationBackend`
into common state-management setups:

- [`conversation_scaffold.dart`](../example/recipes/conversation_scaffold.dart) — the minimal, keyless recipe above: a `LocalConversationBackend` with a mock model wired straight into `AiChatScaffold.conversation`.
- [`bloc_conversation.dart`](../example/recipes/bloc_conversation.dart) — a `ConversationCubit` that owns the backend's change subscription and can dispose an injected backend on replacement or close.
- [`riverpod_conversation.dart`](../example/recipes/riverpod_conversation.dart) — `autoDispose` providers that own a backend, its `ConversationController`, and a `StreamProvider` of snapshots for `ref.watch`.

---

## Runnable example apps

- **[`examples/flutter_chat`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/flutter_chat)** — Full Material 3 chat app with all three controllers
- **[`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)** — Multi-provider Flutter app with every SDK feature
