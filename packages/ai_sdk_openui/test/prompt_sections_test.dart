import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:test/test.dart';

final class _Spec implements ComponentSpec {
  const _Spec(this.typeName, this.props, [this.description = '']);
  @override
  final String typeName;
  @override
  final Map<String, Schema> props;
  @override
  final String description;
}

final _card = _Spec('Card', {'title': S.string()}, 'A card');
final _toggle = _Spec('Toggle', {'on': S.boolean().reactive()});
final _link = _Spec('Link', {
  'label': S.string(),
  'action': S.string().tag('@OpenUrl | @ToAssistant').optional(),
});
final _button = _Spec('Button', {'label': S.string(), 'action': actionSchema});

final _double = FunctionSpec(
  'Double',
  description: 'Twice n',
  params: {'n': S.number()},
  returns: S.number(),
  fn: (a) => (a['n'] as num) * 2,
);
final _copy = ActionSpec(
  'Copy',
  description: 'Copies text',
  params: {'text': S.string()},
);

OpenUiLibrary _lib(
  List<ComponentSpec> components, {
  List<ComponentGroup> groups = const [],
  List<FunctionSpec> functions = const [],
  List<ActionSpec> actions = const [],
}) => OpenUiLibrary(
  root: components.first,
  components: components,
  groups: groups,
  functions: functions,
  actions: actions,
);

/// Lines of [prompt] from [heading] up to the next `## ` heading.
String _section(String prompt, String heading) {
  final start = prompt.indexOf(heading);
  expect(start, isNonNegative, reason: 'missing "$heading"');
  final next = prompt.indexOf('\n## ', start + heading.length);
  return prompt.substring(start, next < 0 ? prompt.length : next).trimRight();
}

