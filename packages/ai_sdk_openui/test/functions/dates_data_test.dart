import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:test/test.dart';

import '../support/run.dart';

const _rows =
    '[{region: "West", product: "A", amount: 10, date: "2026-10-01"}, {region: "East", product: "B", amount: 5, date: "2026-10-02"}, {region: "West", product: "B", amount: 7, date: "2026-10-09"}]';

Object? _r(String expr) => value(expr.replaceAll('ROWS', _rows));

const _cases = <String, List<(String, Object?)>>{
  'FormatDate': [
    (r'@FormatDate("2026-10-09")', 'Oct 9, 2026'),
    (r'@FormatDate("2026-10-09", "short")', 'Oct 9'),
    (r'@FormatDate("2026-10-09", "long")', 'Friday, October 9, 2026'),
    (r'@FormatDate("2026-10-09", "weekday")', 'Fri'),
    (r'@FormatDate("2026-10-09", "month")', 'Oct 2026'),
    (r'@FormatDate("2026-10-09", "iso")', '2026-10-09'),
    (r'@FormatDate("2026-10-09T21:30:00Z", "time")', '9:30 PM'),
    (r'@FormatDate("2026-10-09T21:30:00Z", "datetime")', 'Oct 9, 9:30 PM'),
    (r'@FormatDate(0, "iso")', '1970-01-01'),
    (r'@FormatDate("2026-02-30")', null),
    (r'@FormatDate("soon")', null),
  ],
  'AddDays': [
    (r'@AddDays("2026-10-09", 3)', '2026-10-12'),
    (r'@AddDays("2026-12-30", 5)', '2027-01-04'),
    (r'@AddDays("2026-03-01", -1)', '2026-02-28'),
    (r'@AddDays("2026-10-09T23:00:00Z", 1)', '2026-10-10'),
    (r'@AddDays("bad", 1)', null),
  ],
  'DaysBetween': [
    (r'@DaysBetween("2026-10-09", "2026-12-25")', 77),
    (r'@DaysBetween("2026-12-25", "2026-10-09")', -77),
    (r'@DaysBetween("2026-10-09", "2026-10-09")', 0),
    (r'@DaysBetween("2026-10-09", null)', null),
  ],
  'AddMonths': [
    (r'@AddMonths("2026-01-31", 1)', '2026-02-28'),
    (r'@AddMonths("2026-10-09", -12)', '2025-10-09'),
    (r'@AddMonths("2026-11-15", 3)', '2027-02-15'),
  ],
  'MonthsBetween': [
    (r'@MonthsBetween("1990-05-20", "2026-05-19")', 431),
    (r'@MonthsBetween("1990-05-20", "2026-05-20")', 432),
    (r'@MonthsBetween("2026-03-15", "2026-01-20")', -1),
  ],
  'StartOf': [
    (r'@StartOf("2026-10-09", "week")', '2026-10-05'),
    (r'@StartOf("2026-10-05", "week")', '2026-10-05'),
    (r'@StartOf("2026-10-11", "week")', '2026-10-05'),
    (r'@StartOf("2026-10-09", "month")', '2026-10-01'),
    (r'@StartOf("2026-10-09", "year")', '2026-01-01'),
  ],
  'GroupBy': [
    (
      r'@GroupBy(ROWS, "region", "amount")',
      [
        {'key': 'West', 'value': 17},
        {'key': 'East', 'value': 5},
      ],
    ),
    (
      r'@GroupBy(ROWS, "region")',
      [
        {'key': 'West', 'value': 2},
        {'key': 'East', 'value': 1},
      ],
    ),
    (
      r'@GroupBy(ROWS, "region", "amount", "avg")',
      [
        {'key': 'West', 'value': 8.5},
        {'key': 'East', 'value': 5},
      ],
    ),
    (
      r'@GroupBy(ROWS, "region", "amount", "max")',
      [
        {'key': 'West', 'value': 10},
        {'key': 'East', 'value': 5},
      ],
    ),
    (
      r'@GroupBy([{a: 1}, {b: 2}], "a")',
      [
        {'key': 1, 'value': 1},
        {'key': 'Unknown', 'value': 1},
      ],
    ),
    (r'@GroupBy([], "region")', <Object?>[]),
  ],
  'Pivot': [
    (
      r'@Pivot(ROWS, "region", "product", "amount")',
      [
        {'key': 'West', 'A': 10, 'B': 7},
        {'key': 'East', 'A': 0, 'B': 5},
      ],
    ),
    (
      r'@Pivot(ROWS, "product", "region")',
      [
        {'key': 'A', 'West': 1, 'East': 0},
        {'key': 'B', 'West': 1, 'East': 1},
      ],
    ),
    (r'@Pivot([], "a", "b")', <Object?>[]),
  ],
  'Top': [
    (r'@Top(ROWS, "amount", 2).amount', [10, 7]),
    (r'@Top(ROWS, "amount", 1, "asc").amount', [5]),
    (r'@Top([{v: "x"}, {v: 2}, {v: 9}], "v", 3).v', [9, 2, 'x']),
    (r'@Top(ROWS, "amount", 0)', <Object?>[]),
    (r'@Top([], "amount", 3)', <Object?>[]),
  ],
  'Between': [
    (r'@Between(ROWS, "date", "2026-10-02", "2026-10-09").amount', [5, 7]),
    (r'@Between(ROWS, "date", "2026-10-02").amount', [5, 7]),
    (r'@Between(ROWS, "date", null, "2026-10-01").amount', [10]),
    (r'@Between(ROWS, "amount", 6, 10).amount', [10, 7]),
    (
      r'@Between([{v: 9}, {v: 10}, {w: 1}], "v", 9, 9.5)',
      [
        {'v': 9},
      ],
    ),
    (r'@Between([], "date", "2026-01-01")', <Object?>[]),
    (r'@Between(ROWS, 3, 1)', null),
  ],
  'Bucket': [
    (
      r'@Bucket(ROWS, "date", "week", "amount")',
      [
        {'key': '2026-09-28', 'value': 15},
        {'key': '2026-10-05', 'value': 7},
      ],
    ),
    (
      r'@Bucket(ROWS, "date", "month", "amount")',
      [
        {'key': '2026-10', 'value': 22},
      ],
    ),
    (r'@Bucket(ROWS, "date", "day").value', [1, 1, 0, 0, 0, 0, 0, 0, 1]),
    (
      r'@Bucket(ROWS, "date", "day", "amount", "avg").key',
      ['2026-10-01', '2026-10-02', '2026-10-09'],
    ),
    (
      r'@Bucket([{d: "nope"}, {d: "2026-01-31"}, {d: "2026-03-02"}], "d", "month").key',
      ['2026-01', '2026-02', '2026-03'],
    ),
    (r'@Bucket([], "date", "day")', <Object?>[]),
    (r'@Bucket(ROWS, "date", "year")', null),
  ],
  'Cumulative': [
    (r'@Cumulative([1, 2, 3], "")', [1, 3, 6]),
    (
      r'@Cumulative([{d: 1, v: 2}, {d: 2, v: 3}], "v")',
      [
        {'d': 1, 'v': 2},
        {'d': 2, 'v': 5},
      ],
    ),
    (r'@Cumulative([{v: "x"}, {v: 4}], "v").v', [0, 4]),
    (r'@Cumulative([], "v")', <Object?>[]),
  ],
  'MovingAvg': [
    (r'@MovingAvg([2, 4, 6, 8], "", 2)', [2, 3, 5, 7]),
    (r'@MovingAvg([{v: 3}, {v: 6}, {v: 9}], "v", 3).v', [3, 4.5, 6]),
    (r'@MovingAvg([1, 2], "", 0)', null),
    (r'@MovingAvg([], "", 7)', <Object?>[]),
  ],
  'Change': [
    (r'@Change(120, 100)', 20),
    (r'@Change(80, 100)', -20),
    (r'@Change(-50, -100)', 50),
    (r'@Change(5, 0)', null),
  ],
  'Histogram': [
    (
      r'@Histogram([0.1, 0.2, 0.3, 0.9], 2, 0, 1)',
      [
        {'key': '0', 'value': 3, 'start': 0, 'end': 0.5},
        {'key': '0.5', 'value': 1, 'start': 0.5, 'end': 1},
      ],
    ),
    (r'@Histogram([0, 1, 2], 2, 0, 1).value', [1, 1]),
    (r'@Histogram([0.1, 0.6], 4, 0, 1).key', ['0', '0.25', '0.5', '0.75']),
    (r'@Histogram([1200, 1350, 1990], 2).key', ['1200', '1595']),
    (r'@Histogram([], 3).value', [0, 0, 0]),
    (r'@Histogram([5, 5], 1).value', [2]),
    (r'@Histogram([1, 2], 0)', null),
    (r'@Histogram([{v: 0.2}, {w: 1}].v, 2, 0, 1).value', [1, 0]),
  ],
  'Stats': [
    (
      r'@Stats([2, 4, 4, 4, 5, 5, 7, 9])',
      {'count': 8, 'min': 2, 'max': 9, 'mean': 5, 'median': 4.5, 'stdev': 2},
    ),
    (r'@Stats([3, 1, 2]).median', 2),
    (
      r'@Stats([])',
      {'count': 0, 'min': 0, 'max': 0, 'mean': 0, 'median': 0, 'stdev': 0},
    ),
    (r'@Stats("1, 2")', null),
    (r'@Stats([{v: 1}, {w: 2}, {v: 3}].v).mean', 2),
  ],
};

