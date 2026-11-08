import 'package:intl/intl.dart';

import '../../lang/js.dart';
import '../../spec/library.dart';
import '../../spec/schema.dart';
import 'shared.dart';

const _locale = 'en_US';

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
      final value = a['value'] as num;
      if (!value.isFinite) throw StateError('value is not a finite number');
      final kind = (a['kind'] as String?) ?? 'number';
      final decimals = a['decimals'] as num?;
      final d = decimals?.truncate().clamp(0, 10).toInt();
      final currency = a['currency'] as String?;
      return switch (kind) {
        'currency' => _currency(value, d ?? 2, _currencyCode(currency)),
        'percent' => '${_decimal(0, d ?? 1).format(value)}%',
        'compact' when currency == null || currency.isEmpty => _compact(
          value,
          d ?? 1,
        ),
        'compact' => _compactCurrency(value, d ?? 1, _currencyCode(currency)),
        _ => _decimal(0, d ?? 2).format(value),
      };
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
          .map((v) => v is Map || v is List ? Js.stringify(v) : Js.string(v))
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
    fn: (a) {
      final n = a['n'] as num;
      final word = a['word'] as String;
      final plural = a['plural'] as String?;
      final noun = n.abs() == 1 ? word : (plural ?? '${word}s');
      return '${_decimal(0, 2).format(n)} $noun';
    },
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
    fn: (a) => (a['text'] as String).toUpperCase(),
  ),
  FunctionSpec(
    'Lower',
    description: 'Text in lower case',
    params: {'text': S.string()},
    returns: S.string(),
    fn: (a) => (a['text'] as String).toLowerCase(),
  ),
  FunctionSpec(
    'Trim',
    description: 'Text without spaces at the start and end',
    params: {'text': S.string()},
    returns: S.string(),
    fn: (a) => (a['text'] as String).trim(),
  ),
  FunctionSpec(
    'Capitalize',
    description:
        'Each word with a capital first letter, e.g. "new york" is "New York"',
    params: {'text': S.string()},
    returns: S.string(),
    fn: (a) => (a['text'] as String).replaceAllMapped(
      RegExp(r'(^|[\s\-(/"])(\p{L})', unicode: true),
      (m) => '${m[1]}${m[2]!.toUpperCase()}',
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
          .map((p) => p.trim())
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
      final total = (seconds.abs() + 0.5).floor();
      final h = total ~/ 3600;
      final m = (total % 3600) ~/ 60;
      final s = total % 60;
      String two(int n) => n.toString().padLeft(2, '0');
      if (((a['style'] as String?) ?? 'short') == 'clock') {
        return sign + (h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}');
      }
      if (h > 0) return '$sign${h}h${m > 0 ? ' ${m}m' : ''}';
      if (m > 0) return '$sign${m}m${s > 0 ? ' ${two(s)}s' : ''}';
      return '$sign${s}s';
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

/// The code when it is three letters, else USD, as the reference's `currencyCode`.
String _currencyCode(String? code) {
  final upper = (code ?? 'USD').toUpperCase();
  return RegExp(r'^[A-Z]{3}$').hasMatch(upper) ? upper : 'USD';
}

NumberFormat _decimal(int minDigits, int maxDigits) =>
    NumberFormat('#,##0', _locale)
      ..minimumFractionDigits = minDigits
      ..maximumFractionDigits = maxDigits;

String _currency(num value, int digits, String code) =>
    NumberFormat.simpleCurrency(
      locale: _locale,
      name: code,
      decimalDigits: digits,
    ).format(value);

String _compact(num value, int maxDigits) =>
    (NumberFormat.compact(locale: _locale)
          ..minimumFractionDigits = 0
          ..maximumFractionDigits = maxDigits)
        .format(value);

String _compactCurrency(num value, int maxDigits, String code) =>
    (NumberFormat.compactSimpleCurrency(locale: _locale, name: code)
          ..minimumFractionDigits = 0
          ..maximumFractionDigits = maxDigits)
        .format(value);
