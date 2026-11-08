import 'package:ai_sdk_openui/src/lang/merge.dart';
import 'package:test/test.dart';

const _existing = 'root = Col([a, b])\na = Text("A")\nb = Text("B")';

void main() {
  group('mergeStatements', () {
    test('replaces a statement by name and keeps the others', () {
      expect(
        mergeStatements(_existing, 'b = Text("B2")'),
        'root = Col([a, b])\na = Text("A")\nb = Text("B2")',
      );
    });

    test('drops statements the new root no longer reaches', () {
      expect(
        mergeStatements(_existing, 'root = Col([a])'),
        'root = Col([a])\na = Text("A")',
      );
    });

    test('appends new statements that the patch root reaches', () {
      expect(
        mergeStatements(_existing, 'c = Text("C")\nroot = Col([a, b, c])'),
        'root = Col([a, b, c])\na = Text("A")\nb = Text("B")\nc = Text("C")',
      );
    });

    test('a null statement deletes the statement of that name', () {
      expect(
        mergeStatements(_existing, 'b = null'),
        'root = Col([a, b])\na = Text("A")',
      );
    });

    test('keeps state statements when unreachable statements are dropped', () {
      expect(
        mergeStatements(
          'root = Col([a])\na = Text("A")\n\$x = 1\nq = Query("t", {}, {})',
          'root = Col([])',
        ),
        'root = Col([])\n\$x = 1',
      );
    });

    test('an empty existing program returns the patch without fences', () {
      expect(mergeStatements('', '```\nroot = A()\n```'), 'root = A()');
    });

    test('an empty patch returns the existing program unchanged', () {
      expect(mergeStatements('root = A()\n\n', '  '), 'root = A()\n\n');
    });

    test('without a root statement nothing is dropped', () {
      expect(
        mergeStatements('x = A()\ny = B()', 'y = C()'),
        'x = A()\ny = C()',
      );
    });

    test('keeps a multi-line statement verbatim', () {
      expect(
        mergeStatements(
          'root = Col([\n  a\n])\na = Text("A")',
          'a = Text("Z")',
        ),
        'root = Col([\n  a\n])\na = Text("Z")',
      );
    });

    test('uses the given root name for reachability', () {
      expect(
        mergeStatements(
          'main = Col([a])\na = T()\nb = T()',
          'b = T(1)',
          'main',
        ),
        'main = Col([a])\na = T()',
      );
    });
  });
}
