import 'package:test/test.dart';

import 'support/run.dart';

void main() {
  test('built-in functions evaluate through the parser', () {
    expect(value('@Sum([1, 2, 3])'), 6);
    expect(value('@Round(2.345, 2)'), 2.35);
    expect(value('"n=" + 4'), 'n=4');
    expect(value('[{a: 1}, {a: 2}].a'), [1, 2]);
    expect(value('@Each([1, 2], "x", x * 10)'), [10, 20]);
    expect(value('7 / 0'), 0);
  });

  test('@Round rounds halves toward +Infinity, as Math.round does', () {
    expect(value('@Round(2.5)'), 3);
    expect(value('@Round(-2.5)'), -2);
    expect(value('@Round(-2.6)'), -3);
    expect(value('@Round(1.005, 2)'), 1);
  });

  test('@Set runs in step order at click time', () async {
    final r = run(
      r'$n, Action([@Set($n, $n + 1), @Set($m, $n * 2)])',
      r'$n = 1',
    );
    expect(await r.click(), {r'$n': 2, r'$m': 4});
  });

  test('state overrides replace declared defaults', () {
    expect(run(r'$n + 1', r'$n = 1', {r'$n': 41}).value, 42);
  });
}
