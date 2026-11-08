import 'dart:convert';

/// JavaScript value semantics for OpenUI Lang runtime values.
///
/// Runtime values are `Object?`: `String`, `num`, `bool`, `null`,
/// `List<Object?>`, `Map<String, Object?>`, and the lang's own node types.
/// JavaScript has one numeric type, so `int` and `double` are interchangeable
/// here and every helper treats them alike.
abstract final class Js {
  /// `typeof value === "object"` for a value that is not null: a list, a
  /// map, or one of lang-core's objects ([JsFields]).
  static bool isObject(Object? value) =>
      value is List || value is Map || value is JsFields;

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
    // 0 first: on the web -0.0 is an int and would print as "-0.0".
    if (value == 0) return '0';
    if (value is int && value.abs() <= _maxSafe) return '$value';
    final d = value.toDouble();
    if (d.isNaN) return 'NaN';
    if (d.isInfinite) return d > 0 ? 'Infinity' : '-Infinity';
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
    if (isObject(a)) {
      if (b is String || b is num) return looseEquals(string(a), b);
      return identical(a, b);
    }
    if (isObject(b)) return looseEquals(a, string(b));
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

  /// `JSON.stringify` for runtime values: numbers print as JavaScript prints
  /// them (`3`, `0` for -0, `1e+21`), non-finite numbers and values with no
  /// JSON form are null, and elements, plans and AST nodes are the plain
  /// objects lang-core makes.
  static String stringify(Object? value) {
    final out = StringBuffer();
    _writeJson(value, out);
    return out.toString();
  }

  static void _writeJson(Object? value, StringBuffer out) {
    switch (value) {
      case String():
        out.write(jsonEncode(value));
      case num() when value.isFinite:
        out.write(numberToString(value));
      case bool():
        out.write(value);
      case JsFields():
        _writeJson(value.jsFields, out);
      case List():
        out.write('[');
        for (var i = 0; i < value.length; i++) {
          if (i > 0) out.write(',');
          _writeJson(value[i], out);
        }
        out.write(']');
      case Map():
        out.write('{');
        var first = true;
        final map = value is Map<String, Object?>
            ? ordered(value)
            : object([
                for (final MapEntry(:key, value: v) in value.entries)
                  MapEntry(string(key), v),
              ]);
        for (final MapEntry(:key, value: v) in map.entries) {
          if (!first) out.write(',');
          first = false;
          out
            ..write(jsonEncode(key))
            ..write(':');
          _writeJson(v, out);
        }
        out.write('}');
      default:
        out.write('null');
    }
  }

  static const _maxSafe = 9007199254740992;

  static final _arrayIndex = RegExp(r'^(?:0|[1-9][0-9]{0,9})$');

  /// Whether [key] is an array index ("0" to "4294967294"), which JavaScript
  /// lists before every other key of an object.
  static bool isArrayIndex(String key) =>
      _arrayIndex.hasMatch(key) && int.parse(key) < 4294967295;

  /// [map] in JavaScript's key order: array-index keys ascending, then the
  /// rest in insertion order. [map] itself when it is already in that order.
  static Map<String, Object?> ordered(Map<String, Object?> map) {
    final indices = [
      for (final k in map.keys)
        if (isArrayIndex(k)) int.parse(k),
    ];
    if (indices.isEmpty) return map;
    indices.sort();
    final keys = [
      for (final i in indices) '$i',
      for (final k in map.keys)
        if (!isArrayIndex(k)) k,
    ];
    var i = 0;
    if (map.keys.every((k) => k == keys[i++])) return map;
    return {for (final k in keys) k: map[k]};
  }

  /// A JavaScript object of [entries]: a repeated key keeps its first place
  /// and its last value, and keys are in [ordered] order.
  static Map<String, Object?> object(
    Iterable<MapEntry<String, Object?>> entries,
  ) => ordered(Map.fromEntries(entries));

  /// A copy of [value] with every map in JavaScript key order. With [json],
  /// integral doubles up to 2^53 also become ints (-0 becomes 0), so a
  /// plain `jsonEncode` prints them as `JSON.stringify` does.
  static Object? normalize(Object? value, {bool json = false}) =>
      switch (value) {
        double()
            when json &&
                value.isFinite &&
                value == value.truncateToDouble() &&
                value.abs() <= _maxSafe =>
          value == 0 ? 0 : value.toInt(),
        List() => [for (final v in value) normalize(v, json: json)],
        Map() => object([
          for (final MapEntry(:key, value: v) in value.entries)
            MapEntry(string(key), normalize(v, json: json)),
        ]),
        _ => value,
      };

  /// JavaScript `obj[key]` on a runtime value: a map's own entry, a list's
  /// or string's `length` and canonical indices, and the fields lang-core's
  /// element, plan, step, binding and AST objects have. Members a JavaScript
  /// value inherits (`toString`, `__proto__`) are not data and read as null.
  static Object? property(Object? obj, String key) {
    switch (obj) {
      case Map():
        return obj[key];
      case List():
        if (key == 'length') return obj.length;
        return isArrayIndex(key) && int.parse(key) < obj.length
            ? obj[int.parse(key)]
            : null;
      case String():
        if (key == 'length') return obj.length;
        return isArrayIndex(key) && int.parse(key) < obj.length
            ? obj[int.parse(key)]
            : null;
      case JsFields():
        return obj.jsFields[key];
    }
    return null;
  }
}

/// A Dart object that is a plain object in lang-core: an element, an action
/// plan or step, a binding or an AST node. [Js.property] reads its fields
/// and [Js.stringify] writes them.
abstract interface class JsFields {
  /// Its own properties, in lang-core's order; absent ones are left out.
  Map<String, Object?> get jsFields;
}

/// JavaScript `String(value)`: how a program's value prints (`4` is "4").
String jsString(Object? value) => Js.string(value);

/// JavaScript `Number(value)`: NaN when [value] does not read as a number.
double jsNumber(Object? value) => Js.number(value);
