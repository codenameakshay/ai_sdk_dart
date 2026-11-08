import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

import 'support/run.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

/// `Out(value, action)`, a bound `Field($var)` and a nestable `Box`.
final OpenUiLibrary _library = OpenUiLibrary(
  root: _Spec('Out', {
    'value': S.any(),
    'action': actionSchema.optional(),
    'alt': actionSchema.optional(),
  }),
  components: [
    _Spec('Out', {
      'value': S.any(),
      'action': actionSchema.optional(),
      'alt': actionSchema.optional(),
    }),
    _Spec('Field', {'bind': S.any().reactive()}),
    _Spec('Box', {
      'child': S.ref('Box').optional(),
      'kids': S.list(S.ref('Box')).optional(),
    }),
  ],
);

OpenUiSession open(String program) {
  final s = OpenUiSession(_library)..update(program, streaming: false);
  addTearDown(s.dispose);
  return s;
}

Future<List<ActionEvent>> clickAll(
  OpenUiSession s,
  OpenUiAction? action, {
  String label = '',
}) async {
  final events = <ActionEvent>[];
  await s.run(action, label: label, emit: events.add);
  return events;
}

void main() {
  group('unary operators on state', () {
    test('! negates the truthiness of a variable', () {
      expect(run(r'!$a', r'$a = 0').value, true);
      expect(run(r'!$a', r'$a = "x"').value, false);
    });

    test('- negates a number variable', () {
      expect(run(r'-$a', r'$a = 3').value, -3);
    });
  });

  group('indexing a string', () {
    test('reads the character at a whole index', () {
      expect(run('"abc"[1]').value, 'b');
      expect(run('"abc"[0]').value, 'a');
    });

    test('is null past the end, below zero or between characters', () {
      expect(run('"abc"[3]').value, isNull);
      expect(run(r'"abc"[$i]', r'$i = -1').value, isNull);
      expect(run('"abc"[1.5]').value, isNull);
    });

    test(
      'a property name reads that property',
      () => expect(run('"abc"["length"]').value, 3),
    );
  });

  group('inline components', () {
    test(r'a $binding prop in an @Each template becomes a binding', () {
      final s = open(
        r'root = Out(@Each(["a", "b"], x, Field($name)))'
        '\n'
        r'$name = "Ana"',
      );
      final fields = s.root!.props.list('value').cast<OpenUiElement>();
      expect(fields.map((e) => e.typeName), ['Field', 'Field']);
      final binding = fields.first.props.binding('bind')!;
      expect(binding.variable, r'$name');
      expect(s.field('', binding).value, 'Ana');
      s.field('', binding).set('Bo');
      expect(s.state[r'$name'], 'Bo');
    });

    test(r'a $binding prop in a ternary branch becomes a binding', () {
      final s = open(
        r'root = Out($on ? Field($name) : Box())'
        '\n'
        r'$on = true'
        '\n'
        r'$name = "Ana"',
      );
      final field = s.root!.props['value'] as OpenUiElement;
      expect(field.typeName, 'Field');
      expect(field.props.binding('bind')!.variable, r'$name');
    });

    test('nested components in an @Each template are fully evaluated', () {
      final s = open(
        'root = Out(@Each(["a", "b"], x, Box(Box(), [Box(), Box()])))',
      );
      final boxes = s.root!.props.list('value').cast<OpenUiElement>();
      expect(boxes, hasLength(2));
      for (final box in boxes) {
        expect(box.props.elements('child').map((e) => e.typeName), ['Box']);
        expect(box.props.elements('kids').map((e) => e.typeName), [
          'Box',
          'Box',
        ]);
      }
    });
  });

  group('@Each templates keep the loop value in deferred steps', () {
    test('a unary expression on the loop variable', () async {
      final s = open(
        r'root = Out(@Each([1, 2], x, Out(x, Action([@Set($neg, -x), @Set($not, !x)]))))'
        '\n'
        r'$neg = 0'
        '\n'
        r'$not = true',
      );
      final second = s.root!.props.list('value')[1] as OpenUiElement;
      expect(second.props['value'], 2);
      await clickAll(s, second.props.action('action'));
      expect(s.state[r'$neg'], -2);
      expect(s.state[r'$not'], false);
    });
  });

  group('Action([...]) with legacy action objects', () {
    test('open_url and continue_conversation objects become steps', () async {
      final s = open(
        'root = Out(1, Action([{type: "open_url", url: "https://x.org"}, '
        '{type: "continue_conversation", message: "hi", context: {id: 4}}]))',
      );
      final events = await clickAll(s, s.root!.props.action('action'));
      expect(
        [for (final e in events) e.type],
        [ActionEvent.openUrl, ActionEvent.continueConversation],
      );
      expect(events[0].params, {'url': 'https://x.org'});
      expect(events[1].humanFriendlyMessage, 'hi');
      expect(events[1].params, {
        'context': {'id': 4},
      });
    });

    test(
      'a continue_conversation object without a message sends an empty one',
      () async {
        final s = open(
          'root = Out(1, Action([{type: "continue_conversation"}]))',
        );
        final events = await clickAll(s, s.root!.props.action('action'));
        expect(events.single.type, ActionEvent.continueConversation);
        expect(events.single.humanFriendlyMessage, '');
        expect(events.single.params, isEmpty);
      },
    );

    test(
      'an object of another type, or an open_url without a url, is dropped',
      () async {
        final s = open(
          'root = Out(1, Action([{type: "bogus"}, {type: "open_url"}, 5, '
          '@OpenUrl("https://y.org")]))',
        );
        final events = await clickAll(s, s.root!.props.action('action'));
        expect(events.map((e) => e.params), [
          {'url': 'https://y.org'},
        ]);
      },
    );

    test('plans nested in the list are flattened in order', () async {
      final s = open(
        'root = Out(1, Action([@OpenUrl("https://a.org"), '
        'Action([@OpenUrl("https://b.org"), @OpenUrl("https://c.org")])]))',
      );
      final events = await clickAll(s, s.root!.props.action('action'));
      expect(
        [for (final e in events) e.params['url']],
        ['https://a.org', 'https://b.org', 'https://c.org'],
      );
    });
  });

  group('built-in @First and @Sort', () {
    test('@First reads the first element of a list', () {
      expect(run('@First([5, 6])').value, 5);
      expect(run('@First([])').value, isNull);
    });

    test('@Sort orders text that is not numeric, ascending or descending', () {
      expect(run('@Sort(["pear", "apple", "fig"], "")').value, [
        'apple',
        'fig',
        'pear',
      ]);
      expect(run('@Sort(["pear", "apple", "fig"], "", "desc")').value, [
        'pear',
        'fig',
        'apple',
      ]);
    });

    test('@Sort orders a text field of objects', () {
      expect(run('@Sort([{n: "b"}, {n: "a"}], "n")').value, [
        {'n': 'a'},
        {'n': 'b'},
      ]);
    });

    test(
      '@Sort orders text the way localeCompare does',
      () => expect(run('@Sort(["b", "B", "a"], "")').value, ['a', 'b', 'B']),
    );
  });
}
