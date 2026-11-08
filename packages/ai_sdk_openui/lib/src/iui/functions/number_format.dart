import '../../lang/js.dart';
import 'currency_prefixes.dart';

/// en-US `Intl.NumberFormat`, as `toLocaleString("en-US", options)` formats
/// for `@Format` and `@Plural`.
String formatDecimal(
  num value, {
  required int minFraction,
  required int maxFraction,
}) {
  final (digits, point) = _shortest(value);
  final (whole, fraction) = _round(digits, point, minFraction, maxFraction);
  return _sign(value) +
      _group(whole, 1) +
      (fraction.isEmpty ? '' : '.$fraction');
}

/// `style: "currency"`: the en-US symbol (`$`, `CA$`, `€`) or the code and a
/// no-break space for currencies without one.
String formatCurrency(
  num value,
  String code, {
  required int minFraction,
  required int maxFraction,
}) {
  final (digits, point) = _shortest(value);
  final (whole, fraction) = _round(digits, point, minFraction, maxFraction);
  return _sign(value) +
      currencyPrefix(code) +
      _group(whole, 1) +
      (fraction.isEmpty ? '' : '.$fraction');
}

/// [minor] units of [code] at [scale] decimals as en-US Intl writes the
/// currency, from digits, never a double.
String formatMinorUnits(int minor, int scale, String code) {
  final digits = minor.abs().toString().padLeft(scale + 1, '0');
  final whole = digits.substring(0, digits.length - scale);
  final fraction = digits.substring(digits.length - scale);
  return '${minor < 0 ? '-' : ''}${currencyPrefix(code)}${_group(whole, 1)}'
      '${fraction.isEmpty ? '' : '.$fraction'}';
}

/// `notation: "compact"` with `maximumFractionDigits` [maxFraction]
/// (1.2K, 3.4M, 5B, 1000T), with a currency prefix when [currency] is set.
String formatCompact(num value, {required int maxFraction, String? currency}) {
  final (digits, point) = _shortest(value);
  // ICU picks the unit from the unrounded magnitude, then once more when
  // rounding carried into the next power of ten (999.95 is 1K).
  final magnitude = point - 1;
  var shift = digits.isEmpty ? 0 : _compactShift(magnitude);
  var (whole, fraction) = _round(digits, point - shift, 0, maxFraction);
  if (digits.isNotEmpty && whole.length - 1 > magnitude - shift) {
    final next = _compactShift(magnitude + 1);
    if (next != shift) {
      shift = next;
      (whole, fraction) = _round(digits, point - shift, 0, maxFraction);
    }
  }
  final prefix = currency == null ? '' : currencyPrefix(currency);
  return _sign(value) +
      prefix +
      _group(whole, 2) +
      (fraction.isEmpty ? '' : '.$fraction') +
      _compactSuffix[shift]!;
}

/// The currency prefix en-US Intl writes before the number.
String currencyPrefix(String code) => currencyPrefixes[code] ?? '$code ';

const _compactSuffix = {0: '', 3: 'K', 6: 'M', 9: 'B', 12: 'T'};

int _compactShift(int magnitude) => magnitude < 3
    ? 0
    : magnitude >= 12
    ? 12
    : magnitude - magnitude % 3;

String _sign(num value) =>
    value < 0 || (value == 0 && value.isNegative) ? '-' : '';

/// The shortest round-trip digits of |value|, as JavaScript prints it, and
/// where the decimal point goes: value = 0.digits × 10^point. Zero is ('', 0).
(String, int) _shortest(num value) {
  var text = Js.numberToString(value.toDouble().abs());
  var exponent = 0;
  final e = text.indexOf('e');
  if (e >= 0) {
    exponent = int.parse(text.substring(e + 1));
    text = text.substring(0, e);
  }
  final dot = text.indexOf('.');
  final whole = dot < 0 ? text : text.substring(0, dot);
  final digits = whole + (dot < 0 ? '' : text.substring(dot + 1));
  final trimmed = digits.replaceFirst(RegExp('^0+'), '');
  return (trimmed, whole.length + exponent - (digits.length - trimmed.length));
}

/// 0.digits × 10^point rounded half away from zero to [maxFraction]
/// decimals, as whole and fraction digit strings; the fraction keeps at
/// least [minFraction] digits and drops trailing zeros past that.
(String, String) _round(
  String digits,
  int point,
  int minFraction,
  int maxFraction,
) {
  var n = digits.isEmpty ? BigInt.zero : BigInt.parse(digits);
  final shift = point - digits.length + maxFraction;
  if (shift >= 0) {
    n *= BigInt.from(10).pow(shift);
  } else {
    final unit = BigInt.from(10).pow(-shift);
    final rest = n.remainder(unit);
    n ~/= unit;
    if (rest * BigInt.two >= unit) n += BigInt.one;
  }
  final text = n.toString().padLeft(maxFraction + 1, '0');
  final whole = text.substring(0, text.length - maxFraction);
  var fraction = text.substring(text.length - maxFraction);
  while (fraction.length > minFraction && fraction.endsWith('0')) {
    fraction = fraction.substring(0, fraction.length - 1);
  }
  return (whole, fraction);
}

/// Groups by thousands when the whole part has at least 3 + [minGrouping]
/// digits (compact notation uses 2, so 1500T has no comma).
String _group(String whole, int minGrouping) {
  if (whole.length < 3 + minGrouping) return whole;
  final out = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
    out.write(whole[i]);
  }
  return out.toString();
}
