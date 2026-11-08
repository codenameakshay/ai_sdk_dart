import 'package:test/test.dart';

import 'support/run.dart';

void main() {
  group('size limits make a call evaluate to null', () {
    test('@Concat past 10000 items', () {
      expect(value('@Concat(@Range(0, 6000), @Range(0, 6000))'), isNull);
      expect(
        (value('@Concat(@Range(0, 5000), @Range(0, 5000))') as List).length,
        10000,
      );
    });

    test('@Split past 10000 parts', () {
      const many = '@Join(@Range(0, 10000), ",")';
      expect((value('@Split($many)') as List).length, 10000);
      expect(value('@Split($many + ",x")'), isNull);
    });

    test('@Bucket past 10000 periods', () {
      const rows = '[{d: "1970-01-01"}, {d: "2026-01-01"}]';
      expect(value('@Bucket($rows, "d", "day")'), isNull);
      expect((value('@Bucket($rows, "d", "month")') as List).length, 673);
    });
  });

  group('dot paths step through lists', () {
    const rows = '[{a: [5, 6], n: "x"}, {a: [7], n: "y"}]';

    test('a numeric segment indexes a list', () {
      expect(value('@Find($rows, "a.1", 6)'), {
        'a': [5, 6],
        'n': 'x',
      });
    });

    test('an index past the end finds nothing', () {
      expect(value('@Find($rows, "a.2", 6)'), isNull);
    });

    test('a segment into a plain value finds nothing', () {
      expect(value('@Find($rows, "a.0.deep", 5)'), isNull);
      expect(value('@Find($rows, "n.length", 1)'), isNull);
    });

    test('a non-numeric or negative segment into a list finds nothing', () {
      expect(value('@Find($rows, "a.x", 5)'), isNull);
      expect(value('@Find($rows, "a.-1", 5)'), isNull);
    });
  });

  test('@Cumulative puts the total in a field of a non-object row', () {
    expect(value('@Cumulative([1, {v: 2}, 3], "v")'), [
      {'v': 0},
      {'v': 2},
      {'v': 2},
    ]);
  });

  group('@Histogram keys print the bin starts at their own precision', () {
    test('a width of exactly 1000', () {
      expect(value('@Histogram([0, 2000], 2).key'), ['0', '1000']);
    });

    test('a width just under a power of ten', () {
      expect(value('@Histogram([0, 0.0000000000019999999999999996], 2).key'), [
        '0',
        '1e-12',
      ]);
    });

    test('a width just above a power of ten', () {
      expect(value('@Histogram([0, 10000000000.000002], 1).key'), ['0']);
    });
  });
}
