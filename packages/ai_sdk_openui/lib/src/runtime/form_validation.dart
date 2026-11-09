import '../lang/js.dart';

/// A validation rule: a type such as `minLength` and its optional argument.
final class ParsedRule {
  const ParsedRule(this.type, [this.arg]);

  final String type;

  /// A num for min, max, minLength and maxLength when numeric, else the raw value.
  final Object? arg;

  @override
  bool operator ==(Object other) =>
      other is ParsedRule && other.type == type && other.arg == arg;

  @override
  int get hashCode => Object.hash(type, arg);
}

/// Returns an error message, or null when the value passes.
typedef ValidatorFn = String? Function(Object? value, Object? arg);

/// String rules: `["required", "minLength:3", "pattern:^[a-z]+$"]`. Non-strings are skipped; a non-list gives [].
List<ParsedRule> parseRules(Object? rules) {
  if (rules is! List) return const [];
  return [
    for (final rule in rules)
      if (rule is String) _parseRule(rule),
  ];
}

/// Object rules: `{required: true, minLength: 3, email: true}`. false/null values are skipped; a non-map gives [].
List<ParsedRule> parseStructuredRules(Object? rules) {
  if (rules is! Map) return const [];
  return [
    for (final MapEntry(:key, :value) in rules.entries)
      if (value == true)
        ParsedRule(key as String)
      else if (value != false && value != null)
        ParsedRule(key as String, value),
  ];
}

/// The error messages of the built-in rules, in English. Subclass it and
/// override the members to translate.
class ValidationMessages {
  const ValidationMessages();

  String get fieldRequired => 'This field is required';
  String get optionRequired => 'At least one option is required';
  String get invalidEmail => 'Please enter a valid email';
  String get invalidUrl => 'Please enter a valid URL';
  String get notANumber => 'Must be a number';
  String atLeast(String limit) => 'Must be at least $limit';
  String atMost(String limit) => 'Must be no more than $limit';
  String atLeastCharacters(String limit) =>
      'Must be at least $limit characters';
  String atMostCharacters(String limit) =>
      'Must be no more than $limit characters';
  String get invalidFormat => 'Invalid format';
}

typedef _Rule =
    String? Function(Object? value, Object? arg, ValidationMessages messages);

const _english = ValidationMessages();

final Map<String, _Rule> _rules = {
  'required': _required,
  'email': _email,
  'url': _url,
  'numeric': _numeric,
  'min': _min,
  'max': _max,
  'minLength': _minLength,
  'maxLength': _maxLength,
  'pattern': _pattern,
};

/// required, email, url, numeric, min, max, minLength, maxLength, pattern.
final Map<String, ValidatorFn> builtInValidators = {
  for (final MapEntry(:key, value: rule) in _rules.entries)
    key: (value, arg) => rule(value, arg, _english),
};

/// Runs [rules] in order and returns the first error. A custom validator with the same type wins
/// over the built-in one. An unknown rule type is skipped. With [messages], the built-in rules
/// report in those words; without it they use [builtInValidators].
String? validate(
  Object? value,
  List<ParsedRule> rules, [
  Map<String, ValidatorFn>? customValidators,
  ValidationMessages? messages,
]) {
  for (final rule in rules) {
    final custom = customValidators?[rule.type];
    final builtIn = _rules[rule.type];
    final error = custom != null
        ? custom(value, rule.arg)
        : messages != null && builtIn != null
        ? builtIn(value, rule.arg, messages)
        : builtInValidators[rule.type]?.call(value, rule.arg);
    if (error != null && error.isNotEmpty) return error;
  }
  return null;
}

const _numericRules = {'min', 'max', 'minLength', 'maxLength'};
const _hostSchemes = {'http', 'https', 'ws', 'wss', 'ftp'};
final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final _floatPrefix = RegExp(
  r'^[+-]?(Infinity|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)',
);

ParsedRule _parseRule(String rule) {
  final colon = rule.indexOf(':');
  if (colon == -1) return ParsedRule(rule);
  final type = rule.substring(0, colon);
  final raw = rule.substring(colon + 1);
  final n = Js.number(raw);
  return ParsedRule(type, _numericRules.contains(type) && !n.isNaN ? n : raw);
}

