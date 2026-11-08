import 'package:ai_sdk_openui/src/lang/ast.dart';
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
}
