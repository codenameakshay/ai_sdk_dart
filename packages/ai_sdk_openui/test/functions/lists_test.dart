import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:test/test.dart';

import '../support/run.dart';

void main() {
  tearDown(Impure.reset);

  const cases = <String, List<(String, Object?)>>{
    'Append': [
      ('@Append([1, 2], 3)', [1, 2, 3]),
      ('@Append([], "a")', ['a']),
      (
        '@Append([1], [2])',
        [
          1,
          [2],
        ],
      ),
      ('@Append(null, 1)', null),
      ('@Append("x", 1)', null),
    ],
    'Prepend': [
      ('@Prepend([2, 3], 1)', [1, 2, 3]),
      ('@Prepend([], "a")', ['a']),
      ('@Prepend(5, 1)', null),
    ],
    'Concat': [
      ('@Concat([1], [2, 3])', [1, 2, 3]),
      ('@Concat([], [])', []),
      ('@Concat([1], 2)', null),
    ],
    'Remove': [
      ('@Remove(["a", "b", "a"], "", "a")', ['b']),
      (
        '@Remove([{id: 1}, {id: 2}], "id", 2)',
        [
          {'id': 1},
        ],
      ),
      ('@Remove([{id: 1}], "id", "1")', []),
      (
        '@Remove([{p: {id: 1}}, {p: {id: 2}}], "p.id", 1)',
        [
          {
            'p': {'id': 2},
          },
        ],
      ),
      ('@Remove([], "id", 1)', []),
      ('@Remove(["a"], "", "z")', ['a']),
      ('@Remove([1], 5, 1)', null),
    ],
    'RemoveAt': [
      ('@RemoveAt(["a", "b", "c"], 1)', ['a', 'c']),
      ('@RemoveAt(["a", "b", "c"], -1)', ['a', 'b']),
      ('@RemoveAt(["a", "b", "c"], 9)', ['a', 'b', 'c']),
      ('@RemoveAt([], 0)', []),
      ('@RemoveAt(["a"], "0")', null),
    ],
    'Update': [
      (
        '@Update([{id: 1, done: false}, {id: 2, done: false}], "id", 2, "done", true)',
        [
          {'id': 1, 'done': false},
          {'id': 2, 'done': true},
        ],
      ),
      (
        '@Update([1, {id: 1}], "id", 1, "x", 5)',
        [
          1,
          {'id': 1, 'x': 5},
        ],
      ),
      (
        '@Update([{id: 1}], "id", 3, "x", 5)',
        [
          {'id': 1},
        ],
      ),
      ('@Update([], "id", 1, "x", 5)', []),
      ('@Update([{id: 1}], "id", 1, null, 5)', null),
    ],
    'Toggle': [
      ('@Toggle(["a"], "b")', ['a', 'b']),
      ('@Toggle(["a", "b"], "a")', ['b']),
      ('@Toggle([], 1)', [1]),
      ('@Toggle([1, 2], "2")', [1]),
    ],
    'Includes': [
      ('@Includes([1, 2], 2)', true),
      ('@Includes([1, 2], 3)', false),
      ('@Includes("Hello world", "world")', true),
      ('@Includes("Hello", "z")', false),
      ('@Includes([], "a")', false),
      ('@Includes(5, 5)', null),
    ],
    'Find': [
      ('@Find([{n: "a", v: 1}, {n: "b", v: 2}], "n", "b")', {'n': 'b', 'v': 2}),
      ('@Find([{n: "a"}], "n", "z")', null),
      ('@Find([], "n", "z")', null),
    ],
    'IndexOf': [
      ('@IndexOf(["a", "b"], "b")', 1),
      ('@IndexOf(["a", "b"], "z")', -1),
      ('@IndexOf([], 1)', -1),
      ('@IndexOf([{a: 1, b: [2]}, {a: 2}], {b: [2], a: 1})', 0),
    ],
    'Take': [
      ('@Take([1, 2, 3], 2)', [1, 2]),
      ('@Take([1, 2, 3], -1)', [3]),
      ('@Take([1, 2, 3], 0)', []),
      ('@Take([], 5)', []),
    ],
    'Slice': [
      ('@Slice([1, 2, 3, 4], 1, 3)', [2, 3]),
      ('@Slice([1, 2, 3], -2)', [2, 3]),
      ('@Slice([], 0, 2)', []),
      ('@Slice("Saturday", 0, 3)', 'Sat'),
      ('@Slice("report.pdf", -3)', 'pdf'),
      ('@Slice([1, 2], "a")', null),
    ],
    'Unique': [
      ('@Unique([1, 1, 2, "a", "a"])', [1, 2, 'a']),
      (
        '@Unique([{a: 1}, {a: 1}, {a: 2}])',
        [
          {'a': 1},
          {'a': 2},
        ],
      ),
      ('@Unique([])', []),
    ],
    'Reverse': [
      ('@Reverse([1, 2, 3])', [3, 2, 1]),
      ('@Reverse([])', []),
    ],
    'Flatten': [
      ('@Flatten([[1, 2], [3], 4])', [1, 2, 3, 4]),
      ('@Flatten([])', []),
    ],
    'Chunk': [
      (
        '@Chunk([1, 2, 3, 4, 5], 2)',
        [
          [1, 2],
          [3, 4],
          [5],
        ],
      ),
      ('@Chunk([1], 0)', null),
    ],
    'Range': [
      ('@Range(0, 3)', [0, 1, 2]),
      ('@Range(1, 10, 3)', [1, 4, 7]),
      ('@Range(3, 0, -1)', [3, 2, 1]),
      ('@Range(0, 0.3, 0.1)', [0, 0.1, 0.2]),
      ('@Range(5, 0)', []),
      ('@Range(0, 5, 0)', null),
      ('@Range(0, 100000)', null),
      ('@Range(0)', null),
    ],
  };
  for (final MapEntry(key: name, value: rows) in cases.entries) {
    group('@$name', () {
      for (final (expr, want) in rows) {
        test(expr, () => expect(value(expr), want));
      }
    });
  }

  group('random list functions', () {
    test('@Pick returns a random item, or null for an empty list', () {
      Impure.random = () => 0.5;
      expect(value('@Pick(["a", "b", "c"])'), 'b');
      expect(value('@Pick([])'), isNull);
      expect(value('@Pick("abc")'), isNull);
    });

    test('@Shuffle returns a permutation and leaves the input alone', () {
      Impure.random = () => 0;
      final result = run(r'@Shuffle($xs)', r'$xs = [1, 2, 3, 4]');
      expect(result.value, [2, 3, 4, 1]);
      Impure.reset();
      final shuffled = value('@Shuffle([1, 2, 3, 4, 5])') as List<Object?>;
      expect([...shuffled]..sort(), [1, 2, 3, 4, 5]);
      expect(value('@Shuffle([])'), []);
    });
  });

  group('bad arguments', () {
    test('report a parse error for a wrong literal and evaluate to null', () {
      final result = run('@Take("abc", 1)');
      expect(result.value, isNull);
      expect(result.issues.join(), matches(RegExp('expects array')));
    });

    test('evaluate to null when a \$variable holds the wrong type', () {
      final result = run(r'@Append($xs, 1)', r'$xs = []', {
        r'$xs': 'not a list',
      });
      expect(result.value, isNull);
      expect(result.issues.join(), matches(RegExp('expects array')));
    });
  });
}
