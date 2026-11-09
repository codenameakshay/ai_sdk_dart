import '../../lang/js.dart';
import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'js_number.dart';
import 'locale_format.dart';
import 'number_format.dart';
import 'shared.dart';
import 'unicode.dart';

final List<FunctionSpec> textFunctions = [
  FunctionSpec(
    'Format',
    description:
        'Number as text: "number" 12,345.6, "currency" \$12,345.68 (currency is a code like "EUR"), "percent" 45 -> 45%, "compact" 1.2M (\$1.2M with a currency)',
    params: {
      'value': S.number(),
      'kind': S.oneOf(['number', 'currency', 'percent', 'compact']).optional(),
      'decimals': S.number().optional(),
      'currency': S.string().optional(),
    },
    returns: S.string(),
    fn: (a) {
      final f = _formatArgs(a);
      final d = f.d;
      final currency = f.currency;
      return switch (f.kind) {
        'currency' => formatCurrency(
          f.value,
          _currencyCode(currency),
          minFraction: d ?? 2,
          maxFraction: d ?? 2,
        ),
        'percent' =>
          '${formatDecimal(f.value, minFraction: 0, maxFraction: d ?? 1)}%',
        'compact' => formatCompact(
          f.value,
          maxFraction: d ?? 1,
          currency: currency == null || currency.isEmpty
              ? null
              : _currencyCode(currency),
        ),
        _ => formatDecimal(f.value, minFraction: 0, maxFraction: d ?? 2),
      };
    },
    localized: (a, locale) {
      final f = _formatArgs(a);
      final code = f.currency == null || f.currency!.isEmpty
          ? null
          : _currencyCode(f.currency);
      return localeFormat(
        f.value,
        locale,
        kind: f.kind,
        decimals: f.d,
        currency: f.kind == 'currency' ? (code ?? 'USD') : code,
      );
    },
  ),
  FunctionSpec(
    'Join',
    description:
        'Joins the items (or their field) into text with sep (default ", "), skipping nulls',
    params: {
      'list': list(),
      'sep': S.string().optional(),
      'field': S.string().optional(),
    },
    returns: S.string(),
    fn: (a) {
      final sep = (a['sep'] as String?) ?? ', ';
      final field = (a['field'] as String?) ?? '';
      return (a['list'] as List)
          .map((item) => read(item, field))
          .where((v) => v != null)
          .map((v) => Js.isObject(v) ? Js.stringify(v) : Js.string(v))
          .join(sep);
    },
  ),
  FunctionSpec(
    'Plural',
    description:
        'Count and word: @Plural(1, "guest") is "1 guest", 3 gives "3 guests"; plural defaults to word + "s"',
    params: {
      'n': S.number(),
      'word': S.string(),
      'plural': S.string().optional(),
    },
    returns: S.string(),
    fn: (a) =>
        '${formatDecimal(a['n'] as num, minFraction: 0, maxFraction: 2)} ${_noun(a)}',
    localized: (a, locale) =>
        '${localeNumber(a['n'] as num, locale, maxFraction: 2)} ${_noun(a)}',
  ),
  FunctionSpec(
    'Pad',
    description:
        'Pads the start of value to length with char (default "0"), e.g. 7 -> "07"',
    params: {
      'value': S.union([S.string(), S.number()]),
      'length': S.number(),
      'char': S.string().optional(),
    },
    returns: S.string(),
    fn: (a) {
      final text = Js.string(a['value']);
      final width = (a['length'] as num).truncate().clamp(0, 1000).toInt();
      final pad = (a['char'] as String?) ?? '';
      final fill = pad.isEmpty ? '0' : pad;
      final need = width - text.length;
      if (need <= 0) return text;
      final filler = (fill * ((need ~/ fill.length) + 1)).substring(0, need);
      return filler + text;
    },
  ),
  FunctionSpec(
    'Upper',
    description: 'Text in upper case',
    params: {'text': S.string()},
    returns: S.string(),
    fn: (a) => jsUpperCase(a['text'] as String),
  ),
  FunctionSpec(
    'Lower',
    description: 'Text in lower case',
    params: {'text': S.string()},
    returns: S.string(),
    fn: (a) => jsLowerCase(a['text'] as String),
  ),
  FunctionSpec(
    'Trim',
    description: 'Text without spaces at the start and end',
    params: {'text': S.string()},
    returns: S.string(),
    fn: (a) => jsTrim(a['text'] as String),
  ),
  FunctionSpec(
    'Capitalize',
    description:
        'Each word with a capital first letter, e.g. "new york" is "New York"',
    params: {'text': S.string()},
    returns: S.string(),
    fn: (a) => (a['text'] as String).replaceAllMapped(
      RegExp(r'(^|[\s\-(/"])(\p{L})', unicode: true),
      (m) => '${m[1]}${jsUpperCase(m[2]!)}',
    ),
  ),
  FunctionSpec(
    'Split',
    description:
        'List of the parts of text between sep (default ","), each trimmed, empty parts dropped, e.g. @Split("a, b,,c") is ["a", "b", "c"]',
    params: {'text': S.string(), 'sep': S.string().optional()},
    returns: S.list(S.string()),
    fn: (a) {
      final sep = (a['sep'] as String?) ?? ',';
      final parts = (a['text'] as String)
          .split(sep)
          .map(jsTrim)
          .where((p) => p.isNotEmpty)
          .toList();
      if (parts.length > maxItems) {
        throw StateError('more than $maxItems items');
      }
      return parts;
    },
  ),
  FunctionSpec(
    'Replace',
    description: 'Text with every find replaced by replacement',
    params: {'text': S.string(), 'find': S.string(), 'replacement': S.string()},
    returns: S.string(),
    fn: (a) {
      final text = a['text'] as String;
      final find = a['find'] as String;
      if (find.isEmpty) return text;
      return text.replaceAll(find, a['replacement'] as String);
    },
  ),
  FunctionSpec(
    'Duration',
    description:
        'Seconds as text: "short" 1h 20m, 4m 05s, 45s (default); "clock" 1:20:00, 4:05',
    params: {
      'seconds': S.number(),
      'style': S.oneOf(['short', 'clock']).optional(),
    },
    returns: S.string(),
    fn: (a) {
      final seconds = a['seconds'] as num;
      if (!seconds.isFinite) throw StateError('seconds is not a finite number');
      final sign = seconds < 0 ? '-' : '';
      // Doubles, as JavaScript counts: an int would overflow past 2^63 seconds.
      final total = jsRound(seconds.abs());
      final h = (total / 3600).floorToDouble();
      final m = (total % 3600 / 60).floorToDouble();
      final s = total % 60;
      String two(double n) => Js.numberToString(n).padLeft(2, '0');
      if (((a['style'] as String?) ?? 'short') == 'clock') {
        return sign +
            (h > 0
                ? '${Js.numberToString(h)}:${two(m)}:${two(s)}'
                : '${Js.numberToString(m)}:${two(s)}');
      }
      final hours = Js.numberToString(h);
      final minutes = Js.numberToString(m);
      if (h > 0) return '$sign${hours}h${m > 0 ? ' ${minutes}m' : ''}';
      if (m > 0) return '$sign${minutes}m${s > 0 ? ' ${two(s)}s' : ''}';
      return '$sign${Js.numberToString(s)}s';
    },
  ),
  FunctionSpec(
    'Default',
    description:
        'value, or fallback when value is null, "" or not a number, e.g. an empty number input: @Default(\$weight, 0)',
    params: {'value': S.any().optional(), 'fallback': S.any()},
    returns: S.any(),
    fn: (a) {
      final value = a['value'];
      final missing =
          value == null || value == '' || (value is num && value.isNaN);
      return missing ? a['fallback'] : value;
    },
  ),
];

({num value, String kind, int? d, String? currency}) _formatArgs(
  Map<String, Object?> a,
) {
  final value = a['value'] as num;
  if (!value.isFinite) throw StateError('value is not a finite number');
  final decimals = a['decimals'] as num?;
  return (
    value: value,
    kind: (a['kind'] as String?) ?? 'number',
    d: decimals?.truncate().clamp(0, 10).toInt(),
    currency: a['currency'] as String?,
  );
}

String _noun(Map<String, Object?> a) {
  final n = a['n'] as num;
  final word = a['word'] as String;
  final plural = a['plural'] as String?;
  return n.abs() == 1 ? word : (plural ?? '${word}s');
}

/// The code when it is three letters, else USD, as the reference's `currencyCode`.
String _currencyCode(String? code) {
  final upper = jsUpperCase(code ?? 'USD');
  return RegExp(r'^[A-Z]{3}$').hasMatch(upper) ? upper : 'USD';
}
