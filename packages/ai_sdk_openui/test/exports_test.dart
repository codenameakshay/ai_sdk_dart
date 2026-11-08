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

  test('the lang-core free functions and constants', () {
    final r = parse(
      'root = Col([Text("hi")])',
      CompiledSchema.fromJsonSchema(_lib.toJsonSchema()),
      'Col',
    );
    expect(r.root!.typeName, 'Col');
    expect(actionSteps, {
      'Run': 'run',
      'ToAssistant': 'continue_conversation',
      'OpenUrl': 'open_url',
      'Set': 'set',
      'Reset': 'reset',
    });
    expect(generateSystemPrompt(_lib), _lib.systemPrompt());
    expect(
      generatePrompt(
        const PromptSpec(
          root: 'Col',
          components: {'Col': PromptEntry('Col(children: Text[])')},
          toolCalls: true,
        ),
      ),
      allOf(
        contains('Col(children: Text[])'),
        contains('@Count(array: any[])'),
      ),
    );
    expect(
      buildSignature('Card', {
        'title': S.string(),
        'subtitle': S.string().optional(),
      }),
      'Card(title: string, subtitle?: string)',
    );
    final manager = createQueryManager(
      null,
    )..registerMutations([const MutationNode(statementId: 'm', toolName: 't')]);
    expect(manager.getMutationResult('m'), {'status': 'idle'});
  });

  test('resolveStateField binds a reactive field to the store', () {
    final store = Store()..set(r'$n', 1);
    final ctx = EvaluationContext(getState: store.get, resolveRef: (_) => null);
    final bound = resolveStateField<Object?>(
      'n',
      const ReactiveAssign(
        r'$n',
        BinOpNode('+', StateRefNode(r'$value'), NumNode(1)),
      ),
      store,
      ctx,
      (_) => null,
      (_, _) {},
    );
    expect([bound.value, bound.isReactive], [1, true]);
    bound.setValue(4);
    expect(store.get(r'$n'), 5);

    final fields = <String, Object?>{'n': 'kept'};
    final plain = resolveStateField<Object?>(
      'n',
      'default',
      null,
      null,
      (name) => fields[name],
      (name, value) => fields[name] = value,
    );
    expect([plain.value, plain.isReactive], ['kept', false]);
    plain.setValue('new');
    expect(fields['n'], 'new');
  });
}
