import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:test/test.dart';

import '../support/run.dart';

// Functions count in doubles, as JavaScript does: results past 2^53 round
// the way Node 26 rounds them, and nothing overflows past 2^63.
void main() {
  tearDown(Impure.reset);

  const cases = <String, List<(String, Object?)>>{
    'Pow': [
      ('@Pow(2, 64)', 1.8446744073709552e19),
      ('@Pow(3, 40)', 1.2157665459056929e19),
    ],
    'Lerp': [
      ('@Lerp(0, 9007199254740991, 9007199254740991)', 8.112963841460666e31),
    ],
    'Allocate': [
      ('@Allocate(1e20, [1, 1])', [5e19, 5e19]),
      ('@Allocate(4503599627370497, [1], 0)', [4503599627370497]),
      (
        '@Allocate(9007199254740991, [9007199254740991, 1, 1, 1], 0)',
        [9007199254740990, 1, 0, 0],
      ),
    ],
    'Range': [
      (
        '@Range(9007199254740990, 9007199254740994)',
        [
          9007199254740990,
          9007199254740991,
          9007199254740992,
          9007199254740992,
        ],
      ),
    ],
    'MixColor': [
      ('@MixColor("#000000", "#010101", 0.49999999999999994)', '#000000'),
    ],
    'Histogram': [
      (
        '@Histogram([1e-21, 2e-21], 1)',
        [
          {'key': '1e-21', 'value': 2, 'start': 1e-21, 'end': 2e-21},
        ],
      ),
      ('@Histogram([0, 1e-300], 1)', null),
    ],
    'Cumulative': [
      (
        '@Cumulative([{v: 1}, 3, [1], "ab"], "v")',
        [
          {'v': 1},
          {'v': 1},
          {'0': 1, 'v': 1},
          {'0': 'a', '1': 'b', 'v': 1},
        ],
      ),
      (
        '@Cumulative([9007199254740991, 1, 1, 1], "")',
        [
          9007199254740991,
          9007199254740992,
          9007199254740992,
          9007199254740992,
        ],
      ),
    ],
    'MovingAvg': [
      (
        '@MovingAvg([9007199254740991, 1, 1, 1], "", 4)',
        [
          9007199254740991,
          4503599627370496,
          3002399751580330.5,
          2251799813685248,
        ],
      ),
    ],
    'Stats': [('@Stats([9007199254740991, 1, 1, 1]).mean', 2251799813685248)],
  };

  for (final MapEntry(key: name, value: rows) in cases.entries) {
    group('@$name', () {
      for (final (expr, want) in rows) {
        test(expr, () => expect(value(expr), want));
      }
    });
  }

  group('@Random', () {
    test('draws whole numbers past the int range', () {
      Impure.random = () => 0.5;
      expect(value('@Random(0, 1e300, true)'), 5e299);
    });
  });
}
