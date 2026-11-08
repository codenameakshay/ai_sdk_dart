import 'case_table.dart';

/// JavaScript's `toUpperCase`: full Unicode case mapping, so "ß" is "SS".
String jsUpperCase(String text) => _map(text, jsUpperMap);

/// JavaScript's `toLowerCase`, with the final-sigma rule ("ΟΔΟΣ" is "οδος").
String jsLowerCase(String text) =>
    _map(text.replaceAllMapped(_finalSigma, (_) => 'ς'), jsLowerMap);

/// JavaScript's `trim`: ECMAScript white space and line terminators only, so
/// U+0085 stays (Dart's `trim` removes it).
String jsTrim(String text) {
  var start = 0;
  var end = text.length;
  while (start < end && _isSpace(text.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
    end--;
  }
  return text.substring(start, end);
}

final _finalSigma = RegExp(
  r'(?<=\p{Cased}\p{Case_Ignorable}*)Σ(?!\p{Case_Ignorable}*\p{Cased})',
  unicode: true,
);

String _map(String text, Map<int, String> table) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final mapped = table[rune];
    if (mapped != null) {
      out.write(mapped);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

bool _isSpace(int c) =>
    c == 0x09 ||
    c == 0x0A ||
    c == 0x0B ||
    c == 0x0C ||
    c == 0x0D ||
    c == 0x20 ||
    c == 0xA0 ||
    c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200A) ||
    c == 0x2028 ||
    c == 0x2029 ||
    c == 0x202F ||
    c == 0x205F ||
    c == 0x3000 ||
    c == 0xFEFF;
