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
enum ToolsChatFixture { normal, approval, error, sourcesTool, longHistory }

typedef ToolsChatStreamRunner =
    Future<StreamTextResult> Function(
      List<ModelMessage> messages,
      ToolSet tools,
    );

class ToolsChatPage extends StatefulWidget {
  const ToolsChatPage({
    super.key,
    this.fixture,
    this.streamRunner,
    this.scrollController,
  });

  final ToolsChatFixture? fixture;
  final ToolsChatStreamRunner? streamRunner;
  final ScrollController? scrollController;

  @override
  State<ToolsChatPage> createState() => _ToolsChatPageState();
}

class _ToolsChatPageState extends State<ToolsChatPage> {
  // extractReasoningMiddleware turns `<think>…</think>` spans into reasoning
  // parts, so the model's chain-of-thought shows up in the ReasoningView.
  late final LanguageModelV4 _model = wrapLanguageModel(
    model: OpenAIProvider(apiKey: openAiApiKey)('gpt-4.1-mini'),
    middleware: [extractReasoningMiddleware(tagName: 'think')],
  );

  static const _system =
      'You are a helpful assistant. First think briefly inside '
      '<think></think> tags, then answer. Use the getWeather tool for weather '
      'questions and the calculate tool for arithmetic.';

  late ScrollController _scrollController;
  late bool _ownsScrollController;
  final List<ModelMessage> _history = [];
  final List<_Item> _items = [];
  final List<LanguageModelV4SourcePart> _pendingSources = [];
  final StringBuffer _turnText = StringBuffer();

  _TextItem? _currentAssistant;
  _ReasoningItem? _currentReasoning;
  StreamSubscription<StreamTextEvent>? _sub;
  bool _streaming = false;
  bool _pinnedToBottom = true;
  bool _scrollScheduled = false;

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
  void initState() {
    super.initState();
    _ownsScrollController = widget.scrollController == null;
    _scrollController = widget.scrollController ?? ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pinnedToBottom = ScrollBottomPolicy.isNearBottomController(
        _scrollController,
      );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    if (_streaming) return;
    setState(() {
      _history.add(ModelMessage(role: ModelMessageRole.user, content: text));
      _items.add(_TextItem(ModelMessageRole.user, text));
      _pendingSources.clear();
      _streaming = true;
      _currentAssistant = null;
      _currentReasoning = null;
      _turnText.clear();
    });
    _scheduleScrollToBottom();

    try {
      final result = widget.streamRunner != null
          ? await widget.streamRunner!(_history, _tools)
          : await streamText(
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
        if (_pendingSources.isNotEmpty) {
          item.sources.addAll(_pendingSources);
          _pendingSources.clear();
        }
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
            LanguageModelV4ToolCallPart(
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
        final item = _currentAssistant;
        if (item == null) {
          _pendingSources.add(source);
        } else {
          item.sources.add(source);
        }
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
      if (_currentAssistant != null && _pendingSources.isNotEmpty) {
        _currentAssistant!.sources.addAll(_pendingSources);
      } else if (_pendingSources.isNotEmpty) {
        _items.add(
          _SourcesItem(List<LanguageModelV4SourcePart>.from(_pendingSources)),
        );
      }
      _pendingSources.clear();
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
      _pendingSources.clear();
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
    _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_pinnedToBottom || !_scrollController.hasClients) {
        return;
      }
      if (!_scrollController.position.hasContentDimensions) return;
      final target = _scrollController.position.maxScrollExtent;
      if ((target - _scrollController.position.pixels).abs() <= 0.5) return;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    _pinnedToBottom = ScrollBottomPolicy.isNearBottom(notification.metrics);
    return false;
  }

  void _onFixtureAction(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(label), duration: const Duration(seconds: 1)),
    );
  }

