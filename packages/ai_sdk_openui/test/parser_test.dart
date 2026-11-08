import 'dart:convert';

import 'package:ai_sdk_openui/src/lang/ast.dart';
import 'package:ai_sdk_openui/src/lang/parser.dart';
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
}
