import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

final class _Link implements ComponentSpec {
  @override
  String get typeName => 'Link';
  @override
  String get description => '';
  @override
  Map<String, Schema> get props => {
    'action': S.union([Steps.openUrl, Steps.toAssistant]),
  };
}

final _otherSteps = RegExp(r'@(OpenUrl|Run|Set|Reset|CopyToClipboard)\b');
final _missingCapabilities = RegExp(
  r'\b(tables?|charts?|forms?)\b',
  caseSensitive: false,
);

/// Whether [prompt] calls component [name]: `Name(`, not `SomeName(` or `@Name(`.
bool _calls(String prompt, String name) =>
    RegExp('(?<![\\w@])$name\\(').hasMatch(prompt);

/// [prompt] without each of [hostText].
String _withoutHostText(String prompt, List<String> hostText) {
  var out = prompt;
  for (final t in hostText) {
    expect(out, contains(t));
    out = out.replaceAll(t, '');
  }
  return out;
}

void main() {
  group('a library with components removed', () {
    const keep = {
      'Col',
      'Row',
      'Box',
      'Grid',
      'Card',
      'Title',
      'Text',
      'Caption',
      'Button',
      'Input',
      'Select',
      'SegmentedControl',
      'Checkbox',
    };
    final removed = [
      for (final name in intelligentUi.components.keys)
        if (!keep.contains(name)) name,
    ];
    final lib = intelligentUi.extend(
      LibraryExtension(removeComponents: removed),
    );

    test('its chat prompt calls no removed component', () {
      final prompt = lib.systemPrompt(chatPromptFor(lib));
      expect([
        for (final name in removed)
          if (_calls(prompt, name)) name,
      ], isEmpty);
      expect(prompt, contains('- Spacing is a system with three tiers'));
      expect(prompt, isNot(contains('sits in a Form')));
    });

    test('its dashboard prompt calls no removed component', () {
      final prompt = lib.systemPrompt(dashboardPrompt(library: lib));
      expect([
        for (final name in removed)
          if (_calls(prompt, name)) name,
      ], isEmpty);
      expect(prompt, contains('- Fetch rows with Query'));
    });

    test('a bare prompt keeps descriptions to present components', () {
      final prompt = lib.systemPrompt();
      expect(prompt, isNot(contains('Icon(')));
      expect(prompt, isNot(contains('Badge(')));
      expect(
        prompt,
        contains(
          'Paragraph; supports **bold**, *italic*, `code` and [links](https://…).\n',
        ),
      );
    });

    test('examples and rules that use only present components stay', () {
      final lean = intelligentUiWithout(optionalIuiComponents);
      expect(chatPromptFor(lean).examples, chatPrompt.examples);
      expect(
        dashboardPrompt(library: lean).toolExamples,
        dashboardPrompt().toolExamples,
      );
    });

    test('a medium rule with no present medium is dropped', () {
      final plain = intelligentUi.extend(
        const LibraryExtension(
          removeComponents: [
            'Chart',
            'Svg',
            'Circle',
            'Ellipse',
            'Rect',
            'Line',
            'Path',
            'Polyline',
            'Polygon',
            'G',
            'SvgText',
            'Map',
            'MapMarker',
            'Table',
            'Flashcard',
            'Celebration',
            'HtmlView',
          ],
        ),
      );
      expect(
        chatPromptFor(
          plain,
        ).additionalRules.where((r) => r.startsWith('Pick the medium')),
        isEmpty,
      );
    });
  });

  group('a library with only @ToAssistant and a small layout set', () {
    final lib = OpenUiLibrary(
      root: IuiComponent.col,
      components: const [
        IuiComponent.col,
        IuiComponent.row,
        IuiComponent.card,
        IuiComponent.title,
        IuiComponent.text,
        IuiComponent.button,
      ],
      groups: intelligentUi.groups,
    );
    const preamble = 'You draw cards for a budgeting app.';
    const example = 'Example: root = Col([Title("Budget")])';
    const rule = 'Keep every card short.';
    const options = PromptOptions(
      preamble: preamble,
      examples: [example],
      additionalRules: [rule],
      bindings: true,
      allowedActions: {'ToAssistant'},
    );

    test('its prompt names no other step and no missing capability', () {
      final prompt = lib.systemPrompt(options);
      expect(prompt, contains('- @ToAssistant(message: string'));
      final fixed = _withoutHostText(prompt, [preamble, example, rule]);
      expect(_otherSteps.allMatches(fixed).map((m) => m[0]), isEmpty);
      expect(_missingCapabilities.allMatches(fixed).map((m) => m[0]), isEmpty);
      expect(fixed, isNot(contains('### Media and data')));
    });

    test('a bare prompt still lists @OpenUrl but no missing capability', () {
      final prompt = lib.systemPrompt();
      expect(prompt, contains('- @OpenUrl(url: string)'));
      expect(prompt, isNot(contains('@Set(')));
      expect(_missingCapabilities.allMatches(prompt).map((m) => m[0]), isEmpty);
      expect(
        prompt,
        contains('- Choose components that best represent the content\n'),
      );
    });

    test('function descriptions drop the clauses about a hidden step', () {
      final prompt = OpenUiLibrary(
        root: IuiComponent.col,
        components: const [IuiComponent.col, IuiComponent.button],
        functions: intelligentUi.functions,
      ).systemPrompt(options);
      expect(
        prompt,
        contains(
          '@Pick(list: any[]) → any — A random item, or null for an empty list\n',
        ),
      );
      expect(prompt, isNot(contains('@Set')));
    });

    test('with tools but no @Run there is no refresh step or Mutation', () {
      final prompt = lib.systemPrompt(
        PromptOptions(
          toolNames: const ['get_rows'],
          allowedActions: const {'ToAssistant', 'Set', 'Reset'},
        ),
      );
      expect(prompt, contains('## Query'));
      expect(prompt, isNot(contains('@Run')));
      expect(prompt, isNot(contains('## Mutation')));
      expect(prompt, isNot(contains('Mutation(')));
      expect(prompt, contains('- @Reset(variable: \$variable)'));
    });

    test('bound data and restricted slots name only offered steps', () {
      final prompt = OpenUiLibrary(root: _Link(), components: [_Link()])
          .systemPrompt(
            PromptOptions(
              records: [
                BoundRecord('budget', const {'left': 120}),
              ],
              allowedActions: const {'ToAssistant'},
            ),
          );
      expect(prompt, contains('and never bind them to an input.'));
      expect(prompt, contains('Props typed as a union of @steps accept only'));
      expect(prompt, isNot(contains('@Set')));
      expect(prompt, isNot(contains('@OpenUrl(')));
    });

    test('a library action outside the allowed set is not listed', () {
      final copy = ActionSpec(
        'Copy',
        description: 'Copies text',
        params: {'text': S.string()},
      );
      final withCopy = OpenUiLibrary(
        root: IuiComponent.col,
        components: const [IuiComponent.col, IuiComponent.button],
        actions: [copy],
      );
      expect(withCopy.systemPrompt(), contains('- @Copy(text: string)'));
      expect(withCopy.systemPrompt(options), isNot(contains('@Copy')));
    });
  });
}
