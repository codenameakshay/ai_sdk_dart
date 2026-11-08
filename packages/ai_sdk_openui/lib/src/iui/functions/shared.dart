import 'dart:math' as math;

import '../../lang/js.dart';
import '../../spec/schema.dart';

/// Schema shorthands, as the reference's `shared.ts`.
Schema list() => S.list(S.any());
Schema numbers() => S.list(S.number());
Schema date() => S.union([S.string(), S.number()]);
Schema agg() => S.oneOf(['sum', 'avg', 'count', 'min', 'max']);

const maxItems = 10000;

/// The impure inputs `@Random`, `@Pick`, `@Shuffle`, `@Now` and `@Today`
/// read. Tests replace them.
// ponytail: process-wide seams; pass them per session if two need to differ.
abstract final class Impure {
  static final math.Random _random = math.Random();

  /// `Math.random()`: a double in [0, 1).
  static double Function() random = _random.nextDouble;

  /// `Date.now()`.
  static DateTime Function() now = DateTime.now;

  /// The local time zone JavaScript formats instants in. Tests use UTC,
  /// as the reference's vitest config does.
  static DateTime Function(DateTime instant) toLocal = _toLocal;

  static DateTime _toLocal(DateTime instant) => instant.toLocal();

  static void reset() {
    random = _random.nextDouble;
    now = DateTime.now;
    toLocal = _toLocal;
  }
}

/// Reads [field] from a row with dot paths; "" is the item itself.
Object? read(Object? item, String field) {
  if (field.isEmpty) return item;
  Object? cur = item;
  for (final key in field.split('.')) {
    if (cur is Map) {
      cur = cur[key];
    } else if (cur is List) {
      final i = int.tryParse(key);
      cur = i != null && i >= 0 && i < cur.length ? cur[i] : null;
    } else {
      return null;
    }
  }
  return cur;
}

/// Equality by value: lists and objects compare item by item, and a number
/// matches its string form.
bool same(Object? a, Object? b) {
  if (Js.strictEquals(a, b)) return true;
  if ((a is num && b is String) || (a is String && b is num)) {
    return Js.string(a) == Js.string(b);
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!same(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && same(a[k], b[k]));
  }
  return false;
}

/// A finite number, or a throw the runtime turns into null.
num finite(num value) {
  if (!value.isFinite) throw StateError('result is not a finite number');
  return value;
}

num? toNum(Object? value) {
  if (value is num) return value.isFinite ? value : null;
  if (value is String && value.trim().isNotEmpty) {
    final n = Js.parseNumber(value);
    return n.isFinite ? n : null;
  }
  return null;
}

/// Aggregates the numbers read from rows; count counts rows.
num aggregate(List<Object?> rows, String? field, String how) {
  if (how == 'count') return rows.length;
  final values = [for (final r in rows) ?toNum(read(r, field ?? ''))];
  if (values.isEmpty) return 0;
  return switch (how) {
    'sum' => values.fold<num>(0, (a, b) => a + b),
    'avg' => values.fold<num>(0, (a, b) => a + b) / values.length,
    'min' => values.reduce(math.min),
    _ => values.reduce(math.max),
  };
}

/// Groups items by a key in first-seen order. Number keys stay numbers;
/// missing or empty keys group as "Unknown".
Map<Object, List<Object?>> groups(List<Object?> rows, String key) {
  final out = <Object, List<Object?>>{};
  for (final row in rows) {
    final raw = read(row, key);
    final Object k = raw is num
        ? raw
        : (raw == null || raw == '' ? 'Unknown' : Js.string(raw));
    (out[k] ??= []).add(row);
  }
  return out;
}
