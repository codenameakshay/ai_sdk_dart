import 'dart:convert';
import 'dart:math' as math;

import 'lang/js.dart';
import 'runtime/session.dart';

const _prefix = ']]>openui:';
final _marker = RegExp(r'^\]\]>openui:([a-z]+)(?:\?(.*))?$');
final _retry = RegExp(r'([^\n])(?=\]\]>openui:content(?:\?|\r?\n|$))');
final _retryCut = RegExp(r'[^\n](\]\]>[a-z:]*)$');
final _cr = RegExp(r'\r$');

/// A stored chat message split into its sections, as lang-core's
/// `parseMessage` returns it.
final class OpenUiMessage {
  const OpenUiMessage({
    required this.content,
    this.context,
    this.attributes = const {},
    this.end = false,
  });

  /// The program (assistant) or the text the user wrote (user).
  final String content;

  /// The parsed JSON after `]]>openui:context`, or its raw text when it is
  /// not JSON. An assistant message keeps its `$state` here as `[state]`.
  final Object? context;

  /// The query of the `]]>openui:content?…` marker line.
  final Map<String, String> attributes;

  /// An `]]>openui:end` marker closed the content.
  final bool end;

  /// Splits [raw]. While [streaming], a trailing partial marker is held back.
  /// Text with no marker is all content.
  factory OpenUiMessage.parse(String raw, {bool streaming = false}) {
    var text = raw.replaceAllMapped(_retry, (m) => '${m[1]}\n');
    final cut = streaming ? _retryCut.firstMatch(text) : null;
    if (cut != null && '${_prefix}content'.startsWith(cut[1]!)) {
      text = text.substring(0, cut.start + 1);
    }
    final lines = text.split('\n');
    final last = lines.last;
    final held =
        streaming &&
        last != '' &&
        (last.startsWith(_prefix) || _prefix.startsWith(last));
    if (held) lines.removeLast();
    final sections = [_Section(null, const {})];
    void close() {
      final body = sections.last.lines;
      if (body.isNotEmpty) body.last = body.last.replaceFirst(_cr, '');
    }

    var endAt = -1;
    for (var i = 0; i < lines.length; i++) {
      final match = _marker.firstMatch(lines[i].replaceFirst(_cr, ''));
      if (match == null) {
        sections.last.lines.add(lines[i]);
        continue;
      }
      close();
      if (match[1] == 'end') {
        endAt = sections.length - 1;
        if (i == lines.length - 2 && lines[i + 1] == '') break;
        continue;
      }
      sections.add(_Section(match[1], _readAttributes(match[2] ?? '')));
    }
    if (held) close();
    final kinds = [for (final s in sections) s.kind];
    final win = math.max(0, kinds.lastIndexOf('content'));
    final ctx = kinds.lastIndexOf('context');
    Object? context;
    if (ctx > win) {
      final body = sections[ctx].lines.join('\n');
      try {
        context = jsonDecode(body);
      } on FormatException {
        context = body;
      }
    }
    return OpenUiMessage(
      content: sections[win].lines.join('\n'),
      context: context,
      attributes: sections[win].attributes,
      end: endAt >= win,
    );
  }

  /// The stored form with its marker lines, as lang-core's `buildMessage`
  /// writes it.
  String build() {
    final query = [
      for (final e in attributes.entries)
        '${_encode(e.key)}=${_encode(e.value)}',
    ].join('&');
    var out = '${_prefix}content${query.isEmpty ? '' : '?$query'}\n$content';
    final value = context;
    if (value != null) {
      out +=
          '\n${_prefix}context\n${value is String ? value : Js.stringify(value)}';
    }
    return end ? '$out\n${_prefix}end' : out;
  }

  /// The user turn that a `continue_conversation` [event] sends, as
  /// react-ui's `buildActionUserMessage` writes it: the message, then
  /// `["User clicked: …", formState, context?]`.
  static String fromAction(ActionEvent event) {
    final context = event.params['context'];
    final built = OpenUiMessage(
      content: event.humanFriendlyMessage,
      context: [
        'User clicked: ${event.humanFriendlyMessage}',
        event.formState,
        ?context,
      ],
    ).build();
    return event.humanFriendlyMessage.isNotEmpty
        ? built
        : built.substring(built.indexOf('\n') + 1);
  }
}

final class _Section {
  _Section(this.kind, this.attributes);
  final String? kind;
  final Map<String, String> attributes;
  final List<String> lines = [];
}

Map<String, String> _readAttributes(String query) {
  final out = <String, String>{};
  for (final pair in query.split('&')) {
    final eq = pair.indexOf('=');
    final key = _decode(eq == -1 ? pair : pair.substring(0, eq));
    if (key.isEmpty) continue;
    out[key] = eq == -1 ? '' : _decode(pair.substring(eq + 1));
  }
  return out;
}

String _encode(String s) => Uri.encodeComponent(s)
    .replaceAllMapped(
      RegExp(r"[!'()~]"),
      (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
    )
    .replaceAll('%20', '+');

String _decode(String s) {
  try {
    return Uri.decodeComponent(s.replaceAll('+', ' '));
  } on Object {
    return s;
  }
}
