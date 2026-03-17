import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Chat with [ToolLoopAgent] and tools: getWeather, calculate.
class ToolsChatPage extends StatefulWidget {
  const ToolsChatPage({super.key});

  @override
  State<ToolsChatPage> createState() => _ToolsChatPageState();
}

class _ToolsChatPageState extends State<ToolsChatPage> {
  late final ToolLoopAgent _agent;
  late final ChatController _chat;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  static final _weatherSchema = Schema<Map<String, dynamic>>(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
      'required': ['city'],
    },
    fromJson: (j) => j,
  );

  static final _calcSchema = Schema<Map<String, dynamic>>(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'expression': {'type': 'string'},
      },
      'required': ['expression'],
    },
    fromJson: (j) => j,
  );

  static final _tools = {
    'getWeather': tool<Map<String, dynamic>, String>(
      description: 'Get the current weather for a city.',
      inputSchema: _weatherSchema,
      execute: (input, _) async {
        final city = input['city']?.toString() ?? 'Unknown';
        return 'Sunny, 22°C in $city.';
      },
    ),
    'calculate': tool<Map<String, dynamic>, String>(
      description: 'Evaluate a simple math expression (e.g. 2+3*4).',
      inputSchema: _calcSchema,
      execute: (input, _) async {
        final expr = input['expression']?.toString() ?? '';
        try {
          final result = _eval(expr);
          return '$expr = $result';
        } catch (_) {
          return 'Could not evaluate: $expr';
        }
      },
    ),
  };

  static num _eval(String expr) {
    expr = expr.replaceAll(' ', '');
    if (expr.isEmpty) return 0;
    final r = _parseAdd(expr);
    return r.$1;
  }

  static (num, int) _parseAdd(String s) {
    var n = _parseMul(s);
    var i = n.$2;
    while (i < s.length) {
      final c = s[i];
      if (c == '+') {
        final r = _parseMul(s.substring(i + 1));
        n = (n.$1 + r.$1, n.$2 + 1 + r.$2);
        i = n.$2;
      } else if (c == '-') {
        final r = _parseMul(s.substring(i + 1));
        n = (n.$1 - r.$1, n.$2 + 1 + r.$2);
        i = n.$2;
      } else {
        break;
      }
    }
    return n;
  }

  static (num, int) _parseMul(String s) {
    var n = _parsePrimary(s);
    var i = n.$2;
    while (i < s.length) {
      final c = s[i];
      if (c == '*') {
        final r = _parsePrimary(s.substring(i + 1));
        n = (n.$1 * r.$1, n.$2 + 1 + r.$2);
        i = n.$2;
      } else if (c == '/') {
        final r = _parsePrimary(s.substring(i + 1));
        n = (n.$1 / r.$1, n.$2 + 1 + r.$2);
        i = n.$2;
      } else {
        break;
      }
    }
    return n;
  }

  static (num, int) _parsePrimary(String s) {
    s = s.trimLeft();
    if (s.isEmpty) return (0, 0);
    if (s[0] == '(') {
      final r = _parseAdd(s.substring(1));
      return (r.$1, r.$2 + 2);
    }
    var i = 0;
    while (i < s.length &&
        (s[i].codeUnitAt(0) >= 48 && s[i].codeUnitAt(0) <= 57 || s[i] == '.')) {
      i++;
    }
    if (i == 0) return (0, 0);
    return (num.tryParse(s.substring(0, i)) ?? 0, i);
  }

  @override
  void initState() {
    super.initState();
    _agent = ToolLoopAgent(
      model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
      instructions: 'You are a helpful assistant. Use tools when needed.',
      tools: _tools,
      maxSteps: 5,
    );
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
    _chat.sendMessage(agent: _agent, text: text);
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
        title: const Text('Tools Chat'),
        actions: [
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
                  hintText: 'Ask about weather or math…',
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
