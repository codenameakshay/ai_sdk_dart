import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

import 'answer_view.dart';

/// Renders Open Intelligent UI answers in an `ai_sdk_flutter_ui` chat.
///
/// Pass [buildMessage] as `chatMessageBuilder` to `AiChatScaffold` or
/// `ChatMessageList`. Answers are fed to one [OpenUiAnswers] by message id, so
/// streaming, saving and replay follow one path. A `@ToAssistant` click is sent
/// through [send], or through [agent] when [send] is null; the chat does not add
/// that turn to the transcript itself. Edits are written back into the answer's
/// `]]>openui:context`, so the model sees them on the next turn and a restored
/// transcript starts from them.
base class OpenUiChat {
  OpenUiChat({
    required this.controller,
    this.agent,
    this.send,
    OpenUiLibrary? library,
    OpenUiBuilderLookup? builders,
    this.tools = const [],
    this.onAction,
    this.fallbackServices = const OpenUiServices(),
    this.locale,
    this.records,
  }) : library = intelligentUiFor(
         builders ?? openUiCoreBuilders,
         library: library,
       ),
       builders = builders ?? openUiCoreBuilders {
    if (agent == null && send == null) {
      throw ArgumentError('OpenUiChat needs an agent or a send function.');
    }
    _answers = OpenUiAnswers(
      library: this.library,
      tools: tools,
      locale: locale,
      records: records,
      onSave: _onSave,
    );
    controller.addListener(_prune);
  }

  final ChatController controller;

  /// The agent that answers `@ToAssistant` turns when [send] is null.
  final ToolLoopAgent? agent;

  /// Sends the text of a `@ToAssistant` turn over any transport.
  final Future<void> Function(String text)? send;

  final OpenUiLibrary library;
  final OpenUiBuilderLookup builders;

  /// Tools for `Query` and `Mutation` statements.
  final List<OpenUiTool> tools;

  /// Library actions the view does not handle itself.
  final ValueChanged<ActionEvent>? onAction;

  /// Services for answers' views wherever the app's scope leaves them unset.
  final OpenUiServices fallbackServices;

  /// The locale of each answer's session.
  final String? locale;

  /// The records each answer's session binds, by message id.
  final List<BoundRecord> Function(String id)? records;

  late final OpenUiAnswers _answers;
  final Map<String, ChatMessage> _committedEntries = {};
  String? _writing;
  bool _sendingAction = false;
  bool _disposed = false;

  /// A `chatMessageBuilder` for `AiChatScaffold` and `ChatMessageList`.
  Widget buildMessage(
    BuildContext context,
    ChatMessage message,
    bool isStreaming,
  ) {
    final content = message.message.content;
    final text = _answerText(message.message);
    return switch (message.message.role) {
      ModelMessageRole.user when content != null => OpenUiUserMessage(
        text: content,
      ),
      ModelMessageRole.assistant when text != null => _Answer(
        key: ValueKey(message.id),
        chat: this,
        id: message.id,
        raw: text,
        streaming: isStreaming,
      ),
      ModelMessageRole.user => ChatMessageBubble(message: message.message),
      _ => AssistantMessageView(message: message.message),
    };
  }

  /// The session for the answer with [id], if it has been built.
  OpenUiSession? sessionOf(String id) => _answers.sessionOf(id);

  void dispose() {
    _disposed = true;
    controller.removeListener(_prune);
    _answers.dispose();
    _committedEntries.clear();
  }

  /// Feeds the current text of the answer [id] to its session. The committed
  /// entry it was built from is kept, so a later change to it counts as a
  /// replacement.
  OpenUiSession _update(String id, String raw, {required bool streaming}) {
    final entry = controller.chatMessages.where((m) => m.id == id).firstOrNull;
    if (entry != null) _committedEntries.putIfAbsent(id, () => entry);
    return _answers.update(id, raw, streaming: streaming);
  }

  /// Writes an edited answer's text, with its state, into the committed
  /// transcript.
  void _onSave(String id, String text) {
    _writing = id;
    try {
      controller.updateMessage(
        id,
        ModelMessage(role: ModelMessageRole.assistant, content: text),
      );
    } finally {
      _writing = null;
      final saved = controller.chatMessages
          .where((m) => m.id == id)
          .firstOrNull;
      if (saved != null) _committedEntries[id] = saved;
    }
  }

  void _send(ActionEvent event) {
    if (_disposed || controller.isLoading || _sendingAction) return;
    _sendingAction = true;
    final sender = send;
    unawaited(() async {
      try {
        final text = buildActionUserMessage(event);
        if (sender != null) {
          await sender(text);
        } else {
          await controller.sendMessage(agent: agent!, text: text);
        }
      } finally {
        _sendingAction = false;
      }
    }());
  }

  /// Drops the sessions of answers that left the transcript (reload, clear),
  /// or were replaced by another text, so their Query timers stop. Feeds a
  /// committed answer its final text.
  void _prune() {
    final entries = {for (final m in controller.chatMessages) m.id: m};
    _committedEntries.removeWhere((id, _) => !entries.containsKey(id));
    for (final MapEntry(key: id, value: entry) in entries.entries) {
      final previous = _committedEntries[id];
      final replaced =
          previous != null &&
          !identical(previous, entry) &&
          _writing != id &&
          controller is! ConversationChatController;
      if (replaced) {
        _answers.remove(id);
        _committedEntries.remove(id);
        continue;
      }
      _committedEntries[id] = entry;
      if (_answers.isStreaming(id) &&
          entry.status != ConversationMessageStatus.streaming) {
        final raw = _answerText(entry.message);
        if (raw != null) _answers.update(id, raw, streaming: false);
      }
    }
    final streamingId = controller.isLoading
        ? controller.streamingMessageId
        : null;
    _answers.retain([
      ...entries.keys,
      if (streamingId != null && _answers.isStreaming(streamingId)) streamingId,
    ]);
  }
}

/// The text of an answer: its content, or the text of its text parts, which is
/// how `ConversationChatController` stores assistant messages.
String? _answerText(ModelMessage message) {
  final content = message.content;
  if (content != null) return content;
  if (message.parts == null) return null;
  final text = message.text;
  return text.isEmpty ? null : text;
}

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
    if (widget.chat._disposed) return;
    widget.chat._update(widget.id, widget.raw, streaming: widget.streaming);
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OpenUiAnswerView(
        answers: chat._answers,
        id: widget.id,
        builders: chat.builders,
        onToAssistant: chat._send,
        onAction: chat.onAction,
        fallbackServices: chat.fallbackServices,
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
                            OpenUiLocalizations.of(
                              context,
                            ).formData(fields.length),
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
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
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
