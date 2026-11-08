import 'dart:math' as math;

import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'shared.dart';

final List<FunctionSpec> numberFunctions = [
  FunctionSpec(
    'Pow',
    description: 'base raised to exponent',
    params: {'base': S.number(), 'exponent': S.number()},
    returns: S.number(),
    fn: (a) => finite(math.pow(a['base'] as num, a['exponent'] as num)),
  ),
  FunctionSpec(
    'Sqrt',
    description: 'Square root; null for a negative number',
    params: {'number': S.number()},
    returns: S.number(),
    fn: (a) => finite(math.sqrt(a['number'] as num)),
  ),
  FunctionSpec(
    'Random',
    description:
        'Random number from min to max (integer true: a whole number, max included); draws anew each time, so call it inside @Set',
    params: {
      'min': S.number(),
      'max': S.number(),
      'integer': S.boolean().optional(),
    },
    returns: S.number(),
    fn: (a) {
      final min = a['min'] as num;
      final max = a['max'] as num;
      final lo = math.min(min, max);
      final hi = math.max(min, max);
      if (!((a['integer'] as bool?) ?? false)) {
        return lo + Impure.random() * (hi - lo);
      }
      final first = lo.ceil();
      final last = hi.floor();
      if (first > last) throw StateError('no whole number between min and max');
      return first + (Impure.random() * (last - first + 1)).floor();
    },
  ),
  FunctionSpec(
    'Clamp',
    description: 'number kept between min and max',
    params: {'number': S.number(), 'min': S.number(), 'max': S.number()},
    returns: S.number(),
    fn: (a) {
      final min = a['min'] as num;
      final max = a['max'] as num;
      return math.min(
        math.max(a['number'] as num, math.min(min, max)),
        math.max(min, max),
      );
    },
  ),
  FunctionSpec(
    'Percent',
    description:
        'part / total * 100, e.g. @Percent(3, 4) is 75; 0 when total is 0',
    params: {'part': S.number(), 'total': S.number()},
    returns: S.number(),
    fn: (a) {
      final total = a['total'] as num;
      return total == 0 ? 0 : finite((a['part'] as num) / total * 100);
    },
  ),
  FunctionSpec(
    'Lerp',
    description: 'The value a fraction t of the way from a to b',
    params: {'a': S.number(), 'b': S.number(), 't': S.number()},
    returns: S.number(),
    fn: (a) {
      final from = a['a'] as num;
      return finite(from + ((a['b'] as num) - from) * (a['t'] as num));
    },
  ),
  FunctionSpec(
    'Allocate',
    description:
        'Splits total in proportion to weights, rounded to decimals (default 2), so the parts add up to exactly total, e.g. @Allocate(100, [1, 1, 1]) is [33.34, 33.33, 33.33]',
    params: {
      'total': S.number(),
      'weights': numbers(),
      'decimals': S.number().optional(),
    },
    returns: S.list(S.number()),
    fn: (a) {
      final total = a['total'] as num;
      final weights = (a['weights'] as List).cast<num>();
      if (weights.isEmpty || weights.any((w) => !w.isFinite || w < 0)) {
        throw StateError('weights must be zero or more');
      }
      final sum = weights.fold<num>(0, (x, y) => x + y);
      if (sum == 0) return List<num>.filled(weights.length, 0);
      final decimals = (a['decimals'] as num?) ?? 2;
      // JS Math.round sends halves up; the scaled values are never negative here, so floor(x + 0.5) is exact.
      final scale = math.pow(
        10,
        math.min(6, math.max(0, (decimals + 0.5).floor())),
      );
      final units = (total.abs() * scale + 0.5).floor();
      final exact = [for (final w in weights) units * w / sum];
      final parts = [for (final x in exact) x.floor()];
      var left = units - parts.fold<int>(0, (x, y) => x + y);
      final order =
          [
            for (var i = 0; i < exact.length; i++)
              (i, exact[i] - exact[i].floor()),
          ]..sort((p, q) {
            final c = q.$2.compareTo(p.$2);
            return c != 0 ? c : p.$1 - q.$1;
          });
      for (final (i, _) in order) {
        if (left <= 0) break;
        parts[i] += 1;
        left -= 1;
      }
      return [for (final p in parts) (total < 0 ? -p : p) / scale];
    },
  ),
  FunctionSpec(
    'Payment',
    description:
        'Payment per period that repays principal over periods at rate percent per period, e.g. a 30-year loan at 6% a year: @Payment(300000, 6 / 12, 360)',
    params: {
      'principal': S.number(),
      'rate': S.number(),
      'periods': S.number(),
    },
    returns: S.number(),
    fn: (a) {
      final principal = a['principal'] as num;
      final periods = a['periods'] as num;
      if (!(periods > 0)) throw StateError('periods must be positive');
      final r = (a['rate'] as num) / 100;
      return finite(
        r == 0
            ? principal / periods
            : principal * r / (1 - math.pow(1 + r, -periods)),
      );
    },
  ),
  FunctionSpec(
    'Convert',
    description:
        'value from one unit to another: mm cm m km in ft yd mi; mg g kg oz lb st; ml l tsp tbsp floz cup pt qt gal (US); m/s km/h mph kn; m2 km2 ft2 ha acre; c f k',
    params: {'value': S.number(), 'from': S.string(), 'to': S.string()},
    returns: S.number(),
    fn: (a) {
      final value = a['value'] as num;
      final from = a['from'] as String;
      final to = a['to'] as String;
      final x = from.trim().toLowerCase();
      final y = to.trim().toLowerCase();
      if (_temps.contains(x) && _temps.contains(y)) {
        return finite(_fromCelsius(_toCelsius(value, x), y));
      }
      final ua = _units[x];
      final ub = _units[y];
      if (ua == null || ub == null || ua.$1 != ub.$1) {
        throw StateError('cannot convert $from to $to');
      }
      return finite(value * ua.$2 / ub.$2);
    },
  ),
];