void main() {
  setUp(() => Impure.toLocal = (d) => d.toUtc());
  tearDown(Impure.reset);

  for (final MapEntry(key: name, value: rows) in _cases.entries) {
    group('@$name', () {
      for (final (expr, want) in rows) {
        test(expr, () => expect(_r(expr), want));
      }
    });
  }

  group('@Now', () {
    test('returns the current instant as ISO', () {
      Impure.now = () => DateTime.utc(2026, 10, 9, 12);
      expect(value('@Now()'), '2026-10-09T12:00:00.000Z');
      expect(value('@FormatDate(@AddDays(@Now(), 1), "short")'), 'Oct 10');
    });
  });

  group('@Today', () {
    test("returns the viewer's calendar day", () {
      Impure.now = () => DateTime.utc(2026, 10, 9, 23, 30);
      expect(value('@Today()'), '2026-10-09');
    });
  });

  group('an invalid optional argument', () {
    test('is dropped with an error, so its default applies', () {
      final style = run('@FormatDate("2026-10-09", "fancy")');
      expect(style.value, 'Oct 9, 2026');
      expect(style.issues.join(), contains('one of'));
      final how = run('@GroupBy($_rows, "region", "amount", "median")');
      expect(how.value, [
        {'key': 'West', 'value': 17},
        {'key': 'East', 'value': 5},
      ]);
      expect(how.issues, hasLength(1));
    });
  });

  group('@Stats with a bad item', () {
    test('drops the item, reports it and summarizes the rest', () {
      final result = run(r'@Stats([1, $x, 3])', r'$x = 2', {r'$x': 'two'});
      expect(result.value, {
        'count': 2,
        'min': 1,
        'max': 3,
        'mean': 2,
        'median': 2,
        'stdev': 1,
      });
      expect(result.issues.join(), contains('expects number'));
    });
  });
}
