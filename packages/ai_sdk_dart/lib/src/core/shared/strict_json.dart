import 'dart:convert';

Map<String, dynamic> parseCompleteJsonObject(String text) {
  final trimmed = text.trim();
  final fenced = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (fenced != null) return _decodeObject(fenced.group(1)!);
  return _decodeObject(trimmed);
}

Object parseCompleteJsonValue(String text) {
  final trimmed = text.trim();
  final fenced = RegExp(
    r'^```(?:json)?\s*([\s\S]*?)\s*```$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  final decoded = jsonDecode(fenced?.group(1) ?? trimmed);
  return decoded;
}

Map<String, dynamic> _decodeObject(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map) throw const FormatException('Expected a JSON object');
  return decoded.cast<String, dynamic>();
}