bool _isEmpty(Object? value) {
  if (value == null || value == '') return true;
  if (value is List && value.isEmpty) return true;
  if (value is Map && value.containsKey('value')) {
    return _isEmpty(value['value']);
  }
  if (value is Map && value.isEmpty) return true;
  return false;
}

/// JavaScript `parseFloat`: the longest numeric prefix after leading whitespace.
double _parseFloat(String s) {
  final m = _floatPrefix.firstMatch(Js.trim(s));
  if (m == null) return double.nan;
  final text = m[0]!;
  if (text.endsWith('Infinity')) {
    return text.startsWith('-') ? double.negativeInfinity : double.infinity;
  }
  return double.parse(text);
}

num _toNum(Object? value) =>
    value is num ? value : _parseFloat(Js.string(value));

double _argNumber(Object? arg) => arg == null ? double.nan : Js.number(arg);

// ponytail: Uri approximates WHATWG URL parsing; exotic hosts may differ.
bool _isUrl(String s) {
  final uri = Uri.tryParse(s.trim());
  if (uri == null || !uri.hasScheme || uri.port > 65535) return false;
  if (uri.scheme == 'file' && uri.hasPort) return false;
  return !_hostSchemes.contains(uri.scheme) ||
      (uri.host.isNotEmpty && !uri.host.contains('%'));
}

String? _required(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value)) return m.fieldRequired;
  if (value is Map && value.isNotEmpty) {
    final values = value.values;
    if (values.every((v) => v is bool) && !values.any((v) => v == true)) {
      return m.optionRequired;
    }
  }
  return null;
}

String? _email(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value)) return null;
  if (value is! String || !_emailPattern.hasMatch(value)) {
    return m.invalidEmail;
  }
  return null;
}

String? _url(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value)) return null;
  if (value is! String || !_isUrl(value)) return m.invalidUrl;
  return null;
}

String? _numeric(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value)) return null;
  if (value is num && !value.isNaN) return null;
  if (value is String &&
      !_parseFloat(value).isNaN &&
      Js.trim(value).isNotEmpty) {
    return null;
  }
  return m.notANumber;
}

String? _min(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value)) return null;
  final n = _toNum(value);
  if (n.isNaN) return null;
  final limit = _argNumber(arg);
  return n >= limit ? null : m.atLeast(Js.numberToString(limit));
}

String? _max(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value)) return null;
  final n = _toNum(value);
  if (n.isNaN) return null;
  final limit = _argNumber(arg);
  return n <= limit ? null : m.atMost(Js.numberToString(limit));
}

String? _minLength(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value) || value is! String) return null;
  final limit = _argNumber(arg);
  return value.length >= limit
      ? null
      : m.atLeastCharacters(Js.numberToString(limit));
}

String? _maxLength(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value) || value is! String) return null;
  final limit = _argNumber(arg);
  return value.length <= limit
      ? null
      : m.atMostCharacters(Js.numberToString(limit));
}

String? _pattern(Object? value, Object? arg, ValidationMessages m) {
  if (_isEmpty(value) || value is! String || arg is! String) return null;
  if (_hasNestedQuantifier(arg)) return null;
  try {
    return RegExp(arg).hasMatch(value) ? null : m.invalidFormat;
  } on FormatException {
    return null;
  }
}

/// Whether [pattern] repeats a group that itself repeats, such as `(a+)+` or
/// `(?:a*){2,}`: the shape that backtracks exponentially. Such a pattern is
/// ignored like one that does not compile.
// ponytail: catches nested quantifiers only; overlapping alternation such as
// `(a|a)*` can still backtrack. Run patterns in an isolate if that matters.
bool _hasNestedQuantifier(String pattern) {
  final groups = <bool>[];
  var repeats = false;
  for (var i = 0; i < pattern.length; i++) {
    switch (pattern[i]) {
      case r'\':
        i++;
      case '[':
        i++;
        while (i < pattern.length && pattern[i] != ']') {
          if (pattern[i] == r'\') i++;
          i++;
        }
      case '(':
        groups.add(repeats);
        repeats = false;
      case ')' when groups.isNotEmpty:
        final inner = repeats;
        repeats = groups.removeLast() || inner;
        if (inner && i + 1 < pattern.length && '*+{'.contains(pattern[i + 1])) {
          return true;
        }
      case '?' when i > 0 && pattern[i - 1] != '(':
        repeats = true;
      case '*' || '+' || '{':
        repeats = true;
    }
  }
  return false;
}
