import 'dart:async';
import 'dart:math' as math;

import '../../lang/js.dart';
import '../../spec/schema.dart';

/// Schema shorthands, as the reference's `shared.ts`.
Schema list() => S.list(S.any());
Schema numbers() => S.list(S.number());
Schema date() => S.union([S.string(), S.number()]);
Schema agg() => S.oneOf(['sum', 'avg', 'count', 'min', 'max']);

const maxItems = 10000;

/// A time zone as its offset from UTC at each instant. The host supplies it,
/// for example from its own time zone database; null means device local.
final class OpenUiTimeZone {
  const OpenUiTimeZone(this.offsetAt);

  /// A zone that is always [offset] from UTC, such as +05:30.
  OpenUiTimeZone.fixed(Duration offset) : offsetAt = ((_) => offset);

  static final OpenUiTimeZone utc = OpenUiTimeZone.fixed(Duration.zero);

  /// The offset from UTC at a UTC instant.
  final Duration Function(DateTime utc) offsetAt;

  /// The wall-clock time at [instant], as a UTC DateTime with those fields.
  DateTime toLocal(DateTime instant) {
    final utc = instant.toUtc();
    return utc.add(offsetAt(utc));
  }

  /// The epoch milliseconds of a wall-clock time given as epoch milliseconds
  /// read as UTC, as JavaScript picks them: a time a clock change repeats is
  /// its earlier instant, and one it skips reads with the earlier offset.
  // ponytail: assumes at most one offset change within a day of the time.
  int fromLocal(int wallMs) {
    int offset(int ms) => offsetAt(
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
    ).inMilliseconds;
    const day = 86400000;
    final before = wallMs - offset(wallMs - day);
    final after = wallMs - offset(wallMs + day);
    final valid = [
      for (final t in [before, after])
        if (t + offset(t) == wallMs) t,
    ];
    return valid.isEmpty ? before : valid.reduce(math.min);
  }
}

typedef _Scope = ({
  DateTime Function()? now,
  double Function()? random,
  OpenUiTimeZone? timeZone,
});

/// The impure inputs `@Random`, `@Pick`, `@Shuffle`, `@Now` and `@Today`
/// read. A session's clock, random source and time zone apply while [run]
/// runs its functions; otherwise these process-wide defaults apply, which
/// tests may replace.
abstract final class Impure {
  static final math.Random _random = math.Random();
  static final Object _key = Object();
  static _Scope? get _scope => Zone.current[_key] as _Scope?;

  static double Function() _randomDefault = _random.nextDouble;
  static DateTime Function() _nowDefault = DateTime.now;
  static DateTime Function(DateTime instant) _toLocalDefault = _toLocal;
  static int Function(int wallMs) _fromLocalDefault = _fromLocal;

  /// `Math.random()`: a double in [0, 1).
  static double Function() get random => _scope?.random ?? _randomDefault;
  static set random(double Function() f) => _randomDefault = f;

  /// `Date.now()`.
  static DateTime Function() get now => _scope?.now ?? _nowDefault;
  static set now(DateTime Function() f) => _nowDefault = f;

  /// The local time zone JavaScript formats instants in. Tests use UTC,
  /// as the reference's vitest config does.
  static DateTime Function(DateTime instant) get toLocal =>
      _scope?.timeZone?.toLocal ?? _toLocalDefault;
  static set toLocal(DateTime Function(DateTime instant) f) =>
      _toLocalDefault = f;

  /// The epoch milliseconds of a local wall-clock time, given as epoch
  /// milliseconds read as UTC: how JavaScript reads a date string without a
  /// time zone.
  static int Function(int wallMs) get fromLocal =>
      _scope?.timeZone?.fromLocal ?? _fromLocalDefault;
  static set fromLocal(int Function(int wallMs) f) => _fromLocalDefault = f;

  /// Runs [body] with these inputs in place of the defaults; null keeps one.
  static T run<T>(
    T Function() body, {
    DateTime Function()? now,
    double Function()? random,
    OpenUiTimeZone? timeZone,
  }) => runZoned(
    body,
    zoneValues: {_key: (now: now, random: random, timeZone: timeZone)},
  );

  static DateTime _toLocal(DateTime instant) => instant.toLocal();

  static int _fromLocal(int wallMs) {
    final w = DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true);
    return DateTime(
      w.year,
      w.month,
      w.day,
      w.hour,
      w.minute,
      w.second,
      w.millisecond,
    ).millisecondsSinceEpoch;
  }

  /// Reads and formats dates in UTC, as the reference's tests run with TZ=UTC.
  static void useUtc() {
    toLocal = (instant) => instant.toUtc();
    fromLocal = (wallMs) => wallMs;
  }

  static void reset() {
    random = _random.nextDouble;
    now = DateTime.now;
    toLocal = _toLocal;
    fromLocal = _fromLocal;
  }
}

/// Reads [field] from a row with dot paths; "" is the item itself. Only
/// objects are read into: a string has no fields here.
Object? read(Object? item, String field) {
  if (field.isEmpty) return item;
  Object? cur = item;
  for (final key in field.split('.')) {
    if (!Js.isObject(cur)) return null;
    cur = Js.property(cur, key);
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
  final x = a is JsFields ? a.jsFields : a;
  final y = b is JsFields ? b.jsFields : b;
  if (x is Map && y is Map) {
    return x.length == y.length &&
        x.keys.every((k) => y.containsKey(k) && same(x[k], y[k]));
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
    'sum' => values.fold<double>(0, (a, b) => a + b),
    'avg' => values.fold<double>(0, (a, b) => a + b) / values.length,
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
