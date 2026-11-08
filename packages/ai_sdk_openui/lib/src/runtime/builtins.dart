import '../lang/js.dart';
import '../spec/library.dart';
import '../spec/schema.dart';

/// lang-core `resolveField`: a dot path into an object.
Object? resolveField(Object? obj, String? path) {
  if (path == null || path.isEmpty || obj == null) return null;
  Object? cur = obj;
  for (final p in path.split('.')) {
    if (cur is! Map) return null;
    cur = cur[p];
  }
  return cur;
}

num _sum(List<Object?> xs) => xs.fold<num>(0, (a, b) => a + Js.toNumber(b));

bool _isNumeric(Object? v) =>
    v is num || (v is String && v.isNotEmpty && !Js.parseNumber(v).isNaN);

/// `[...list].sort(compare)`, stable as in JavaScript.
List<Object?> stableSort(
  List<Object?> list,
  int Function(Object?, Object?) compare,
) {
  final indexed = [for (final (i, v) in list.indexed) (i, v)];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1 - b.$1;
  });
  return [for (final (_, v) in indexed) v];
}

int _sign(num n) => n < 0 ? -1 : (n > 0 ? 1 : 0);

num _extreme(Object? xs, bool Function(num candidate, num best) better) {
  if (xs is! List || xs.isEmpty) return 0;
  return xs.skip(1).fold<num>(Js.toNumber(xs.first), (best, b) {
    final n = Js.toNumber(b);
    if (n.isNaN || best.isNaN) return double.nan;
    return better(n, best) ? n : best;
  });
}

/// JavaScript `Math.round`: halves round toward +Infinity.
num jsRound(num n) {
  if (n is int) return n;
  final d = n.toDouble();
  if (d.isNaN || d.isInfinite) return d;
  final r = d.roundToDouble();
  return r - d == -0.5 ? r + 1 : r;
}

num _whole(num n, double Function(double) f) {
  if (n is int) return n;
  final d = n.toDouble();
  return d.isNaN || d.isInfinite ? d : f(d);
}

num _pow10(num d) {
  var r = 1.0;
  final n = d.toInt();
  for (var i = 0; i < n.abs(); i++) {
    r = n >= 0 ? r * 10 : r / 10;
  }
  return r;
}

Object? _sort(Map<String, Object?> a) {
  final list = a['array'];
  if (list is! List) return list;
  final f = a['field'] == null ? '' : Js.string(a['field']);
  final desc = Js.string(a['direction'] ?? 'asc') == 'desc';
  return stableSort(list.cast(), (x, y) {
    final av = f.isNotEmpty ? resolveField(x, f) : x;
    final bv = f.isNotEmpty ? resolveField(y, f) : y;
    if (_isNumeric(av) && _isNumeric(bv)) {
      final diff = _sign(Js.toNumber(av) - Js.toNumber(bv));
      return desc ? -diff : diff;
    }
    // ponytail: code-unit order, not ICU localeCompare; matches for ASCII.
    final cmp = Js.string(av ?? '').compareTo(Js.string(bv ?? ''));
    return desc ? -cmp : cmp;
  });
}

bool _matches(Object? v, String op, Object? value) => switch (op) {
  '==' => Js.looseEquals(v, value),
  '!=' => !Js.looseEquals(v, value),
  '>' => Js.toNumber(v) > Js.toNumber(value),
  '<' => Js.toNumber(v) < Js.toNumber(value),
  '>=' => Js.toNumber(v) >= Js.toNumber(value),
  '<=' => Js.toNumber(v) <= Js.toNumber(value),
  'contains' => Js.string(v ?? '').contains(Js.string(value ?? '')),
  _ => false,
};

Object? _filter(Map<String, Object?> a) {
  final list = a['array'];
  if (list is! List) return const <Object?>[];
  final f = a['field'] == null ? '' : Js.string(a['field']);
  final op = Js.string(a['operator'] ?? '==');
  return [
    for (final item in list)
      if (_matches(f.isNotEmpty ? resolveField(item, f) : item, op, a['value']))
        item,
  ];
}

Object? _lazy(Map<String, Object?> args) => throw StateError('lazy built-in');

final _anyList = S.list(S.any());
final _numbers = {'numbers': S.list(S.number())};
final _number = {'number': S.number()};

