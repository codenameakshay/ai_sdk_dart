import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

class _ChatSnippetPage extends StatefulWidget {
  const _ChatSnippetPage({required this.chat, required this.agent});

  final ChatController chat;
  final ToolLoopAgent agent;

  @override
  State<_ChatSnippetPage> createState() => _ChatSnippetPageState();
}

class _ChatSnippetPageState extends State<_ChatSnippetPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final agent = widget.agent;

    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: chat.messages.length,
              itemBuilder: (context, i) {
                final msg = chat.messages[i];
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
          if (chat.isStreaming) const LinearProgressIndicator(),
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
                  onPressed: chat.isLoading
                      ? null
                      : () {
                          final text = _controller.text.trim();
                          if (text.isEmpty) return;
                          _controller.clear();
                          chat.sendMessage(agent: agent, text: text);
                        },
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionSnippetPage extends StatefulWidget {
  const _CompletionSnippetPage({required this.completion});

  final CompletionController completion;

  @override
  State<_CompletionSnippetPage> createState() => _CompletionSnippetPageState();
}

class _CompletionSnippetPageState extends State<_CompletionSnippetPage> {
  @override
  Widget build(BuildContext context) {
    final completion = widget.completion;

    return ListenableBuilder(
      listenable: completion,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: completion.isStreaming
                  ? null
                  : () => completion.complete('Write a haiku about Dart.'),
              child: const Text('Generate haiku'),
            ),
            const SizedBox(height: 16),
            Text(completion.completion),
          ],
        ),
      ),
    );
  }
}

class _ObjectSnippetPage extends StatefulWidget {
  const _ObjectSnippetPage({required this.controller});

  final ObjectStreamController<Map<String, dynamic>> controller;

  @override
  State<_ObjectSnippetPage> createState() => _ObjectSnippetPageState();
}

class _ObjectSnippetPageState extends State<_ObjectSnippetPage> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: controller.isStreaming
                  ? null
                  : () => controller.submit('Describe Japan as a JSON object.'),
              child: const Text('Describe Japan'),
            ),
            const SizedBox(height: 16),
            if (controller.value != null) Text(controller.value.toString()),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('flutter_ui README and example snippets build', (tester) async {
    final agent = ToolLoopAgent(
      model: MockLanguageModelV3(response: [mockText('reply')]),
    );
    final chat = ChatController();
    final completion = CompletionController(agent: agent);
    final objectController = ObjectStreamController<Map<String, dynamic>>(
      model: MockLanguageModelV3(response: [mockText('{"country":"Japan"}')]),
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {
          'type': 'object',
          'properties': {
            'country': {'type': 'string'},
          },
        },
        fromJson: (json) => json,
      ),
    );
    final compiledExamplePages = <Widget>[
      _ChatSnippetPage(chat: chat, agent: agent),
      _CompletionSnippetPage(completion: completion),
      _ObjectSnippetPage(controller: objectController),
    ];

    await tester.pumpWidget(
      _wrap(
        Column(
          children: [
            Expanded(
              child: AiChatScaffold(controller: chat, agent: agent),
            ),
            StreamingTextView(
              text: completion.completion,
              isStreaming: completion.isStreaming,
            ),
            Expanded(
              child: ObjectStreamView<Map<String, dynamic>>(
                controller: objectController,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.byType(AiChatScaffold), findsOneWidget);
    expect(compiledExamplePages, hasLength(3));
    expect(find.byType(StreamingTextView), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ObjectStreamView<Map<String, dynamic>>,
      ),
      findsOneWidget,
    );

    chat.dispose();
    completion.dispose();
    objectController.dispose();
  });
}
