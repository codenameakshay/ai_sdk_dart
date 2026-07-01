import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Multi-turn streaming chat built entirely from the prebuilt
/// [AiChatScaffold] widget — no hand-rolled message list or composer.
///
/// [AiChatScaffold] wires a [ChatMessageList] and a [ChatComposer] to the
/// [ChatController] + [ToolLoopAgent]; tokens stream into bubbles reactively
/// and the composer flips to a stop button while a response is in flight.
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
    _agent = ToolLoopAgent(
      model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
      instructions: 'You are a helpful assistant. Be concise.',
      maxSteps: 5,
    );
    _chat = ChatController(onError: (err) => _showSnackBar('Error: $err'));
  }

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: _chat.clear,
          ),
        ],
      ),
      // The entire chat surface is one prebuilt widget.
      body: AiChatScaffold(
        controller: _chat,
        agent: _agent,
        emptyState: const _EmptyState(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Say hello to start the conversation',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
