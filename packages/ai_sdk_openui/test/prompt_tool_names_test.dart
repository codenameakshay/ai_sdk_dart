import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/src/spec/schema.dart';
import 'package:test/test.dart';

final class _C implements ComponentSpec {
  const _C(this.typeName, this.props);
  @override
  final String typeName;
  @override
  final Map<String, Schema> props;
  @override
  String get description => '';
}

final _text = _C('Text', {'text': S.string()});
final _col = _C('Col', {'children': S.list(S.ref('Text'))});
final _lib = OpenUiLibrary(root: _col, components: [_col, _text]);

void main() {
  test('tool names are listed under Available Tools with the Query guidance', () {
    final prompt = _lib.systemPrompt(
      const PromptOptions(toolNames: ['get_users', 'create_item']),
    );

    expect(
      prompt,
      contains(
        "## Available Tools\n\nUse these with Query() for read operations or Mutation() for write operations. The LLM decides which is appropriate based on the tool's purpose.\n\n- get_users\n- create_item\n\nCRITICAL: Use ONLY the tools listed above",
      ),
    );
    expect(prompt, contains('## Query — Live Data Fetching'));
    expect(prompt, isNot(contains('### Default values for Query results')));
  });

  test('tool names are listed before tool signatures', () {
    final prompt = _lib.systemPrompt(
      PromptOptions(
        toolNames: const ['a'],
        tools: [
          OpenUiTool(name: 'b', description: 'B tool', call: (_) async => null),
        ],
      ),
    );

    expect(prompt, contains('- a\n- b()\n  B tool'));
  });

  test('tool names without tool calls leave out the Query section', () {
    final prompt = _lib.systemPrompt(
      const PromptOptions(toolNames: ['a'], toolCalls: false),
    );

    expect(prompt, isNot(contains('## Query — Live Data Fetching')));
    expect(prompt, contains('- a'));
  });

  test('toSpec includes the library id as its last key only when set', () {
    final withId = OpenUiLibrary(
      root: _col,
      components: [_col, _text],
      id: 'my-lib',
    ).toSpec();

    expect(withId['id'], 'my-lib');
    expect(withId.keys.last, 'id');
    expect(_lib.toSpec().containsKey('id'), isFalse);
  });

  test('an action ref prints as the action name', () {
    final copy = ActionSpec(
      'Copy',
      description: 'Copy',
      params: {'text': S.string()},
    );

    expect(typeAnnotation(copy.ref), '@Copy');
  });
}
