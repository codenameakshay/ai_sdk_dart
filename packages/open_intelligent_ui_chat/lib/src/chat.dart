import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

/// Renders Open Intelligent UI answers in an `ai_sdk_flutter_ui` chat.
///
/// Pass [buildMessage] as `chatMessageBuilder` to `AiChatScaffold` or
/// `ChatMessageList`, and give the agent `library.systemPrompt(chatPromptFor(library))`
/// as its instructions. Each answer keeps one [OpenUiSession] by message id,
/// from the first streamed token to the committed message. A `@ToAssistant`
/// click sends the next user turn with its form state, as react-ui does.
/// Edits are written back into the answer's `]]>openui:context`, so the model
/// sees them on the next turn and a restored transcript starts from them.
base class OpenUiChat {
  OpenUiChat({
    required this.controller,
    required this.agent,
    OpenUiLibrary? library,
    OpenUiBuilderLookup? builders,
    this.tools = const [],
    this.onAction,
    this.fallbackServices = const OpenUiServices(),
  }) : library = library ?? intelligentUiFor(builders ?? openUiCoreBuilders),
       builders = builders ?? openUiCoreBuilders {
    controller.addListener(_prune);
  }

  final ChatController controller;

  /// The agent that answers `@ToAssistant` turns.
  final ToolLoopAgent agent;
  final OpenUiLibrary library;
  final OpenUiBuilderLookup builders;

  /// Tools for `Query` and `Mutation` statements.
  final List<OpenUiTool> tools;

  /// Library actions the view does not handle itself.
  final ValueChanged<ActionEvent>? onAction;

  /// Services for answers' views wherever the app's scope leaves them unset.
  final OpenUiServices fallbackServices;

  final Map<String, OpenUiSession> _sessions = {};
  final Set<String> _unsaved = {};
  final Map<String, ChatMessage> _committedEntries = {};
  String? _writing;
  bool _disposed = false;

  /// A `chatMessageBuilder` for `AiChatScaffold` and `ChatMessageList`.
  Widget buildMessage(
    BuildContext context,
    ChatMessage message,
    bool isStreaming,
  ) {
    final content = message.message.content;
    return switch (message.message.role) {
      ModelMessageRole.user when content != null => OpenUiUserMessage(
        text: content,
      ),
      ModelMessageRole.assistant when content != null => _Answer(
        key: ValueKey(message.id),
        chat: this,
        id: message.id,
        raw: content,
        streaming: isStreaming,
      ),
      ModelMessageRole.user => ChatMessageBubble(message: message.message),
      _ => AssistantMessageView(message: message.message),
    };
  }

  /// The session for the answer with [id], if it has been built.
  OpenUiSession? sessionOf(String id) => _sessions[id];

  void dispose() {
    _disposed = true;
    controller.removeListener(_prune);
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    _committedEntries.clear();
    _unsaved.clear();
  }

  OpenUiSession _session(String id, ParsedMessage message) {
    return _sessions.putIfAbsent(id, () {
      final entry = controller.chatMessages
          .where((m) => m.id == id)
          .firstOrNull;
      if (entry != null) _committedEntries[id] = entry;
      return OpenUiSession(
        library,
        tools: tools,
        initialState: _stateOf(message.context),
        onStateUpdate: (_) => _save(id),
      );
    });
  }

  void _save(String id) {
    if (_unsaved.add(id)) scheduleMicrotask(() => _write(id));
  }

  /// Writes the session's state into the committed answer. An answer that is
  /// still streaming has no committed message yet; it is written on commit.
  void _write(String id) {
    final session = _sessions[id];
    if (_disposed || !_unsaved.contains(id) || session == null) {
      return;
    }
    final entry = controller.chatMessages.where((m) => m.id == id).firstOrNull;
    final raw = entry?.message.content;
    if (raw == null || entry!.status == ConversationMessageStatus.streaming) {
      return;
    }
    _unsaved.remove(id);
    final state = session.state;
    _writing = id;
    try {
      controller.updateMessage(
        id,
        ModelMessage(
          role: ModelMessageRole.assistant,
          content: _withState(raw, state),
        ),
      );
    } finally {
      _writing = null;
      final saved = controller.chatMessages
          .where((m) => m.id == id)
          .firstOrNull;
      if (saved != null) _committedEntries[id] = saved;
    }
  }

  void _committed(String id) {
    if (_unsaved.contains(id)) scheduleMicrotask(() => _write(id));
  }

  void _send(ActionEvent event) {
    if (_disposed || controller.isLoading) return;
    unawaited(
      controller.sendMessage(agent: agent, text: buildActionUserMessage(event)),
    );
  }

  /// Drops the sessions of answers that left the transcript (reload, clear),
  /// so their Query timers stop.
  void _prune() {
    final entries = {for (final m in controller.chatMessages) m.id: m};
    _sessions.removeWhere((id, session) {
      final entry = entries[id];
      if (entry != null) {
        final previous = _committedEntries[id];
        final replaced =
            previous != null &&
            !identical(previous, entry) &&
            _writing != id &&
            controller is! ConversationChatController;
        if (!replaced) {
          _committedEntries[id] = entry;
          if (session.isStreaming &&
              entry.status != ConversationMessageStatus.streaming) {
            final raw = entry.message.content;
            if (raw != null) {
              session.update(raw, streaming: false);
              _committed(id);
            }
          }
          return false;
        }
      } else if (controller.isLoading &&
          session.isStreaming &&
          controller.streamingMessageId == id) {
        return false;
      }
      session.dispose();
      _unsaved.remove(id);
      _committedEntries.remove(id);
      return true;
    });
  }
}

