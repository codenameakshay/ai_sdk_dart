import 'dart:convert';

import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:ai_sdk_openui/src/runtime/evaluator.dart';
import 'package:ai_sdk_openui/src/lang/validation.dart';
import 'package:test/test.dart';

/// A small library: `Card(title*, subtitle)`, `Row(gap* = 8)`,
/// `Badge(label* = "new")`, `Stack(children: [Card])`, the functions
/// `Upper(s*)` and `Tag(meta)`, and `Pair(xs: [number])`.
final schema = CompiledSchema.fromJsonSchema({
  'properties': {'Card': {}, 'Row': {}, 'Badge': {}, 'Stack': {}},
  r'$defs': {
    'Card': {
      'properties': {
        'title': {'type': 'string'},
        'subtitle': {'type': 'string'},
      },
      'required': ['title'],
    },
    'Row': {
      'properties': {
        'gap': {'type': 'number', 'default': 8},
      },
      'required': ['gap'],
    },
    'Badge': {
      'properties': {
        'label': {'type': 'string', 'default': 'new'},
      },
      'required': ['label'],
    },
    'Stack': {
      'properties': {
        'children': {
          'type': 'array',
          'items': {r'$ref': r'#/$defs/Card'},
        },
      },
    },
  },
  'functions': {
    'Upper': {
      'params': {
        'properties': {
          's': {'type': 'string'},
        },
        'required': ['s'],
      },
    },
    'Tag': {
      'params': {
        'properties': {
          'meta': {
            'type': 'object',
            'properties': {
              'a': {'type': 'number'},
              'b': {'type': 'number'},
            },
          },
        },
      },
    },
    'Pair': {
      'params': {
        'properties': {
          'xs': {
            'type': 'array',
            'items': {'type': 'number'},
          },
        },
      },
    },
  },
});

ParseResult parse(String src, {String? root = 'Stack'}) =>
    parseProgram(src, schema, rootName: root);

List<String> errorsOf(ParseResult r) => [
  for (final e in r.meta.errors) e.message,
];

/// An s-expression for [n].
String show(Ast n) => switch (n) {
  StrNode(:final value) => jsonEncode(value),
  NumNode(:final value) => '$value',
  BoolNode(:final value) => '$value',
  NullNode() => 'null',
  ValueNode(:final value) => jsonEncode(value),
  RefNode(:final name) => name,
  StateRefNode(:final name) => name,
  RuntimeRefNode(:final name) => name,
  PlaceholderNode(:final name) => '?$name',
  UnaryOpNode(:final op, :final operand) => '($op ${show(operand)})',
  BinOpNode(:final op, :final left, :final right) =>
    '(${show(left)} $op ${show(right)})',
  TernaryNode(:final condition, :final then, :final otherwise) =>
    '(${show(condition)} ? ${show(then)} : ${show(otherwise)})',
  MemberNode(:final object, :final field) => '${show(object)}.$field',
  IndexNode(:final object, :final index) => '${show(object)}[${show(index)}]',
  ArrNode(:final elements) => '[${elements.map(show).join(', ')}]',
  ObjNode(:final entries) =>
    '{${entries.map((e) => '${e.$1}: ${show(e.$2)}').join(', ')}}',
  CompNode(:final name, :final args) => '$name(${args.map(show).join(', ')})',
  AssignNode(:final target, :final value) => '$target = ${show(value)}',
};

/// A materialized value as text.
String plain(Object? v) => switch (v) {
  ElementNode(:final typeName, :final props) =>
    '$typeName(${props.entries.map((e) => '${e.key}: ${plain(e.value)}').join(', ')})',
  Ast() => show(v),
  List() => '[${v.map(plain).join(', ')}]',
  String() => jsonEncode(v),
  _ => '$v',
};

/// The named args of a call node.
String named(CompNode call) => [
  for (final e in call.mappedProps!.entries) '${e.key}=${show(e.value)}',
].join(' ');

/// Every call node named [name] under [node].
List<CompNode> callsOf(Ast node, String name) {
  final out = <CompNode>[];
  walkAst(node, (n) {
    if (n is CompNode && n.name == name) out.add(n);
  });
  return out;
}

