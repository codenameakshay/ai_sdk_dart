import 'dart:math' as math;

import '../../lang/js.dart';
import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'dates.dart' show dayOf, isoDay, parseDate, utcDay;
import 'js_number.dart';
import 'shared.dart';

Schema _keyValue() => S.list(
  S.object({
    'key': S.union([S.string(), S.number()]),
    'value': S.number(),
  }),
);

// Untyped arrays (a pluck over rows that lack the field) can still hold nulls.
List<num> _finiteOnly(List<Object?> values) => [
  for (final v in values)
    if (v is num && v.isFinite) v,
];

String _defaultAgg(String? field, String? how) =>
    how ?? (field != null && field.isNotEmpty ? 'sum' : 'count');

/// Copy of each row with [field] replaced; an empty field maps a list of numbers.
List<Object?> _mapField(List<Object?> rows, String field, List<num> values) {
  if (field.isEmpty) return values;
  final out = <Object?>[];
  for (var i = 0; i < rows.length; i++) {
    out.add(
      Js.object([..._spread(rows[i]).entries, MapEntry(field, values[i])]),
    );
  }
  return out;
}

/// The own properties `{...row}` copies in JavaScript: a map's entries, a
/// list's or string's indices, nothing for a number, boolean or null.
Map<String, Object?> _spread(Object? row) => switch (row) {
  Map() => row.cast<String, Object?>(),
  List() => {for (var i = 0; i < row.length; i++) '$i': row[i]},
  String() => {for (var i = 0; i < row.length; i++) '$i': row[i]},
  JsFields() => row.jsFields,
  _ => const {},
};

/// How many rows a `Top` slice takes: JavaScript's `slice(0, Math.trunc(n))`.
int _take(num n, int length) {
  if (n.isNaN || n < 1) return 0;
  return n >= length ? length : n.truncate();
}

/// Orders two field values: numbers by value, anything else (such as "YYYY-MM-DD") as text.
num _compare(Object? a, Object? b) {
  final x = toNum(a);
  final y = toNum(b);
  if (x != null && y != null) return x - y;
  final s = Js.string(a);
  final t = Js.string(b);
  return s == t ? 0 : (s.compareTo(t) < 0 ? -1 : 1);
}

int _periodStart(int day, String unit) {
  if (unit == 'day') return day;
  if (unit == 'week') return day - (utcDay(day).weekday - 1);
  final d = utcDay(day);
  return dayOf(d.year, d.month, 1);
}

int _nextPeriod(int start, String unit) {
  if (unit == 'day') return start + 1;
  if (unit == 'week') return start + 7;
  final d = utcDay(start);
  return dayOf(d.year, d.month + 1, 1);
}

String _label(int start, String unit) {
  final iso = isoDay(start);
  return unit == 'month' ? iso.substring(0, 7) : iso;
}

int? _tryParseDay(Object? value) {
  if (value == null) return null;
  try {
    return parseDate(value).day;
  } on StateError {
    return null;
  }
}

/// floor(log10(x)) for x > 0, exact at powers of ten where `math.log` drifts.
int _floorLog10(num x) {
  var e = (math.log(x) / math.ln10).floor();
  while (math.pow(10, e) > x) {
    e--;
  }
  while (math.pow(10, e + 1) <= x) {
    e++;
  }
  return e;
}

