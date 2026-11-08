import '../../lang/js.dart';
import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'shared.dart';

/// JavaScript's slice bound: negative counts from the end, clamped to the list.
int _bound(num i, int length) {
  final t = i.truncateToDouble();
  final at = t < 0 ? length + t : t;
  return at.clamp(0, length).toInt();
}

(int, int) _span(num start, num? end, int length) {
  final from = _bound(start, length);
  final to = end == null ? length : _bound(end, length);
  return to > from ? (from, to) : (from, from);
}

bool _isInteger(num x) => x.isFinite && x == x.truncateToDouble();

final List<FunctionSpec> listFunctions = [
  FunctionSpec(
    'Append',
    description: 'Copy of the list with item added at the end',
    params: {'list': list(), 'item': S.any()},
    returns: list(),
    fn: (a) => [...a['list'] as List<Object?>, a['item']],
  ),
  FunctionSpec(
    'Prepend',
    description: 'Copy of the list with item added at the start',
    params: {'list': list(), 'item': S.any()},
    returns: list(),
    fn: (a) => [a['item'], ...a['list'] as List<Object?>],
  ),
  FunctionSpec(
    'Concat',
    description: 'Joins two lists',
    params: {'list': list(), 'more': list()},
    returns: list(),
    fn: (a) {
      final list = a['list'] as List<Object?>;
      final more = a['more'] as List<Object?>;
      if (list.length + more.length > maxItems) {
        throw StateError('more than $maxItems items');
      }
      return [...list, ...more];
    },
  ),
  FunctionSpec(
    'Remove',
    description:
        'Copy without the items whose field equals value; field "" compares the items themselves',
    params: {'list': list(), 'field': S.string(), 'value': S.any()},
    returns: list(),
    fn: (a) {
      final field = a['field'] as String;
      final value = a['value'];
      return (a['list'] as List<Object?>)
          .where((item) => !same(read(item, field), value))
          .toList();
    },
  ),
  FunctionSpec(
    'RemoveAt',
    description:
        'Copy without the item at index (0-based; negative counts from the end)',
    params: {'list': list(), 'index': S.number()},
    returns: list(),
    fn: (a) {
      final list = a['list'] as List<Object?>;
      final t = (a['index'] as num).truncateToDouble();
      final i = t < 0 ? list.length + t : t;
      return [
        for (final (j, item) in list.indexed)
          if (j != i) item,
      ];
    },
  ),
  FunctionSpec(
    'Update',
    description:
        'Copy where items whose field equals value get setField set to setValue',
    params: {
      'list': list(),
      'field': S.string(),
      'value': S.any(),
      'setField': S.string(),
      'setValue': S.any(),
    },
    returns: list(),
    fn: (a) {
      final field = a['field'] as String;
      final value = a['value'];
      final setField = a['setField'] as String;
      final setValue = a['setValue'];
      return [
        for (final item in a['list'] as List<Object?>)
          item is Map && same(read(item, field), value)
              ? {...item, setField: setValue}
              : item,
      ];
    },
  ),
  FunctionSpec(
    'Toggle',
    description:
        'Adds item if missing, removes it if present (a set of strings or numbers)',
    params: {'list': list(), 'item': S.any()},
    returns: list(),
    fn: (a) {
      final list = a['list'] as List<Object?>;
      final item = a['item'];
      if (list.any((x) => same(x, item))) {
        return list.where((x) => !same(x, item)).toList();
      }
      return [...list, item];
    },
  ),
  FunctionSpec(
    'Includes',
    description: 'True if the list has item, or the text contains it',
    params: {
      'list': S.union([list(), S.string()]),
      'item': S.any(),
    },
    returns: S.boolean(),
    fn: (a) {
      final list = a['list'];
      final item = a['item'];
      if (list is String) {
        return item != null && list.contains(Js.string(item));
      }
      return (list as List<Object?>).any((x) => same(x, item));
    },
  ),
  FunctionSpec(
    'Find',
    description: 'First item whose field equals value, or null',
    params: {'list': list(), 'field': S.string(), 'value': S.any()},
    returns: S.any(),
    fn: (a) {
      final field = a['field'] as String;
      final value = a['value'];
      for (final item in a['list'] as List<Object?>) {
        if (same(read(item, field), value)) return item;
      }
      return null;
    },
  ),
  FunctionSpec(
    'IndexOf',
    description: 'Index of item in the list, or -1',
    params: {'list': list(), 'item': S.any()},
    returns: S.number(),
    fn: (a) {
      final item = a['item'];
      return (a['list'] as List<Object?>).indexWhere((x) => same(x, item));
    },
  ),
  FunctionSpec(
    'Take',
    description: 'The first n items; a negative n takes the last n',
    params: {'list': list(), 'n': S.number()},
    returns: list(),
    fn: (a) {
      final list = a['list'] as List<Object?>;
      final n = (a['n'] as num).truncateToDouble();
      if (n >= 0) return list.sublist(0, _bound(n, list.length));
      return list.sublist(_bound(n, list.length));
    },
  ),
  FunctionSpec(
    'Slice',
    description:
        'Items, or characters of text, from start up to end (not included); negative counts from the end',
    params: {
      'list': S.union([list(), S.string()]),
      'start': S.number(),
      'end': S.number().optional(),
    },
    returns: S.union([list(), S.string()]),
    fn: (a) {
      final source = a['list'];
      final start = a['start'] as num;
      final end = a['end'] as num?;
      if (source is String) {
        final (from, to) = _span(start, end, source.length);
        return source.substring(from, to);
      }
      final items = source as List<Object?>;
      final (from, to) = _span(start, end, items.length);
      return items.sublist(from, to);
    },
  ),
  FunctionSpec(
    'Unique',
    description: 'Distinct items in first-seen order',
    params: {'list': list()},
    returns: list(),
    fn: (a) {
      final seen = <String>{};
      return (a['list'] as List<Object?>).where((item) {
        final key = item is Map || item is List
            ? 'o:${Js.stringify(item)}'
            : 'p:${Js.string(item)}';
        return seen.add(key);
      }).toList();
    },
  ),
  FunctionSpec(
    'Reverse',
    description: 'Copy in reverse order',
    params: {'list': list()},
    returns: list(),
    fn: (a) => (a['list'] as List<Object?>).reversed.toList(),
  ),
  FunctionSpec(
    'Range',
    description:
        'Numbers from start up to end (not included) by step (default 1), e.g. @Range(0, 3) is [0, 1, 2]',
    params: {
      'start': S.number(),
      'end': S.number(),
      'step': S.number().optional(),
    },
    returns: S.list(S.number()),
    fn: (a) {
      final start = a['start'] as num;
      final end = a['end'] as num;
      final step = (a['step'] as num?) ?? 1;
      if (step == 0 || !step.isFinite) {
        throw StateError('step must be a non-zero number');
      }
      final raw = ((end - start) / step).ceilToDouble();
      if (raw > maxItems) throw StateError('more than $maxItems items');
      final count = raw.isNaN || raw < 0 ? 0 : raw.toInt();
      final whole = _isInteger(start) && _isInteger(step);
      return [
        for (var i = 0; i < count; i++)
          if (whole)
            start + i * step
          else
            double.parse((start + i * step).toDouble().toStringAsPrecision(12)),
      ];
    },
  ),
  FunctionSpec(
    'Pick',
    description:
        'A random item, or null for an empty list; draws anew each time, so call it inside @Set',
    params: {'list': list()},
    returns: S.any(),
    fn: (a) {
      final list = a['list'] as List<Object?>;
      if (list.isEmpty) return null;
      return list[(Impure.random() * list.length).floor()];
    },
  ),
  FunctionSpec(
    'Shuffle',
    description: 'Copy in random order; call it inside @Set',
    params: {'list': list()},
    returns: list(),
    fn: (a) {
      final out = [...a['list'] as List<Object?>];
      for (var i = out.length - 1; i > 0; i--) {
        final j = (Impure.random() * (i + 1)).floor();
        final swap = out[i];
        out[i] = out[j];
        out[j] = swap;
      }
      return out;
    },
  ),
  FunctionSpec(
    'Flatten',
    description:
        'One list from a list of lists, e.g. [[1, 2], [3]] is [1, 2, 3]',
    params: {'list': list()},
    returns: list(),
    fn: (a) {
      final out = <Object?>[];
      for (final item in a['list'] as List<Object?>) {
        if (item is List) {
          out.addAll(item);
        } else {
          out.add(item);
        }
      }
      if (out.length > maxItems) throw StateError('more than $maxItems items');
      return out;
    },
  ),
  FunctionSpec(
    'Chunk',
    description:
        'The list cut into lists of size items, e.g. for weeks of 7 days or pages',
    params: {'list': list(), 'size': S.number()},
    returns: S.list(list()),
    fn: (a) {
      final list = a['list'] as List<Object?>;
      final n = (a['size'] as num).truncateToDouble();
      if (n < 1) throw StateError('size must be 1 or more');
      final size = n > list.length ? list.length : n.toInt();
      return [
        for (var i = 0; i < list.length; i += size)
          list.sublist(i, i + size > list.length ? list.length : i + size),
      ];
    },
  ),
];