void main() {
  group('streaming order follows what the prompt teaches', () {
    test('without bindings or tools there are three steps', () {
      final p = _lib([_card]).systemPrompt();
      expect(
        _section(p, '**Recommended statement order'),
        '**Recommended statement order for optimal streaming:**\n'
        '1. `root = Card(...)` — UI shell appears immediately\n'
        '2. Component definitions — fill in as they stream\n'
        '3. Data values — leaf content last\n\n'
        'Always write the root = Card(...) statement first so the UI shell appears immediately, even before child data has streamed in.',
      );
    });

    test('bindings add variable declarations', () {
      final p = _lib([_card]).systemPrompt(const PromptOptions(bindings: true));
      expect(
        p,
        contains(
          '1. `root = Card(...)` — UI shell appears immediately\n'
          '2. \$variable declarations — state ready for bindings\n'
          '3. Component definitions — fill in with data already available\n'
          '4. Data values — leaf content last',
        ),
      );
    });

    test('tool calls add the query step', () {
      final p = _lib([
        _card,
      ]).systemPrompt(const PromptOptions(toolCalls: true));
      expect(
        p,
        contains(
          '2. \$variable declarations — state ready for bindings\n'
          '3. Query statements — defaults resolve immediately so components render with data\n'
          '4. Component definitions — fill in with data already available\n'
          '5. Data values — leaf content last',
        ),
      );
    });
  });

  group('component signatures', () {
    test('without groups components list in order, with descriptions', () {
      final p = _lib([_card, _toggle]).systemPrompt();
      expect(
        _section(p, '## Component Signatures'),
        '## Component Signatures\n\n'
        'Arguments marked with ? are optional. Sub-components can be inline or referenced; prefer references for better streaming.\n'
        'Props marked `\$binding<type>` accept a `\$variable` reference for two-way binding.\n\n'
        'Card(title: string) — A card\n'
        'Toggle(on: \$binding<boolean>)',
      );
    });

    test('components outside every group list under Other', () {
      final p = _lib(
        [_card, _toggle, _link],
        groups: [
          ComponentGroup('Content', [_card], notes: ['Note: cards nest.']),
        ],
      ).systemPrompt();
      expect(
        _section(p, '## Component Signatures'),
        '## Component Signatures\n\n'
        'Arguments marked with ? are optional. Sub-components can be inline or referenced; prefer references for better streaming.\n'
        'Props typed `ActionExpression` accept one @step, or Action([@steps...]) for several. See the Action section for available steps (@ToAssistant, @OpenUrl).\n'
        'Props typed like `@OpenUrl | @ToAssistant` accept only the steps listed.\n'
        'Props marked `\$binding<type>` accept a `\$variable` reference for two-way binding.\n\n'
        '### Content\n'
        'Card(title: string) — A card\n'
        'Note: cards nest.\n\n'
        '### Other\n'
        'Toggle(on: \$binding<boolean>)\n'
        'Link(label: string, action?: @OpenUrl | @ToAssistant)',
      );
    });

    test('a component named in two groups prints once', () {
      final p = _lib(
        [_card, _toggle],
        groups: [
          ComponentGroup('A', [_card]),
          ComponentGroup('B', [_card, _toggle]),
        ],
      ).systemPrompt();
      expect(
        _section(p, '### A'),
        '### A\nCard(title: string) — A card\n\n### B\nToggle(on: \$binding<boolean>)',
      );
      expect(p, isNot(contains('### Other')));
    });
  });

  group('functions and actions without the built-in sections', () {
    test('builtinFunctions: false still lists the library functions', () {
      final p = _lib(
        [_card],
        functions: [_double],
      ).systemPrompt(const PromptOptions());
      expect(
        _section(p, '## Built-in Functions'),
        '## Built-in Functions\n\n@Double(n: number) → number — Twice n',
      );
      expect(p, isNot(contains('These are the ONLY functions available')));
    });

    test('builtinFunctions: false with bindings drops the built-in lines', () {
      final p = _lib([_card], functions: [_double]).systemPrompt(
        const PromptOptions(bindings: true, builtinFunctions: false),
      );
      expect(
        _section(p, '## Built-in Functions'),
        '## Built-in Functions\n\n@Double(n: number) → number — Twice n',
      );
    });

    test('builtinFunctions: true prints the full built-in section', () {
      final p = _lib([
        _card,
      ]).systemPrompt(const PromptOptions(builtinFunctions: true));
      expect(
        p,
        contains(
          'Data functions prefixed with `@` to distinguish from components. These are the ONLY functions available — do NOT invent new ones.',
        ),
      );
      expect(p, contains('@Count(array: any[]) → number'));
    });

    test('no functions and builtinFunctions: false print no section', () {
      final p = _lib([_card]).systemPrompt();
      expect(p, isNot(contains('## Built-in Functions')));
    });

    test('actions without an ActionExpression prop get a short section', () {
      final p = _lib([_card], actions: [_copy]).systemPrompt();
      expect(
        _section(p, '## Action — Button Behavior'),
        '## Action — Button Behavior\n\n'
        'Pass one step, or Action([...]) with several steps, as a button\'s action.\n\n'
        'Available steps:\n'
        '- @Copy(text: string) — Copies text',
      );
    });

    test('no actions and no ActionExpression print no action section', () {
      final p = _lib([_card]).systemPrompt();
      expect(p, isNot(contains('## Action')));
    });

    test('an ActionExpression prop prints the full action section', () {
      final p = _lib([_button], actions: [_copy]).systemPrompt();
      final section = _section(p, '## Action — Button Behavior');
      expect(
        section,
        contains(
          'Available steps:\n'
          '- @ToAssistant(message: string, context?: any)',
        ),
      );
      expect(section, contains('- @OpenUrl(url: string) — Navigate to a URL'));
      expect(
        section,
        endsWith(
          '- @Copy(text: string) — Copies text\n\n'
          'Example — simple nav:\n'
          '```\n'
          'viewBtn = Button("View", @OpenUrl("https://example.com"))\n'
          '```\n\n'
          '- An action can be assigned to a variable or inlined: Button("Go", onSubmit) and Button("Go", Action([...])) both work',
        ),
      );
      expect(
        section,
        isNot(contains('@Run')),
        reason: 'no tool calls, so no @Run step',
      );
      expect(
        section,
        isNot(contains('@Set')),
        reason: 'no bindings, so no @Set step',
      );
    });
  });

  group('optional sections', () {
    test('tool calls add Query, Mutation, workflow and filter sections', () {
      final p = _lib([
        _card,
      ]).systemPrompt(const PromptOptions(toolCalls: true));
      for (final heading in [
        '## Query — Live Data Fetching',
        '## Mutation — Write Operations',
        '## Interactive Filters',
        '## Data Workflow',
      ]) {
        expect(p, contains('\n$heading\n'));
      }
      expect(
        p,
        contains(
          '3. Every Query result is referenced by at least one component.\n'
          '4. Every \$binding appears in at least one component or expression.\n'
          '5. Every visible filter \$binding appears in at least one Query args object.',
        ),
      );
    });

    test('tool calls without bindings skip the filters section', () {
      final p = _lib([
        _card,
      ]).systemPrompt(const PromptOptions(toolCalls: true, bindings: false));
      expect(p, isNot(contains('## Interactive Filters')));
      expect(
        p,
        endsWith(
          '2. Every referenced name is defined. Every defined name (other than root) is reachable from root.\n'
          '3. Every Query result is referenced by at least one component.',
        ),
      );
    });

    test('edit mode appends the patch rules before the final rules', () {
      final p = _lib([_card]).systemPrompt(const PromptOptions(editMode: true));
      expect(
        _section(p, '## Edit Mode'),
        startsWith(
          '## Edit Mode\n\n'
          'The runtime merges by statement name: same name = replace, new name = append.\n'
          'Output ONLY statements that changed or are new. Everything else is kept automatically.',
        ),
      );
      expect(
        p,
        contains(
          '- If you are about to output more than 10 statements, reconsider — most edits need fewer\n## Important Rules',
        ),
      );
    });

    test('inline mode explains the two response kinds', () {
      final p = _lib([
        _card,
      ]).systemPrompt(const PromptOptions(inlineMode: true));
      expect(
        _section(p, '## Inline Mode'),
        startsWith(
          '## Inline Mode\n\n'
          'You are in inline mode. You can respond in two ways:\n\n'
          '### 1. Code response (when the user wants to CREATE or CHANGE the UI)',
        ),
      );
      expect(
        p,
        contains(
          '- The parser extracts code from fences automatically. Text outside fences is shown as chat.\n## Important Rules',
        ),
      );
    });

    test('examples and additional rules close the prompt', () {
      final p = _lib([_card]).systemPrompt(
        const PromptOptions(
          preamble: 'Speak openui.',
          examples: ['root = Card("a")'],
          toolExamples: ['root = Card("b")'],
          additionalRules: ['Keep it short.'],
        ),
      );
      expect(p, startsWith('Speak openui.\n\n## Syntax Rules'));
      expect(
        p,
        contains('## Examples\n\nroot = Card("a")\n\nroot = Card("b")\n\n'),
      );
      expect(p, endsWith('\n\n- Keep it short.'));
    });

    test('tools list their arguments, return type and query defaults', () {
      final tool = OpenUiTool(
        name: 'get_rows',
        description: 'Reads rows',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'days': {'type': 'number'},
            'tag': {'type': 'string'},
          },
          'required': ['days'],
        },
        outputSchema: const {
          'type': 'object',
          'properties': {
            'rows': {
              'type': 'array',
              'items': {'type': 'string'},
            },
            'total': {'type': 'number'},
          },
          'required': ['rows'],
        },
        call: (args) async => null,
      );
      final p = _lib([_card]).systemPrompt(PromptOptions(tools: [tool]));
      expect(
        p,
        contains(
          '- get_rows(days: number, tag?: string) → {rows: string[], total?: number}\n'
          '  Reads rows',
        ),
      );
      expect(p, contains('- get_rows: `{"rows":[],"total":0}`'));
    });
  });
}
