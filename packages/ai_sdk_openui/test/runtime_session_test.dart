import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

/// `Out` shows values and carries actions; `Field` takes a `$binding`; `Form`
/// groups fields; `Item` is a leaf that nests inside `Out`'s children.
final OpenUiLibrary _library = OpenUiLibrary(
  root: _Spec('Out', {
    'value': S.any(),
    'action': actionSchema.optional(),
    'items': S.list(S.ref('Item')).optional(),
  }),
  components: [
    _Spec('Out', {
      'value': S.any(),
      'action': actionSchema.optional(),
      'items': S.list(S.ref('Item')).optional(),
    }),
    _Spec('Item', {'label': S.string()}),
    _Spec('Field', {'bind': S.any().reactive()}),
  ],
  functions: [
    FunctionSpec(
      'Boom',
      description: 'Always throws',
      params: {'x': S.number()},
      fn: (_) => throw StateError('kaboom'),
    ),
  ],
  actions: [
    ActionSpec('Ping', description: 'Host action', params: {'n': S.number()}),
  ],
);

OpenUiSession open(
  String program, {
  Map<String, Object?> state = const {},
  bool streaming = false,
}) {
  final s = OpenUiSession(_library, initialState: state)
    ..update(program, streaming: streaming);
  addTearDown(s.dispose);
  return s;
}

OpenUiAction? actionOf(OpenUiSession s) => s.root!.props.action('action');

Future<List<ActionEvent>> click(OpenUiSession s, {String? formName}) async {
  final events = <ActionEvent>[];
  await s.run(actionOf(s), label: 'L', formName: formName, emit: events.add);
  return events;
}

