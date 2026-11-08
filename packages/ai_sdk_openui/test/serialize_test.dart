import 'dart:convert';

import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/js.dart';
import 'package:ai_sdk_openui/src/lang/lexer.dart';
import 'package:ai_sdk_openui/src/lang/merge.dart';
import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:ai_sdk_openui/src/lang/serialize.dart';
import 'package:ai_sdk_openui/src/spec/library.dart';
import 'package:ai_sdk_openui/src/spec/schema.dart';
import 'package:test/test.dart';

final class _C implements ComponentSpec {
  _C(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

final _text = _C('Text', {'text': S.string(), 'size': S.string().optional()});
final _col = _C('Col', {
  'children': S.list(S.ref('Text')),
  'gap': S.string().optional(),
});
final _lib = OpenUiLibrary(root: _col, components: [_col, _text]);

String _roundTrip(String src, {bool withState = true}) {
  final r = parseProgram(src, _lib.compiled, rootName: 'Col');
  return jsonToOpenUI(
    r.root!,
    _lib,
    stateDeclarations: withState ? r.stateDeclarations : null,
  );
}

void main() {
  group('jsonToOpenUI', () {
    test('writes inline and referenced elements back as the program', () {
      const src =
          'root = Col([t1, Text("inline")])\nt1 = Text("Hi", "lg")\n\$n = 3';
      expect(_roundTrip(src), src);
    });

    test('writes a string concatenation with a state reference back', () {
      const src = 'root = Col([t])\nt = Text("n=" + \$n)\n\$n = 1';
      expect(_roundTrip(src), src);
    });

    test('keeps only the parentheses that precedence needs', () {
      const src = 'root = Col([Text("" + (1 + 2) * 3)])';
      expect(_roundTrip(src), src);
    });

    test('writes a ternary and a call with @ back as the program', () {
      const src = 'root = Col([Text(\$on ? "a" : "b"), Text(@Count([1, 2]))])';
      expect(_roundTrip(src), src);
    });

    test('writes member and index expressions back as the program', () {
      const src = 'root = Col([Text(\$o.a), Text(\$o[0])])';
      expect(_roundTrip(src), src);
    });

    test('writes an object and an index value of a prop back', () {
      expect(
        jsonToOpenUI(
          ElementNode(
            typeName: 'Box',
            props: {
              'a': ObjNode([('k', RefNode('x'))]),
              'b': IndexNode(StateRefNode(r'$o'), NumNode(0)),
            },
            partial: false,
            hasDynamicProps: false,
          ),
          _lib,
        ),
        'root = Box({k: x}, \$o[0])',
      );
    });

    test('writes a call without @ back without the @', () {
      const src = 'root = Col([Text(Action([]))])';
      expect(_roundTrip(src), src);
    });

    test('writes a state map declaration back as an object literal', () {
      expect(
        jsonToOpenUI(
          ElementNode(
            typeName: 'Col',
            props: {'children': <Object?>[]},
            partial: false,
            hasDynamicProps: false,
          ),
          _lib,
          stateDeclarations: {
            r'$m': {'a': 1},
          },
        ),
        'root = Col([])\n\$m = {a: 1}',
      );
    });

    test('writes an element of an unknown component from its props', () {
      expect(
        jsonToOpenUI(
          ElementNode(
            typeName: 'Box',
            props: {'a': 1, 'b': 'x'},
            partial: false,
            hasDynamicProps: false,
          ),
          _lib,
        ),
        'root = Box(1, "x")',
      );
    });

    test('omits state declarations when none are given', () {
      expect(
        _roundTrip(
          'root = Col([t1, Text("inline")])\nt1 = Text("Hi", "lg")\n\$n = 3',
          withState: false,
        ),
        'root = Col([t1, Text("inline")])\nt1 = Text("Hi", "lg")',
      );
    });

    test('output patches an existing program with mergeStatements', () {
      final r = parseProgram(
        'root = Col([t1, Text("inline")])\nt1 = Text("Hi", "lg")',
        _lib.compiled,
        rootName: 'Col',
      );
      expect(
        mergeStatements(jsonToOpenUI(r.root!, _lib), 't1 = Text("Bye")'),
        'root = Col([t1, Text("inline")])\nt1 = Text("Bye")',
      );
    });
  });

  // Ported from lang-core 1.0.0 parser/__tests__/serialize.test.ts, case for
  // case; elements are written as the plain JSON objects lang-core uses.
  group('lang-core serializer cases', () {
    final stack = _C('Stack', {'children': S.list(S.any())});
    final title = _C('Title', {'text': S.string()});
    final table = _C('Table', {
      'columns': S.list(S.any()),
      'rows': S.list(S.any()),
    });
    final card = _C('Card', {
      'title': S.string(),
      'subtitle': S.string().optional(),
    });
    final library = OpenUiLibrary(
      root: stack,
      components: [stack, title, table, card],
    );
    Map<String, Object?> el(
      String typeName,
      Map<String, Object?> props, {
      bool partial = false,
      bool? hasDynamicProps,
      String? statementId,
    }) => {
      'type': 'element',
      'typeName': typeName,
      'props': props,
      'partial': partial,
      'hasDynamicProps': ?hasDynamicProps,
      'statementId': ?statementId,
    };
    Object? strip(Object? v) => switch (v) {
      Map() when v['type'] == 'element' => {
        for (final MapEntry(:key, :value) in v.entries)
          if (key != 'partial' && key != 'hasDynamicProps')
            '$key': key == 'props'
                ? {
                    for (final p in (value! as Map).entries)
                      '${p.key}': strip(p.value),
                  }
                : value,
      },
      List() => [for (final x in v) strip(x)],
      _ => v,
    };
    void expectRoundTrip(String input) {
      final first = parse(input, library.compiled);
      expect(first.root, isNotNull);
      final second = parse(
        jsonToOpenUI(first.root!, library),
        library.compiled,
      );
      expect(strip(second.root!.toJson()), strip(first.root!.toJson()));
    }

    test('writes @ before library functions and actions', () {
      final btn = _C('Btn', {
        'label': S.any(),
        'action': actionSchema.optional(),
      });
      final lib = OpenUiLibrary(
        root: btn,
        components: [btn],
        functions: [
          FunctionSpec(
            'Upper',
            description: '',
            params: {'s': S.string()},
            fn: (a) => (a['s']! as String).toUpperCase(),
          ),
        ],
        actions: [
          ActionSpec('Copy', description: '', params: {'t': S.string()}),
        ],
      );
      const src = r'root = Btn(@Upper($name), @Copy("x"))';
      final root = createParser(
        lib.toJsonSchema(),
        rootName: 'Btn',
      ).parse(src).root;
      expect(jsonToOpenUI(root!, lib), src);
    });

    test('serializes a simple component', () {
      expect(
        jsonToOpenUI(
          el('Title', {'text': 'Hello'}, hasDynamicProps: false),
          library,
        ),
        'root = Title("Hello")',
      );
    });

    test('uses statementId as root name', () {
      expect(
        jsonToOpenUI(
          el('Title', {'text': 'Hi'}, statementId: 'header'),
          library,
        ),
        'header = Title("Hi")',
      );
    });

    test('extracts children with statementId as separate statements', () {
      final child = el('Title', {'text': 'Hello'}, statementId: 'header');
      final result = jsonToOpenUI(
        el('Stack', {
          'children': [child],
        }, statementId: 'root'),
        library,
      );
      expect(result, contains('root = Stack([header])'));
      expect(result, contains('header = Title("Hello")'));
    });

    test('inlines components without statementId', () {
      final child = el('Title', {'text': 'Inline'});
      expect(
        jsonToOpenUI(
          el('Stack', {
            'children': [child],
          }),
          library,
        ),
        'root = Stack([Title("Inline")])',
      );
    });

    test('serializes strings with escaping', () {
      expect(
        jsonToOpenUI(el('Title', {'text': 'Hello "world"'}), library),
        r'root = Title("Hello \"world\"")',
      );
    });

    test('serializes numbers', () {
      final result = jsonToOpenUI(
        el('Table', {
          'columns': [42],
          'rows': [
            [3.14],
          ],
        }),
        library,
      );
      expect(result, contains('42'));
      expect(result, contains('3.14'));
    });

    test('serializes booleans', () {
      final result = jsonToOpenUI(
        el('Table', {
          'columns': [true],
          'rows': [
            [false],
          ],
        }),
        library,
      );
      expect(result, contains('true'));
      expect(result, contains('false'));
    });

    test('serializes null', () {
      expect(
        jsonToOpenUI(
          el('Table', {
            'columns': [null],
            'rows': [<Object?>[]],
          }),
          library,
        ),
        contains('null'),
      );
    });

    test('serializes plain objects', () {
      expect(
        jsonToOpenUI(
          el('Table', {
            'columns': [
              {'name': 'col1', 'key': 'id'},
            ],
            'rows': <Object?>[],
          }),
          library,
        ),
        contains('{name: "col1", key: "id"}'),
      );
    });

    test('maps props to positional args via ParamMap', () {
      expect(
        jsonToOpenUI(
          el('Table', {
            'columns': ['A', 'B'],
            'rows': [
              [1, 2],
            ],
          }),
          library,
        ),
        'root = Table(["A", "B"], [[1, 2]])',
      );
    });

    test('trims trailing optional args', () {
      expect(
        jsonToOpenUI(el('Card', {'title': 'Hello'}), library),
        'root = Card("Hello")',
      );
    });

    test('fills middle gaps with null', () {
      expect(
        jsonToOpenUI(
          el('Table', {
            'rows': [
              [1, 2],
            ],
          }),
          library,
        ),
        'root = Table(null, [[1, 2]])',
      );
    });

    test('serializes StateRef', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {'k': 'StateRef', 'n': r'$name'},
          }, hasDynamicProps: true),
          library,
        ),
        r'root = Title($name)',
      );
    });

    test('serializes RuntimeRef', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {'k': 'RuntimeRef', 'n': 'queryData', 'refType': 'query'},
          }, hasDynamicProps: true),
          library,
        ),
        'root = Title(queryData)',
      );
    });

    test('serializes BinOp with correct precedence', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {
              'k': 'BinOp',
              'op': '*',
              'left': {
                'k': 'BinOp',
                'op': '+',
                'left': {'k': 'StateRef', 'n': r'$a'},
                'right': {'k': 'StateRef', 'n': r'$b'},
              },
              'right': {'k': 'StateRef', 'n': r'$c'},
            },
          }, hasDynamicProps: true),
          library,
        ),
        r'root = Title(($a + $b) * $c)',
      );
    });

    test('serializes Ternary', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {
              'k': 'Ternary',
              'cond': {'k': 'StateRef', 'n': r'$active'},
              'then': {'k': 'Str', 'v': 'Yes'},
              'else': {'k': 'Str', 'v': 'No'},
            },
          }, hasDynamicProps: true),
          library,
        ),
        r'root = Title($active ? "Yes" : "No")',
      );
    });

    test('serializes Member access', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {
              'k': 'Member',
              'obj': {'k': 'RuntimeRef', 'n': 'data', 'refType': 'query'},
              'field': 'name',
            },
          }, hasDynamicProps: true),
          library,
        ),
        'root = Title(data.name)',
      );
    });

    test('serializes Index access', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {
              'k': 'Index',
              'obj': {'k': 'RuntimeRef', 'n': 'items', 'refType': 'query'},
              'index': {'k': 'Num', 'v': 0},
            },
          }, hasDynamicProps: true),
          library,
        ),
        'root = Title(items[0])',
      );
    });

    test('serializes UnaryOp', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {
              'k': 'UnaryOp',
              'op': '!',
              'operand': {'k': 'StateRef', 'n': r'$flag'},
            },
          }, hasDynamicProps: true),
          library,
        ),
        r'root = Title(!$flag)',
      );
    });

    test('serializes builtins with @ prefix', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {
              'k': 'Comp',
              'name': 'Count',
              'args': [
                {'k': 'RuntimeRef', 'n': 'items', 'refType': 'query'},
              ],
            },
          }, hasDynamicProps: true),
          library,
        ),
        'root = Title(@Count(items))',
      );
    });

    test('serializes Action without @ prefix', () {
      expect(
        jsonToOpenUI(
          el('Title', {
            'text': {
              'k': 'Comp',
              'name': 'Action',
              'args': [
                {
                  'k': 'Arr',
                  'els': [
                    {
                      'k': 'Comp',
                      'name': 'Run',
                      'args': [
                        {'k': 'Ref', 'n': 'myQuery'},
                      ],
                    },
                  ],
                },
              ],
            },
          }, hasDynamicProps: true),
          library,
        ),
        contains('Action([@Run(myQuery)])'),
      );
    });

    test('includes non-null state declarations', () {
      final result = jsonToOpenUI(
        el('Title', {'text': 'Hi'}),
        library,
        stateDeclarations: {r'$count': 0, r'$name': 'default'},
      );
      expect(result, contains(r'$count = 0'));
      expect(result, contains(r'$name = "default"'));
    });

    test('omits null state declarations', () {
      expect(
        jsonToOpenUI(
          el('Title', {'text': 'Hi'}),
          library,
          stateDeclarations: {r'$filter': null},
        ),
        isNot(contains(r'$filter')),
      );
    });

    test('round-trips a simple component', () {
      expectRoundTrip('root = Title("Hello")');
    });

    test('round-trips nested components', () {
      expectRoundTrip(
        'root = Stack([header, tbl])\nheader = Title("Hi")\ntbl = Table(["A", "B"], [[1, 2]])',
      );
    });

    test('round-trips with optional args', () {
      expectRoundTrip('root = Card("Main Title")');
    });

    test('serialized output works as a merge patch', () {
      const existing = 'root = Stack([header])\nheader = Title("Old")';
      final patch = jsonToOpenUI(
        el('Stack', {
          'children': [
            el('Title', {'text': 'New'}, statementId: 'header'),
          ],
        }, statementId: 'root'),
        library,
      );
      final merged = mergeStatements(existing, patch);
      expect(merged, 'root = Stack([header])\nheader = Title("New")');
      final result = parse(merged, library.compiled);
      expect(result.root!.typeName, 'Stack');
      final children = result.root!.props['children']! as List;
      expect((children.first! as ElementNode).props['text'], 'New');
    });

    test('handles empty children array', () {
      expect(
        jsonToOpenUI(el('Stack', {'children': <Object?>[]}), library),
        'root = Stack([])',
      );
    });

    test('handles partial nodes', () {
      expect(
        jsonToOpenUI(
          el('Title', {'text': 'Streaming'}, partial: true),
          library,
        ),
        'root = Title("Streaming")',
      );
    });

    test('handles duplicate statementIds without infinite loop', () {
      final child = el('Title', {'text': 'Same'}, statementId: 'shared');
      final result = jsonToOpenUI(
        el('Stack', {
          'children': [child, child],
        }),
        library,
      );
      expect(result, contains('Stack([shared, shared])'));
      expect(RegExp('shared = Title').allMatches(result), hasLength(1));
    });
  });

  group('JSON forms', () {
    test('an element round-trips through its JSON', () {
      final r = parse(
        'root = Col([t1, Text(\$n + 1)])\nt1 = Text("Hi", "lg")\n\$n = 3',
        _lib.compiled,
        'Col',
      );
      final json = r.root!.toJson();
      expect(json['statementId'], 'root');
      expect(jsonToOpenUI(json, _lib), jsonToOpenUI(r.root!, _lib));
      expect(ElementNode.fromJson(json).toJson(), json);
    });

    test('a parse result is lang-core\'s JSON', () {
      final out = _C('Out', {
        'value': S.any(),
        'action': actionSchema.optional(),
      });
      final lib = OpenUiLibrary(root: out, components: [out]);
      final r = createParser(lib.toJsonSchema(), rootName: 'Out').parse(
        'root = Out(a)\na = Out(\$x + 1, @OpenUrl("u"))\n\$x = 2\n'
        'q = Query("t", {a: \$x}, [], 5)\nm = Mutation("w", {b: 1})\n'
        'zz = Out(missing.k, Action([@Set(\$x, 3), @ToAssistant("hi"), @Run(m), @Reset(\$x)]))',
      );
      // JSON.stringify of lang-core 1.0.0's createParser(...).parse(...) in Node 26.
      expect(
        jsonEncode(r.toJson()),
        r'{"root":{"type":"element","typeName":"Out","props":{"value":{"type":"e'
        r'lement","typeName":"Out","props":{"value":{"k":"BinOp","op":"+","left"'
        r':{"k":"StateRef","n":"$x"},"right":{"k":"Num","v":1}},"action":{"k":"C'
        r'omp","name":"OpenUrl","args":[{"k":"Str","v":"u"}],"mappedProps":{"url'
        r'":{"k":"Str","v":"u"}}}},"partial":false,"hasDynamicProps":true,"state'
        r'mentId":"a"}},"partial":false,"hasDynamicProps":true,"statementId":"ro'
        r'ot"},"meta":{"incomplete":false,"unresolved":[],"orphaned":["zz"],"sta'
        r'tementCount":6,"errors":[]},"stateDeclarations":{"$x":2},"queryStateme'
        r'nts":[{"statementId":"q","toolAST":{"k":"Str","v":"t"},"argsAST":{"k":'
        r'"Obj","entries":[["a",{"k":"StateRef","n":"$x"}]]},"defaultsAST":{"k":'
        r'"Arr","els":[]},"refreshAST":{"k":"Num","v":5},"deps":["$x"],"complete'
        r'":true}],"mutationStatements":[{"statementId":"m","toolAST":{"k":"Str"'
        r',"v":"w"},"argsAST":{"k":"Obj","entries":[["b",{"k":"Num","v":1}]]}}]}',
      );
    });

    test('every AST kind round-trips through its JSON', () {
      final ast = parseExpression(
        tokenize(
          r'@Foo(a.b, c[1], !d, e ? 1 : "s", [true, null], {k: $v}, $v = 2, -1)',
        ),
      );
      final text = Js.stringify(ast);
      expect(Js.stringify(astFromJson(jsonDecode(text) as Map)), text);
      for (final json in [
        {'k': 'Ph', 'n': 'x'},
        {
          'k': 'Comp',
          'name': 'Count',
          'args': [
            {'k': 'Arr', 'els': <Object?>[]},
          ],
          'mappedProps': {
            'array': {'k': 'Arr', 'els': <Object?>[]},
          },
        },
      ]) {
        expect(jsonDecode(Js.stringify(astFromJson(json))), json);
      }
      expect(() => astFromJson({'k': 'Nope'}), throwsArgumentError);
    });

    test("a parse result's errors are lang-core's ValidationError objects", () {
      final out = _C('Out', {
        'value': S.any(),
        'action': actionSchema.optional(),
      });
      final lib = OpenUiLibrary(root: out, components: [out]);
      final parser = createParser(lib.toJsonSchema(), rootName: 'Out');
      // JSON.stringify(parser.parse(src).meta.errors) in Node 26.
      expect(
        jsonEncode(parser.parse('root = Out(Nope(1))').toJson()['meta']),
        '{"incomplete":false,"unresolved":[],"orphaned":[],"statementCount":1,"errors":['
        r'{"code":"unknown-component","component":"Nope","path":"","message":"Unknown component \"Nope\" — not found in catalog or builtins. Available components: Out","statementId":"root"},'
        r'{"code":"null-required","component":"Out","path":"/value","message":"required field \"/value\" cannot be null — signature: Out(value*, action)","statementId":"root"}]}',
      );
      expect(
        jsonEncode(
          (parser.parse('page = Out(1)').toJson()['meta']! as Map)['errors'],
        ),
        '[{"code":"no-root","component":"Out","path":"","message":"No root statement. Rendering the first statement that calls the root component Out","statementId":"page","severity":"warning"}]',
      );
    });

    test('an element prop given as JSON is written as an element', () {
      expect(
        jsonToOpenUI(
          ElementNode(
            typeName: 'Col',
            props: {
              'children': [
                {
                  'type': 'element',
                  'typeName': 'Text',
                  'props': {'text': 'x'},
                  'partial': false,
                },
              ],
            },
            partial: false,
            hasDynamicProps: false,
          ),
          _lib,
        ),
        'root = Col([Text("x")])',
      );
    });

    test('a JSON map that is not an element is rejected', () {
      expect(() => jsonToOpenUI({'type': 'other'}, _lib), throwsArgumentError);
    });
  });
}
