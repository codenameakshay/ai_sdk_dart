import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:ai_sdk_openui/src/lang/validation.dart';
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

void main() {
  group('createParser', () {
    test('parses a program against the named root', () {
      final r = createParser(
        _lib.toJsonSchema(),
        rootName: 'Col',
      ).parse('root = Col([Text("a")])');
      expect(r.root!.typeName, 'Col');
      expect(r.meta.errors, isEmpty);
      expect(r.meta.statementCount, 1);
    });

    test('reports no-root when no root name is given', () {
      final r = createParser(_lib.toJsonSchema()).parse('x = Col([])');
      expect(r.root, isNull);
      expect(r.meta.errors.single.code, ValidationCode.noRoot);
    });
  });

  group('createStreamingParser', () {
    test('marks the root partial until the stream completes', () {
      final p = createStreamingParser(_lib.toJsonSchema(), rootName: 'Col');
      expect(p.push('root = Col([Text("a"').root!.partial, isTrue);
      expect(p.push(')])', complete: true).root!.partial, isFalse);
      expect(p.getResult(complete: true).root!.typeName, 'Col');
    });
  });
}
