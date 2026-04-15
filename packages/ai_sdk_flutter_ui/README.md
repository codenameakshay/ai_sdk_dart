# ai_sdk_flutter_ui

Flutter UI controllers for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart) — the Dart/Flutter equivalent of the Vercel AI SDK React hooks (`useChat`, `useCompletion`, `useObject`).

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_flutter_ui: ^1.1.0
  ai_sdk_openai: ^1.1.0   # or another provider
```

## Controllers

### ChatController — streaming chat

```dart
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

class ChatPage extends StatefulWidget {
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _chat;

  @override
  void initState() {
    super.initState();
    _chat = ChatController(
      model: openai('gpt-4.1-mini'),
      onFinish: (event) => print('Done: ${event.text}'),
      onError: (error) => print('Error: $error'),
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
            if (_chat.isStreaming) const LinearProgressIndicator(),
            ElevatedButton(
              onPressed: () => _chat.append('Tell me a joke'),
              child: const Text('Ask'),
            ),
          ],
        );
      },
    );
  }
}
```

### CompletionController — single-turn completion

```dart
final completion = CompletionController(model: openai('gpt-4.1-mini'));

// Start streaming a completion
await completion.complete('Explain async/await in Dart.');
print(completion.text); // streamed result

completion.dispose();
```

### ObjectStreamController — live structured output

```dart
final controller = ObjectStreamController<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  schema: Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object', 'properties': {'title': {'type': 'string'}}},
    fromJson: (json) => json,
  ),
);

await controller.submit('Give me a book title');
print(controller.object); // partially streamed object
controller.dispose();
```

## License

MIT
