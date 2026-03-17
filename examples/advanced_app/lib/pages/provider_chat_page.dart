import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Multi-provider chat using [createProviderRegistry].
/// Switch between OpenAI, Anthropic, and Google models.
class ProviderChatPage extends StatefulWidget {
  const ProviderChatPage({super.key});

  @override
  State<ProviderChatPage> createState() => _ProviderChatPageState();
}

class _ProviderChatPageState extends State<ProviderChatPage> {
  late final ProviderRegistry _registry;
  late final ChatController _chat;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  static const _modelIds = [
    'openai:gpt-4.1-mini',
    'anthropic:claude-sonnet-4-20250514',
    'google:gemini-2.0-flash',
  ];

  String _selectedModelId = _modelIds.first;

  @override
  void initState() {
    super.initState();
    _registry = createProviderRegistry({
      'openai': RegistrableProvider(
        languageModelFactory: (id) => OpenAIProvider(apiKey: openAiApiKey)(id),
        embeddingModelFactory: (id) =>
            OpenAIProvider(apiKey: openAiApiKey).embedding(id),
      ),
      'anthropic': RegistrableProvider(
        languageModelFactory: (id) =>
            AnthropicProvider(apiKey: anthropicApiKey)(id),
        embeddingModelFactory: (_) =>
            throw UnsupportedError('Anthropic has no embedding model'),
      ),
      'google': RegistrableProvider(
        languageModelFactory: (id) =>
            GoogleGenerativeAIProvider(apiKey: googleApiKey)(id),
        embeddingModelFactory: (id) =>
            GoogleGenerativeAIProvider(apiKey: googleApiKey).embedding(id),
      ),
    });
    _chat = ChatController(
      onFinish: (_) => _scrollToBottom(),
      onError: (err) => _showSnackBar('Error: $err'),
    );
  }

  @override
  void dispose() {
    _chat.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _chat.status == ChatStatus.streaming) return;
    _controller.clear();

    final model = _registry.languageModel(_selectedModelId);
    final agent = ToolLoopAgent(
      model: model,
      instructions: 'You are a helpful assistant. Be concise.',
      maxSteps: 5,
    );
    _chat.sendMessage(agent: agent, text: text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Chat'),
        actions: [
          DropdownButton<String>(
            value: _selectedModelId,
            underline: const SizedBox(),
            items: _modelIds
                .map(
                  (id) => DropdownMenuItem(
                    value: id,
                    child: Text(id.split(':').first),
                  ),
                )
                .toList(),
            onChanged: _chat.status == ChatStatus.streaming
                ? null
                : (v) =>
                      setState(() => _selectedModelId = v ?? _modelIds.first),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear chat',
            onPressed: () => _chat.clear(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _chat,
        builder: (context, _) {
          final messages = _chat.messages;
          final streaming = _chat.streamingContent;
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: messages.length + (streaming.isNotEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return _MessageBubble(
                        text: streaming,
                        isUser: false,
                        isStreaming: true,
                      );
                    }
                    final msg = messages[index];
                    return _MessageBubble(
                      text: msg.content ?? '',
                      isUser: msg.role == ModelMessageRole.user,
                    );
                  },
                ),
              ),
              _InputBar(
                controller: _controller,
                isStreaming: _chat.status == ChatStatus.streaming,
                onSend: _send,
                onStop: _chat.stop,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
  });

  final String text;
  final bool isUser;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isUser ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = isUser ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                text.isEmpty ? '…' : text,
                style: TextStyle(color: fg, height: 1.4),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isStreaming
                  ? IconButton.filled(
                      key: const ValueKey('stop'),
                      onPressed: onStop,
                      icon: const Icon(Icons.stop_rounded),
                    )
                  : IconButton.filled(
                      key: const ValueKey('send'),
                      onPressed: onSend,
                      icon: const Icon(Icons.send_rounded),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
