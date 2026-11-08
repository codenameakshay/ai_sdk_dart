import 'dart:convert';
import 'dart:math';

import 'js.dart';

/// A stored message split into its parts (lang-core `ParsedMessage`).
final class ParsedMessage {
  const ParsedMessage({
    required this.content,
    required this.context,
    required this.attributes,
    required this.end,
  });

  /// Body of the last content section, or the whole text.
  final String content;

  /// Parsed JSON of the context section, else its raw text; null when absent.
  final Object? context;
  final Map<String, String> attributes;
  final bool end;
}

/// Splits a stored message into its content, context, attributes and end flag.
ParsedMessage parseMessage(String raw, {bool streaming = false}) {
  var text = raw.replaceAllMapped(_retry, (m) => '${m[1]}\n');
  final cut = streaming ? _retryCut.firstMatch(text) : null;
  if (cut != null && '${_prefix}content'.startsWith(cut[1]!)) {
    text = text.substring(0, cut.start + 1);
  }

  final lines = text.split('\n').toList();
  final last = lines.last;
  final held =
      streaming &&
      last.isNotEmpty &&
      (last.startsWith(_prefix) || _prefix.startsWith(last));
  if (held) lines.removeLast();

  final sections = [_Section(null, {})];
  void close() {
    final body = sections.last.lines;
    if (body.isNotEmpty) {
      body[body.length - 1] = body.last.replaceFirst(_carriageReturn, '');
    }
  }

  var endAt = -1;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final match = _marker.firstMatch(line.replaceFirst(_carriageReturn, ''));
    if (match == null) {
      sections.last.lines.add(line);
      continue;
    }
    close();
    if (match[1] == 'end') {
      endAt = sections.length - 1;
      if (i == lines.length - 2 && lines[i + 1].isEmpty) break;
      continue;
    }
    sections.add(_Section(match[1], _readAttributes(match[2] ?? '')));
  }
  if (held) close();

  final kinds = [for (final s in sections) s.kind];
  final win = max(0, kinds.lastIndexOf('content'));
  final ctx = kinds.lastIndexOf('context');
  final Object? context = ctx > win
      ? _jsonOrText(sections[ctx].lines.join('\n'))
      : null;
  final winner = sections[win];
  return ParsedMessage(
    content: winner.lines.join('\n'),
    context: context,
    attributes: winner.attributes,
    end: endAt >= win,
  );
}

/// Writes a stored message with its marker lines.
String buildMessage({
  required String content,
  Object? context,
  Map<String, String> attributes = const {},
  bool end = false,
}) {
  final query = [
    for (final entry in attributes.entries)
      '${_encode(entry.key)}=${_encode(entry.value)}',
  ].join('&');
  var out = '${_prefix}content${query.isNotEmpty ? '?$query' : ''}\n$content';
  if (context != null) {
    final body = context is String ? context : Js.stringify(context);
    out += '\n${_prefix}context\n$body';
  }
  return end ? '$out\n${_prefix}end' : out;
}

const _prefix = ']]>openui:';
final _marker = RegExp(r'^\]\]>openui:([a-z]+)(?:\?(.*))?$');
final _retry = RegExp(r'([^\n])(?=\]\]>openui:content(?:\?|\r?\n|$))');
final _retryCut = RegExp(r'[^\n](\]\]>[a-z:]*)$');
final _carriageReturn = RegExp(r'\r$');

final class _Section {
  _Section(this.kind, this.attributes);

  final String? kind;
  final Map<String, String> attributes;
  final List<String> lines = [];
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
  } catch (_) {
    return s;
  }
}

Map<String, String> _readAttributes(String query) {
  final out = <String, String>{};
  for (final pair in query.split('&')) {
    final eq = pair.indexOf('=');
    final key = _decode(eq == -1 ? pair : pair.substring(0, eq));
    if (key.isNotEmpty) {
      out[key] = eq == -1 ? '' : _decode(pair.substring(eq + 1));
    }
  }
  return out;
}

Object? _jsonOrText(String s) {
  try {
    return jsonDecode(s);
  } on FormatException {
    return s;
  }
}
