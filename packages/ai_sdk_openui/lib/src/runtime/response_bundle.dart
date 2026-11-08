import 'dart:convert';

import '../lang/message.dart';

/// react-lang's reading of an OpenUI Cloud response: the program, its scripts, and whether it may run.
final class ResponseBundle {
  const ResponseBundle({
    required this.program,
    this.metadata = const {},
    this.scripts = const {},
    this.complete = true,
    this.isBundle = false,
    this.error,
    this.scriptRevision,
  });

  final String program;

  /// `name` when the response is framed and its content marker has `?name=`.
  final Map<String, String> metadata;
  final Set<String> scripts;
  final bool complete;
  final bool isBundle;

  /// 'Invalid scripts bundle', never while streaming.
  final String? error;
  final String? scriptRevision;
}

/// Reads an OpenUI Cloud response: a stored message (see parseMessage) plus its scripts section.
ResponseBundle parseResponseBundle(
  String? response, {
  required bool streaming,
}) {
  final text = response ?? '';
  final line = _contentLine.firstMatch(text);
  final framed = line != null && (!streaming || line[1] == '\n');
  final message = parseMessage(
    text.replaceAllMapped(_bareScripts, (m) => '${m[0]} '),
    streaming: streaming,
  );

  var program = message.content;
  var section = false;
  _Scripts? scripts;
  final at = _markerIndex(program);
  if (at >= 0 && program.startsWith(_scripts, at)) {
    section = true;
    final newline = program.indexOf('\n', at);
    var to = program.length;
    if (newline >= 0) {
      final next = _markerIndex(program.substring(newline + 1));
      if (next >= 0) to = newline + 1 + next;
      scripts = _readScripts(
        program.substring(at + _scripts.length, newline),
        program.substring(newline + 1, to),
      );
    }
    final before = at > 0
        ? program.substring(0, at).replaceFirst(_trailingNewline, '')
        : '';
    final after = program.substring(to);
    program = after.isNotEmpty ? '$before\n$after' : before;
  }

  if (!framed && !section && !message.end) {
    return ResponseBundle(program: program);
  }

  final error = section && scripts == null ? 'Invalid scripts bundle' : null;
  return ResponseBundle(
    program: program,
    metadata: {
      if (framed && message.attributes.containsKey('name'))
        'name': message.attributes['name']!,
    },
    scripts: scripts?.names ?? const {},
    complete: error == null && (message.end || !streaming || !framed),
    isBundle: true,
    error: streaming ? null : error,
    scriptRevision: scripts != null && scripts.names.isNotEmpty
        ? scripts.revision
        : null,
  );
}

const _scripts = ']]>openui:scripts';
final _contentLine = RegExp(
  r'^\]\]>openui:content(?:\?.*)?\r?$(\n?)',
  multiLine: true,
);
final _bareScripts = RegExp(
  r'^\]\]>openui:scripts(?=\?|\r?$)',
  multiLine: true,
);
final _trailingNewline = RegExp(r'\r?\n$');

final class _Scripts {
  const _Scripts(this.names, this.revision);

  final Set<String> names;

  /// Equal for equal bundles; the order is only for comparison, so any fixed order works.
  final String revision;
}

/// Index of the first `]]>` outside a string or a `#` or `//` comment, or -1.
int _markerIndex(String text) {
  var quote = '';
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quote.isNotEmpty) {
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == quote) {
        quote = '';
      }
    } else if (c == '#' ||
        (c == '/' && i + 1 < text.length && text[i + 1] == '/')) {
      final newline = text.indexOf('\n', i);
      if (newline < 0) return -1;
      i = newline;
    } else if (c == '"' || c == "'") {
      quote = c;
    } else if (text.startsWith(']]>', i)) {
      return i;
    }
  }
  return -1;
}

_Scripts? _readScripts(String header, String payload) {
  try {
    final head = jsonDecode(header);
    final values = jsonDecode(payload);
    final count = head is Map ? head['count'] : null;
    if (values is! List || !_isSafeInteger(count) || count != values.length) {
      return null;
    }
    final names = <String>{};
    for (final script in values) {
      if (script is! Map) return null;
      final name = script['name'];
      final code = script['code'];
      if (name is! String || name.isEmpty || code is! String) return null;
      if (!names.add(name)) return null;
    }
    final sorted = [
      for (final script in values)
        {'name': script['name'], 'code': script['code']},
    ]..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return _Scripts(names, jsonEncode(sorted));
  } on FormatException {
    return null;
  }
}

bool _isSafeInteger(Object? value) =>
    value is num &&
    value.isFinite &&
    value == value.truncateToDouble() &&
    value.abs() <= 9007199254740991;