/// Replaces the saved context without dropping Cloud scripts or framing.
String _withState(String raw, Map<String, Object?> state) {
  final markers = RegExp(
    r'^\]\]>openui:([a-z]+)([^\n]*)$',
    multiLine: true,
  ).allMatches(raw).toList();
  bool section(RegExpMatch marker, String kind) =>
      marker[1] == kind &&
      (marker[2]!.trim().isEmpty || marker[2]!.startsWith('?'));
  final content = markers.where((m) => section(m, 'content')).lastOrNull;
  final context = markers
      .where((m) => section(m, 'context') && m.start > (content?.start ?? -1))
      .lastOrNull;
  final built = buildMessage(
    content: '',
    context: state.isEmpty ? null : [state],
  );
  final saved = state.isEmpty ? '' : built.substring(built.indexOf('\n') + 2);
  if (context != null) {
    final next = markers.where((m) => m.start > context.start).firstOrNull;
    return raw.substring(0, context.start) +
        saved +
        (next == null ? '' : '\n${raw.substring(next.start)}');
  }
  final framed = content == null ? buildMessage(content: raw) : raw;
  return saved.isEmpty ? framed : '$framed\n$saved';
}

/// react-ui keeps an answer's state as the first item of its context.
Map<String, Object?> _stateOf(Object? context) => switch (context) {
  [final Map<String, Object?> state, ...] => state,
  final Map<String, Object?> state => state,
  _ => const {},
};

class _Answer extends StatefulWidget {
  const _Answer({
    super.key,
    required this.chat,
    required this.id,
    required this.raw,
    required this.streaming,
  });

  final OpenUiChat chat;
  final String id;
  final String raw;
  final bool streaming;

  @override
  State<_Answer> createState() => _AnswerState();
}

class _AnswerState extends State<_Answer> {
  late ParsedMessage _message;
  late OpenUiSession _session;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Answer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    _message = parseMessage(widget.raw, streaming: widget.streaming);
    _session = widget.chat._session(widget.id, _message)
      ..update(widget.raw, streaming: widget.streaming);
    if (!widget.streaming) widget.chat._committed(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final prose =
        !widget.streaming &&
        _session.root == null &&
        _message.content.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: prose
          ? AssistantMessageView(
              message: ModelMessage(
                role: ModelMessageRole.assistant,
                content: _message.content,
              ),
            )
          : OpenUiView(
              session: _session,
              builders: widget.chat.builders,
              onToAssistant: widget.chat._send,
              onAction: widget.chat.onAction,
              fallbackServices: widget.chat.fallbackServices,
            ),
    );
  }
}

/// A user turn. A `@ToAssistant` turn shows its message and, folded, the
/// form values that went with it, like react-ui's `GenUIUserMessage`.
class OpenUiUserMessage extends StatefulWidget {
  const OpenUiUserMessage({super.key, required this.text});

  /// The stored message, with or without `]]>openui:` markers.
  final String text;

  @override
  State<OpenUiUserMessage> createState() => _OpenUiUserMessageState();
}

class _OpenUiUserMessageState extends State<OpenUiUserMessage> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final message = parseMessage(widget.text);
    final fields = formFields(message.context);
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final theme = OpenUiTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (fields.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(theme.radii.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(theme.radii.lg),
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Form data (${fields.length} '
                            '${fields.length == 1 ? 'field' : 'fields'})',
                            style: small,
                          ),
                        ),
                        Icon(
                          _open ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_open)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (label, value) in fields)
                          Text('$label: $value', style: small),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (message.content.isNotEmpty)
          ChatMessageBubble(
            message: ModelMessage(
              role: ModelMessageRole.user,
              content: message.content,
            ),
          ),
      ],
    );
  }
}

/// The filled form fields in a user turn's context, as react-ui's
/// `GenUIUserMessage` lists them: the first object in the context, flat
/// `{name: {value}}` or nested by form name.
@visibleForTesting
List<(String, String)> formFields(Object? context) {
  final state = switch (context) {
    final List<Object?> list =>
      list.whereType<Map<String, Object?>>().firstOrNull ?? const {},
    final Map<String, Object?> map => map,
    _ => const <String, Object?>{},
  };
  bool isField(Object? v) => v is Map && v.containsKey('value');
  final nested = state.values.any(
    (v) => v is Map && !isField(v) && v.values.any(isField),
  );
  final groups = nested
      ? state.values.whereType<Map<Object?, Object?>>()
      : [state];
  return [
    for (final group in groups)
      for (final MapEntry(:key, :value) in group.entries)
        if (isField(value) && _shown((value as Map)['value']))
          ('$key', jsString(value['value'])),
  ];
}

bool _shown(Object? v) => v != null && v != '';
