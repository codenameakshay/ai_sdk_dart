import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

void main() {
  test('parses minor units from a number or a string', () {
    expect(
      Money.parse({'minor': 12345, 'currency': 'INR'}),
      Money(12345, 'INR'),
    );
    expect(
      Money.parse({'minor': '12345', 'currency': 'INR'}),
      Money(12345, 'INR'),
    );
    expect(
      Money.parse({'minor': 12345.0, 'currency': 'INR'}),
      Money(12345, 'INR'),
    );
  });

  test('parses a decimal amount at the currency\'s scale', () {
    expect(Money.parse({'amount': '123.4', 'currency': 'INR'}).minor, 12340);
    expect(Money.parse({'amount': '-0.05', 'currency': 'USD'}).minor, -5);
    expect(Money.parse({'amount': '1.234', 'currency': 'KWD'}).minor, 1234);
    expect(Money.parse({'amount': '1234', 'currency': 'JPY'}).minor, 1234);
    expect(Money(1, 'KWD').scale, 3);
    expect(Money(1, 'JPY').scale, 0);
  });

  test('rejects anything inexact', () {
    final bad = <Object?>[
      {'minor': 1.5, 'currency': 'INR'},
      {'amount': '1.234', 'currency': 'INR'},
      {'minor': 1, 'currency': 'inr'},
      {'minor': '9007199254740992', 'currency': 'USD'},
      {'amount': '1e3', 'currency': 'USD'},
      {'minor': 1, 'amount': '1', 'currency': 'USD'},
      'INR 5',
    ];
    for (final json in bad) {
      expect(() => Money.parse(json), throwsFormatException, reason: '$json');
    }
    expect(Money.tryParse('INR 5'), isNull);
    expect(Money.parse(Money(7, 'USD')), Money(7, 'USD'));
  });

  test('adds and subtracts in one currency', () {
    expect(Money(150, 'INR') + Money(250, 'INR'), Money(400, 'INR'));
    expect(Money(150, 'INR') - Money(250, 'INR'), Money(-100, 'INR'));
    expect(() => Money(1, 'INR') + Money(1, 'USD'), throwsArgumentError);
    expect(
      () => Money(Money.maxMinor, 'USD') + Money(1, 'USD'),
      throwsArgumentError,
    );
    expect(Money(5, 'EUR').toJson(), {'minor': 5, 'currency': 'EUR'});
    expect(() => Money(1, 'inr'), throwsArgumentError);
    expect(Money(7, 'USD').hashCode, Money(7, 'USD').hashCode);
    expect(Money(7, 'USD') == Money(7, 'EUR'), false);
  });

  test('formats like the reference with no locale', () {
    expect(Money(123456700, 'INR').format(), '₹1,234,567.00');
    expect(Money(-5, 'USD').format(), r'-$0.05');
    expect(Money(1234, 'JPY').format(), '¥1,234');
    expect(Money(9007199254740991, 'USD').format(), r'$90,071,992,547,409.91');
    expect(Money(123456700, 'INR').format(locale: 'en-US'), '₹1,234,567.00');
    expect(Money(1234, 'JPY').toString(), '¥1,234');
  });

  test('formats exactly for a locale', () {
    expect(Money(123456700, 'INR').format(locale: 'en_IN'), '₹12,34,567.00');
    expect(Money(123456, 'EUR').format(locale: 'de_DE'), '1.234,56\u00A0€');
    expect(Money(123456, 'EUR').format(locale: 'de-DE'), '1.234,56\u00A0€');
    expect(Money(-5, 'USD').format(locale: 'de_DE'), '-0,05\u00A0\$');
    expect(Money(-123456, 'EUR').format(locale: 'de_DE'), '-1.234,56\u00A0€');
    expect(Money(-1234, 'JPY').format(locale: 'de_DE'), '-1.234\u00A0¥');
    expect(
      Money(9007199254740991, 'USD').format(locale: 'en_IN'),
      r'$9,00,71,99,25,47,409.91',
    );
  });

  test('an unknown locale is an error', () {
    expect(() => Money(1, 'USD').format(locale: 'xx_YY'), throwsArgumentError);
  });
}