final List<FunctionSpec> dataFunctions = [
  FunctionSpec(
    'GroupBy',
    description:
        'One row per distinct key, in first-seen order; value is agg of field (default "sum"), or the row count without a field',
    params: {
      'rows': list(),
      'key': S.string(),
      'field': S.string().optional(),
      'agg': agg().optional(),
    },
    returns: _keyValue(),
    fn: (a) {
      final field = a['field'] as String?;
      final how = _defaultAgg(field, a['agg'] as String?);
      return [
        for (final e in groups(
          a['rows'] as List<Object?>,
          a['key'] as String,
        ).entries)
          {'key': e.key, 'value': aggregate(e.value, field, how)},
      ];
    },
  ),
  FunctionSpec(
    'Pivot',
    description:
        'One row per rowKey value with a column per colKey value holding agg of field, for stacked or grouped charts',
    params: {
      'rows': list(),
      'rowKey': S.string(),
      'colKey': S.string(),
      'field': S.string().optional(),
      'agg': agg().optional(),
    },
    returns: S.list(S.record(S.string(), S.union([S.string(), S.number()]))),
    fn: (a) {
      final rows = a['rows'] as List<Object?>;
      final colKey = a['colKey'] as String;
      final field = a['field'] as String?;
      final how = _defaultAgg(field, a['agg'] as String?);
      final cols = [for (final c in groups(rows, colKey).keys) Js.string(c)];
      final out = <Map<String, Object?>>[];
      for (final e in groups(rows, a['rowKey'] as String).entries) {
        final row = <String, Object?>{'key': e.key};
        // JavaScript assigns the columns: a __proto__ column sets no key.
        for (final col in cols) {
          if (col != '__proto__') row[col] = 0;
        }
        for (final c in groups(e.value, colKey).entries) {
          final col = Js.string(c.key);
          if (col != '__proto__') row[col] = aggregate(c.value, field, how);
        }
        out.add(Js.ordered(row));
      }
      return out;
    },
  ),
  FunctionSpec(
    'Top',
    description: 'The n rows with the largest field ("asc": the smallest)',
    params: {
      'rows': list(),
      'field': S.string(),
      'n': S.number(),
      'direction': S.oneOf(['desc', 'asc']).optional(),
    },
    returns: list(),
    fn: (a) {
      final field = a['field'] as String;
      final sign = a['direction'] == 'asc' ? 1 : -1;
      final ranked =
          [
            for (final (i, row) in (a['rows'] as List<Object?>).indexed)
              (row: row, i: i, v: toNum(read(row, field))),
          ]..sort((x, y) {
            if (x.v == null || y.v == null) {
              return x.v == y.v ? x.i - y.i : (x.v == null ? 1 : -1);
            }
            final d = (x.v! - y.v!) * sign;
            return d != 0 ? (d < 0 ? -1 : 1) : x.i - y.i;
          });
      final n = a['n'] as num;
      return [for (final r in ranked.take(_take(n, ranked.length))) r.row];
    },
  ),
  FunctionSpec(
    'Between',
    description:
        'Rows whose field is from min to max, both included; compares numbers, or text such as "YYYY-MM-DD" dates. Leave min or max null for an open end',
    params: {
      'rows': list(),
      'field': S.string(),
      'min': S.any().optional(),
      'max': S.any().optional(),
    },
    returns: list(),
    fn: (a) {
      final field = a['field'] as String;
      final min = a['min'];
      final max = a['max'];
      return (a['rows'] as List<Object?>).where((row) {
        final v = read(row, field);
        if (v == null) return false;
        return (min == null || _compare(v, min) >= 0) &&
            (max == null || _compare(v, max) <= 0);
      }).toList();
    },
  ),
  FunctionSpec(
    'Bucket',
    description:
        'Rows per day, week (from Monday) or month of dateField, in date order, empty periods 0 for sum and count; key is "YYYY-MM-DD", or "YYYY-MM" for months',
    params: {
      'rows': list(),
      'dateField': S.string(),
      'unit': S.oneOf(['day', 'week', 'month']),
      'field': S.string().optional(),
      'agg': agg().optional(),
    },
    returns: _keyValue(),
    fn: (a) {
      final unit = a['unit'] as String;
      final dateField = a['dateField'] as String;
      final field = a['field'] as String?;
      final how = _defaultAgg(field, a['agg'] as String?);
      final byPeriod = <int, List<Object?>>{};
      for (final row in a['rows'] as List<Object?>) {
        final day = _tryParseDay(read(row, dateField));
        if (day == null) continue;
        (byPeriod[_periodStart(day, unit)] ??= []).add(row);
      }
      if (byPeriod.isEmpty) return <Object?>[];
      final fill = how == 'sum' || how == 'count';
      final starts = byPeriod.keys.toList()..sort();
      final out = <Map<String, Object?>>[];
      for (var s = starts.first; s <= starts.last; s = _nextPeriod(s, unit)) {
        final members = byPeriod[s];
        if (members != null) {
          out.add({
            'key': _label(s, unit),
            'value': aggregate(members, field, how),
          });
        } else if (fill) {
          out.add({'key': _label(s, unit), 'value': 0});
        }
        if (out.length > maxItems) {
          throw StateError('more than $maxItems periods');
        }
      }
      return out;
    },
  ),
  FunctionSpec(
    'Cumulative',
    description:
        'Copy of the rows with field replaced by its running total (field "" for a list of numbers)',
    params: {'rows': list(), 'field': S.string()},
    returns: list(),
    fn: (a) {
      final rows = a['rows'] as List<Object?>;
      final field = a['field'] as String;
      var total = 0.0;
      final running = <num>[];
      for (final row in rows) {
        total += toNum(read(row, field)) ?? 0;
        running.add(total);
      }
      return _mapField(rows, field, running);
    },
  ),
  FunctionSpec(
    'MovingAvg',
    description:
        'Copy of the rows with field replaced by the average of its last window values (field "" for a list of numbers)',
    params: {'rows': list(), 'field': S.string(), 'window': S.number()},
    returns: list(),
    fn: (a) {
      final rows = a['rows'] as List<Object?>;
      final field = a['field'] as String;
      final window = a['window'] as num;
      if (window < 1) throw StateError('window must be at least 1');
      final w = window.isInfinite ? rows.length : window.truncate();
      final values = [for (final row in rows) toNum(read(row, field)) ?? 0];
      final averages = <num>[];
      for (var i = 0; i < values.length; i++) {
        final from = math.max(0, i - w + 1);
        var total = 0.0;
        for (var j = from; j <= i; j++) {
          total += values[j];
        }
        averages.add(total / (i - from + 1));
      }
      return _mapField(rows, field, averages);
    },
  ),
  FunctionSpec(
    'Change',
    description:
        'Percent change from previous to current, e.g. @Change(120, 100) is 20; null when previous is 0',
    params: {'current': S.number(), 'previous': S.number()},
    returns: S.number().nullable(),
    fn: (a) {
      final current = a['current'] as num;
      final previous = a['previous'] as num;
      // No previous value is normal while data loads, so it is null without an error.
      if (previous == 0) return null;
      return finite(((current - previous) / previous.abs()) * 100);
    },
  ),
  FunctionSpec(
    'Histogram',
    description:
        "Counts numbers into equal-width bins (value is the count); min and max fix the range, default the data's",
    params: {
      'values': numbers(),
      'bins': S.number(),
      'min': S.number().optional(),
      'max': S.number().optional(),
    },
    returns: S.list(
      S.object({
        'key': S.string(),
        'value': S.number(),
        'start': S.number(),
        'end': S.number(),
      }),
    ),
    fn: (a) {
      final values = _finiteOnly(a['values'] as List<Object?>);
      final n = (a['bins'] as num).truncate();
      if (n < 1 || n > 500) throw StateError('bins must be from 1 to 500');
      final lo =
          a['min'] as num? ?? (values.isEmpty ? 0 : values.reduce(math.min));
      var hi =
          a['max'] as num? ?? (values.isEmpty ? 1 : values.reduce(math.max));
      if (hi <= lo) hi = lo + 1;
      final width = (hi - lo) / n;
      final decimals = math.max(0, 1 - _floorLog10(width));
      final counts = List<int>.filled(n, 0);
      for (final v in values) {
        if (v < lo || v > hi) continue;
        counts[math.min(n - 1, ((v - lo) / width).floor())]++;
      }
      final out = <Map<String, Object?>>[];
      for (var i = 0; i < n; i++) {
        final start = lo + i * width;
        out.add({
          'key': Js.string(Js.parseNumber(toFixed(start.toDouble(), decimals))),
          'value': counts[i],
          'start': start,
          'end': start + width,
        });
      }
      return out;
    },
  ),
  FunctionSpec(
    'Stats',
    description: 'Summary of numbers, all zeros for an empty list',
    params: {'values': numbers()},
    returns: S.object({
      'count': S.number(),
      'min': S.number(),
      'max': S.number(),
      'mean': S.number(),
      'median': S.number(),
      'stdev': S.number(),
    }),
    fn: (a) {
      final values = _finiteOnly(a['values'] as List<Object?>);
      final count = values.length;
      if (count == 0) {
        return {
          'count': 0,
          'min': 0,
          'max': 0,
          'mean': 0,
          'median': 0,
          'stdev': 0,
        };
      }
      final sorted = [...values]..sort();
      final mean = values.fold<double>(0, (x, v) => x + v) / count;
      final mid = count ~/ 2;
      final median = count.isOdd
          ? sorted[mid]
          : (sorted[mid - 1] + sorted[mid]) / 2;
      final stdev = math.sqrt(
        values.fold<double>(0, (x, v) => x + (v - mean) * (v - mean)) / count,
      );
      return {
        'count': count,
        'min': sorted.first,
        'max': sorted.last,
        'mean': mean,
        'median': median,
        'stdev': stdev,
      };
    },
  ),
];
