import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

var _dateData = false;

String localeNumber(num value, String locale, {required int maxFraction}) =>
    (NumberFormat.decimalPattern(locale)
          ..minimumFractionDigits = 0
          ..maximumFractionDigits = maxFraction)
        .format(value);

/// `@Format` for [locale]: [currency] is a checked code, or null.
String localeFormat(
  num value,
  String locale, {
  required String kind,
  int? decimals,
  String? currency,
}) => switch (kind) {
  'currency' => NumberFormat.simpleCurrency(
    locale: locale,
    name: currency,
    decimalDigits: decimals ?? 2,
  ).format(value),
  'percent' => (NumberFormat.decimalPercentPattern(
    locale: locale,
    decimalDigits: decimals ?? 1,
  )..minimumFractionDigits = 0).format(value / 100),
  'compact' =>
    ((currency == null
              ? NumberFormat.compact(locale: locale)
              : NumberFormat.compactSimpleCurrency(
                  locale: locale,
                  name: currency,
                ))
          ..maximumFractionDigits = decimals ?? 1)
        .format(value),
  _ => localeNumber(value, locale, maxFraction: decimals ?? 2),
};

/// `@FormatDate` for [locale]; intl's date data loads on first use (a no-op
/// if the app loaded it).
String localeDate(DateTime at, String style, String locale) {
  if (!_dateData) {
    unawaited(initializeDateFormatting());
    _dateData = true;
  }
  final format = switch (style) {
    'short' => DateFormat.MMMd(locale),
    'long' => DateFormat.yMMMMEEEEd(locale),
    'weekday' => DateFormat.E(locale),
    'month' => DateFormat.yMMM(locale),
    'time' => DateFormat.jm(locale),
    'datetime' => DateFormat.MMMd(locale).add_jm(),
    _ => DateFormat.yMMMd(locale),
  };
  return format.format(at);
}