/// The built-in functions, in prompt order. `@Each` is lazy: the evaluator
/// runs it, so its [FunctionSpec.fn] is never called.
final List<FunctionSpec> builtinFunctionSpecs = [
  FunctionSpec(
    'Count',
    description: 'Returns array length',
    params: {'array': _anyList},
    returns: S.number(),
    fn: (a) => a['array'] is List ? (a['array'] as List).length : 0,
  ),
  FunctionSpec(
    'First',
    description: 'Returns first element of array',
    params: {'array': _anyList},
    returns: S.any(),
    fn: (a) => a['array'] is List && (a['array'] as List).isNotEmpty
        ? (a['array'] as List).first
        : null,
  ),
  FunctionSpec(
    'Last',
    description: 'Returns last element of array',
    params: {'array': _anyList},
    returns: S.any(),
    fn: (a) => a['array'] is List && (a['array'] as List).isNotEmpty
        ? (a['array'] as List).last
        : null,
  ),
  FunctionSpec(
    'Sum',
    description: 'Sum of numeric array',
    params: _numbers,
    returns: S.number(),
    fn: (a) => a['numbers'] is List ? _sum((a['numbers'] as List).cast()) : 0,
  ),
  FunctionSpec(
    'Avg',
    description: 'Average of numeric array',
    params: _numbers,
    returns: S.number(),
    fn: (a) {
      final xs = a['numbers'];
      return xs is List && xs.isNotEmpty ? _sum(xs.cast()) / xs.length : 0;
    },
  ),
  FunctionSpec(
    'Min',
    description: 'Minimum value in array',
    params: _numbers,
    returns: S.number(),
    fn: (a) => _extreme(a['numbers'], (n, best) => n < best),
  ),
  FunctionSpec(
    'Max',
    description: 'Maximum value in array',
    params: _numbers,
    returns: S.number(),
    fn: (a) => _extreme(a['numbers'], (n, best) => n > best),
  ),
  FunctionSpec(
    'Sort',
    description: 'Sort array by field. Direction: "asc" (default) or "desc"',
    params: {
      'array': _anyList,
      'field': S.string(),
      'direction': S.oneOf(['asc', 'desc']).optional(),
    },
    returns: _anyList,
    fn: _sort,
  ),
  FunctionSpec(
    'Filter',
    description: 'Filter array by field value',
    params: {
      'array': _anyList,
      'field': S.string(),
      'operator': S.oneOf(['==', '!=', '>', '<', '>=', '<=', 'contains']),
      'value': S.any(),
    },
    returns: _anyList,
    fn: _filter,
  ),
  FunctionSpec(
    'Round',
    description: 'Round to N decimal places (default 0)',
    params: {'number': S.number(), 'decimals': S.number().optional()},
    returns: S.number(),
    fn: (a) {
      final factor = _pow10(
        a['decimals'] != null ? Js.toNumber(a['decimals']) : 0,
      );
      return jsRound(Js.toNumber(a['number']) * factor) / factor;
    },
  ),
  FunctionSpec(
    'Abs',
    description: 'Absolute value',
    params: _number,
    returns: S.number(),
    fn: (a) => Js.toNumber(a['number']).abs(),
  ),
  FunctionSpec(
    'Floor',
    description: 'Round down to nearest integer',
    params: _number,
    returns: S.number(),
    fn: (a) => _whole(Js.toNumber(a['number']), (d) => d.floorToDouble()),
  ),
  FunctionSpec(
    'Ceil',
    description: 'Round up to nearest integer',
    params: _number,
    returns: S.number(),
    fn: (a) => _whole(Js.toNumber(a['number']), (d) => d.ceilToDouble()),
  ),
  FunctionSpec(
    'Each',
    description:
        'Evaluate template for each element. varName is the loop variable — use it ONLY inside the template expression (inline). Do NOT create a separate statement for the template.',
    params: {'array': _anyList, 'varName': S.string(), 'template': S.any()},
    fn: _lazy,
  ),
];

/// Built-in action steps, in prompt order.
final List<ActionSpec> builtinStepSpecs = [
  ActionSpec(
    'Run',
    description:
        'Execute a Mutation or re-fetch a Query (ref must be a declared Query/Mutation)',
    params: {'ref': S.any().tag('Query | Mutation')},
  ),
  ActionSpec(
    'ToAssistant',
    description:
        'Send a message to the assistant (for conversational buttons like "Tell me more", "Explain this"). The optional context is any value (object, array, string, number) passed to the assistant as hidden data, e.g. @ToAssistant("Show details", {orderId: 42})',
    params: {'message': S.string(), 'context': S.any().optional()},
  ),
  ActionSpec(
    'OpenUrl',
    description: 'Navigate to a URL',
    params: {'url': S.string()},
  ),
  ActionSpec(
    'Set',
    description: r'Set a $variable to a specific value',
    params: {'variable': S.any().tag(r'$variable'), 'value': S.any()},
  ),
  ActionSpec(
    'Reset',
    description:
        r'Reset $variables to their declared defaults; pass several to reset each (e.g. @Reset($title, $priority) restores $title="" and $priority="medium")',
    params: {'variable': S.any().tag(r'$variable')},
  ),
];

/// Eager built-ins by name.
final Map<String, FunctionSpec> builtinFunctions = {
  for (final f in builtinFunctionSpecs)
    if (f.name != 'Each') f.name: f,
};

/// Calls that take their args as syntax, not values.
const lazyCalls = {'Each', 'Run', 'Set', 'Reset', 'Action'};

/// Every built-in call name: functions, steps and `Action`.
final Set<String> builtinNames = {
  ...builtinFunctionSpecs.map((f) => f.name),
  ...builtinStepSpecs.map((s) => s.name),
  'Action',
};
