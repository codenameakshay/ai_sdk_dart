import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../config.dart';

/// Tool-calling chat that renders the *whole* agentic turn with the prebuilt
/// widgets: [ChatMessageBubble] for text, [ToolCallCard] for each tool call +
/// its result, [ReasoningView] for the model's `<think>` reasoning, and
/// [SourceCitations] for any sources. Input is the prebuilt [ChatComposer].
///
/// Unlike [ChatController] (which surfaces only the assistant's text), this
/// page drives `streamText` directly so it can read tool-call / tool-result /
/// reasoning / source events off `fullStream` and show them as they arrive.
class ToolsChatPage extends StatefulWidget {
  const ToolsChatPage({super.key});

  @override
  State<ToolsChatPage> createState() => _ToolsChatPageState();
}

class _ToolsChatPageState extends State<ToolsChatPage> {
  // extractReasoningMiddleware turns `<think>…</think>` spans into reasoning
  // parts, so the model's chain-of-thought shows up in the ReasoningView.
  late final LanguageModelV3 _model = wrapLanguageModel(
    model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
    middleware: [extractReasoningMiddleware(tagName: 'think')],
  );

  static const _system =
      'You are a helpful assistant. First think briefly inside '
      '<think></think> tags, then answer. Use the getWeather tool for weather '
      'questions and the calculate tool for arithmetic.';

  final _scrollController = ScrollController();
  final List<ModelMessage> _history = [];
  final List<_Item> _items = [];
  final List<LanguageModelV3SourcePart> _sources = [];
  final StringBuffer _turnText = StringBuffer();

  _TextItem? _currentAssistant;
  _ReasoningItem? _currentReasoning;
  StreamSubscription<StreamTextEvent>? _sub;
  bool _streaming = false;

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

  static final _tools = <String, Tool<dynamic, dynamic>>{
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
          return '$expr = ${_eval(expr)}';
        } catch (_) {
          return 'Could not evaluate: $expr';
        }
      },
    ),
  };

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (_streaming) return;
    setState(() {
      _history.add(ModelMessage(role: ModelMessageRole.user, content: text));
      _items.add(_TextItem(ModelMessageRole.user, text));
      _streaming = true;
      _currentAssistant = null;
      _currentReasoning = null;
      _turnText.clear();
    });
    _scrollToBottom();

    try {
      final result = await streamText(
        model: _model,
        system: _system,
        messages: _history,
        tools: _tools,
        maxSteps: 5,
      );
      // The `text` future rejects on a streaming error; we surface errors via
      // fullStream below, so swallow it to avoid an unhandled async error.
      result.text.then((_) {}, onError: (_) {});
      _sub = result.fullStream.listen(
        _onEvent,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: true,
      );
    } catch (err) {
      _onError(err);
    }
  }

  void _onEvent(StreamTextEvent event) {
    switch (event) {
      // Each new step starts a fresh assistant bubble / reasoning panel.
      case StreamTextStartStepEvent():
        _currentAssistant = null;
        _currentReasoning = null;
      case StreamTextTextDeltaEvent(:final delta):
        _turnText.write(delta);
        final item = _currentAssistant ??= _push(
          _TextItem(ModelMessageRole.assistant, ''),
        );
        item.text += delta;
        _bump();
      case StreamTextReasoningDeltaEvent(:final delta):
        final item = _currentReasoning ??= _push(_ReasoningItem(''));
        item.text += delta;
        _bump();
      case StreamTextToolInputEndEvent(
        :final toolCallId,
        :final toolName,
        :final input,
      ):
        _currentAssistant = null;
        _push(
          _ToolItem(
            LanguageModelV3ToolCallPart(
              toolCallId: toolCallId,
              toolName: toolName,
              input: input,
            ),
          ),
        );
        _bump();
      case StreamTextToolResultEvent(:final toolResult):
        for (final item in _items) {
          if (item is _ToolItem &&
              item.call.toolCallId == toolResult.toolCallId) {
            item.result = toolResult;
          }
        }
        _bump();
      case StreamTextSourceEvent(:final source):
        _sources.add(source);
        _bump();
      case StreamTextErrorEvent(:final error):
        _onError(error);
      default:
        break;
    }
  }

  void _onError(Object err) {
    _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    setState(() => _streaming = false);
    _showSnackBar('Error: $err');
  }

  void _onDone() {
    _sub = null;
    final text = _turnText.toString();
    if (text.isNotEmpty) {
      _history.add(
        ModelMessage(role: ModelMessageRole.assistant, content: text),
      );
    }
    if (!mounted) return;
    setState(() {
      _streaming = false;
      _currentAssistant = null;
      _currentReasoning = null;
    });
  }

  Future<void> _stop() async {
    await _sub?.cancel();
    _sub = null;
    if (!mounted) return;
    setState(() => _streaming = false);
  }

  void _clear() {
    _sub?.cancel();
    _sub = null;
    setState(() {
      _history.clear();
      _items.clear();
      _sources.clear();
      _turnText.clear();
      _currentAssistant = null;
      _currentReasoning = null;
      _streaming = false;
    });
  }

  /// Add [item] to the transcript and return it (so callers can keep a handle).
  T _push<T extends _Item>(T item) {
    _items.add(item);
    return item;
  }

  void _bump() {
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
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
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? const _EmptyState()
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    children: [
                      for (final item in _items) _buildItem(item),
                      if (_sources.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: SourceCitations(sources: _sources),
                        ),
                    ],
                  ),
          ),
          ChatComposer(
            onSend: _send,
            isLoading: _streaming,
            onStop: _stop,
            hintText: 'Ask about weather or math…',
          ),
        ],
      ),
    );
  }

  Widget _buildItem(_Item item) {
    return switch (item) {
      _TextItem() => ChatMessageBubble(
        message: ModelMessage(role: item.role, content: item.text),
        isStreaming: _streaming && identical(item, _currentAssistant),
      ),
      _ReasoningItem() => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          child: ReasoningView(text: item.text, initiallyExpanded: true),
        ),
      ),
      _ToolItem() => ToolCallCard(call: item.call, result: item.result),
    };
  }

  // ── tiny arithmetic evaluator (supports + - * / and parentheses) ──────────

  static num _eval(String expr) {
    expr = expr.replaceAll(' ', '');
    if (expr.isEmpty) return 0;
    return _parseAdd(expr).$1;
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
}

// ── transcript item types ───────────────────────────────────────────────────

sealed class _Item {}

class _TextItem extends _Item {
  _TextItem(this.role, this.text);
  final ModelMessageRole role;
  String text;
}

class _ReasoningItem extends _Item {
  _ReasoningItem(this.text);
  String text;
}

class _ToolItem extends _Item {
  _ToolItem(this.call);
  final LanguageModelV3ToolCallPart call;
  LanguageModelV3ToolResultPart? result;
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
          Icon(Icons.build_circle_outlined, size: 48, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Try "What\'s the weather in Tokyo?"\nor "What is 12 * (3 + 4)?"',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
