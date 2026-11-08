import 'package:intl/intl.dart';

/// The verified intl locale for [locale] ("de-DE", "en_IN"), or null for the
/// reference's en-US output (null, "en_US" or "en-US"). Throws ArgumentError
/// for an unknown locale.
String? resolveLocale(String? locale) {
  if (locale == null) return null;
  final name = Intl.verifiedLocale(
    Intl.canonicalizedLocale(locale),
    NumberFormat.localeExists,
    onFailure: (_) =>
        throw ArgumentError.value(locale, 'locale', 'Unknown locale'),
  )!;
  return name == 'en_US' ? null : name;
}