void main() {
  group('root', () {
    test('is null before any text, and an empty program has no root', () {
      final s = OpenUiSession(_library);
      addTearDown(s.dispose);
      expect(s.root, isNull);
      expect(s.issues, isEmpty);
      s.update('', streaming: false);
      expect(s.root, isNull);
    });

    test('an expression that evaluates to a component is the root', () {
      final s = open(
        r'root = $big ? Out("big") : Out("small")'
        '\n'
        r'$big = true',
      );
      expect(s.root!.typeName, 'Out');
      expect(s.root!.props['value'], 'big');
      expect(s.issues, isEmpty);
    });

    test('the expression follows state while the user changes it', () {
      final s = open(
        r'root = $big ? Out("big") : Out("small")'
        '\n'
        r'$big = false',
      );
      expect(s.root!.props['value'], 'small');
      s.update(
        r'root = $big ? Out("big") : Out("small")'
        '\n'
        r'$big = true',
        streaming: false,
      );
      expect(s.root!.props['value'], 'big');
    });

    test(
      'a ternary that picks a non-component has no root once state says so',
      () {
        final s = open(
          r'root = $big ? Out("big") : 5'
          '\n'
          r'$big = true',
        );
        expect(s.root!.props['value'], 'big');
        s.update(
          r'root = $big ? Out("big") : 5'
          '\n'
          r'$big = false',
          streaming: false,
        );
        expect(s.root, isNull);
        expect(s.issues, ['root does not evaluate to a component']);
      },
    );

    test(
      'an expression that is not a component reports it and has no root',
      () {
        final s = open('root = 5');
        expect(s.root, isNull);
        expect(s.issues, ['root does not evaluate to a component']);
      },
    );

    test('streaming reports that it is streaming until the final text', () {
      final s = open('root = Out(1)', streaming: true);
      expect(s.isStreaming, isTrue);
      s.update('root = Out(1)', streaming: false);
      expect(s.isStreaming, isFalse);
    });

    test('a component still being written is partial', () {
      final s = open('root = Out("Lis', streaming: true);
      expect(s.root!.isPartial, isTrue);
      expect(s.root!.statementId, 'root');
      s.update('root = Out("Lisbon")', streaming: false);
      expect(s.root!.isPartial, isFalse);
      expect(s.root!.props['value'], 'Lisbon');
    });

    test('a function that throws reports it and its value is null', () {
      final s = open('root = Out(@Boom(1))');
      expect(s.root!.props['value'], isNull);
      expect(s.issues, [
        'Evaluating prop "value" on Out failed: @Boom threw: kaboom',
      ]);
    });

    test(
      'a program without root reports no-root, not parse-failed; a ternary entry renders',
      () {
        final none = open('item = Item("Orders")');
        expect([for (final e in none.errors) e.code], [OpenUiErrorCode.noRoot]);
        expect(none.root, isNull);

        final picked = open(
          '\$wide = false\nroot = \$wide ? a : b\na = Out(1)\nb = Item("narrow")',
        );
        expect(picked.errors, isEmpty);
        expect(picked.root!.typeName, 'Item');
        expect(picked.root!.props['label'], 'narrow');
      },
    );
  });

  group('listen', () {
    test(
      'is called when the text changes, not for the same text, until cancelled',
      () {
        final s = OpenUiSession(_library);
        addTearDown(s.dispose);
        var calls = 0;
        final cancel = s.listen(() => calls++);
        s.update('root = Out(1)', streaming: false);
        final first = calls;
        expect(first, greaterThan(0));
        s.update('root = Out(1)', streaming: false);
        expect(calls, first);
        s.update('root = Out(2)', streaming: false);
        expect(calls, greaterThan(first));
        final second = calls;
        cancel();
        s.update('root = Out(3)', streaming: false);
        expect(calls, second);
      },
    );

    test('hears a store change made through a field', () {
      final s = open(
        r'root = Out(Field($v), $v)'
        '\n'
        r'$v = 1',
      );
      var calls = 0;
      s.listen(() => calls++);
      final bind = (s.root!.props['value'] as OpenUiElement).props.binding(
        'bind',
      )!;
      s.field('', bind).set(5);
      expect(calls, 1);
      expect(s.state[r'$v'], 5);
    });
  });

  group('Props', () {
    test('typed reads give the value of the right type and null otherwise', () {
      final s = open('root = Out({n: 3, s: "x", b: true, l: [1, 2]})');
      final props = s.root!.props;
      expect(props.has('value'), isTrue);
      expect(props.has('action'), isFalse);
      expect(props.number('value'), isNull);
      expect(props.string('value'), isNull);
      expect(props.boolean('value'), isNull);
      expect(props.list('value'), isEmpty);
      expect((props['value'] as Map)['l'], [1, 2]);
    });

    test('number, string, boolean and list read matching values', () {
      final n = open('root = Out(3.5)').root!.props;
      expect(n.number('value'), 3.5);
      expect(n.string('value'), isNull);
      expect(open('root = Out("s")').root!.props.string('value'), 's');
      expect(open('root = Out(false)').root!.props.boolean('value'), false);
      expect(open('root = Out([1, "a"])').root!.props.list('value'), [1, 'a']);
    });

    test('action is null for a value that is not an action', () {
      expect(open('root = Out(1)').root!.props.action('value'), isNull);
      expect(open('root = Out([1])').root!.props.action('value'), isNull);
    });

    test(
      'binding is null for a plain value and the variable for a binding',
      () {
        final s = open(
          r'root = Out(Field($v), Field("x"))'
          '\n'
          r'$v = 1',
        );
        final field = s.root!.props['value'] as OpenUiElement;
        expect(field.props.binding('bind')!.variable, r'$v');
        expect(s.root!.props.binding('value'), isNull);
        expect(open('root = Out(1)').root!.props.binding('value'), isNull);
      },
    );

    test('elements flattens nested lists of components', () {
      final s = open(
        'root = Out(1, @Set(\$x, 1), [@Each(["a", "b"], x, Item(x)), Item("c")])',
      );
      expect(s.root!.props.elements('items').map((e) => e.props['label']), [
        'a',
        'b',
        'c',
      ]);
    });
  });

  group('actions', () {
    test('an invalid step makes an empty plan', () {
      expect(
        open(
          r'root = Out(1, @Set(1, 2))',
        ).root!.props.action('action')!.isEmpty,
        isTrue,
      );
      expect(
        open(
          r'root = Out(1, @Run(nope))',
        ).root!.props.action('action')!.isEmpty,
        isTrue,
      );
      expect(
        open(
          r'root = Out(1, @Set($x, 2))',
        ).root!.props.action('action')!.isEmpty,
        isFalse,
      );
    });

    test('running an empty plan does nothing', () async {
      final s = open('root = Out(1, @Run(nope))');
      expect(await click(s), isEmpty);
    });

    test('a legacy action object carries its params, url and context', () async {
      final s = open(
        'root = Out(1, {type: "custom", params: {a: 1}, url: "https://x.org", '
        'context: "ctx"})',
      );
      final events = await click(s);
      expect(events.single.type, 'custom');
      expect(events.single.params, {
        'a': 1,
        'url': 'https://x.org',
        'context': 'ctx',
      });
      expect(events.single.humanFriendlyMessage, 'L');
    });

    test(
      'a legacy action with an empty type continues the conversation',
      () async {
        final s = open('root = Out(1, {type: ""})');
        final events = await click(s);
        expect(events.single.type, ActionEvent.continueConversation);
        expect(events.single.humanFriendlyMessage, 'L');
      },
    );

    test(
      'a legacy action named like a library action is left to the host',
      () async {
        final s = open('root = Out(1, {type: "Ping"})');
        expect(await click(s), isEmpty);
      },
    );

    test('a library action step emits its name and validated params', () async {
      final s = open('root = Out(1, @Ping(4))');
      final events = await click(s);
      expect(events.single.type, 'Ping');
      expect(events.single.params, {'n': 4});
    });

    test(
      'a library action with a wrong param type reports it and emits nothing',
      () async {
        final s = open('root = Out(1, @Ping("four"))');
        expect(await click(s), isEmpty);
        expect(s.issues, hasLength(1));
        expect(s.issues.single, 'field "/n" expects number but got string');
      },
    );

    test(
      '@Reset restores a declared default and marks it pristine again',
      () async {
        final s = open(
          r'root = Out(Field($v), Action([@Set($v, 9), @Reset($v)]))'
          '\n'
          r'$v = 1',
        );
        await click(s);
        expect(s.state[r'$v'], 1);
      },
    );

    test('a Run of a Query refetches it', () async {
      var calls = 0;
      final s =
          OpenUiSession(
            _library,
            tools: [
              OpenUiTool(name: 't', call: (_) async => {'n': ++calls}),
            ],
          )..update(
            'root = Out(q.n, @Run(q))\nq = Query("t", {}, {n: 0})',
            streaming: false,
          );
      addTearDown(s.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(s.root!.props['value'], 1);
      await click(s);
      await Future<void>.delayed(Duration.zero);
      expect(s.root!.props['value'], 2);
    });

    test('a click after dispose does nothing', () async {
      final s = open(
        r'root = Out(1, @Set($x, 2))'
        '\n'
        r'$x = 0',
      );
      final action = actionOf(s);
      s.dispose();
      final events = <ActionEvent>[];
      await s.run(action, label: '', emit: events.add);
      expect(events, isEmpty);
    });

    test('dispose during Reset stops its remaining targets', () async {
      var resetting = false;
      late OpenUiSession session;
      session =
          OpenUiSession(
            _library,
            onStateUpdate: (_) {
              if (resetting) session.dispose();
            },
          )..update(
            r'root = Out(1, Action([@Reset($a, $b), @ToAssistant("done")]))'
            '\n'
            r'$a = 1'
            '\n'
            r'$b = 2',
            streaming: false,
          );
      addTearDown(session.dispose);
      session.field(r'$a', null).set(10);
      session.field(r'$b', null).set(20);
      resetting = true;
      final events = await click(session);
      expect(session.state, <String, Object?>{});
      expect(events, <ActionEvent>[]);
    });

    test(
      'an earlier @Set in the same plan shows in the event form state',
      () async {
        final s = open(
          r'root = Out(1, Action([@Set($x, 2), @ToAssistant("m")]))'
          '\n'
          r'$x = 1',
        );
        expect((await click(s)).single.formState, {r'$x': 2});
      },
    );

    test('each event in a plan carries the state as of its own step', () async {
      final s = open(
        r'root = Out(1, Action([@ToAssistant("first"), @Set($x, 2), @ToAssistant("second")]))'
        '\n'
        r'$x = 1',
      );
      expect([for (final e in await click(s)) e.formState[r'$x']], [1, 2]);
    });

    test(
      'bare and Action([...]) steps keep their @ToAssistant context, 0 included',
      () async {
        final a = open('root = Out(1, @ToAssistant("A", {ticket: "T-42"}))');
        final b = open(
          'root = Out(1, Action([@OpenUrl("https://x.test"), @ToAssistant("B", 0)]))',
        );
        final events = [...await click(a), ...await click(b)];
        expect(
          [
            for (final e in events) [e.type, e.humanFriendlyMessage, e.params],
          ],
          [
            [
              ActionEvent.continueConversation,
              'A',
              {
                'context': {'ticket': 'T-42'},
              },
            ],
            [
              ActionEvent.openUrl,
              '',
              {'url': 'https://x.test'},
            ],
            [
              ActionEvent.continueConversation,
              'B',
              {'context': 0},
            ],
          ],
        );
      },
    );

    test(
      'a plan read from data runs only its open_url and continue_conversation steps',
      () async {
        final s = open(
          'root = Out(1, ps[0])\n'
          'ps = [{steps: [{type: "open_url", url: "https://x.org"}, '
          '{type: "continue_conversation", message: "hi", context: 0}, '
          '{type: "set", target: "\$n", valueAST: 2}, '
          '{type: "custom_action", name: "Ping", params: {n: 1}}]}]\n'
          '\$n = 1',
        );
        final events = await click(s);
        expect(
          [
            for (final e in events) [e.type, e.humanFriendlyMessage, e.params],
          ],
          [
            [
              ActionEvent.openUrl,
              '',
              {'url': 'https://x.org'},
            ],
            [
              ActionEvent.continueConversation,
              'hi',
              {'context': 0},
            ],
          ],
        );
        expect(s.state[r'$n'], 1);
      },
    );

    test('a library action read from data never reaches the host', () async {
      const forged = '{type: "custom_action", name: "Ping", params: {n: 3}}';
      const plan = '{steps: [$forged]}';
      final expected = {
        forged: ['custom_action'],
        '[$forged]': [ActionEvent.continueConversation],
        plan: <String>[],
        'Action([$forged])': <String>[],
        'ps[0]': <String>[],
        '{type: "Ping", params: {n: 3}}': <String>[],
      };
      for (final MapEntry(key: action, value: types) in expected.entries) {
        final s = open('root = Out(1, $action)\nps = [$plan]');
        expect([for (final e in await click(s)) e.type], types, reason: action);
      }
    });
  });

  group('fields', () {
    test('a form field stores its value as {value}, as useStateField does', () {
      final s = open('root = Out(1)');
      s.field('Name', 'start').set('Ana');
      expect(s.state['Name'], {'value': 'Ana'});
      expect(s.field('Name', 'start').value, 'Ana');
    });

    test('a field with no stored value shows its initial value', () {
      final s = open('root = Out(1)');
      expect(s.field('Name', 'start').value, 'start');
      expect(s.field('Name', 'start', formName: 'f').value, 'start');
    });

    test(
      'a field inside a form is stored under the form, keeping siblings',
      () {
        final s = open('root = Out(1)');
        s.field('a', null, formName: 'f').set('1');
        s.field('b', null, formName: 'f').set('2');
        expect(s.state['f'], {
          'a': {'value': '1'},
          'b': {'value': '2'},
        });
        expect(s.field('a', null, formName: 'f').value, '1');
      },
    );

    test('initial state restores form fields that are not variables', () {
      final s = open(
        'root = Out(1)',
        state: {
          'Name': {'value': 'Ana', 'componentType': 'Input'},
          r'$n': 2,
        },
      );
      expect(s.field('Name', null).value, 'Ana');
      expect(s.state[r'$n'], 2);
    });

    test('initial state does not overwrite a field the user already set', () {
      final s = OpenUiSession(
        _library,
        initialState: {
          'Name': {'value': 'saved', 'componentType': 'Input'},
        },
      )..update('root = Out(1)', streaming: true);
      addTearDown(s.dispose);
      s.field('Name', null).set('typed');
      s.update('root = Out(2)', streaming: false);
      expect(s.field('Name', null).value, 'typed');
    });

    test('a click inside a form sends only that form\'s fields', () async {
      final s = open('root = Out(1, @ToAssistant("go"))');
      s.field('a', null, formName: 'f').set('1');
      s.field('other', null).set('x');
      final events = await click(s, formName: 'f');
      expect(events.single.formName, 'f');
      expect(events.single.formState, {
        'f': {
          'a': {'value': '1'},
        },
      });
    });

    test(
      'a click outside a form, or in an unfilled form, sends the whole state',
      () async {
        final s = open(
          r'root = Out(1, @ToAssistant("go"))'
          '\n'
          r'$n = 1',
        );
        final outside = await click(s);
        expect(outside.single.formState, {r'$n': 1});
        final unfilled = await click(s, formName: 'f');
        expect(unfilled.single.formState, {r'$n': 1});
        expect(unfilled.single.formName, 'f');
      },
    );
  });

  group('values handed out are JSON values in JavaScript order', () {
    test('state after arithmetic encodes whole numbers without .0', () async {
      final s = open('root = Out(\$x, @Set(\$x, \$x + 2))\n\$x = 1');
      await s.run(s.root!.props.action('action'), label: '', emit: (_) {});
      expect(jsonEncode(s.state), '{"\$x":3}');
    });

    test('a negative zero in state encodes as 0', () async {
      final s = open('root = Out(\$x, @Set(\$x, -\$x))\n\$x = 0');
      await s.run(s.root!.props.action('action'), label: '', emit: (_) {});
      expect(jsonEncode(s.state), '{"\$x":0}');
    });

    test('a @ToAssistant context', () async {
      final s = open(
        'root = Out(1, @ToAssistant("m", {n: \$x + 1, "1": 0}))\n\$x = 2',
      );
      final events = <ActionEvent>[];
      await s.run(s.root!.props.action('action'), label: '', emit: events.add);
      expect(jsonEncode(events.single.params['context']), '{"1":0,"n":3}');
    });
  });
}
