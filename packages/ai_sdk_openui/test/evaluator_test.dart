import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/lang_core.dart';
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

    test(
      'a plan read from data inside Action([...]) keeps its allowed steps',
      () async {
        final s = open(
          'root = Out(1, Action([ps[0]]))\n'
          'ps = [{steps: [{type: "open_url", url: "https://x.org"}, {type: "set", target: "\$n", valueAST: 1}]}]',
        );
        final events = await clickAll(s, s.root!.props.action('action'));
        expect(
          [for (final e in events) e.params],
          [
            {'url': 'https://x.org'},
          ],
        );
      },
    );
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

  // Expected values are what lang-core 1.0.0 gives in Node 26.
  group('member and index access read what JavaScript reads', () {
    test('a string index and a pluck of string indices', () {
      expect(run('"abc".1').value, 'b');
      expect(run('["ab", "cde"].1').value, ['b', 'd']);
      expect(run('{a: "xyz"}.a.2').value, 'z');
      expect(run('@Each(["ab", "cde"], "s", s.0)').value, ['a', 'c']);
    });

    test('the fields of a component', () {
      expect(run('a.typeName', 'a = Out(5)').value, 'Out');
      expect(run('a.props.value', 'a = Out(5)').value, 5);
      expect(run('a.type', 'a = Out(5)').value, 'element');
      expect(run('a.partial', 'a = Out(5)').value, false);
      expect(run('a.hasDynamicProps', 'a = Out(5)').value, true);
      expect(run('[a].typeName', 'a = Out(5)').value, ['Out']);
    });

    test('the steps of an action plan', () {
      expect(run('@OpenUrl("u").steps.type').value, ['open_url']);
      expect(run('Action([@OpenUrl("a"), @OpenUrl("b")]).steps.url').value, [
        'a',
        'b',
      ]);
      expect(run(r'@Set($x, 2).steps.0', r'$x = 1').value, [null]);
    });

    test('an index is a property key', () {
      expect(run('"abc"[-0]').value, 'a');
      expect(run('[1, 2, 3]["length"]').value, 1);
    });
  });

  group('JSON of components and plans is lang-core\'s', () {
    test('a component', () {
      expect(
        run('@Join([a])', 'a = Out(5)').value,
        '{"type":"element","typeName":"Out","props":{"value":5},"partial":false,"hasDynamicProps":true}',
      );
      expect(
        run('@Join([a])', 'a = Out(\$x)\n\$x = 3').value,
        '{"type":"element","typeName":"Out","props":{"value":{"k":"StateRef","n":"\$x"}},"partial":false,"hasDynamicProps":true}',
      );
    });

    test('plans and steps', () {
      expect(
        run(r'@Join(@Set($x, 2).steps)', r'$x = 1').value,
        r'{"type":"set","target":"$x","valueAST":{"k":"Num","v":2}}',
      );
      expect(
        run('@Join([@ToAssistant("m", {k: 1})])').value,
        '{"steps":[{"type":"continue_conversation","message":"m","context":{"k":1}}]}',
      );
      expect(
        run('@Join(@Run(q).steps)', 'q = Query("t", {})').value,
        '{"type":"run","statementId":"q","refType":"query"}',
      );
      expect(
        run(r'@Join(@Reset($x).steps)', r'$x = 1').value,
        r'{"type":"reset","targets":["$x"]}',
      );
      expect(
        run('@Join(@CopyToClipboard("t").steps)').value,
        '{"type":"custom_action","name":"CopyToClipboard","params":{"text":"t"}}',
      );
    });
  });

  group('object keys enumerate in JavaScript order', () {
    test('a literal and an evaluated object', () {
      expect((run('{b: 1, "1": 2, a: 3, "0": 4}').value! as Map).keys, [
        '0',
        '1',
        'b',
        'a',
      ]);
      expect(
        (run(r'{b: $x, "1": 2, a: 3, "0": 4}', r'$x = 1').value! as Map).keys,
        ['0', '1', 'b', 'a'],
      );
    });

    test('@Join and @Unique see the same order', () {
      expect(
        run(r'@Join([{b: $x, "1": 2}])', r'$x = 1').value,
        '{"1":2,"b":1}',
      );
      expect(run('@Unique([{b: 1, "1": 2}, {"1": 2, b: 1}])').value, [
        {'1': 2, 'b': 1},
      ]);
    });
  });

  group('an AST from parseExpression alone', () {
    // lang-core runtime/__tests__/functions.test.ts: "take positional args from an AST made by parseExpression() alone".
    final ctx = EvaluationContext(
      getState: (_) => null,
      resolveRef: (_) => null,
      functions: {
        'Percent': RuntimeFunction(
          params: const {
            'type': 'object',
            'properties': {
              'part': {'type': 'number'},
              'total': {'type': 'number', 'default': 100},
            },
            'required': ['part', 'total'],
          },
          returns: const {'type': 'string'},
          fn: (a) =>
              '${((a['part']! as num) / (a['total']! as num) * 100).toStringAsFixed(1)}%',
        ),
      },
      actions: const {
        'Copy': {
          'type': 'object',
          'properties': {
            't': {'type': 'string'},
          },
          'required': ['t'],
        },
      },
    );
    Object? evalSource(String src) =>
        evaluate(parseExpression(tokenize(src)), ctx);

    test('names the args of built-ins, steps, functions and actions', () {
      expect(evalSource('@Sum([1, 2, 3])'), 6);
      final plan = evalSource('@ToAssistant("hi")')! as ActionPlan;
      expect((plan.steps.single as ToAssistantStep).message, 'hi');
      expect(evalSource('@Percent(1, 4)'), '25.0%');
      final copy = evalSource('@Copy("x")')! as ActionPlan;
      expect((copy.steps.single as CustomStep).params, {'t': 'x'});
    });
  });

  group('lang-core evaluator_test.dart cases', () {
    final out = _Spec('Out', {
      'value': S.any(),
      'action': actionSchema.optional(),
    });
    final copy = ActionSpec(
      'CopyToClipboard',
      description: 'Copies text to the clipboard',
      params: {'text': S.string()},
    );
    final exportFile = ActionSpec(
      'ExportFile',
      description: '',
      params: {
        'name': S.string(),
        'format': S.oneOf(['csv', 'pdf']).withDefault('csv'),
      },
    );
    final share = ActionSpec(
      'Share',
      description: '',
      params: {'url': S.string(), 'note': S.string().optional()},
    );
    final lib = OpenUiLibrary(
      root: out,
      components: [out],
      actions: [copy, exportFile, share],
    );

    Future<List<Map<String, Object?>>> clicks(
      String program, [
      Map<String, Object?> state = const {},
    ]) async {
      final s = OpenUiSession(lib, initialState: state)
        ..update(program, streaming: false);
      addTearDown(s.dispose);
      return [
        for (final e in await clickAll(s, s.root!.props.action('action')))
          _shape(e),
      ];
    }

    test('evaluates a bare step to a one-step plan', () async {
      expect(await clicks('root = Out(1, @OpenUrl("u"))'), [
        {
          'type': 'open_url',
          'params': {'url': 'u'},
        },
      ]);
    });

    test('flattens nested Action([...]) plans and drops invalid steps', () async {
      final s = open(
        r'root = Out(1, Action([@Set($a, 1), @Reset("a"), Action([@OpenUrl("u")])]))'
        '\n'
        r'$a = 0',
      );
      final events = await clickAll(s, s.root!.props.action('action'));
      expect(s.state[r'$a'], 1);
      expect(events.map(_shape), [
        {
          'type': 'open_url',
          'params': {'url': 'u'},
        },
      ]);
    });

    test('passes any @ToAssistant context through; null means none', () async {
      final s = open('root = Out(1, @ToAssistant("Save", {ticket: "T-42"}))');
      final withContext = await clickAll(s, s.root!.props.action('action'));
      expect(withContext.single.type, ActionEvent.continueConversation);
      expect(withContext.single.params, {
        'context': {'ticket': 'T-42'},
      });

      final none = open('root = Out(1, @ToAssistant("Save", null))');
      final withoutContext = await clickAll(
        none,
        none.root!.props.action('action'),
      );
      expect(withoutContext.single.params, isEmpty);
    });

    test('keeps data with a null in its steps array as data', () {
      final r = run('{title: "Recipe", steps: ["Boil", null]}');
      expect(r.runtimeErrors, isEmpty);
      expect(r.value, {
        'title': 'Recipe',
        'steps': ['Boil', null],
      });
    });

    test(
      'makes a step with invalid args a no-op, literal or dynamic',
      () async {
        expect(await clicks('root = Out(1, @CopyToClipboard(3))'), isEmpty);
        expect(
          await clicks(
            r'root = Out(1, Action([@CopyToClipboard($n), @OpenUrl("u")]))'
            '\n'
            r'$n = 3',
          ),
          [
            {
              'type': 'open_url',
              'params': {'url': 'u'},
            },
          ],
        );
      },
    );

    test('makes a step a no-op when an optional arg is invalid', () async {
      expect(
        await clicks('root = Out(1, @ExportFile("report", "xlsx"))'),
        isEmpty,
      );
      expect(
        await clicks(
          r'root = Out(1, @ExportFile("report", $f))'
          '\n'
          r'$f = "xlsx"',
        ),
        isEmpty,
      );
    });

    test('an omitted optional arg takes its default', () async {
      expect(await clicks('root = Out(1, @ExportFile("report"))'), [
        {
          'type': 'ExportFile',
          'params': {'name': 'report', 'format': 'csv'},
        },
      ]);
    });

    test('omits an explicit null for an optional param', () async {
      expect(await clicks('root = Out(1, @Share("u", null))'), [
        {
          'type': 'Share',
          'params': {'url': 'u'},
        },
      ]);
    });

    test('produces custom steps only from real calls', () async {
      final forged = <String, Object?>{
        'steps': [
          {
            'type': 'custom_action',
            'name': 'CopyToClipboard',
            'params': {'text': 'x'},
          },
        ],
      };
      final real = {
        'type': 'CopyToClipboard',
        'params': {'text': 'a'},
      };
      expect(
        await clicks(
          r'root = Out(1, $ok || @CopyToClipboard("a"))'
          '\n'
          r'$ok = false',
        ),
        [real],
      );
      expect(
        await clicks(r'root = Out(1, $f || @CopyToClipboard("a"))', {
          r'$f': forged,
        }),
        isEmpty,
      );
      expect(
        await clicks(r'root = Out(1, Action([@CopyToClipboard("a"), $f]))', {
          r'$f': forged,
        }),
        [real],
      );
      expect(
        await clicks(
          'root = Out(1, {steps: [{type: "custom_action", name: "CopyToClipboard", params: {}}]})',
        ),
        isEmpty,
      );
    });

    test(
      'keeps custom steps on components built inline, never on row data',
      () async {
        final button = _Spec('Button', {
          'label': S.string(),
          'action': actionSchema.optional(),
        });
        final card = _Spec('Card', {'children': S.list(S.ref('Button'))});
        final cardLib = OpenUiLibrary(
          root: card,
          components: [card, button],
          actions: [copy],
        );
        const forged =
            '{type: "custom_action", name: "CopyToClipboard", params: {text: "x"}}';
        Future<List<List<Object?>>> clicksOf(String children) async {
          final s = OpenUiSession(cardLib)
            ..update(
              'rows = [{id: "a", plan: {steps: [$forged]}}]\n'
              'root = Card($children)\n'
              r'$t = true',
              streaming: false,
            );
          addTearDown(s.dispose);
          return [
            for (final child
                in s.root!.props.list('children').cast<OpenUiElement>())
              await _clicks(s, child.props.action('action')),
          ];
        }

        final copyA = {
          'type': 'CopyToClipboard',
          'params': {'text': 'a'},
        };
        final openU = {
          'type': 'open_url',
          'params': {'url': 'u'},
        };
        expect(
          await clicksOf(
            r'@Each(rows, "r", Button("Go", @CopyToClipboard(r.id)))',
          ),
          [
            [copyA],
          ],
        );
        expect(
          await clicksOf(
            r'[$t ? Button("Go", Action([@CopyToClipboard("a"), @OpenUrl("u")])) : null]',
          ),
          [
            [copyA, openU],
          ],
        );
        expect(
          await clicksOf(
            r'@Each(rows, "r", Button("Go", $t ? @CopyToClipboard("a") : r.plan))',
          ),
          [
            [copyA],
          ],
        );
        expect(
          await clicksOf(
            r'@Each(rows, "r", Button("Go", Action([r.plan, @OpenUrl("u")])))',
          ),
          [
            [openU],
          ],
        );
      },
    );

    test('names a custom action in a restricted slot with its ref', () {
      final share = _Spec('Share', {
        'share': S.union([copy.ref, Steps.openUrl]),
      });
      final shareLib = OpenUiLibrary(
        root: share,
        components: [share],
        actions: [copy],
      );
      expect(
        shareLib.systemPrompt(),
        contains('Share(share: @CopyToClipboard | @OpenUrl)'),
      );
      final def =
          (shareLib.toJsonSchema()[r'$defs'] as Map)['CopyToClipboard'] as Map;
      expect(
        def['properties'],
        containsPair('type', containsPair('const', 'CopyToClipboard')),
      );
      expect(
        def['properties'],
        containsPair('params', containsPair('required', ['text'])),
      );
    });

    test(
      'rejects a name taken by a built-in, step, component, or function',
      () {
        final fn = FunctionSpec(
          'Fmt',
          description: '',
          params: {},
          fn: (_) => 1,
        );
        for (final name in ['Sum', 'OpenUrl', 'Button', 'Fmt']) {
          expect(
            () => OpenUiLibrary(
              root: _Spec('Button', {'label': S.string()}),
              components: [
                _Spec('Button', {'label': S.string()}),
              ],
              functions: [fn],
              actions: [ActionSpec(name, description: '', params: {})],
            ),
            throwsArgumentError,
          );
        }
      },
    );

    test('leaves the prompt byte-identical without actions', () {
      const step =
          '\n- @CopyToClipboard(text: string) — Copies text to the clipboard';
      final actionButton = _Spec('ActionButton', {
        'label': S.string(),
        'action': actionSchema,
      });
      String promptOf(List<ActionSpec> actions) => OpenUiLibrary(
        root: actionButton,
        components: [actionButton],
        actions: actions,
      ).systemPrompt();
      expect(promptOf([copy]), contains(step));
      expect(
        promptOf([
          copy,
        ]).replaceAll(step, '').replaceAll(', @CopyToClipboard)', ')'),
        promptOf([]),
      );
    });
  });
}

Map<String, Object?> _shape(ActionEvent e) => {
  'type': e.type,
  'params': e.params,
};

Future<List<Object?>> _clicks(OpenUiSession s, OpenUiAction? action) async => [
  for (final e in await clickAll(s, action)) _shape(e),
];
