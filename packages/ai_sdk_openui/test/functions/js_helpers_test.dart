import 'package:ai_sdk_openui/src/iui/functions/js_date.dart';
import 'package:ai_sdk_openui/src/iui/functions/js_number.dart';
import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:test/test.dart';

// Expected values are what Node 26 prints for the same calls with TZ=UTC.
void main() {
  tearDown(Impure.reset);

  group('toFixed', () {
    test('prints a 2^53 double with exact digits', () {
      expect(toFixed(9007199254740992.0, 2), '9007199254740992.00');
    });

    test('prints a negative 2^53 double with one digit', () {
      expect(toFixed(-9007199254740992.0, 1), '-9007199254740992.0');
    });
  });

  group('Impure.fromLocal', () {
    test('reads a zone-less date string in the device zone by default', () {
      Impure.reset();
      expect(
        jsDateParse('2026-10-09T10:00', Impure.fromLocal),
        DateTime(2026, 10, 9, 10).millisecondsSinceEpoch,
      );
    });

    test('reads a zone-less date string in the zone a session picks', () {
      final kolkata = OpenUiTimeZone.fixed(
        const Duration(hours: 5, minutes: 30),
      );
      expect(
        Impure.run(
          timeZone: kolkata,
          () => jsDateParse('2026-10-09T10:00', Impure.fromLocal),
        ),
        1791520200000,
      );
    });
  });

  group('jsDateParse', () {
    const cases = <(String, int?)>[
      ('2026-10-09T10:00:00.12', 1791540000120),
      ('2026-10-09T10:00:00Q', null),
      ('Oct 9 2026 10:00:00Q', null),
      ('2026-10-09T24:00:00.5', null),
    ];
    for (final (text, want) in cases) {
      test('"$text" parses to ${want ?? 'NaN'}', () {
        final got = Impure.run(
          timeZone: OpenUiTimeZone.utc,
          () => jsDateParse(text, Impure.fromLocal),
        );
        expect(got.isNaN ? null : got.toInt(), want);
      });
    }
  });
}
