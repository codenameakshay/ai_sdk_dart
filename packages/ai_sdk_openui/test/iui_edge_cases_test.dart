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

  // Expected values are what the reference functions give in Node 26.
  group('functions build objects as JavaScript does', () {
    test('@Pivot lists year columns first and drops a __proto__ column', () {
      final years =
          value(
                '@Pivot([{r: "x", c: 2024, v: 1}, {r: "x", c: 2023, v: 2}], "r", "c", "v")',
              )!
              as List;
      expect((years.single as Map).keys, ['2023', '2024', 'key']);
      expect(years, [
        {'2023': 2, '2024': 1, 'key': 'x'},
      ]);
      expect(
        value(
          '@Pivot([{r: "x", c: "__proto__", v: 1}, {r: "x", c: "a", v: 2}], "r", "c", "v")',
        ),
        [
          {'key': 'x', 'a': 2},
        ],
      );
    });

    test('@Update and @Cumulative put an index-like field first', () {
      final updated =
          value('@Update([{id: 1, a: 2}], "id", 1, "0", 9)')! as List;
      expect((updated.single as Map).keys, ['0', 'id', 'a']);
      expect(
        run('@Update([a], "typeName", "Out", "x", 1)', 'a = Out(5)').value,
        [
          {
            'type': 'element',
            'typeName': 'Out',
            'props': {'value': 5},
            'partial': false,
            'hasDynamicProps': true,
            'x': 1,
          },
        ],
      );
      final totals =
          value('@Cumulative([{v: 1, b: 0}, {v: 2, b: 0}], "1")')! as List;
      expect((totals.first as Map).keys, ['1', 'v', 'b']);
      expect(totals, [
        {'1': 0, 'v': 1, 'b': 0},
        {'1': 0, 'v': 2, 'b': 0},
      ]);
    });

    test('a field path reads a component and a list, not a string', () {
      expect(run('@GroupBy([a, a], "typeName")', 'a = Out(5)').value, [
        {'key': 'Out', 'value': 2},
      ]);
      expect(value('@GroupBy([["x", "y"]], "1")'), [
        {'key': 'y', 'value': 1},
      ]);
      expect(value('@GroupBy([{t: "ab"}], "t.0")'), [
        {'key': 'Unknown', 'value': 1},
      ]);
    });
  });
}
