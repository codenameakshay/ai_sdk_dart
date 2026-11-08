import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/lang_core.dart';
import 'package:test/test.dart';

final class _Component implements ComponentSpec {
  _Component(this.typeName, this.props);
  @override
  final String typeName;
  @override
  String get description => '';
  @override
  final Map<String, Schema> props;
}

final _text = _Component('Text', {'text': S.string()});
final _col = _Component('Col', {'children': S.list(S.ref('Text'))});
final _lib = OpenUiLibrary(root: _col, components: [_col, _text]);

void main() {
  test(
    'the lang-core surface lexes, parses, evaluates and serializes a program',
    () {
      expect(tokenize('a = 1').first.t, T.ident);
      expect(split(tokenize('a = 1')).single.id, 'a');
      expect(autoClose('x = Col([').text, 'x = Col([])');

      final r = createParser(
        _lib.toJsonSchema(),
        rootName: 'Col',
      ).parse('root = Col([Text("hi")])');
      expect(
        evaluateRoot(
          r,
          EvaluationContext(getState: (_) => null, resolveRef: (_) => null),
          _lib.isReactive,
          [],
        )!.typeName,
        'Col',
      );
      expect(jsonToOpenUI(r.root!, _lib), 'root = Col([Text("hi")])');
      expect(
        mergeStatements('root = Col([a])\na = Text("A")', 'a = Text("B")'),
        'root = Col([a])\na = Text("B")',
      );
    },
  );

  test('the main barrel exposes messages, validation and cloud helpers', () {
    expect(parseMessage(buildMessage(content: 'x')).content, 'x');
    expect(validate('', parseRules(['required'])), 'This field is required');
    expect(cloudSystemPrompt(), startsWith(']]>openui:config\n'));
    expect(
      const ToolNotFoundError('t').message,
      '[openui] No handler for tool "t". Available: (none)',
    );
  });
}
