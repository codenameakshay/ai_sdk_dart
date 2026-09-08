import 'dart:convert';

/// Coerces [value] to an [int], accepting `int`, `num`, or a numeric
/// [String]. Returns `null` for anything else, including unparsable strings.
int? intOrNull(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v),
  _ => null,
};

/// Parses [text] as JSON, returning the raw decoded value.
///
/// Falls back to returning [text] unchanged if it isn't valid JSON, so
/// callers that feed this into a tool-call `input` always get an object back.
Object safeParseJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return text;
  }
}

/// Generates a probably-unique id of the form `<prefix>-<microseconds>`.
String prefixedId(String prefix) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  return '$prefix-$micros';
}
