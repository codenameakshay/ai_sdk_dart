import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

void main() {
  group('Money portable bounds', () {
    final minimumInt64 = int.parse('-9223372036854775808');

    test('constructor rejects the VM minimum int64', () {
      expect(() => Money(minimumInt64, 'USD'), throwsArgumentError);
    });

    test('numeric minor parsing rejects the VM minimum int64', () {
      expect(
        () => Money.parse({'minor': minimumInt64, 'currency': 'USD'}),
        throwsFormatException,
      );
      expect(
        Money.tryParse({'minor': minimumInt64, 'currency': 'USD'}),
        isNull,
      );
    });

    test('parsing and arithmetic keep both portable boundaries exact', () {
      for (final sign in [-1, 1]) {
        final edge = sign * Money.maxMinor;
        final money = Money(edge, 'USD');
        expect(Money.parse({'minor': '$edge', 'currency': 'USD'}), money);
        expect(Money.parse({'minor': edge, 'currency': 'USD'}), money);
        expect(
          Money.parse({
            'amount': '${sign < 0 ? '-' : ''}90071992547409.91',
            'currency': 'USD',
          }),
          money,
        );
        expect(money - Money(sign, 'USD'), Money(edge - sign, 'USD'));
        expect(Money(edge - sign, 'USD') + Money(sign, 'USD'), money);
        expect(() => money + Money(sign, 'USD'), throwsArgumentError);
        expect(() => money - Money(-sign, 'USD'), throwsArgumentError);
        expect(money - money, Money(0, 'USD'));
      }
    });

    test('maximum formats exactly at scales zero, two, and three', () {
      const expectations = {
        'JPY': {
          'en_US': '¥9,007,199,254,740,991',
          'en_IN': '¥9,00,71,99,25,47,40,991',
          'de_DE': '9.007.199.254.740.991\u00a0¥',
        },
        'USD': {
          'en_US': '\$90,071,992,547,409.91',
          'en_IN': '\$9,00,71,99,25,47,409.91',
          'de_DE': '90.071.992.547.409,91\u00a0\$',
        },
        'KWD': {
          'en_US': 'KWD\u00a09,007,199,254,740.991',
          'en_IN': 'din90,07,19,92,54,740.991',
          'de_DE': '9.007.199.254.740,991\u00a0din',
        },
      };
      for (final currency in expectations.entries) {
        for (final locale in currency.value.entries) {
          for (final sign in [-1, 1]) {
            final money = Money(sign * Money.maxMinor, currency.key);
            final expected = '${sign < 0 ? '-' : ''}${locale.value}';
            expect(
              money.format(locale: locale.key),
              expected,
              reason: '${currency.key} ${locale.key} $sign',
            );
            if (locale.key == 'en_US') expect(money.format(), expected);
          }
        }
      }
    });
  });
}
