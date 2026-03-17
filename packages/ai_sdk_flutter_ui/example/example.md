# ai_sdk_flutter_ui examples

Flutter UI controllers for AI SDK Dart — the Dart/Flutter equivalent of the
Vercel AI SDK React hooks (`useChat`, `useCompletion`, `useObject`).

## Installation

```sh
dart pub add ai_sdk_dart ai_sdk_openai ai_sdk_flutter_ui
export OPENAI_API_KEY=sk-...
```

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
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _chat = ChatController(
      model: openai('gpt-4.1-mini'),
      onError: (e) => debugPrint('Error: $e'),
    );
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
                  final isUser = msg.role == LanguageModelV3Role.user;
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
                      child: Text(msg.content),
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
                    onPressed: _chat.isStreaming
                        ? null
                        : () {
                            final text = _controller.text.trim();
                            if (text.isEmpty) return;
                            _controller.clear();
                            _chat.append(text);
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
    _completion = CompletionController(model: openai('gpt-4.1-mini'));
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
              Text(_completion.text),
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
              if (_controller.object != null)
                Text(_controller.object.toString()),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## Runnable example apps

- **[`examples/flutter_chat`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/flutter_chat)** — Full Material 3 chat app with all three controllers
- **[`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)** — Multi-provider Flutter app with every SDK feature
