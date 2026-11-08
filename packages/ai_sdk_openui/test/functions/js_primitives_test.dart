import 'package:ai_sdk_openui/src/iui/functions/js_number.dart';
import 'package:ai_sdk_openui/src/iui/functions/number_format.dart';
import 'package:ai_sdk_openui/src/iui/functions/unicode.dart';
import 'package:test/test.dart';

// Expected values are what Node 26 prints for the same calls.
void main() {
  group('formatDecimal', () {
    const cases = <(num, int, int, String)>[
      (1.005, 0, 2, '1.01'),
      (2.675, 0, 2, '2.68'),
      (8.345, 0, 2, '8.35'),
      (999.995, 0, 2, '1,000'),
      (1e21, 0, 2, '1,000,000,000,000,000,000,000'),
      (123456789.12345679, 0, 10, '123,456,789.12345679'),
      (1e-7, 0, 10, '0.0000001'),
      (-0.001, 0, 2, '-0'),
      (2.5, 0, 0, '3'),
      (-2.5, 0, 0, '-3'),
      (0.125, 2, 2, '0.13'),
      (12345.6, 0, 2, '12,345.6'),
    ];
    for (final (v, min, max, want) in cases) {
      test('$v with $min to $max decimals is $want', () {
        expect(formatDecimal(v, minFraction: min, maxFraction: max), want);
      });
    }
  });

  group('formatCurrency', () {
    const cases = <(num, String, String)>[
      (1234.5, 'CAD', 'CA\$1,234.50'),
      (1234.5, 'AUD', 'A\$1,234.50'),
      (1234.5, 'MXN', 'MX\$1,234.50'),
      (1234.5, 'CHF', 'CHF 1,234.50'),
      (1234.5, 'XYZ', 'XYZ 1,234.50'),
      (1234.5, 'KWD', 'KWD 1,234.50'),
      (1234.5, 'JPY', '¥1,234.50'),
      (1234.5, 'XOF', 'F CFA 1,234.50'),
      (-1234.5, 'USD', '-\$1,234.50'),
      (-1234.5, 'CHF', '-CHF 1,234.50'),
      (1e21, 'USD', '\$1,000,000,000,000,000,000,000.00'),
      (0.125, 'EUR', '€0.13'),
    ];
    for (final (v, code, want) in cases) {
      test('$v $code is $want', () {
        expect(formatCurrency(v, code, minFraction: 2, maxFraction: 2), want);
      });
    }
  });

  group('formatCompact', () {
    const cases = <(num, int, String?, String)>[
      (1234567, 1, null, '1.2M'),
      (1234567, 3, null, '1.235M'),
      (999950, 1, null, '1M'),
      (999949, 1, null, '999.9K'),
      (999.95, 1, null, '1K'),
      (12.34, 1, null, '12.3'),
      (1e15, 1, null, '1000T'),
      (1.2345e16, 1, null, '12,345T'),
      (1e21, 1, null, '1,000,000,000T'),
      (0.05, 1, null, '0.1'),
      (-0.04, 1, null, '-0'),
      (123456, 0, null, '123K'),
      (99949, 0, null, '100K'),
      (1234567, 1, 'CAD', 'CA\$1.2M'),
      (1234.5, 1, 'JPY', '¥1.2K'),
      (999, 1, 'CHF', 'CHF 999'),
      (-999999, 1, 'USD', '-\$1M'),
    ];
    for (final (v, max, code, want) in cases) {
      test('$v with $max decimals and currency $code is $want', () {
        expect(formatCompact(v, maxFraction: max, currency: code), want);
      });
    }
  });

  group('jsUpperCase', () {
    test('uses full case mappings', () {
      expect(jsUpperCase('straße ﬁ ŉ'), 'STRASSE FI ʼN');
      expect(jsUpperCase('ǰ'), 'J̌');
      expect(jsUpperCase('ǅ'), 'Ǆ');
    });
  });

  group('jsLowerCase', () {
    test('uses full mappings and the final-sigma rule', () {
      expect(jsLowerCase('ΟΔΟΣ İ'), 'οδος i̇');
      expect(jsLowerCase('ΣΣ'), 'σς');
      expect(jsLowerCase("ΑΣ'Α"), "ασ'α");
      expect(jsLowerCase('Α.Σ'), 'α.ς');
      expect(jsLowerCase('Ᲊ'), 'ᲊ');
    });
  });

  group('jsTrim', () {
    test('trims ECMAScript white space only', () {
      expect(jsTrim('\u0085x\u0085'), '\u0085x\u0085');
      expect(jsTrim('﻿  x　'), 'x');
      expect(jsTrim('᠎x'), '᠎x');
    });
  });

  group('jsRound', () {
    test('sends halves up, exactly', () {
      expect(jsRound(2.5), 3);
      expect(jsRound(-2.5), -2);
      expect(jsRound(-1.5), -1);
      expect(jsRound(0.49999999999999994), 0);
      expect(jsRound(4503599627370497), 4503599627370497);
    });
  });

  group('toFixed', () {
    const cases = <(double, int, String)>[
      (1.005, 2, '1.00'),
      (1e-21, 22, '0.0000000000000000000010'),
      (0.1, 25, '0.1000000000000000055511151'),
      (123.456, 0, '123'),
      (2.5, 0, '3'),
      (-2.5, 0, '-3'),
      (1e21, 2, '1e+21'),
      (0.000001, 7, '0.0000010'),
    ];
    for (final (v, digits, want) in cases) {
      test('$v to $digits digits is $want', () {
        expect(toFixed(v, digits), want);
      });
    }
    test('throws past 100 digits, as JavaScript does', () {
      expect(() => toFixed(1, 101), throwsRangeError);
    });
  });
}
