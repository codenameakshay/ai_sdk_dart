import 'package:intl/intl.dart';
import 'package:intl/number_symbols_data.dart' show currencyFractionDigits;

import '../iui/functions/number_format.dart' show formatMinorUnits;
import 'locale.dart';

final _code = RegExp(r'^[A-Z]{3}$');
final _integer = RegExp(r'^-?\d+$');
final _decimal = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$');
final _maxBig = BigInt.from(Money.maxMinor);

/// An exact amount in integer minor units of an ISO 4217 [currency]. It never
/// uses a double: [parse] takes `{minor, currency}` or `{amount, currency}`
/// with a decimal string, and only what is exact at the currency's scale.
final class Money {
  /// The largest magnitude of [minor] that stays exact on every platform.
  static const maxMinor = 9007199254740991;

  Money(this.minor, this.currency) {
    if (minor < -maxMinor || minor > maxMinor) {
      throw ArgumentError.value(
        minor,
        'minor',
        'Money is limited to ±$maxMinor',
      );
    }
    if (!_code.hasMatch(currency)) {
      throw ArgumentError.value(currency, 'currency', 'Not an ISO 4217 code');
    }
  }

  final int minor;
  final String currency;

  int get scale => scaleOf(currency);

  /// The digits after the decimal point for [currency] (CLDR: JPY 0, KWD 3).
  static int scaleOf(String currency) =>
      currencyFractionDigits[currency] ?? currencyFractionDigits['DEFAULT']!;

  static Money parse(Object? json) {
    if (json is Money) return json;
    if (json is! Map) {
      throw const FormatException(
        'Money must be an object with minor or amount, and currency',
      );
    }
    final currency = json['currency'];
    if (currency is! String || !_code.hasMatch(currency)) {
      throw FormatException(
        'Money currency must be an ISO 4217 code such as "USD"',
        currency,
      );
    }
    final minor = switch ((json['minor'], json['amount'])) {
      (final int m, null) => m >= -maxMinor && m <= maxMinor ? m : null,
      (final double m, null)
          when m == m.truncateToDouble() && m.abs() <= maxMinor =>
        m.toInt(),
      (final String m, null) when _integer.hasMatch(m) => _exact(m),
      (null, final String a) => _amount(a, scaleOf(currency)),
      _ => null,
    };
    if (minor == null) {
      throw FormatException('Money must have exact whole minor units', json);
    }
    return Money(minor, currency);
  }

  static Money? tryParse(Object? json) {
    try {
      return parse(json);
    } on FormatException {
      return null;
    }
  }

  Money operator +(Money other) => _combine(other, minor + other.minor);

  Money operator -(Money other) => _combine(other, minor - other.minor);

  Map<String, Object?> toJson() => {'minor': minor, 'currency': currency};

  /// The amount as text: the reference's en-US output with no [locale], or
  /// the intl output for [locale] (`de_DE`, `en-IN`), exact to the minor unit.
  String format({String? locale}) {
    final name = resolveLocale(locale);
    return name == null
        ? formatMinorUnits(minor, scale, currency)
        : _localized(name);
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => format();

  Money _combine(Money other, int result) {
    if (other.currency != currency) {
      throw ArgumentError.value(
        other.currency,
        'other',
        'Money adds only one currency',
      );
    }
    return Money(result, currency);
  }

  static int? _exact(String digits) {
    final v = BigInt.parse(digits);
    return v.abs() > _maxBig ? null : v.toInt();
  }

  static int? _amount(String a, int scale) {
    final m = _decimal.firstMatch(a);
    final fraction = m?[3] ?? '';
    if (m == null || fraction.length > scale) return null;
    return _exact('${m[1]}${m[2]}${fraction.padRight(scale, '0')}');
  }

  // The whole units go through intl exactly (an int); the minor digits replace
  // the zeros it writes.
  String _localized(String locale) {
    final f = NumberFormat.simpleCurrency(
      locale: locale,
      name: currency,
      decimalDigits: scale,
    );
    final s = f.symbols;
    var unit = 1;
    for (var i = 0; i < scale; i++) {
      unit *= 10;
    }
    final major = minor.abs() ~/ unit;
    // intl has no -0, so -0.05 formats -1 and its digit is zeroed.
    final tiny = minor < 0 && major == 0;
    var text = f.format(minor < 0 ? -(tiny ? 1 : major) : major);
    if (scale == 0) return text;
    final zero = s.ZERO_DIGIT.codeUnitAt(0);
    final zeros = s.DECIMAL_SEP + String.fromCharCode(zero) * scale;
    final at = text.lastIndexOf(zeros);
    if (tiny) text = text.replaceRange(at - 1, at, String.fromCharCode(zero));
    final fraction = String.fromCharCodes(
      (minor.abs() % unit)
          .toString()
          .padLeft(scale, '0')
          .codeUnits
          .map((c) => zero + c - 48),
    );
    return text.replaceRange(at, at + zeros.length, s.DECIMAL_SEP + fraction);
  }
}
