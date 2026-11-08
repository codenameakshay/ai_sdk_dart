import 'package:ai_sdk_openui/lang_core.dart';
import 'package:test/test.dart';

void main() {
  test('the lang-core barrel exports mergeStatements', () {
    expect(
      mergeStatements('root = Col([a])\na = Text("A")', 'a = Text("B")'),
      'root = Col([a])\na = Text("B")',
    );
  });
}