// Units per kind, as the factor to the kind's base unit (m, kg, l, m/s).
const _units = <String, (String, double)>{
  'mm': ('length', 0.001),
  'cm': ('length', 0.01),
  'm': ('length', 1),
  'km': ('length', 1000),
  'in': ('length', 0.0254),
  'ft': ('length', 0.3048),
  'yd': ('length', 0.9144),
  'mi': ('length', 1609.344),
  'mg': ('mass', 1e-6),
  'g': ('mass', 0.001),
  'kg': ('mass', 1),
  'oz': ('mass', 0.028349523125),
  'lb': ('mass', 0.45359237),
  'st': ('mass', 6.35029318),
  'ml': ('volume', 0.001),
  'l': ('volume', 1),
  'tsp': ('volume', 0.00492892159375),
  'tbsp': ('volume', 0.0147867647812),
  'floz': ('volume', 0.0295735295625),
  'cup': ('volume', 0.2365882365),
  'pt': ('volume', 0.473176473),
  'qt': ('volume', 0.946352946),
  'gal': ('volume', 3.785411784),
  'm/s': ('speed', 1),
  'km/h': ('speed', 1 / 3.6),
  'mph': ('speed', 0.44704),
  'kn': ('speed', 0.514444),
  'm2': ('area', 1),
  'km2': ('area', 1e6),
  'ft2': ('area', 0.09290304),
  'ha': ('area', 10000),
  'acre': ('area', 4046.8564224),
};

const _temps = ['c', 'f', 'k'];

num _toCelsius(num v, String u) =>
    u == 'f' ? (v - 32) * 5 / 9 : (u == 'k' ? v - 273.15 : v);

num _fromCelsius(num v, String u) =>
    u == 'f' ? v * 9 / 5 + 32 : (u == 'k' ? v + 273.15 : v);
