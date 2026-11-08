import 'dart:convert';

/// JavaScript value semantics for OpenUI Lang runtime values.
///
/// Runtime values are `Object?`: `String`, `num`, `bool`, `null`,
/// `List<Object?>`, `Map<String, Object?>`, and the lang's own node types.
/// JavaScript has one numeric type, so `int` and `double` are interchangeable
/// here and every helper treats them alike.
abstract final class Js {
  static String typeOf(Object? value) => switch (value) {
    null => 'object',
    String() => 'string',
    num() => 'number',
    bool() => 'boolean',
    _ => 'object',
  };

  static bool truthy(Object? value) => switch (value) {
    null => false,
    bool() => value,
    num() => value != 0 && !value.isNaN,
    String() => value.isNotEmpty,
    _ => true,
  };

  static final _edgeWhitespace = RegExp(r'^\s+|\s+$');

  static String trim(String value) => value.replaceAll(_edgeWhitespace, '');

  /// `Number(value)` for a string, as JavaScript parses it.
  static double parseNumber(String text) {
    final s = trim(text);
    if (s.isEmpty) return 0;
    if (s == 'Infinity' || s == '+Infinity') return double.infinity;
    if (s == '-Infinity') return double.negativeInfinity;
    final radix = RegExp(r'^0([xXoObB])([0-9a-fA-F]+)$').firstMatch(s);
    if (radix != null) {
      final base = switch (radix.group(1)!.toLowerCase()) {
        'x' => 16,
        'o' => 8,
        _ => 2,
      };
      return BigInt.tryParse(radix.group(2)!, radix: base)?.toDouble() ??
          double.nan;
    }
    if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(s)) {
      return double.nan;
    }
    return double.parse(s);
  }

  /// lang-core's `toNumber`: numbers pass, numeric strings parse (NaN is 0),
  /// booleans are 1 or 0, everything else is 0.
  static num toNumber(Object? value) => switch (value) {
    num() => value,
    String() => _nanToZero(parseNumber(value)),
    bool() => value ? 1 : 0,
    _ => 0,
  };

  static num _nanToZero(double n) => n.isNaN ? 0 : n;

  /// JavaScript `Number(value)` (NaN stays NaN).
  static double number(Object? value) => switch (value) {
    null => 0,
    num() => value.toDouble(),
    String() => parseNumber(value),
    bool() => value ? 1 : 0,
    List() => parseNumber(string(value)),
    _ => double.nan,
  };

  /// JavaScript `String(value)`.
  static String string(Object? value) => switch (value) {
    null => 'null',
    String() => value,
    bool() => '$value',
    num() => numberToString(value),
    List() => value.map((v) => v == null ? '' : string(v)).join(','),
    _ => '[object Object]',
  };

  /// JavaScript `Number.prototype.toString()`.
  static String numberToString(num value) {
    if (value is int) return '$value';
    final d = value as double;
    if (d.isNaN) return 'NaN';
    if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
    if (d == 0) return '0';
    // Dart prints the shortest round-trip digits, as JavaScript does, and
    // writes integral doubles below 1e21 out in full with a ".0".
    final s = d.toString();
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  /// JavaScript `==`.
  static bool looseEquals(Object? a, Object? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a is num && b is num) return a == b;
    if (a is String && b is String) return a == b;
    if (a is bool && b is bool) return a == b;
    if (a is bool) return looseEquals(a ? 1 : 0, b);
    if (b is bool) return looseEquals(a, b ? 1 : 0);
    if (a is num && b is String) return a == parseNumber(b);
    if (a is String && b is num) return parseNumber(a) == b;
    if (a is List || a is Map) {
      if (b is String || b is num) return looseEquals(string(a), b);
      return identical(a, b);
    }
    if (b is List || b is Map) return looseEquals(a, string(b));
    return identical(a, b);
  }

  /// JavaScript `===`.
  static bool strictEquals(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (a is String && b is String) return a == b;
    if (a is bool && b is bool) return a == b;
    if (a == null || b == null) return a == null && b == null;
    return identical(a, b);
  }

  /// SameValueZero, as `Array.prototype.includes` uses.
  static bool sameValueZero(Object? a, Object? b) {
    if (a is num && b is num && a.isNaN && b.isNaN) return true;
    return strictEquals(a, b);
  }

  /// `Object.is`.
  static bool objectIs(Object? a, Object? b) {
    if (a is num && b is num) {
      if (a.isNaN && b.isNaN) return true;
      if (a == 0 && b == 0) return a.isNegative == b.isNegative;
      return a == b;
    }
    return strictEquals(a, b);
  }

  /// `JSON.stringify` for runtime values (non-JSON values become null).
  /// Numbers use JavaScript's spelling (`1e21` is `1e+21`, `2^53` has no
  /// `.0`), and array-index keys come first in ascending order.
  static String stringify(Object? value) => switch (value) {
    null || String() || bool() => jsonEncode(value),
    num() => _jsonNumber(value),
    List() => '[${value.map(stringify).join(',')}]',
    Map() =>
      '{${_jsKeyOrder(value).map((e) => '${jsonEncode('${e.key}')}:${stringify(e.value)}').join(',')}}',
    _ => 'null',
  };

  static String _jsonNumber(num value) {
    if (value is int) return '$value';
    if (!value.isFinite) return 'null';
    if (value == 0) return '0';
    final text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  static Iterable<MapEntry<Object?, Object?>> _jsKeyOrder(Map value) {
    final indexed =
        [
          for (final e in value.entries)
            if (_arrayIndex('${e.key}') != null) e,
        ]..sort(
          (a, b) =>
              _arrayIndex('${a.key}')!.compareTo(_arrayIndex('${b.key}')!),
        );
    return [
      ...indexed,
      for (final e in value.entries)
        if (_arrayIndex('${e.key}') == null) e,
    ];
  }

  static int? _arrayIndex(String key) {
    final index = int.tryParse(key);
    return index != null && index >= 0 && index < 4294967295 && '$index' == key
        ? index
        : null;
  }
}

/// JavaScript `String(value)`: how a program's value prints (`4` is "4").
String jsString(Object? value) => Js.string(value);