void main() {
  group('CompNode.copyWith', () {
    final original = CompNode(
      'Card',
      const [StrNode('a')],
      mappedProps: const {'title': StrNode('a')},
      isAtCall: true,
    );

    test('replacing the mapped props keeps the args', () {
      final copy = original.copyWith(mappedProps: const {'x': NumNode(1)});
      expect(show(copy), 'Card("a")');
      expect(named(copy), 'x=1');
      expect(copy.isAtCall, isTrue);
    });

    test('replacing the args keeps the mapped props', () {
      final copy = original.copyWith(args: const [NumNode(2)]);
      expect(show(copy), 'Card(2)');
      expect(named(copy), 'title="a"');
    });

    test('walkAst visits args and mapped props', () {
      final seen = <String>[];
      walkAst(original, (n) => seen.add(show(n)));
      expect(seen, ['Card("a")', '"a"', '"a"']);
    });
  });

  group('CompiledSchema', () {
    test('without a properties list, every def but an action def is a '
        'component', () {
      final compiled = CompiledSchema.fromJsonSchema({
        r'$defs': {
          'Card': {
            'properties': {
              'title': {'type': 'string'},
            },
            'required': ['title'],
          },
          'OpenUrl': {
            'properties': {
              'url': {'type': 'string'},
            },
          },
          'Go': {
            'properties': {
              'to': {'type': 'string'},
            },
          },
        },
        'actions': {
          'Go': {
            'params': {
              'properties': {
                'to': {'type': 'string'},
              },
            },
          },
        },
      });
      expect(compiled.components.keys, ['Card']);
      expect(compiled.components['Card']!.single.name, 'title');
      expect(compiled.components['Card']!.single.required, isTrue);
      expect(compiled.calls['Go']!.kind, CallKind.action);
      expect(compiled.calls['Go']!.builtin, isFalse);
    });

    test('with a properties list, only those defs are components', () {
      final compiled = CompiledSchema.fromJsonSchema({
        'properties': {'Card': {}},
        r'$defs': {
          'Card': {'properties': <String, Object?>{}},
          'Shared': {'properties': <String, Object?>{}},
        },
      });
      expect(compiled.components.keys, ['Card']);
    });

    test('the built-in registry', () {
      expect(builtinCalls['Sum']!.kind, CallKind.function);
      expect(builtinCalls['Sum']!.builtin, isTrue);
      expect(builtinCalls['Sum']!.lazy, isFalse);
      expect(builtinCalls['Each']!.lazy, isTrue);
      expect(builtinCalls['Set']!.kind, CallKind.action);
      expect(builtinCalls['Set']!.lazy, isTrue);
      expect(builtinCalls['Action']!.params.single.name, 'steps');
      expect(builtinCalls['Action']!.params.single.required, isTrue);
      expect(builtinCalls['Action']!.lazy, isTrue);
    });
  });

  group('argument counts', () {
    test('a component drops excess args and says so', () {
      final r = parse('root = Stack([Card("a", "b", "c")])');
      expect(errorsOf(r), ['Card takes 2 arg(s), got 3 (1 excess dropped)']);
      expect(
        plain(r.root),
        'Stack(children: [Card(title: "a", subtitle: "b")])',
      );
    });

    test('a library function drops excess args and says so', () {
      final r = parse('root = Card(@Upper("a", "b"))');
      expect(errorsOf(r), ['Upper takes 1 arg(s), got 2 (1 excess dropped)']);
      final call = r.root!.props['title'] as CompNode;
      expect(call.name, 'Upper');
      expect(named(call), 's="a"');
    });

    test('a function missing a required arg becomes null', () {
      final r = parse('root = Card("t", @Upper())');
      expect(errorsOf(r), [
        'missing required field "/s" — signature: Upper(s*: string)',
      ]);
      expect(plain(r.root!.props['subtitle']), 'null');
    });
  });

  group('function arguments', () {
    test('an invalid element inside an array literal is pruned', () {
      final r = parse('root = Card("t", @Pair([1, "a", 2]))');
      expect(errorsOf(r), ['field "/xs/1" expects number but got string']);
      final call = r.root!.props['subtitle'] as CompNode;
      expect(named(call), 'xs=[1, 2]');
    });

    test('an invalid object property is dropped', () {
      final r = parse('root = Card("t", @Tag({a: 1, b: "x"}))');
      expect(errorsOf(r), ['field "/meta/b" expects number but got string']);
      final call = r.root!.props['subtitle'] as CompNode;
      expect(named(call), 'meta={a: 1}');
    });

    test('a valid literal keeps its original node', () {
      final r = parse('root = Card("t", @Pair([1, 2]))');
      expect(errorsOf(r), isEmpty);
      final call = r.root!.props['subtitle'] as CompNode;
      expect(named(call), 'xs=[1, 2]');
    });
  });

  group('Query and Mutation arguments', () {
    test('calls in the args are named by their parameters', () {
      final r = parse(
        'q = Query("tool", {a: @Sum([1, 2]), b: @Upper("x")})\n'
        'root = Card("t")',
      );
      final args = r.queryStatements.single.argsAst!;
      expect(named(callsOf(args, 'Sum').single), 'numbers=[1, 2]');
      expect(named(callsOf(args, 'Upper').single), 's="x"');
      expect(errorsOf(r), isEmpty);
    });

    test('an invalid call falls back to naming its args as written', () {
      final r = parse('q = Query("tool", {c: @Upper(5)})\nroot = Card("t")');
      expect(errorsOf(r), ['field "/s" expects string but got number']);
      expect(r.meta.errors.single.statementId, 'q');
      final call = callsOf(r.queryStatements.single.argsAst!, 'Upper').single;
      expect(named(call), 's=5');
    });

    test('a lazy call keeps its args unnamed', () {
      final r = parse(
        'q = Query("tool", {d: @Each([1], "i", i)})\nroot = Card("t")',
      );
      final call = callsOf(r.queryStatements.single.argsAst!, 'Each').single;
      expect(call.mappedProps, isNull);
    });

    test('a Mutation names its args too', () {
      final r = parse(
        'm = Mutation("save", {t: @Upper("x")})\nroot = Card("t")',
      );
      final args = r.mutationStatements.single.argsAst!;
      expect(named(callsOf(args, 'Upper').single), 's="x"');
    });

    test('an unknown call in the args is left unnamed', () {
      final r = parse('q = Query("tool", {e: Nope(1)})\nroot = Card("t")');
      expect(
        callsOf(r.queryStatements.single.argsAst!, 'Nope').single.mappedProps,
        isNull,
      );
    });
  });

  group('unknown names', () {
    test('an unknown @function as a value is null', () {
      final r = parse('root = Card("t", @Nope(1))');
      expect(errorsOf(r), [
        'Unknown function "@Nope": not a built-in or action step. The call '
            'evaluates to null',
      ]);
      expect(r.root!.props['subtitle'], isNull);
    });

    test('an unknown @function in an expression becomes null', () {
      final r = parse('root = Card("t", @Nope(1) + 1)');
      expect(errorsOf(r), [
        'Unknown function "@Nope": not a built-in or action step. The call '
            'evaluates to null',
      ]);
      expect(plain(r.root!.props['subtitle']), '(null + 1)');
    });

    test('an unknown component in an expression is reported and kept', () {
      final r = parse(r'root = Card("t", $x ? Foo(1) : null)');
      expect(errorsOf(r), [
        'Unknown component "Foo" — not found in catalog or builtins. '
            'Available components: Card, Row, Badge, Stack',
      ]);
      expect(plain(r.root!.props['subtitle']), r'($x ? Foo(1) : null)');
    });

    test('an unknown component as a value is null', () {
      final r = parse('root = Stack([Foo(1), Card("a")])');
      expect(errorsOf(r), [
        'Unknown component "Foo" — not found in catalog or builtins. '
            'Available components: Card, Row, Badge, Stack',
      ]);
      expect(plain(r.root), 'Stack(children: [Card(title: "a")])');
    });

    test('a Query used inline is reported and dropped', () {
      final r = parse('root = Card("t", Query("a"))');
      expect(errorsOf(r), [
        'Query() must be declared as a top-level statement, not used inline '
            'as a value',
      ]);
      expect(r.root!.props['subtitle'], isNull);
    });
  });

  group('required params with a default', () {
    test('fill silently when the arg is missing', () {
      final r = parse('root = Stack([Row()])');
      expect(errorsOf(r), isEmpty);
      expect(plain(r.root), 'Stack(children: [Row(gap: 8)])');
    });

    test('a component with only defaulted params still builds', () {
      final r = parse('root = Badge()', root: 'Badge');
      expect(errorsOf(r), isEmpty);
      expect(plain(r.root), 'Badge(label: "new")');
    });

    test('a null arg takes the default too', () {
      final r = parse('root = Badge(null)', root: 'Badge');
      expect(errorsOf(r), isEmpty);
      expect(plain(r.root), 'Badge(label: "new")');
    });

    test('a given arg wins', () {
      expect(
        plain(parse('root = Badge("hot")', root: 'Badge').root),
        'Badge(label: "hot")',
      );
    });

    test('a required param with no default is reported with the signature', () {
      final r = parse('root = Card()', root: 'Card');
      expect(errorsOf(r), [
        'missing required field "/title" — signature: '
            'Card(title*: string, subtitle: string)',
      ]);
      expect(r.root, isNull);
    });
  });

  group('choosing the root', () {
    test('a statement named root wins', () {
      final r = parse('a = Stack([])\nroot = Stack([Card("r")])');
      expect(plain(r.root), 'Stack(children: [Card(title: "r")])');
      expect(errorsOf(r), isEmpty);
      expect(r.meta.orphaned, ['a']);
    });

    test('without root, the first statement calling the root component '
        'renders, with a warning', () {
      final r = parse('a = Card("x")\nmain = Stack([a])\nother = Stack([])');
      expect(plain(r.root), 'Stack(children: [Card(title: "x")])');
      expect(r.root!.statementId, 'main');
      expect(r.meta.errors.single.isWarning, isTrue);
      expect(
        r.meta.errors.single.message,
        'No root statement. Rendering the first statement that calls the '
        'root component Stack',
      );
      expect(r.meta.errors.single.statementId, 'main');
      expect(r.meta.orphaned, ['other']);
    });

    test('a fallback that fails to build says no statement calls the root', () {
      final r = parse('main = Card()', root: 'Card');
      expect(r.root, isNull);
      expect(errorsOf(r), [
        'missing required field "/title" — signature: '
            'Card(title*: string, subtitle: string)',
        'No root statement, and no statement calls the root component Card',
      ]);
      expect(r.meta.errors.last.isWarning, isFalse);
    });

    test('no statement calls the root component', () {
      final r = parse('a = Card("x")');
      expect(r.root, isNull);
      expect(errorsOf(r), [
        'No root statement, and no statement calls the root component Stack',
      ]);
      expect(r.meta.orphaned, isEmpty);
    });

    test('with no root name there is nothing to fall back on', () {
      final r = parse('a = Card("x")', root: null);
      expect(errorsOf(r), ['No root statement']);
    });

    test('an @call, a built-in or a Query is not a component call', () {
      expect(errorsOf(parse('main = @Stack([])')), [
        'No root statement, and no statement calls the root component Stack',
      ]);
      expect(errorsOf(parse('main = Action([])', root: 'Action')), [
        'No root statement, and no statement calls the root component Action',
      ]);
      expect(errorsOf(parse('main = Query("t")', root: 'Query')), [
        'No root statement, and no statement calls the root component Query',
      ]);
    });

    test('a value that is not a component is reported', () {
      final r = parse('root = 5');
      expect(r.root, isNull);
      expect(errorsOf(r), ['root does not evaluate to a component']);
      expect(errorsOf(parse(r'root = $x ? 1 : 2')), [
        'root does not evaluate to a component',
      ]);
    });

    test('a chain of references that ends in a component is not reported', () {
      final r = parse('root = a\na = b\nb = Card()', root: 'Card');
      expect(r.root, isNull);
      expect(errorsOf(r), [
        'missing required field "/title" — signature: '
            'Card(title*: string, subtitle: string)',
      ]);
    });

    test('a chain of references that never ends is not a component', () {
      final r = parse('root = a\na = b\nb = a');
      expect(r.root, isNull);
      expect(r.meta.unresolved, ['a']);
      expect(errorsOf(r), ['root does not evaluate to a component']);
    });

    test('a root that is a reference to an unknown name', () {
      final r = parse('root = missing');
      expect(r.meta.unresolved, ['missing']);
      expect(errorsOf(r), ['root does not evaluate to a component']);
    });

    test('an expression that holds components is the root expression', () {
      final r = parse(r'root = $x ? Card("a") : Card("b")');
      expect(r.root, isNull);
      expect(show(r.rootExpression!), r'($x ? Card("a") : Card("b"))');
      expect(errorsOf(r), isEmpty);
      expect(r.stateDeclarations, {r'$x': null});
    });

    test('an expression with no component is not a root expression', () {
      final r = parse(r'root = $x ? 1 : 2');
      expect(r.rootExpression, isNull);
    });

    test('state declarations are never orphans', () {
      final r = parse('\$n = 3\nroot = Stack([])');
      expect(r.stateDeclarations, {r'$n': 3});
      expect(r.meta.orphaned, isEmpty);
    });
  });

  group('empty programs', () {
    test('an empty or comment-only program is an incomplete empty result', () {
      for (final src in ['', '  \n ', '// nothing', '```\n```']) {
        final r = parse(src);
        expect(
          (r.root, r.meta.incomplete, r.meta.statementCount),
          (null, true, 0),
          reason: src,
        );
      }
    });

    test('text with no statements is empty and complete', () {
      final r = parse('hello world');
      expect(
        (r.root, r.meta.incomplete, r.meta.statementCount),
        (null, false, 0),
      );
    });

    test('text with no statements and an open bracket is incomplete', () {
      final r = parse('hello (');
      expect(r.meta.incomplete, isTrue);
      expect(r.meta.statementCount, 0);
    });
  });

  group('StreamParser', () {
    test('push appends chunks and builds as the program grows', () {
      final p = StreamParser(schema, rootName: 'Stack');
      expect(p.push('root = Stack([Card("a"').meta.incomplete, isTrue);
      expect(
        plain(p.push('), Card("b")').root),
        'Stack(children: [Card(title: "a"), Card(title: "b")])',
      );
      final done = p.push('])\n');
      expect(done.meta.incomplete, isFalse);
      expect(
        plain(done.root),
        'Stack(children: [Card(title: "a"), Card(title: "b")])',
      );
    });

    test('push and set give the same tree', () {
      const text = 'a = Card("x")\nb = Card("y")\nroot = Stack([a, b])\n';
      final pushed = StreamParser(schema, rootName: 'Stack');
      late ParseResult last;
      for (var i = 0; i < text.length; i += 5) {
        last = pushed.push(text.substring(i, (i + 5).clamp(0, text.length)));
      }
      final set = StreamParser(schema, rootName: 'Stack').set(text);
      expect(plain(last.root), plain(set.root));
      expect(
        plain(set.root),
        'Stack(children: [Card(title: "x"), Card(title: "y")])',
      );
      expect(last.meta.statementCount, 3);
      expect(set.meta.statementCount, 3);
    });

    test('set with a longer text that extends the buffer keeps the buffer', () {
      final p = StreamParser(schema, rootName: 'Stack');
      p.set('a = Card("x")\n');
      final r = p.set('a = Card("x")\nroot = Stack([a])');
      expect(plain(r.root), 'Stack(children: [Card(title: "x")])');
      expect(r.meta.statementCount, 2);
    });

    test('set with text that is not an extension starts over', () {
      final p = StreamParser(schema, rootName: 'Stack');
      p.set('a = Card("x")\nroot = Stack([a])');
      final r = p.set('root = Stack([Card("fresh")])');
      expect(plain(r.root), 'Stack(children: [Card(title: "fresh")])');
      expect(r.meta.statementCount, 1);
      expect(r.meta.orphaned, isEmpty);
    });

    test('set with shorter text starts over', () {
      final p = StreamParser(schema, rootName: 'Stack');
      p.set('a = Card("x")\nroot = Stack([a])\n');
      final r = p.set('root = Stack([');
      expect(plain(r.root), 'Stack(children: [])');
      expect(r.meta.statementCount, 1);
      expect(r.meta.incomplete, isTrue);
    });

    test('reset forgets everything', () {
      final p = StreamParser(schema, rootName: 'Stack');
      p.push('a = Card("x")\nroot = Stack([a])');
      p.reset();
      final r = p.push('root = Stack([])');
      expect(plain(r.root), 'Stack(children: [])');
      expect(r.meta.statementCount, 1);
      expect(r.meta.unresolved, isEmpty);
    });

    test('a later change to earlier text drops the cached statements', () {
      final p = StreamParser(schema, rootName: 'Stack');
      final first = p.push('a = Card("x")\nroot = Stack([a])\n');
      expect(plain(first.root), 'Stack(children: [Card(title: "x")])');
      // A fence now wraps the program, so only its body counts.
      final r = p.push('```\nroot = Stack([])\n');
      expect(plain(r.root), 'Stack(children: [])');
      expect(r.meta.statementCount, 1);
      expect(r.meta.orphaned, isEmpty);
    });

    test('prose before a fence arriving later replaces the cached program', () {
      final p = StreamParser(schema, rootName: 'Stack');
      p.push('a = Card("x")\n');
      final r = p.push('```openui\nroot = Stack([])\n');
      expect(r.meta.statementCount, 1);
      expect(plain(r.root), 'Stack(children: [])');
    });

    test('blank lines and indentation between statements', () {
      final p = StreamParser(schema, rootName: 'Stack');
      final r = p.set(
        'a = Card("x")\n\n  \n   b = Card("y")\n\nroot = Stack([a, b])',
      );
      expect(
        plain(r.root),
        'Stack(children: [Card(title: "x"), Card(title: "y")])',
      );
      expect(r.meta.statementCount, 3);
    });

    test('a ? on the next line continues the statement', () {
      final p = StreamParser(schema, rootName: 'Card');
      final r = p.set('a = Card("x")\n   \n  ? 1\n  : 2\nroot = Card("t", a)');
      expect(r.meta.statementCount, 2);
      expect(plain(r.root), 'Card(title: "t", subtitle: (Card("x") ? 1 : 2))');
    });

    test('empty input is an empty incomplete result', () {
      final p = StreamParser(schema, rootName: 'Stack');
      for (final text in ['', ' \n ', '// c']) {
        final r = p.set(text);
        expect(
          (r.root, r.meta.incomplete, r.meta.statementCount),
          (null, true, 0),
          reason: text,
        );
      }
    });

    test('complete text with no statements is empty', () {
      final r = StreamParser(schema, rootName: 'Stack').set('hello');
      expect(
        (r.root, r.meta.incomplete, r.meta.statementCount),
        (null, false, 0),
      );
    });

    test('a half-written line after complete statements keeps them', () {
      final p = StreamParser(schema, rootName: 'Stack');
      final r = p.set('a = Card("x")\nhello (');
      expect(r.meta.incomplete, isTrue);
      expect(r.meta.statementCount, 1);
      expect(plain(r.root), 'null');
    });

    test('a partial state variable at the end is not declared as state', () {
      final p = StreamParser(schema, rootName: 'Stack');
      expect(p.push('root = Stack([Card(\$na').stateDeclarations, isEmpty);
      expect(p.push('me)])\n').stateDeclarations.keys, [r'$name']);
    });

    test('a complete parse keeps a trailing state variable', () {
      final r = StreamParser(
        schema,
        rootName: 'Stack',
      ).push(r'root = Stack([Card($na', complete: true);
      expect(r.stateDeclarations.keys, [r'$na']);
    });
  });

  // Ported from lang-core 1.0.0 parser/__tests__/parser.test.ts, case for case.
  group('lang-core parser cases', () {
    final refSchema = CompiledSchema.fromJsonSchema({
      r'$defs': {
        'Stack': {
          'properties': {'children': <String, Object?>{}},
          'required': ['children'],
        },
        'Title': {
          'properties': {'text': <String, Object?>{}},
          'required': ['text'],
        },
        'Table': {
          'properties': {
            'columns': <String, Object?>{},
            'rows': <String, Object?>{},
          },
          'required': ['columns', 'rows'],
        },
      },
    });
    ParseResult parse(String input) => parseProgram(input, refSchema);
    List<ValidationError> errors(String input) => parse(input).meta.errors;
    List<String> codes(String input) => [
      for (final e in errors(input)) e.code.wire,
    ];
    List<Object?> children(ParseResult r) =>
        r.root!.props['children']! as List<Object?>;
    String? titleText(ParseResult r) {
      final kids = r.root?.props['children'] as List<Object?>?;
      final first = kids == null || kids.isEmpty ? null : kids.first;
      return first is ElementNode ? first.props['text'] as String? : null;
    }

    group('unknown-component', () {
      test('reports when component name is not in schema', () {
        final result = parse('root = DataTable("col")');
        expect(result.meta.errors, hasLength(1));
        expect(result.meta.errors.single.code, ValidationCode.unknownComponent);
        expect(result.meta.errors.single.component, 'DataTable');
      });

      test('drops unknown component from tree (returns null)', () {
        expect(parse('root = DataTable("col")').root, isNull);
      });

      test('reports all unknown components in a tree', () {
        expect(
          codes('root = Stack([Ghost("a")])\n'),
          contains('unknown-component'),
        );
      });

      test('does not report for known component names', () {
        expect(
          codes('root = Stack(["hello"])'),
          isNot(contains('unknown-component')),
        );
        expect(parse('root = Stack(["hello"])').meta.errors, isEmpty);
      });
    });

    group('excess-args', () {
      test('reports excess-args error but still renders with valid args', () {
        final result = parse('root = Title("hello", "extra")');
        expect(
          codes('root = Title("hello", "extra")'),
          contains('excess-args'),
        );
        expect(result.root!.props['text'], 'hello');
      });

      test('excess-args message lists count', () {
        final excess = errors(
          'root = Title("hello", "extra", "more")',
        ).firstWhere((e) => e.code == ValidationCode.excessArgs);
        expect(excess.message, contains('2 excess dropped'));
      });

      test('does not report when arg count matches param count', () {
        expect(codes('root = Title("hello")'), isNot(contains('excess-args')));
      });

      test('does not report when fewer args than params', () {
        expect(codes('root = Table([], [])'), isNot(contains('excess-args')));
      });
    });

    group('unresolved references', () {
      test('tracks unresolved refs in meta.unresolved (one-shot)', () {
        expect(parse('root = Stack([tbl])').meta.unresolved, contains('tbl'));
      });

      test('does not produce errors for unresolved refs', () {
        expect(parse('root = Stack([tbl])').meta.errors, isEmpty);
      });

      test('clears unresolved when ref is defined', () {
        expect(
          parse('root = Stack([tbl])\ntbl = Title("hello")').meta.unresolved,
          isEmpty,
        );
      });
    });

    group('unresolved references (streaming)', () {
      test('tracks unresolved refs mid-stream without errors', () {
        final mid = StreamParser(refSchema).push('root = Stack([tbl])\n');
        expect(mid.meta.unresolved, contains('tbl'));
        expect(mid.meta.errors, isEmpty);
      });

      test('resolves automatically when ref is defined in a later chunk', () {
        final sp = StreamParser(refSchema)..push('root = Stack([tbl])\n');
        expect(sp.push('tbl = Title("hello")\n').meta.unresolved, isEmpty);
      });

      test('keeps unresolved refs in meta.unresolved at end of stream', () {
        final sp = StreamParser(refSchema)..push('root = Stack([tbl])\n');
        final result = sp.getResult();
        expect(result.meta.unresolved, contains('tbl'));
        expect(result.meta.errors, isEmpty);
      });
    });

    group('existing errors carry type and code', () {
      test('missing-required has correct shape', () {
        final result = parse('root = Stack()');
        expect(result.meta.errors, hasLength(1));
        expect(result.meta.errors.single.code, ValidationCode.missingRequired);
        expect(result.meta.errors.single.component, 'Stack');
      });

      test('null-required has correct shape', () {
        final result = parse('root = Stack(null)');
        expect(result.meta.errors, hasLength(1));
        expect(result.meta.errors.single.code, ValidationCode.nullRequired);
        expect(result.meta.errors.single.component, 'Stack');
      });
    });

    group('array null-dropping', () {
      test('drops unresolved refs from children arrays', () {
        final kids = children(
          parse('root = Stack([missing, t1])\nt1 = Title("ok")'),
        );
        expect(kids, hasLength(1));
        expect((kids.single! as ElementNode).typeName, 'Title');
      });

      test('drops invalid components (missing required props) from arrays', () {
        final kids = children(
          parse('root = Stack([bad, good])\nbad = Title()\ngood = Title("ok")'),
        );
        expect(kids, hasLength(1));
        expect((kids.single! as ElementNode).props['text'], 'ok');
      });

      test('drops unknown components from arrays', () {
        final kids = children(
          parse('root = Stack([u, t1])\nu = Ghost("x")\nt1 = Title("ok")'),
        );
        expect(kids, hasLength(1));
        expect((kids.single! as ElementNode).typeName, 'Title');
      });

      test('preserves null literals in arrays', () {
        expect(children(parse('root = Stack([null, null])')), [null, null]);
      });

      test('streaming: unresolved refs fill in when defined later', () {
        final sp = StreamParser(refSchema);
        final p1 = sp.push('root = Stack([t1, t2])\nt1 = Title("first")\n');
        expect(children(p1), hasLength(1));
        final p2 = sp.push('t2 = Title("second")\n');
        expect(children(p2), hasLength(2));
      });
    });

    group('orphaned statements', () {
      test('detects unreachable statements on complete parse', () {
        final orphaned = parse(
          'root = Stack([t1])\nt1 = Title("used")\norphan = Title("unused")',
        ).meta.orphaned;
        expect(orphaned, contains('orphan'));
        expect(orphaned, isNot(contains('t1')));
        expect(orphaned, isNot(contains('root')));
      });

      test('no orphans when all statements are reachable', () {
        expect(
          parse(
            'root = Stack([t1, t2])\nt1 = Title("a")\nt2 = Title("b")',
          ).meta.orphaned,
          isEmpty,
        );
      });

      test('orphaned computed during streaming too', () {
        final p1 = StreamParser(refSchema).push(
          'root = Stack([t1])\nt1 = Title("a")\norphan = Title("stray")\n',
        );
        expect(p1.meta.orphaned, contains('orphan'));
        expect(p1.meta.orphaned, isNot(contains('t1')));
      });

      test('detects multiple orphaned statements', () {
        expect(
          parse(
            'root = Stack([t1])\nt1 = Title("used")\na = Title("x")\nb = Title("y")',
          ).meta.orphaned,
          unorderedEquals(['a', 'b']),
        );
      });

      test('deeply nested refs are not orphaned', () {
        expect(
          parse(
            'root = Stack([t1])\nt1 = Table([col], rows)\ncol = Title("Name")\nrows = [["Alice"]]',
          ).meta.orphaned,
          isEmpty,
        );
      });
    });

    group('markdown fences and multiline comments in strings', () {
      test('preserves js markdown fences inside strings', () {
        final result = parse(
          r'root = Title("```js\nconsole.log(\"Hello World\");\n```")',
        );
        expect(result.meta.errors, isEmpty);
        expect(
          result.root!.props['text'],
          '```js\nconsole.log("Hello World");\n```',
        );
      });

      test('preserves python fenced code blocks inside strings', () {
        final result = parse(
          r'''root = Title("```python\nprint('hi')\n```")''',
        );
        expect(result.meta.errors, isEmpty);
        expect(result.root!.props['text'], "```python\nprint('hi')\n```");
      });

      test('preserves // inside multiline strings', () {
        final result = parse(
          'root = Title("\nHello // World\nhttps://example.com/\n")',
        );
        expect(result.meta.errors, isEmpty);
        expect(
          result.root!.props['text'],
          '\nHello // World\nhttps://example.com/\n',
        );
      });

      test('preserves # inside multiline strings', () {
        final result = parse(
          'root = Title("\nHello # World\nhttps://example.com/\n")',
        );
        expect(result.meta.errors, isEmpty);
        expect(
          result.root!.props['text'],
          '\nHello # World\nhttps://example.com/\n',
        );
      });

      test(
        'does not treat apostrophes as string delimiters when stripping fences',
        () {
          final result = parse(
            "Here's the code:\n\n```js\nroot = Title(\"hello\")\n```",
          );
          expect(result.meta.errors, isEmpty);
          expect(result.root!.props['text'], 'hello');
        },
      );
    });

    group('redefined statement IDs', () {
      const withNewline = 'root = Stack([a])\na = Title("x")\na = Title("y")\n';
      const withoutNewline =
          'root = Stack([a])\na = Title("x")\na = Title("y")';
      String? pushAll(void Function(StreamParser sp) write) {
        final sp = StreamParser(refSchema);
        write(sp);
        return titleText(sp.getResult());
      }

      test('parse() last-wins with and without a trailing newline', () {
        expect(titleText(parse(withNewline)), 'y');
        expect(titleText(parse(withoutNewline)), 'y');
      });

      test('stream parser last-wins for a single push, matching parse()', () {
        expect(pushAll((sp) => sp.push(withNewline)), 'y');
        expect(pushAll((sp) => sp.push(withoutNewline)), 'y');
      });

      test(
        'stream parser last-wins line-by-line and character-by-character',
        () {
          expect(
            pushAll((sp) {
              for (final line in withNewline.split(RegExp('(?<=\n)'))) {
                if (line.isNotEmpty) sp.push(line);
              }
            }),
            'y',
          );
          expect(
            pushAll((sp) {
              for (final ch in withNewline.split('')) {
                sp.push(ch);
              }
            }),
            'y',
          );
          expect(
            pushAll((sp) {
              for (final ch in withoutNewline.split('')) {
                sp.push(ch);
              }
            }),
            'y',
          );
        },
      );

      test('stream parser last-wins across a two-chunk split', () {
        expect(
          pushAll(
            (sp) => sp
              ..push('root = Stack([a])\na = Title("x")\n')
              ..push('a = Title("y")\n'),
          ),
          'y',
        );
        expect(
          pushAll(
            (sp) => sp
              ..push('root = Stack([a])\na = Title("x")\n')
              ..push('a = Title("y")'),
          ),
          'y',
        );
      });

      test('stream parser last-wins via set(), matching the renderer path', () {
        expect(titleText(StreamParser(refSchema).set(withoutNewline)), 'y');
      });

      test(
        'an incomplete pending redefinition does not clobber a completed statement',
        () {
          final sp = StreamParser(refSchema)
            ..push('root = Stack([a])\na = Title("x")\n');
          expect(titleText(sp.push('a = Title("y')), 'x');
          expect(titleText(sp.push('")\n')), 'y');
        },
      );
    });
  });

  // Ported from lang-core 1.0.0 parser/__tests__/entry.test.ts.
  group('lang-core entry rule cases', () {
    final entrySchema = CompiledSchema.fromJsonSchema({
      r'$defs': {
        'Card': {
          'properties': {'children': <String, Object?>{}},
          'required': ['children'],
        },
        'Title': {
          'properties': {'text': <String, Object?>{}},
          'required': ['text'],
        },
      },
    });
    List<String> codes(ParseResult r) => [
      for (final e in r.meta.errors) e.code.wire,
    ];

    test(
      'falls back to a first root-component statement, after \$state, with a no-root warning',
      () {
        final r = parseProgram(
          '\$t = 1\npage = Card([t])\nt = Title("x")',
          entrySchema,
          rootName: 'Card',
        );
        expect([r.root!.typeName, r.root!.statementId], ['Card', 'page']);
        expect(codes(r), ['no-root']);
        expect(r.meta.errors.single.isWarning, isTrue);
      },
    );

    test(
      'falls back to a later root-component statement when children come first',
      () {
        final r = parseProgram(
          't = Title("x")\npage = Card([t])',
          entrySchema,
          rootName: 'Card',
        );
        expect([r.root!.typeName, r.root!.statementId], ['Card', 'page']);
        expect(r.meta.orphaned, isEmpty);
        expect(codes(r), ['no-root']);
        expect(r.meta.errors.single.isWarning, isTrue);
      },
    );

    test('renders nothing and reports no orphans when there is no entry', () {
      final r = parseProgram('t = Title("x")', entrySchema, rootName: 'Card');
      expect(r.root, isNull);
      expect(r.meta.orphaned, isEmpty);
      expect(codes(r), ['no-root']);
      expect(r.meta.errors.single.isWarning, isFalse);
      expect(codes(parseProgram('page = Card([])', entrySchema)), ['no-root']);
    });

    test('evaluates a ternary entry at runtime', () {
      final r = parseProgram(
        '\$t = true\nroot = \$t ? a : b\na = Title("A")\nb = Title("B")',
        entrySchema,
      );
      expect(r.meta.errors, isEmpty);
      final picked = evaluateRoot(
        r,
        EvaluationContext(getState: (_) => false, resolveRef: (_) => null),
        (_, _) => false,
        [],
      );
      expect([picked!.typeName, picked.props['text']], ['Title', 'B']);
    });

    test(
      'reports an unknown @Name call as unknown-function and keeps the statement',
      () {
        final r = parseProgram('root = Title("p" + @Foo(1))', entrySchema);
        expect(codes(r), ['unknown-function']);
        final text = r.root!.props['text']! as BinOpNode;
        expect(text.right, isA<NullNode>());
      },
    );
  });
}
