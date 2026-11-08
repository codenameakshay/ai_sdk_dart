import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:test/test.dart';

import '../support/run.dart';

void main() {
  tearDown(Impure.reset);

  const cases = <String, List<(String, Object?)>>{
    'Pow': [
      ('@Pow(2, 10)', 1024),
      ('@Pow(9, 0.5)', 3),
      ('@Pow(2, -1)', 0.5),
      ('@Pow(0, -1)', null),
      ('@Pow(-8, 1 / 3)', null),
      ('@Pow("2", 2)', null),
    ],
    'Sqrt': [
      ('@Sqrt(9)', 3),
      ('@Sqrt(0)', 0),
      ('@Sqrt(-1)', null),
      ('@Sqrt(null)', null),
    ],
    'Clamp': [
      ('@Clamp(5, 0, 3)', 3),
      ('@Clamp(-1, 0, 3)', 0),
      ('@Clamp(2, 0, 3)', 2),
      ('@Clamp(2, 3, 0)', 2),
      ('@Clamp(2, 0)', null),
    ],
    'Percent': [
      ('@Percent(3, 4)', 75),
      ('@Percent(1, 0)', 0),
      ('@Percent(-1, 4)', -25),
      ('@Percent(1, null)', null),
    ],
    'Lerp': [
      ('@Lerp(0, 10, 0.25)', 2.5),
      ('@Lerp(10, 0, 1)', 0),
      ('@Lerp(0, 10)', null),
    ],
    'Allocate': [
      ('@Allocate(100, [1, 1, 1])', [33.34, 33.33, 33.33]),
      ('@Allocate(10, [1, 2, 1])', [2.5, 5, 2.5]),
      ('@Allocate(-1, [1, 1, 1])', [-0.34, -0.33, -0.33]),
      ('@Allocate(7, [1, 1], 0)', [4, 3]),
      ('@Allocate(5, [0, 0])', [0, 0]),
      ('@Allocate(5, [1, -1])', null),
    ],
    'MixColor': [
      ('@MixColor("#ffffff", "#000000", 0.5)', '#808080'),
      ('@MixColor("#fff", "#0285ff", 1)', '#0285ff'),
      ('@MixColor("#ff0000", "#0000ff", 2)', '#0000ff'),
      ('@MixColor("red", "#000000", 0.5)', null),
    ],
    'Format': [
      ('@Format(12345.678)', '12,345.68'),
      ('@Format(12345.6, "number")', '12,345.6'),
      ('@Format(2.5, "number", 0)', '3'),
      ('@Format(1234.5, "currency")', '\$1,234.50'),
      ('@Format(1234.5, "currency", 0, "EUR")', '€1,235'),
      ('@Format(1, "currency", 2, "nope")', '\$1.00'),
      ('@Format(45, "percent")', '45%'),
      ('@Format(12.345, "percent", 1)', '12.3%'),
      ('@Format(600, "number", 1)', '600'),
      ('@Format(12, "currency", 2)', '\$12.00'),
      ('@Format(1234567, "compact")', '1.2M'),
      ('@Format(1234567, "compact", null, "USD")', '\$1.2M'),
      ('@Format(999, "compact")', '999'),
      ('@Format(-5, "currency")', '-\$5.00'),
      ('@Format("12", "number")', null),
      ('@Format(1234.5, "money")', '1,234.5'),
    ],
    'Join': [
      ('@Join(["a", "b"])', 'a, b'),
      ('@Join(["a", "b"], " / ")', 'a / b'),
      ('@Join([{n: "x"}, {n: "y"}], "\\n", "n")', 'x\ny'),
      ('@Join(["a", null, "b"], "-")', 'a-b'),
      ('@Join([1, 2.5])', '1, 2.5'),
      ('@Join([])', ''),
      ('@Join("ab")', null),
    ],
    'Plural': [
      ('@Plural(1, "guest")', '1 guest'),
      ('@Plural(3, "guest")', '3 guests'),
      ('@Plural(0, "item")', '0 items'),
      ('@Plural(2, "person", "people")', '2 people'),
      ('@Plural(1500, "step")', '1,500 steps'),
      ('@Plural("2", "cat")', null),
    ],
    'Pad': [
      ('@Pad(7, 2)', '07'),
      ('@Pad("5", 3, " ")', '  5'),
      ('@Pad(123, 2)', '123'),
      ('@Pad(7)', null),
    ],
    'Payment': [
      ('@Round(@Payment(300000, 0.5, 360), 2)', 1798.65),
      ('@Payment(1200, 0, 12)', 100),
      ('@Payment(1000, 1, 0)', null),
    ],
    'Convert': [
      ('@Round(@Convert(10, "km", "mi"), 3)', 6.214),
      ('@Convert(100, "c", "f")', 212),
      ('@Round(@Convert(2, "CUP", "ml"))', 473),
      ('@Convert(1, "kg", "m")', null),
      ('@Convert(1, "parsec", "m")', null),
    ],
    'Trim': [('@Trim("  hi there ")', 'hi there'), ('@Trim(3)', null)],
    'Capitalize': [
      ('@Capitalize("new york-city trip")', 'New York-City Trip'),
      ('@Capitalize("élan vital")', 'Élan Vital'),
    ],
    'Split': [
      ('@Split("a, b,,c")', ['a', 'b', 'c']),
      ('@Split("eggs\nmilk", "\n")', ['eggs', 'milk']),
      ('@Split("")', <Object?>[]),
    ],
    'Replace': [
      ('@Replace("a-b-c", "-", " / ")', 'a / b / c'),
      ('@Replace("abc", "", "x")', 'abc'),
    ],
    'Duration': [
      ('@Duration(4800)', '1h 20m'),
      ('@Duration(245)', '4m 05s'),
      ('@Duration(45)', '45s'),
      ('@Duration(4805, "clock")', '1:20:05'),
      ('@Duration(65, "clock")', '1:05'),
      ('@Duration(-60)', '-1m'),
    ],
    'Default': [
      ('@Default("", 0)', 0),
      ('@Default(null, "n/a")', 'n/a'),
      ('@Default(0, 5)', 0),
      ('@Default(false, true)', false),
    ],
    'Upper': [
      ('@Upper("abc")', 'ABC'),
      ('@Upper("")', ''),
      ('@Upper(5)', null),
    ],
    'Lower': [('@Lower("AbC")', 'abc'), ('@Lower(null)', null)],
  };

  group('@Default with state', () {
    test('falls back for an empty input and keeps typed values', () {
      expect(run('@Default(\$w, 0) + 1', '\$w = null').value, 1);
      expect(run('@Default(\$w, 0) + 1', '\$w = ""').value, 1);
      expect(run('@Default(\$w, 0) + 1', '\$w = 4').value, 5);
    });
  });

  for (final MapEntry(key: name, value: rows) in cases.entries) {
    group('@$name', () {
      for (final (expr, want) in rows) {
        test(expr, () => expect(value(expr), want));
      }
    });
  }

  group('@Random', () {
    test('scales a draw into the range, swapping reversed bounds', () {
      Impure.random = () => 0.5;
      expect(value('@Random(0, 10)'), 5);
      expect(value('@Random(10, 0)'), 5);
    });

    test('gives whole numbers with max included when integer is true', () {
      Impure.random = () => 0.999;
      expect(value('@Random(1, 6, true)'), 6);
      Impure.random = () => 0;
      expect(value('@Random(1, 6, true)'), 1);
    });

    test('is null without a whole number in range or with missing args', () {
      expect(value('@Random(0.2, 0.8, true)'), isNull);
      expect(value('@Random(1)'), isNull);
    });
  });
}
