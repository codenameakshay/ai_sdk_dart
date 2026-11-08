import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/iui/functions/shared.dart';
import 'package:test/test.dart';

import '../support/run.dart';

// The patterns the working-tool prompt teaches, run by the 1.0 evaluator.
void main() {
  tearDown(Impure.reset);

  group('working-tool patterns', () {
    test(r'@Each maps a @Range into rows that follow $state', () {
      const src =
          'rows = @Each(@Range(0, \$years + 1), "y", {year: y, balance: @Round(\$p * @Pow(1 + \$r / 100, y), 2)})\n\$years = 2\n\$p = 1000\n\$r = 5';
      expect(run('rows', src).value, [
        {'year': 0, 'balance': 1000},
        {'year': 1, 'balance': 1050},
        {'year': 2, 'balance': 1102.5},
      ]);
      expect(run('rows', src, {r'$years': 4}).value, hasLength(5));
    });

    test('@Set evaluates functions at click time, in step order', () async {
      final r = run(
        r'$people, Action([@Set($people, @Append($people, $name)), @Set($name, "")])',
        '\$people = ["You"]\n\$name = "Alex"',
      );
      expect(await r.click(), {
        r'$people': ['You', 'Alex'],
        r'$name': '',
      });
    });

    test(
      'a nested @Each toggles one person on one item with @Update and @Toggle',
      () async {
        final r = run(
          r'$items, @Each($items, "it", @Each(["A", "B"], "p", @Set($items, @Update($items, "name", it.name, "people", @Toggle(it.people, p)))))',
          r'$items = [{name: "Mains", people: ["A", "B"]}, {name: "Wine", people: ["A"]}]',
        );
        final buttons = r.actions as List<Object?>;
        // The (Wine, B) button adds B to the wine; then (Mains, A) takes A off the mains.
        await r.click((buttons[1] as List<Object?>)[1] as OpenUiAction);
        final state = await r.click(
          (buttons[0] as List<Object?>)[0] as OpenUiAction,
        );
        expect(state[r'$items'], [
          {
            'name': 'Mains',
            'people': ['B'],
          },
          {
            'name': 'Wine',
            'people': ['A', 'B'],
          },
        ]);
      },
    );

    test('per-person shares from a nested @Each and @Includes', () {
      const src =
          'shares = @Each(\$people, "p", {name: p, amount: @Sum(@Each(\$items, "it", @Includes(it.people, p) ? it.amount / @Count(it.people) : 0))})\n'
          '\$people = ["A", "B"]\n'
          '\$items = [{amount: 30, people: ["A", "B"]}, {amount: 10, people: ["A"]}]';
      expect(run('shares', src).value, [
        {'name': 'A', 'amount': 25},
        {'name': 'B', 'amount': 15},
      ]);
    });

    test(
      '@CopyToClipboard becomes a custom step with the joined text',
      () async {
        final r = run(r'"x", @CopyToClipboard(@Join(["a", "b"], "\n"))');
        final events = <ActionEvent>[];
        await r.click(null, events.add);
        expect(
          [
            for (final e in events) {'type': e.type, 'params': e.params},
          ],
          [
            {
              'type': 'CopyToClipboard',
              'params': {'text': 'a\nb'},
            },
          ],
        );
      },
    );

    test('@Random inside @Set draws once per click', () async {
      Impure.random = () => 0.4;
      final r = run(r'$door, @Set($door, @Random(0, 2, true))', r'$door = -1');
      expect((await r.click())[r'$door'], 1);
    });
  });
}
