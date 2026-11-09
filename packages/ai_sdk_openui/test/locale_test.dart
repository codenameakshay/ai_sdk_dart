import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/iui/functions/dates.dart';
import 'package:ai_sdk_openui/src/iui/functions/money.dart';
import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:ai_sdk_openui/src/iui/functions/text.dart';
import 'package:test/test.dart';

/// A one-prop component: each expression runs through the real parser,
/// evaluator and session, with the session's locale.
final class _Out implements ComponentSpec {
  const _Out();
  @override
  String get typeName => 'Out';
  @override
  String get description => 'Test output';
  @override
  Map<String, Schema> get props => {'value': S.any()};
}

final OpenUiLibrary _lib = OpenUiLibrary(
  root: const _Out(),
  components: const [_Out()],
  functions: [...textFunctions, ...dateFunctions, formatMoney],
);

Object? _value(String expr, {String? locale}) {
  final s = OpenUiSession(_lib, locale: locale)
    ..update('root = Out($expr)', streaming: false);
  addTearDown(s.dispose);
  return s.root!.props['value'];
}

void main() {
  setUp(Impure.useUtc);
  tearDown(Impure.reset);

  test('no locale and en-US keep the reference output', () {
    for (final locale in <String?>[null, 'en_US', 'en-US']) {
      expect(
        _value('@Format(1234567, "currency", null, "INR")', locale: locale),
        '₹1,234,567.00',
        reason: '$locale',
      );
      expect(
        _value('@Format(1234567.891)', locale: locale),
        '1,234,567.89',
        reason: '$locale',
      );
      expect(
        _value(
          '@FormatDate("2026-10-09T21:30:00Z", "datetime")',
          locale: locale,
        ),
        'Oct 9, 9:30 PM',
        reason: '$locale',
      );
    }
  });

  test('en-IN groups in lakhs', () {
    const locale = 'en_IN';
    expect(_value('@Format(1234567.891)', locale: locale), '12,34,567.89');
    expect(
      _value('@Format(1234567, "currency", null, "INR")', locale: locale),
      '₹12,34,567.00',
    );
    expect(_value('@Format(45.5, "percent")', locale: locale), '45.5%');
    expect(_value('@Format(1234567, "compact")', locale: locale), '12.3L');
    expect(_value('@Plural(1234.5, "item")', locale: locale), '1,234.5 items');
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z")', locale: locale),
      '9 Oct 2026',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "long")', locale: locale),
      'Friday, 9 October 2026',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "time")', locale: locale),
      '9:30 pm',
    );
  });

  test('de-DE writes comma decimals and the symbol after', () {
    const locale = 'de-DE';
    expect(_value('@Format(1234567.891)', locale: locale), '1.234.567,89');
    expect(
      _value('@Format(1234.56, "currency", null, "EUR")', locale: locale),
      '1.234,56 €',
    );
    expect(_value('@Format(45.5, "percent")', locale: locale), '45,5 %');
    expect(_value('@Format(1234567, "compact")', locale: locale), '1,2 Mio.');
    expect(_value('@Plural(1234.5, "item")', locale: locale), '1.234,5 items');
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z")', locale: locale),
      '9. Okt. 2026',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "long")', locale: locale),
      'Freitag, 9. Oktober 2026',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "time")', locale: locale),
      '21:30',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "datetime")', locale: locale),
      '9. Okt. 21:30',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "iso")', locale: locale),
      '2026-10-09',
    );
  });

  test('compact currency and the other date styles follow the locale', () {
    expect(
      _value('@Format(1234567, "compact", null, "EUR")', locale: 'de_DE'),
      '1,2 Mio. €',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "short")', locale: 'de_DE'),
      '9. Okt.',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "weekday")', locale: 'de_DE'),
      'Fr',
    );
    expect(
      _value('@FormatDate("2026-10-09T21:30:00Z", "month")', locale: 'de_DE'),
      'Okt. 2026',
    );
  });

  test('@FormatMoney formats exactly in the session\'s locale', () {
    expect(
      _value('@FormatMoney({minor: 123456700, currency: "INR"})'),
      '₹1,234,567.00',
    );
    expect(
      _value(
        '@FormatMoney({minor: 123456700, currency: "INR"})',
        locale: 'en_IN',
      ),
      '₹12,34,567.00',
    );
    expect(
      _value(
        '@FormatMoney({amount: "1234.56", currency: "EUR"})',
        locale: 'de_DE',
      ),
      '1.234,56 €',
    );
    expect(
      _value(
        '@FormatMoney({amount: "1.234", currency: "EUR"})',
        locale: 'de_DE',
      ),
      isNull,
    );
  });

  test('the session resolves its locale', () {
    final de = OpenUiSession(_lib, locale: 'de-DE');
    addTearDown(de.dispose);
    expect(de.locale, 'de');
    final us = OpenUiSession(_lib, locale: 'en-US');
    addTearDown(us.dispose);
    expect(us.locale, isNull);
    expect(() => OpenUiSession(_lib, locale: 'xx_YY'), throwsArgumentError);
  });
}
