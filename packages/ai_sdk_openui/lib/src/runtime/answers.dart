import 'dart:async';

import '../lang/merge.dart';
import '../lang/message.dart';
import '../spec/bound.dart';
import '../spec/library.dart';
import 'response_bundle.dart';
import 'session.dart';

/// Replaces the saved context without dropping Cloud scripts or framing.
String messageWithState(String raw, Map<String, Object?> state) {
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

/// The saved state in a parsed message context: its first object, or {}.
Map<String, Object?> messageState(Object? context) => switch (context) {
  [final Map<String, Object?> state, ...] => state,
  final Map<String, Object?> state => state,
  _ => const {},
};

String _messageWithProgram(String raw, String program) {
  final markers = RegExp(
    r'^\]\]>openui:[a-z]+[^\n]*$',
    multiLine: true,
  ).allMatches(raw).toList();
  final content = markers
      .where((m) => RegExp(r'^\]\]>openui:content(?:\?.*)?$').hasMatch(m[0]!))
      .lastOrNull;
  if (content == null) {
    final next = markers.firstOrNull;
    return next == null ? program : '$program\n${raw.substring(next.start)}';
  }

  final bodyStart =
      content.end +
      (raw.substring(content.end).startsWith('\r\n')
          ? 2
          : raw.substring(content.end).startsWith('\n')
          ? 1
          : 0);
  final next = markers.where((m) => m.start >= bodyStart).firstOrNull;
  if (next == null) return '${raw.substring(0, bodyStart)}$program';
  return '${raw.substring(0, bodyStart)}$program\n${raw.substring(next.start)}';
}

/// One event for [OpenUiAnswers.listen], keyed by message id.
sealed class OpenUiMessageEvent {
  const OpenUiMessageEvent(this.id);
  final String id;
}

/// Streamed text appended to message [id].
final class OpenUiTextDelta extends OpenUiMessageEvent {
  const OpenUiTextDelta(super.id, this.delta);
  final String delta;
}

/// The full text of message [id] so far.
final class OpenUiTextSnapshot extends OpenUiMessageEvent {
  const OpenUiTextSnapshot(super.id, this.text, {this.streaming = true});
  final String text;
  final bool streaming;
}

/// Edit-mode statements for message [id], merged into its last finished program.
final class OpenUiPatch extends OpenUiMessageEvent {
  const OpenUiPatch(super.id, this.patch, {this.streaming = false});
  final String patch;
  final bool streaming;
}

/// Message [id] has finished streaming.
final class OpenUiMessageDone extends OpenUiMessageEvent {
  const OpenUiMessageDone(super.id);
}

/// One [OpenUiSession] per message id, fed by any transport: full text, deltas,
/// patches, or a stream of [OpenUiMessageEvent]s.
///
/// A user change on a finished message calls [onSave] with its text and state
/// in the `]]>openui:context`. Replay a saved text with
/// `update(id, text, streaming: false)` on a new instance.
final class OpenUiAnswers {
  OpenUiAnswers({
    required this.library,
    this.tools = const [],
    this.locale,
    this.records,
    this.onSave,
  });

  final OpenUiLibrary library;
  final List<OpenUiTool> tools;
  final String? locale;
  final List<BoundRecord> Function(String id)? records;
  final void Function(String id, String text)? onSave;

  final Map<String, OpenUiSession> _sessions = {};
  final Map<String, String> _rawTexts = {};
  final Map<String, String> _texts = {};
  final Map<String, String> _finished = {};
  final Map<String, bool> _streaming = {};
  final Set<String> _unsaved = {};
  final Set<String> _hasLocalState = {};
  final Set<StreamSubscription<OpenUiMessageEvent>> _subscriptions = {};
  bool _disposed = false;

  /// Sets the full text of message [id].
  OpenUiSession update(String id, String text, {required bool streaming}) {
    if (_disposed) throw StateError('OpenUiAnswers is disposed');
    final session = _sessions.putIfAbsent(
      id,
      () => OpenUiSession(
        library,
        tools: tools,
        locale: locale,
        records: records?.call(id) ?? const [],
        actionScope: id,
        initialState: messageState(
          parseMessage(text, streaming: streaming).context,
        ),
        onStateUpdate: (_) => _save(id),
      ),
    );
    _rawTexts[id] = text;
    _texts[id] = text;
    _streaming[id] = streaming;
    if (!streaming) _finished[id] = text;
    session.update(
      text,
      streaming: streaming,
      restoredState: messageState(
        parseMessage(text, streaming: streaming).context,
      ),
    );
    if (_hasLocalState.contains(id)) {
      _texts[id] = messageWithState(text, session.state);
    }
    if (!streaming && _unsaved.contains(id)) {
      scheduleMicrotask(() => _write(id));
    }
    return session;
  }

  /// Appends [delta] to the text of message [id], which is streaming.
  OpenUiSession append(String id, String delta) =>
      update(id, (_rawTexts[id] ?? '') + delta, streaming: true);

  /// Merges edit-mode [patch] statements into the last finished program of [id].
  OpenUiSession patch(String id, String patch, {bool streaming = false}) {
    final base = _finished[id] ?? _rawTexts[id] ?? '';
    final merged = mergeStatements(
      parseResponseBundle(base, streaming: false).program,
      patch,
    );
    final updated = _messageWithProgram(base, merged);
    return update(id, updated, streaming: streaming);
  }

  /// Marks message [id] as finished.
  OpenUiSession finish(String id) =>
      update(id, _rawTexts[id] ?? '', streaming: false);

  /// Applies each event of [events] to its message until the stream ends.
  StreamSubscription<OpenUiMessageEvent> listen(
    Stream<OpenUiMessageEvent> events,
  ) {
    if (_disposed) throw StateError('OpenUiAnswers is disposed');
    late final StreamSubscription<OpenUiMessageEvent> subscription;
    subscription = events.listen((event) {
      switch (event) {
        case OpenUiTextDelta(:final id, :final delta):
          append(id, delta);
        case OpenUiTextSnapshot(:final id, :final text, :final streaming):
          update(id, text, streaming: streaming);
        case OpenUiPatch(:final id, :final patch, :final streaming):
          this.patch(id, patch, streaming: streaming);
        case OpenUiMessageDone(:final id):
          finish(id);
      }
    }, onDone: () => _subscriptions.remove(subscription));
    _subscriptions.add(subscription);
    return subscription;
  }

  OpenUiSession? sessionOf(String id) => _sessions[id];

  String? textOf(String id) => _texts[id];

  bool isStreaming(String id) => _streaming[id] ?? false;

  /// Disposes the session of message [id] and forgets it.
  void remove(String id) {
    _sessions.remove(id)?.dispose();
    _rawTexts.remove(id);
    _texts.remove(id);
    _finished.remove(id);
    _streaming.remove(id);
    _unsaved.remove(id);
    _hasLocalState.remove(id);
  }

  /// Removes every message whose id is not in [ids].
  void retain(Iterable<String> ids) {
    final keep = ids.toSet();
    for (final id in [..._texts.keys]) {
      if (!keep.contains(id)) remove(id);
    }
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    _rawTexts.clear();
    _texts.clear();
    _finished.clear();
    _streaming.clear();
    _unsaved.clear();
    _hasLocalState.clear();
  }

  void _save(String id) {
    if (_unsaved.add(id)) scheduleMicrotask(() => _write(id));
  }

  void _write(String id) {
    final session = _sessions[id];
    final text = _rawTexts[id];
    if (_disposed ||
        session == null ||
        text == null ||
        !_unsaved.contains(id) ||
        (_streaming[id] ?? true)) {
      return;
    }
    _unsaved.remove(id);
    _hasLocalState.add(id);
    final saved = messageWithState(text, session.state);
    _texts[id] = saved;
    _finished[id] = text;
    onSave?.call(id, saved);
  }
}