  Widget _buildFixture(ToolsChatFixture fixture) {
    return switch (fixture) {
      ToolsChatFixture.normal => _FixtureScaffold(
        items: const [
          _FixtureBubble(
            role: ModelMessageRole.user,
            text: 'What can this page do?',
          ),
          _FixtureBubble(
            role: ModelMessageRole.assistant,
            text: 'Offline fixture reply',
          ),
        ],
        composer: ChatComposer(
          onSend: (_) {},
          hintText: 'Ask about weather or math…',
        ),
      ),
      ToolsChatFixture.approval => _FixtureScaffold(
        items: const [
          _FixtureBubble(
            role: ModelMessageRole.user,
            text: 'Delete q3.pdf from reports.',
          ),
        ],
        panels: [
          ToolApprovalCard(
            request: const LanguageModelV4ToolApprovalRequestPart(
              approvalId: 'approval-delete',
              toolCall: LanguageModelV4ToolCallPart(
                toolCallId: 'call-delete',
                toolName: 'deleteFile',
                input: {'path': '/Users/me/reports/q3.pdf'},
              ),
            ),
            onApprove: (_) => _onFixtureAction('Approved fixture action'),
            onDeny: (_) => _onFixtureAction('Denied fixture action'),
          ),
        ],
        composer: const ChatComposer(
          onSend: _noopSend,
          enabled: false,
          hintText: 'Approval pending…',
        ),
      ),
      ToolsChatFixture.error => _FixtureScaffold(
        items: const [
          _FixtureBubble(
            role: ModelMessageRole.user,
            text: 'Summarise my deploy notes.',
          ),
        ],
        panels: [
          ChatErrorView(
            error: StateError('Fixture request failed'),
            onRetry: () => _onFixtureAction('Retry'),
            onDismiss: () => _onFixtureAction('Dismissed fixture error'),
          ),
        ],
        composer: ChatComposer(
          onSend: (_) {},
          hintText: 'Ask about weather or math…',
        ),
      ),
      ToolsChatFixture.sourcesTool => _FixtureScaffold(
        items: const [
          _FixtureBubble(
            role: ModelMessageRole.user,
            text: 'What is the weather in Tokyo?',
          ),
          _FixtureReasoning(text: 'Use the weather tool and cite the source.'),
          _FixtureTool(
            call: LanguageModelV4ToolCallPart(
              toolCallId: 'call-weather',
              toolName: 'getWeather',
              input: {'city': 'Tokyo'},
            ),
            result: LanguageModelV4ToolResultPart(
              toolCallId: 'call-weather',
              toolName: 'getWeather',
              output: ToolResultOutputText('Sunny, 22°C in Tokyo.'),
            ),
          ),
          _FixtureBubble(
            role: ModelMessageRole.assistant,
            text: 'It is currently 22°C and sunny in Tokyo.',
          ),
        ],
        sources: const [
          LanguageModelV4SourcePart(
            id: 'source-weather',
            url: 'https://weather.example.com/tokyo',
            title: 'Example Weather Feed',
          ),
        ],
        composer: ChatComposer(
          onSend: (_) {},
          hintText: 'Ask about weather or math…',
        ),
      ),
      ToolsChatFixture.longHistory => _FixtureScaffold(
        items: List<_FixtureItem>.generate(
          12,
          (i) => _FixtureBubble(
            role: i.isEven ? ModelMessageRole.user : ModelMessageRole.assistant,
            text: 'Conversation history ${i + 1}',
          ),
        ),
        composer: ChatComposer(
          onSend: (_) {},
          hintText: 'Ask about weather or math…',
        ),
      ),
    };
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    if (fixture != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tools Chat')),
        body: _buildFixture(fixture),
      );
    }

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
                : NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      children: [for (final item in _items) _buildItem(item)],
                    ),
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
      _TextItem() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatMessageBubble(
            message: ModelMessage(role: item.role, content: item.text),
            isStreaming: _streaming && identical(item, _currentAssistant),
          ),
          if (item.role == ModelMessageRole.assistant &&
              item.sources.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: SourceCitations(sources: item.sources),
            ),
        ],
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
      _SourcesItem() => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: SourceCitations(sources: item.sources),
      ),
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
  final List<LanguageModelV4SourcePart> sources = [];
}

class _ReasoningItem extends _Item {
  _ReasoningItem(this.text);
  String text;
}

class _ToolItem extends _Item {
  _ToolItem(this.call);
  final LanguageModelV4ToolCallPart call;
  LanguageModelV4ToolResultPart? result;
}

class _SourcesItem extends _Item {
  _SourcesItem(this.sources);
  final List<LanguageModelV4SourcePart> sources;
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

void _noopSend(String _) {}

sealed class _FixtureItem {
  const _FixtureItem();
}

class _FixtureBubble extends _FixtureItem {
  const _FixtureBubble({required this.role, required this.text});

  final ModelMessageRole role;
  final String text;
}

class _FixtureReasoning extends _FixtureItem {
  const _FixtureReasoning({required this.text});

  final String text;
}

class _FixtureTool extends _FixtureItem {
  const _FixtureTool({required this.call, this.result});

  final LanguageModelV4ToolCallPart call;
  final LanguageModelV4ToolResultPart? result;
}

class _FixtureScaffold extends StatelessWidget {
  const _FixtureScaffold({
    required this.items,
    required this.composer,
    this.panels = const [],
    this.sources = const [],
  });

  final List<_FixtureItem> items;
  final Widget composer;
  final List<Widget> panels;
  final List<LanguageModelV4SourcePart> sources;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              for (final panel in panels) ...[
                panel,
                const SizedBox(height: 12),
              ],
              for (final item in items) _buildFixtureItem(context, item),
              if (sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SourceCitations(sources: sources),
                ),
            ],
          ),
        ),
        composer,
      ],
    );
  }

  Widget _buildFixtureItem(BuildContext context, _FixtureItem item) {
    return switch (item) {
      _FixtureBubble() => ChatMessageBubble(
        message: ModelMessage(role: item.role, content: item.text),
      ),
      _FixtureReasoning() => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.85,
          ),
          child: ReasoningView(text: item.text, initiallyExpanded: true),
        ),
      ),
      _FixtureTool() => ToolCallCard(call: item.call, result: item.result),
    };
  }
}
