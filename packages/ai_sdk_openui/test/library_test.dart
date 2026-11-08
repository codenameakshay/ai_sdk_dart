import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/lang_core.dart';
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props, [this.description = '']);
  @override
  final String typeName;
  @override
  final Map<String, Schema> props;
  @override
  final String description;
}

final _missing = {'body': S.ref('Missing')};

final _card = _Spec('Card', {
  'title': S.string(),
  'count': S.number().optional(),
}, 'A card');

OpenUiLibrary _library({
  List<FunctionSpec> functions = const [],
  List<ActionSpec> actions = const [],
}) => OpenUiLibrary(
  root: _card,
  components: [_card],
  functions: functions,
  actions: actions,
);

FunctionSpec _fn(String name, [Map<String, Schema>? params]) => FunctionSpec(
  name,
  description: 'd',
  params: params ?? {'n': S.number()},
  fn: (a) => a['n'],
);

void main() {
  group('a library rejects names that cannot work', () {
    test('a root outside the component list', () {
      expect(
        () => OpenUiLibrary(root: const _Spec('Page', {}), components: [_card]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'Root component "Page" is not in components.',
          ),
        ),
      );
    });

    test('a function named like a built-in', () {
      expect(
        () => _library(functions: [_fn('Count')]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '"Count" collides with a built-in, component, function or action.',
          ),
        ),
      );
    });

    test('a function named like a component', () {
      expect(
        () => _library(functions: [_fn('Card')]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '"Card" collides with a built-in, component, function or action.',
          ),
        ),
      );
    });

    test('an action named like a function', () {
      expect(
        () => _library(
          functions: [_fn('Copy')],
          actions: [ActionSpec('Copy', description: 'd', params: {})],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            '"Copy" collides with a built-in, component, function or action.',
          ),
        ),
      );
    });

    test('a function named like Query', () {
      expect(
        () => _library(functions: [_fn('Query')]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('the JSON schema rejects references that cannot resolve', () {
    test('a prop that references a missing component', () {
      final lib = OpenUiLibrary(
        root: _Spec('Page', _missing),
        components: [_Spec('Page', _missing)],
      );
      expect(
        lib.toJsonSchema,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'No component "Missing" to reference.',
          ),
        ),
      );
    });

    test('a function param that references a component', () {
      final lib = _library(
        functions: [
          _fn('Show', {'card': S.ref('Card')}),
        ],
      );
      expect(
        lib.toJsonSchema,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Call schemas cannot reference "Card".',
          ),
        ),
      );
    });
  });

  group('parse reports what a server needs', () {
    final lib = _library();

    test('a clean program', () {
      final report = lib.parse('root = Card("hi", 2)');
      expect(report.isClean, isTrue);
      expect(report.hasRoot, isTrue);
      expect(report.errors, isEmpty);
      expect(report.warnings, isEmpty);
      expect(report.unresolved, isEmpty);
      expect(report.orphaned, isEmpty);
    });

    test('a missing root statement falls back with a warning', () {
      final report = lib.parse('page = Card("hi")');
      expect(report.hasRoot, isTrue);
      expect(report.errors, isEmpty);
      expect(report.warnings, [
        'No root statement. Rendering the first statement that calls the root component Card',
      ]);
      expect(report.isClean, isFalse);
    });

    test('an unreferenced statement is orphaned', () {
      final report = lib.parse('root = Card("hi")\nextra = Card("x")');
      expect(report.orphaned, ['extra']);
      expect(report.isClean, isFalse);
    });

    test('no program at all has no root', () {
      final report = lib.parse('');
      expect(report.hasRoot, isFalse);
      expect(report.isClean, isFalse);
    });
  });

  group('lang-core library.test.ts cases', () {
    test(
      'action slots are ActionExpression or restricted @Name refs in JSON',
      () {
        final button = _Spec('Button', {
          'label': S.string(),
          'action': actionSchema.optional(),
          'share': S.union([Steps.toAssistant, Steps.openUrl]).optional(),
        }, 'A button');
        final lib = OpenUiLibrary(root: button, components: [button]);
        expect(
          lib.systemPrompt(),
          contains(
            'action?: ActionExpression, share?: @ToAssistant | @OpenUrl)',
          ),
        );
        expect(
          lib.systemPrompt(),
          contains('Put several steps in Action([...])'),
        );
        final schema = lib.toJsonSchema();
        final buttonDef = (schema[r'$defs'] as Map)['Button'] as Map;
        expect((buttonDef['properties'] as Map)['action'], {
          r'$ref': r'#/$defs/ActionExpression',
        });
        final parsed = createParser(schema, rootName: 'Button').parse(
          'root = Button("x", {type: "continue_conversation", context: "x"})',
        );
        expect(parsed.meta.errors, isEmpty);
      },
    );

    test('toJsonSchema produces \$defs with \$ref pointers', () {
      final text = _Spec('TextContent', {'text': S.string()}, 'text');
      final card = _Spec('Card', {
        'title': S.string(),
        'children': S.list(S.union([S.ref('TextContent')])),
      }, 'card');
      final defs =
          OpenUiLibrary(
                root: card,
                components: [text, card],
              ).toJsonSchema()[r'$defs']
              as Map;
      expect(
        ((defs['TextContent'] as Map)['properties'] as Map)['text'],
        isNotNull,
      );
      expect(((defs['Card'] as Map)['properties'] as Map)['title'], isNotNull);
      expect(jsonEncode(defs['Card']), contains(r'#/$defs/TextContent'));
    });

    test('toSpec carries the library JSON schema alongside signatures', () {
      final text = _Spec('TextContent', {'text': S.string()}, 'text');
      final card = _Spec('Card', {'title': S.string()}, 'card');
      final lib = OpenUiLibrary(
        root: card,
        components: [text, card],
        groups: [
          ComponentGroup('Content', [text]),
        ],
      );
      final spec = lib.toSpec();
      expect(spec['root'], 'Card');
      expect(
        ((spec['components'] as Map)['Card'] as Map)['signature'],
        contains('title'),
      );
      expect(spec['componentGroups'], [
        {
          'name': 'Content',
          'components': ['TextContent'],
        },
      ]);
      expect(spec['schema'], lib.toJsonSchema());
    });

    test('toSpec carries the library id, omitted when unset', () {
      final text = _Spec('TextContent', {'text': S.string()}, 'text');
      final named = OpenUiLibrary(
        root: text,
        components: [text],
        id: 'acme-support@3',
      );
      expect(named.id, 'acme-support@3');
      expect(named.toSpec()['id'], 'acme-support@3');
      final anonymous = OpenUiLibrary(root: text, components: [text]);
      expect(anonymous.id, isNull);
      expect(anonymous.toSpec().containsKey('id'), isFalse);
    });

    test('toJsonSchema carries component descriptions on \$defs entries', () {
      final text = _Spec('TextContent', {
        'text': S.string(),
      }, 'Plain text content');
      final lib = OpenUiLibrary(root: text, components: [text]);
      expect(
        ((lib.toJsonSchema()[r'$defs'] as Map)['TextContent']
            as Map)['description'],
        'Plain text content',
      );
    });

    test('a component ref resolves its name even when not in this library', () {
      final card = _Spec('Card', {
        'children': S.list(S.union([S.ref('TextContent')])),
      }, 'card');
      final lib = OpenUiLibrary(root: card, components: [card]);
      expect(lib.systemPrompt(), contains('TextContent'));
      expect(lib.systemPrompt(), isNot(contains('children: any')));
    });
  });

  group('lang-core functions.test.ts cases', () {
    final text = _Spec('Text', {'value': S.any()}, 'Shows a value');
    final percent = FunctionSpec(
      'Percent',
      description: 'Formats part / total as a percentage',
      params: {'part': S.number(), 'total': S.number().optional()},
      returns: S.string(),
      fn: (a) =>
          '${((a['part']! as num) / ((a['total'] as num?) ?? 100) * 100).toStringAsFixed(1)}%',
    );
    final sum2 = FunctionSpec(
      'Sum2',
      description: 'Sums numbers, with an optional label',
      params: {'numbers': S.list(S.number()), 'label': S.string().optional()},
      fn: (a) {
        final total = (a['numbers']! as List).fold<num>(
          0,
          (s, n) => s + (n as num),
        );
        return '${a['label'] ?? ''}$total';
      },
    );
    final lib = OpenUiLibrary(
      root: text,
      components: [text],
      functions: [percent, sum2],
    );

    test('are described in toSpec and toJsonSchema', () {
      expect((lib.toSpec()['functions'] as Map)['Percent'], {
        'signature': 'Percent(part: number, total?: number) → string',
        'description': 'Formats part / total as a percentage',
      });
      final percentSchema =
          (lib.toJsonSchema()['functions'] as Map)['Percent'] as Map;
      expect(((percentSchema['params'] as Map)['properties'] as Map).keys, [
        'part',
        'total',
      ]);
    });

    test(
      'map args by name, validate literals at parse time, apply defaults',
      () {
        final a = _evalText(lib, '@Percent(1, 4)');
        expect(a.value, '25.0%');
        expect(a.parseErrors, isEmpty);
        expect(a.runtimeErrors, isEmpty);
        expect(_evalText(lib, '@Percent(25)').value, '25.0%');
        final b = _evalText(lib, '@Percent("1", 4)');
        expect(b.value, isNull);
        expect(b.parseErrors, ['type-mismatch']);
        final c = _evalText(lib, '@Sum2([1, 2], 3, 4)');
        expect(c.value, '3');
        expect(c.parseErrors, ['excess-args', 'type-mismatch']);
        expect(_evalText(lib, '@Sum2([1], null)').value, '1');
      },
    );

    test(
      'validate literal args in Query and Mutation statements at parse time',
      () {
        final errors = createParser(lib.toJsonSchema(), rootName: 'Text')
            .parse(
              'root = Text("a")\n'
              'q = Query("save", { p: @Sum2([@Percent("bad")]), n: @Percent(3) })\n'
              'm = Mutation("save", { p: @Percent("bad") })',
            )
            .meta
            .errors;
        expect(
          [
            for (final e in errors) [e.code.wire, e.statementId],
          ],
          [
            ['type-mismatch', 'q'],
            ['type-mismatch', 'm'],
          ],
        );
      },
    );

    test('validate dynamic args at runtime without touching the data', () {
      final sum = _evalText(
        lib,
        r'@Sum2($n)',
        state: {
          r'$n': [1, 'x', 2],
        },
      );
      expect(sum.value, '3');
      expect(sum.parseErrors, isEmpty);
      expect(sum.state[r'$n'], [1, 'x', 2]);
      expect(_evalText(lib, r'@Percent($p)', state: {r'$p': '1'}).runtimeErrors, [
        'Evaluating prop "value" on Text failed: @Percent: field "/part" expects number but got string',
      ]);
      final unset = _evalText(lib, r'@Percent($p)');
      expect(unset.value, isNull);
      expect(unset.runtimeErrors, isEmpty);
    });

    test('run on every streamed chunk', () {
      final s = OpenUiSession(lib)
        ..update('root = Text(@Percent(1', streaming: true);
      expect(s.root!.props['value'], '1.0%');
      s.update('root = Text(@Percent(12, 4))', streaming: true);
      expect(s.root!.props['value'], '300.0%');
    });

    test('reject a name taken by a built-in or a component', () {
      for (final name in ['Sum', 'Text']) {
        expect(
          () => OpenUiLibrary(
            root: text,
            components: [text],
            functions: [
              FunctionSpec(name, description: '', params: {}, fn: (_) => 1),
            ],
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('collides'),
            ),
          ),
        );
      }
    });

    test('are listed in the prompt with the generated built-in lines', () {
      const line =
          '@Percent(part: number, total?: number) → string — Formats part / total';
      final plain = OpenUiLibrary(root: text, components: [text]);
      expect(
        lib.systemPrompt(const PromptOptions(toolCalls: true)),
        contains('@Sum(numbers: number[]) → number — Sum of numeric array'),
      );
      expect(lib.systemPrompt(), contains('## Built-in Functions\n\n$line'));
      expect(
        plain.systemPrompt(const PromptOptions(toolCalls: true)),
        isNot(contains('@Percent')),
      );
      expect(
        plain.systemPrompt(
          const PromptOptions(toolCalls: true, builtinFunctions: false),
        ),
        isNot(contains('## Built-in Functions')),
      );
    });
  });
}

typedef _Eval = ({
  Object? value,
  List<String> parseErrors,
  List<String> runtimeErrors,
  Map<String, Object?> state,
});

_Eval _evalText(
  OpenUiLibrary lib,
  String expr, {
  String extra = '',
  Map<String, Object?> state = const {},
}) {
  final s = OpenUiSession(lib, initialState: state)
    ..update('root = Text($expr)\n$extra', streaming: false);
  return (
    value: s.root?.props['value'],
    parseErrors: [
      for (final e in s.errors)
        if (e.source == OpenUiErrorSource.parser) e.code.wire,
    ],
    runtimeErrors: [
      for (final e in s.errors)
        if (e.source == OpenUiErrorSource.runtime) e.message,
    ],
    state: s.state,
  );
}
