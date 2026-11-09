import 'dart:convert';

import '../lang/js.dart';
import '../runtime/builtins.dart';
import 'bound.dart';
import 'schema.dart';

/// One line of the prompt: a component, function or action signature.
final class PromptEntry {
  const PromptEntry(this.signature, [this.description]);
  final String signature;
  final String? description;
}

final class PromptGroup {
  const PromptGroup(this.name, this.components, [this.notes = const []]);
  final String name;
  final List<String> components;
  final List<String> notes;
}

/// A tool the program may call from `Query`/`Mutation`, as the prompt shows it.
final class PromptTool {
  const PromptTool(
    this.name, {
    this.description,
    this.inputSchema,
    this.outputSchema,
  });
  final String name;
  final String? description;
  final Map<String, Object?>? inputSchema;
  final Map<String, Object?>? outputSchema;
}

/// Everything lang-core's `generatePrompt` reads.
final class PromptSpec {
  const PromptSpec({
    required this.root,
    required this.components,
    this.groups = const [],
    this.functions = const {},
    this.actions = const {},
    this.builtinFunctionLines,
    this.builtinSteps,
    this.preamble,
    this.bindings,
    this.toolCalls,
    this.builtinFunctions,
    this.tools = const [],
    this.toolNames = const [],
    this.examples = const [],
    this.toolExamples = const [],
    this.additionalRules = const [],
    this.editMode = false,
    this.inlineMode = false,
    this.records = const [],
    this.state = const {},
    this.allowedActions,
  });

  final String root;
  final Map<String, PromptEntry> components;
  final List<PromptGroup> groups;
  final Map<String, PromptEntry> functions;
  final Map<String, PromptEntry> actions;

  /// `@Count(array: any[]) → number — Returns array length`, in order.
  /// Null lists the built-in functions.
  final List<String>? builtinFunctionLines;

  /// Built-in steps in prompt order (Run, ToAssistant, OpenUrl, Set, Reset).
  /// Null lists the built-in steps.
  final Map<String, PromptEntry>? builtinSteps;

  final String? preamble;
  final bool? bindings;
  final bool? toolCalls;
  final bool? builtinFunctions;
  final List<PromptTool> tools;

  /// Tools listed by name only, without a signature.
  final List<String> toolNames;
  final List<String> examples;
  final List<String> toolExamples;
  final List<String> additionalRules;
  final bool editMode;
  final bool inlineMode;

  /// Host-bound read-only `$variables`, listed in a "Bound Data" section.
  final List<BoundRecord> records;

  /// Seeded `$variables` with their values, listed in a "Current State" section.
  /// Other keys are ignored.
  final Map<String, Object?> state;

  /// Built-in steps and [actions] the prompt may name; null allows all.
  final Set<String>? allowedActions;
}

const _preamble =
    'You are an AI assistant that responds using openui-lang, a declarative UI language. Your ENTIRE response must be valid openui-lang code — no markdown, no explanations, just openui-lang.';

final _restrictedSlot = RegExp(r'[:|] @[A-Z]');
final _componentCall = RegExp(r'(?<![@\w.])([A-Z]\w*)\(');
final _stepCall = RegExp(r'@([A-Z]\w*)\b');
const _languageCalls = {'Query', 'Mutation', 'Action'};

/// What the prompt offers, to keep library text from naming anything else.
final class _Scope {
  _Scope(this.components, this.absent, this.hidden);

  /// Components the library has.
  final Set<String> components;

  /// Components a group lists that the library does not have.
  final Set<String> absent;

  /// Built-in steps and library actions the prompt does not list.
  final Set<String> hidden;

  bool offers(String text) =>
      _componentCall
          .allMatches(text)
          .every(
            (m) => components.contains(m[1]) || _languageCalls.contains(m[1]),
          ) &&
      !_stepCall.allMatches(text).any((m) => hidden.contains(m[1])) &&
      !absent.any((n) => RegExp('\\b$n\\b').hasMatch(text));

  /// [signature] with the hidden steps taken out of its step unions; null
  /// when a slot keeps only hidden steps, so the component cannot be written.
  String? signature(String signature) {
    var out = signature;
    for (final h in hidden) {
      out = out
          .replaceAll(RegExp('@$h\\b\\s*\\|\\s*'), '')
          .replaceAll(RegExp('\\s*\\|\\s*@$h\\b'), '');
    }
    return _stepCall.allMatches(out).any((m) => hidden.contains(m[1]))
        ? null
        : out;
  }

  /// [text] without the sentences and `;` clauses that name what is not offered.
  String clauses(String text) {
    if (offers(text)) return text;
    final kept = text.split(RegExp(r'(?<=[.;])\s+')).where(offers).join(' ');
    return kept.endsWith(';') ? kept.substring(0, kept.length - 1) : kept;
  }

  PromptEntry entry(PromptEntry e) =>
      PromptEntry(e.signature, clauses(e.description ?? ''));
}

String functionLine(PromptEntry f) => (f.description ?? '').isNotEmpty
    ? '@${f.signature} — ${f.description}'
    : '@${f.signature}';

String _jsonSchemaType(Map<String, Object?> schema) {
  final type = schema['type'];
  if (type == 'string') {
    final values = schema['enum'];
    if (values is List) return values.map((v) => '"$v"').join(' | ');
    return 'string';
  }
  if (type == 'number' || type == 'integer') return 'number';
  if (type == 'boolean') return 'boolean';
  if (type == 'array') {
    final items = schema['items'];
    return items is Map ? '${_jsonSchemaType(items.cast())}[]' : 'any[]';
  }
  if (type == 'object') {
    final props = schema['properties'];
    if (props is Map && props.isNotEmpty) {
      final required = (schema['required'] as List?) ?? const [];
      return '{${props.entries.map((e) => '${e.key}${required.contains(e.key) ? '' : '?'}: ${_jsonSchemaType((e.value as Map).cast())}').join(', ')}}';
    }
    return 'object';
  }
  return 'any';
}

Object? _defaultFor(Map<String, Object?> schema) {
  final type = schema['type'];
  if (type == 'string') return '';
  if (type == 'number' || type == 'integer') return 0;
  if (type == 'boolean') return false;
  if (type == 'array') return const [];
  if (type == 'object') {
    final props = schema['properties'];
    if (props is Map && props.isNotEmpty) {
      return {
        for (final e in props.entries)
          e.key: _defaultFor((e.value as Map).cast()),
      };
    }
    return const <String, Object?>{};
  }
  return null;
}

String _valueType(Object? v) => switch (v) {
  null => 'null',
  bool() => 'boolean',
  num() => 'number',
  String() => 'string',
  List() => v.isEmpty ? 'any[]' : '${_valueType(v.first)}[]',
  Map() =>
    v.isEmpty
        ? 'object'
        : '{${v.entries.map((e) => '${e.key}: ${_valueType(e.value)}').join(', ')}}',
  _ => 'any',
};

/// The prompt's "Bound Data" section for [records].
String describeBoundRecords(List<BoundRecord> records) => [
  '## Bound Data',
  '',
  'The host provides these read-only \$variables. Read them with dot and index access (`\$name.field`, `\$name[0]`). Never copy their values into literals, and never @Set, @Reset or bind them to an input.',
  '',
  for (final r in records)
    '- ${r.variable}: ${r.schema != null ? _jsonSchemaType(r.schema!) : _valueType(r.value)}'
        '${r.description.isNotEmpty ? ' — ${r.description}' : ''}',
].join('\n');

bool _isStateKey(String key) => key.startsWith(r'$');

String _stateSection(Map<String, Object?> state) => [
  '## Current State',
  '',
  'These \$variables already hold values. Read them; do not declare them again:',
  for (final MapEntry(:key, :value) in state.entries)
    if (_isStateKey(key)) '- $key = ${Js.stringify(value)}',
].join('\n');

String _syntaxRules(
  String root, {
  required bool supportsExpressions,
  required bool bindings,
}) {
  final lines = [
    '## Syntax Rules',
    '',
    '1. Each statement is on its own line: `identifier = Expression`',
    '2. `root` is the entry point — every program must define `root = $root(...)`',
    '3. Expressions are: strings ("..."), numbers, booleans (true/false), null, arrays ([...]), objects ({...}), or component calls TypeName(arg1, arg2, ...)',
    '4. Use references for readability: define `name = ...` on one line, then use `name` later',
    "5. EVERY variable (except root) MUST be referenced by at least one other variable. Unreferenced variables are silently dropped and will NOT render. Always include defined variables in their parent's children/items array.",
    '6. Arguments are POSITIONAL (order matters, not names). Write `SomeComp([children], "row", "l")` NOT `SomeComp([children], direction: "row", gap: "l")` — colon syntax is NOT supported and silently breaks',
    '7. Optional arguments can be omitted from the end',
  ];
  var n = 8;
  if (bindings) {
    lines.add(
      '${n++}. Declare mutable state with `\$varName = defaultValue`. Components marked with `\$binding` can read/write these. Undeclared \$variables are auto-created with null default.',
    );
  }
  if (supportsExpressions) {
    lines.addAll([
      '${n++}. String concatenation: `"text" + \$var + "more"`',
      '${n++}. Dot member access: `query.field` reads a field; on arrays it extracts that field from every element',
      '${n++}. Index access: `arr[0]`, `data[index]`',
      '${n++}. Arithmetic operators: +, -, *, /, % (work on numbers; + is string concat when either side is a string)',
      '${n++}. Comparison: ==, !=, >, <, >=, <=',
      '${n++}. Logical: &&, ||, ! (prefix)',
      '${n++}. Ternary: `condition ? valueIfTrue : valueIfFalse`',
      '${n++}. Parentheses for grouping: `(a + b) * c`',
    ]);
  }
  lines.add('- Strings use double quotes with backslash escaping');
  return lines.join('\n');
}

String _builtinFunctionsSection(
  List<String> builtinLines,
  List<String> custom,
  bool toolCalls, {
  required bool charts,
  required bool tables,
}) {
  final lines = [...builtinLines, ...custom].join('\n');
  final pluckUses = [
    '@Sum',
    '@Avg',
    if (charts) 'charts',
    if (tables) 'tables',
  ].join(', ');
  return '''## Built-in Functions

Data functions prefixed with `@` to distinguish from components. These are the ONLY functions available — do NOT invent new ones.
Use @-prefixed built-in functions (@Count, @Sum, @Avg, @Min, @Max, @Round) on ${toolCalls ? 'Query results' : 'data'}. Do NOT hardcode computed values.

$lines

Builtins compose — output of one is input to the next:
`@Count(@Filter(data.rows, "field", "==", "val"))` for KPIs${charts ? '/chart values' : ''}, `@Round(@Avg(data.rows.score), 1)`, `@Each(data.rows, "item", Comp(item.field))` for per-item rendering.
Array pluck: `data.rows.field` extracts a field from every row → use with $pluckUses.

IMPORTANT @Each rule: The loop variable (e.g. "item") is ONLY available inside the @Each template expression. Always inline the template — do NOT extract it to a separate statement.
CORRECT: `list = @Each(rows, "t", Comp(t.name))`
WRONG: `item = Comp(t.name)` then `list = @Each(rows, "t", item)`, because t is undefined in item.''';
}

const _querySection = r'''## Query — Live Data Fetching

Fetch data from available tools. Returns defaults instantly, swaps in real data when it arrives.

```
metrics = Query("tool_name", {arg1: value, arg2: $binding}, {defaultField: 0, defaultData: []}, refreshInterval?)
```

- First arg: tool name (string)
- Second arg: arguments object (may reference $bindings — re-fetches automatically on change)
- Third arg: default data (rendered immediately before fetch resolves)
- Fourth arg (optional): refresh interval in seconds (e.g. 30 for auto-refresh every 30s)
- Use dot access on results: metrics.totalEvents, metrics.data.day (array pluck)
- Query results must use regular identifiers: `metrics = Query(...)`, NOT `$metrics = Query(...)`
- Manual refresh: `Button("Refresh", Action([@Run(query1), @Run(query2)]), "secondary")` — re-fetches the listed queries
- Refresh all queries: create Action with @Run for each query''';

/// [_querySection], without its `@Run` refresh lines unless [run].
String _query(bool run) => run
    ? _querySection
    : _querySection.substring(0, _querySection.indexOf('\n- Manual refresh'));

const _mutationSection = r'''## Mutation — Write Operations

Execute state-changing tool calls (create, update, delete). Unlike Query (auto-fetches on render), Mutation fires only on button click via Action.

```
result = Mutation("tool_name", {arg1: $binding, arg2: "value"})
```

- First arg: tool name (string)
- Second arg: arguments object (evaluated with current $binding values at click time)
- result.status: "idle" | "loading" | "success" | "error"
- result.data: tool response on success
- result.error: error message on failure
- Mutation results use regular identifiers: `result = Mutation(...)`, NOT `$result`
- Show loading state: `result.status == "loading" ? TextContent("Saving...") : null`''';

const _actionHeader = '## Action — Button Behavior';

List<MapEntry<String, PromptEntry>> _visibleSteps(
  PromptSpec spec, {
  required bool toolCalls,
  required bool bindings,
}) => [
  for (final e in (spec.builtinSteps ?? _builtinSteps).entries)
    if ((e.key == 'Run'
            ? toolCalls
            : (e.key == 'Set' || e.key == 'Reset')
            ? bindings
            : true) &&
        (spec.allowedActions?.contains(e.key) ?? true))
      e,
];

String _actionSection(List<String> steps, Set<String> offered) {
  final ask = offered.contains('ToAssistant');
  final open = offered.contains('OpenUrl');
  final run = offered.contains('Run');
  final examples = [
    if (run && offered.contains('Reset'))
      'Example — mutation + refresh + reset (PREFERRED pattern):\n```\n\$binding = "default"\nresult = Mutation("tool_name", {field: \$binding})\ndata = Query("tool_name", {}, {rows: []})\nonSubmit = Action([@Run(result), @Run(data), @Reset(\$binding)])\n```',
    if (open)
      'Example — simple nav:\n```\nviewBtn = Button("View", @OpenUrl("https://example.com"))\n```',
  ];
  final rules = [
    '- An action can be assigned to a variable or inlined: Button("Go", onSubmit) and Button("Go", Action([...])) both work',
    if (run) ...[
      '- If a @Run(mutation) step fails, remaining steps are skipped (halt on failure)',
      '- @Run(queryRef) re-fetches the query (fire-and-forget, cannot fail)',
    ],
  ];
  return '''$_actionHeader

An action wires a button click to operations. Pass one @-prefixed step bare${ask ? ', e.g. Button("Ask", @ToAssistant("Tell me more"))' : ''}. Put several steps in Action([...])${ask && open ? ', e.g. Button("Read", Action([@OpenUrl("https://example.com"), @ToAssistant("Summarize this page")]))' : ''}. Steps execute in order.
Buttons without an action automatically send their label to the assistant${ask ? ' (equivalent to @ToAssistant(label))' : ''}.

Available steps:
${steps.join('\n')}

${[if (examples.isNotEmpty) examples.join('\n\n'), rules.join('\n')].join('\n\n')}''';
}

const _interactiveFiltersSection = r'''## Interactive Filters

To let the user filter data with a dropdown:
1. Declare a $variable with a default: `$dateRange = "14"`
2. Create a Select with name, items, and binding: `Select("dateRange", [SelectItem("7", "Last 7 days"), ...], null, null, $dateRange)`
3. Wrap in FormControl for a label: `FormControl("Date Range", Select(...))`
4. Pass $dateRange in Query args: `Query("tool", {dateRange: $dateRange}, {defaults})`
5. When the user changes the Select, $dateRange updates and the Query automatically re-fetches

FILTER WIRING RULE: If a $binding filter is visible in the UI, EVERY relevant Query MUST reference that $binding in its args. Never show a filter dropdown while hardcoding the query args.

Rules for $variables:
- $variables hold simple values (strings or numbers), NOT arrays or objects
- $variables must be bound to a Select/Input component via the value argument (last positional arg) to be interactive
- Queries must use regular identifiers (NOT $variables): `metrics = Query(...)` not `$metrics = Query(...)`
- **Auto-declare**: You do NOT need to explicitly declare $variables. If you use `$foo` without declaring it, the parser auto-creates `$foo = null`. You can still declare explicitly to set a default: `$days = "14"`

## Forms

Simple form — no $bindings needed. Field values are managed internally by the Form via the name prop:
```
contactForm = Form("contact", submitBtn, [nameField, emailField])
nameField = FormControl("Name", Input("name", "Your name", "text", {required: true}))
emailField = FormControl("Email", Input("email", "your@email.com", "email", {required: true, email: true}))
submitBtn = Button("Submit")
```

Use $bindings when you need to read field values elsewhere (in Action context, Query args, or conditionals). They are auto-declared:
```
$role = "engineer"
contactForm = Form("contact", submitBtn, [nameField, emailField, roleField])
nameField = FormControl("Name", Input("name", "Enter your name", "text", {required: true}, $name))
emailField = FormControl("Email", Input("email", "Enter your email", "email", {required: true, email: true}, $email))
roleField = FormControl("Role", Select("role", [SelectItem("engineer", "Engineer"), SelectItem("designer", "Designer"), SelectItem("pm", "PM")], null, {required: true}, $role))
submitBtn = Button("Submit")
```

For form + mutation patterns (create, refresh, reset), see the Action section example above.

IMPORTANT: Always add validation rules to form fields used with Mutations. Use OBJECT syntax: {required: true, email: true, minLength: 8}. The renderer shows error messages automatically and blocks submit when validation fails.''';

/// [_interactiveFiltersSection] with only the form text the library and steps
/// support.
String _filters({
  required bool forms,
  required bool run,
  required bool mutationExample,
}) {
  const s = _interactiveFiltersSection;
  final formsAt = s.indexOf('\n\n## Forms');
  final patternsAt = s.indexOf('\n\nFor form + mutation');
  final importantAt = s.indexOf('\n\nIMPORTANT: Always');
  return [
    s.substring(0, formsAt),
    if (forms) s.substring(formsAt, patternsAt),
    if (forms && mutationExample) s.substring(patternsAt, importantAt),
    if (forms && run) s.substring(importantAt),
  ].join();
}

const _editModeSection = '''## Edit Mode

The runtime merges by statement name: same name = replace, new name = append.
Output ONLY statements that changed or are new. Everything else is kept automatically.

### Delete
To remove a component, re-declare its parent without that component in the parent's children array. The removed component and any statements only it referenced are automatically garbage-collected.

### Patch size guide
- Changing a title or label: 1 statement
- Adding a component: 2-3 statements (the new component + parent update)
- Removing a component: 1 statement (re-declare parent without the removed child)
- Adding a filter + wiring to query: 3-5 statements
- Restructuring into tabs: 5-10 statements

### Rules
- Reuse existing statement names exactly — do not rename
- Do NOT re-emit unchanged statements — the runtime keeps them
- A typical edit patch is 1-10 statements, not 20+
- If the existing code already satisfies the request, output only the root statement
- NEVER output the entire program as a patch. Only output what actually changes
- If you are about to output more than 10 statements, reconsider — most edits need fewer''';

String _streamingRules(
  String root, {
  required bool supportsExpressions,
  required bool toolCalls,
}) {
  final steps = ['1. `root = $root(...)` — UI shell appears immediately'];
  if (supportsExpressions) {
    steps.add(r'2. $variable declarations — state ready for bindings');
    if (toolCalls) {
      steps.add(
        '3. Query statements — defaults resolve immediately so components render with data',
      );
    }
    final n = steps.length;
    steps.add(
      '${n + 1}. Component definitions — fill in with data already available',
    );
    steps.add('${n + 2}. Data values — leaf content last');
  } else {
    steps.add('2. Component definitions — fill in as they stream');
    steps.add('3. Data values — leaf content last');
  }
  return '''## Hoisting & Streaming (CRITICAL)

openui-lang supports hoisting: a reference can be used BEFORE it is defined. The parser resolves all references after the full input is parsed.

During streaming, the output is re-parsed on every chunk. Undefined references are temporarily unresolved and appear once their definitions stream in. This creates a progressive top-down reveal — structure first, then data fills in.

**Recommended statement order for optimal streaming:**
${steps.join('\n')}

Always write the root = $root(...) statement first so the UI shell appears immediately, even before child data has streamed in.''';
}

const _inlineModeSection = '''## Inline Mode

You are in inline mode. You can respond in two ways:

### 1. Code response (when the user wants to CREATE or CHANGE the UI)
Wrap openui-lang code in triple-backtick fences. You can include explanatory text before/after:

Here's your dashboard:

```openui-lang
root = RootComp([header, content])
header = SomeHeader("Title")
content = SomeContent("Hello world")
```

I created a simple layout with a header.

### 2. Text-only response (when the user asks a QUESTION)
If the user asks "what is this?", "explain the chart", "how does this work", etc. — respond with plain text. Do NOT output any openui-lang code. The existing dashboard stays unchanged.

### Rules
- When the user asks for changes, output ONLY the changed/new statements in a fenced block
- When the user asks a question, respond with text only — NO code. The dashboard stays unchanged.
- The parser extracts code from fences automatically. Text outside fences is shown as chat.''';

const _toolWorkflowSection = r'''## Data Workflow

When tools are available, follow this workflow:
1. FIRST: Call the most relevant tool to inspect the real data shape before generating code
2. Use Query() for READ operations (data that should stay live) — NEVER hardcode tool results as literal arrays or objects
3. Use Mutation() for WRITE operations (create, update, delete) — triggered by button clicks via @Run(mutationRef)
4. Use the real data from step 1 as condensed Query defaults (3-5 rows) so the UI renders immediately
5. Use @-prefixed builtins (@Count, @Filter, @Sort, @Sum) on Query results for KPIs and aggregations — the runtime evaluates these live on every refresh
6. Hardcoded arrays are ONLY for static display data (labels, options) where no tool exists

WRONG — you called a tool and got data back, but you inlined the results:
```
openCount = 2
item1 = SomeComp("first item title")
item2 = SomeComp("second item title")
list = SomeList([item1, item2])
chart = SomeChart(["A", "B"], [12, 8])
```
This is static — it shows stale data and won't update. Creating item1, item2, item3... manually is ALWAYS wrong when a tool exists.

RIGHT — use Query() for live data, Mutation() for writes, @builtins to derive values:
```
data = Query("tool_name", {}, {rows: []})
openCount = @Count(@Filter(data.rows, "field", "==", "value"))
list = @Each(data.rows, "item", SomeComp(item.title, item.field))
createResult = Mutation("create_tool", {title: $title})
submitBtn = Button("Create", Action([@Run(createResult), @Run(data), @Reset($title)]))
```
Everything derives from the Query — when data refreshes, the entire dashboard updates automatically.''';

/// [_toolWorkflowSection] without the lines that need `@Run`, `@Reset` or a chart.
String _workflow({
  required bool run,
  required bool mutationExample,
  required bool charts,
}) {
  var n = 0;
  return [
    for (final line in _toolWorkflowSection.split('\n'))
      if ((run || !line.startsWith('3. Use Mutation()')) &&
          (mutationExample ||
              !line.startsWith(RegExp('createResult|submitBtn'))) &&
          (charts || !line.startsWith('chart = ')))
        (run ? line : line.replaceFirst(', Mutation() for writes', ''))
            .replaceFirstMapped(RegExp(r'^\d(?=\. )'), (_) => '${++n}'),
  ].join('\n');
}

String _importantRules(
  String root, {
  required bool toolCalls,
  required bool bindings,
  required List<String> uses,
}) {
  final verify = [
    '1. root = $root(...) is the FIRST line (for optimal streaming).',
    '2. Every referenced name is defined. Every defined name (other than root) is reachable from root.',
    if (toolCalls)
      '3. Every Query result is referenced by at least one component.',
    if (bindings)
      '${toolCalls ? '4' : '3'}. Every \$binding appears in at least one component or expression.',
    if (toolCalls && bindings)
      '5. Every visible filter \$binding appears in at least one Query args object.',
  ];
  return '''## Important Rules
- Choose components that best represent the content${uses.isEmpty ? '' : ' (${uses.join(', ')}, etc.)'}

## Final Verification
Before finishing, walk your output and verify:
${verify.join('\n')}''';
}

String _renderTool(PromptTool tool) {
  var args = '';
  final input = tool.inputSchema;
  if (input != null) {
    final props = input['properties'];
    final required = (input['required'] as List?) ?? const [];
    if (props is Map && props.isNotEmpty) {
      args = props.entries
          .map(
            (e) =>
                '${e.key}${required.contains(e.key) ? '' : '?'}: ${_jsonSchemaType((e.value as Map).cast())}',
          )
          .join(', ');
    }
  }
  final returns = tool.outputSchema != null
      ? ' → ${_jsonSchemaType(tool.outputSchema!)}'
      : '';
  var line = '- ${tool.name}($args)$returns';
  if ((tool.description ?? '').isNotEmpty) line += '\n  ${tool.description}';
  return line;
}

String _toolsSection(List<String> names, List<PromptTool> tools, bool run) {
  final lines = [
    '## Available Tools',
    '',
    run
        ? "Use these with Query() for read operations or Mutation() for write operations. The LLM decides which is appropriate based on the tool's purpose."
        : 'Use these with Query() for read operations.',
    '',
    for (final name in names) '- $name',
    for (final t in tools) _renderTool(t),
  ];
  final withOutput = tools.where((t) => t.outputSchema != null).toList();
  if (withOutput.isNotEmpty) {
    lines.addAll([
      '',
      '### Default values for Query results',
      '',
      'Use these shapes as minimal Query defaults:',
    ]);
    for (final t in withOutput) {
      lines.add('- ${t.name}: `${jsonEncode(_defaultFor(t.outputSchema!))}`');
    }
  }
  lines.addAll([
    '',
    "CRITICAL: Use ONLY the tools listed above in ${run ? 'Query() and Mutation()' : 'Query()'} calls. Do NOT invent or guess tool names. If the user asks for functionality that doesn't match any available tool, use realistic mock data instead of fabricating a tool call.",
  ]);
  return lines.join('\n');
}

String _componentSignatures(
  PromptSpec spec,
  _Scope scope,
  Set<String> offered, {
  required bool bindings,
  required bool usesActionExpression,
}) {
  final lines = [
    '## Component Signatures',
    '',
    'Arguments marked with ? are optional. Sub-components can be inline or referenced; prefer references for better streaming.',
  ];
  if (usesActionExpression) {
    lines.add(
      'Props typed `ActionExpression` accept one @step, or Action([@steps...]) for several. See the Action section for available steps (${offered.map((n) => '@$n').join(', ')}).',
    );
    if (spec.components.values.any(
      (c) => _restrictedSlot.hasMatch(c.signature),
    )) {
      final like = offered.containsAll(const ['OpenUrl', 'ToAssistant'])
          ? 'like `@OpenUrl | @ToAssistant`'
          : 'as a union of @steps';
      lines.add('Props typed $like accept only the steps listed.');
    }
  }
  if (bindings ||
      spec.components.values.any((c) => c.signature.contains(r'$binding'))) {
    lines.add(
      'Props marked `\$binding<type>` accept a `\$variable` reference for two-way binding.',
    );
  }
  final entries = [
    ...spec.components.values,
    ...spec.functions.values,
    ...spec.actions.values,
  ];
  if (entries.any((e) => e.signature.contains(r'$bound<'))) {
    lines.add(
      'Props marked `\$bound<type>` take only a path into a host \$variable from Bound Data, such as `\$name.field`. A literal or computed value there is rejected.',
    );
  }
  // A component whose step slot keeps no allowed step is left out.
  String? format(PromptEntry c) {
    final signature = scope.signature(c.signature);
    if (signature == null) return null;
    final description = scope.clauses(c.description ?? '');
    return description.isNotEmpty ? '$signature — $description' : signature;
  }

  if (spec.groups.isNotEmpty) {
    final grouped = <String>{};
    for (final g in spec.groups) {
      if (!g.components.any(spec.components.containsKey)) continue;
      lines.addAll(['', '### ${g.name}']);
      for (final name in g.components) {
        final comp = spec.components[name];
        if (comp == null || !grouped.add(name)) continue;
        lines.addAll([?format(comp)]);
      }
      lines.addAll(g.notes.where(scope.offers));
    }
    final ungrouped = spec.components.keys
        .where((n) => !grouped.contains(n))
        .toList();
    if (ungrouped.isNotEmpty) {
      lines.addAll(['', '### Other']);
      for (final n in ungrouped) {
        lines.addAll([?format(spec.components[n]!)]);
      }
    }
  } else {
    lines.add('');
    lines.addAll(spec.components.values.map(format).nonNulls);
  }
  return lines.join('\n');
}

final List<String> _builtinFunctionLines = [
  for (final b in builtinFunctionSpecs)
    functionLine(
      PromptEntry(signature(b.name, b.params, b.returns), b.description),
    ),
];

final Map<String, PromptEntry> _builtinSteps = {
  for (final s in builtinStepSpecs)
    s.name: PromptEntry(signature(s.name, s.params), s.description),
};

/// lang-core `generatePrompt`.
String generatePrompt(PromptSpec spec) {
  final root = spec.root;
  final hasTools = spec.tools.isNotEmpty || spec.toolNames.isNotEmpty;
  final toolCalls = spec.toolCalls ?? hasTools;
  final hasState = spec.state.keys.any(_isStateKey);
  final bindings =
      spec.bindings ?? (toolCalls || spec.records.isNotEmpty || hasState);
  final supportsExpressions = toolCalls || bindings;
  final usesActionExpression = spec.components.values.any(
    (c) =>
        c.signature.contains('ActionExpression') ||
        _restrictedSlot.hasMatch(c.signature),
  );
  bool allows(String name) => spec.allowedActions?.contains(name) ?? true;
  final steps = _visibleSteps(spec, toolCalls: toolCalls, bindings: bindings);
  final actions = [
    for (final a in spec.actions.entries)
      if (allows(a.key)) a,
  ];
  final offered = {...steps.map((s) => s.key), ...actions.map((a) => a.key)};
  final scope = _Scope(
    spec.components.keys.toSet(),
    {
      for (final g in spec.groups)
        for (final n in g.components)
          if (!spec.components.containsKey(n)) n,
    },
    {
      ...builtinStepSpecs.map((s) => s.name),
      ...spec.actions.keys,
    }.difference(offered),
  );
  final run = offered.contains('Run');
  final mutationExample = run && offered.contains('Reset');
  bool has(String kind) => spec.components.keys.any((n) => n.contains(kind));
  final charts = has('Chart'), tables = has('Table'), forms = has('Form');
  final parts = <String>[
    spec.preamble ?? _preamble,
    '',
    _syntaxRules(
      root,
      supportsExpressions: supportsExpressions,
      bindings: bindings,
    ),
    '',
    _componentSignatures(
      spec,
      scope,
      offered,
      bindings: bindings,
      usesActionExpression: usesActionExpression,
    ),
  ];
  final custom = spec.functions.values
      .map((f) => functionLine(scope.entry(f)))
      .toList();
  if (spec.builtinFunctions ?? supportsExpressions) {
    parts.addAll([
      '',
      _builtinFunctionsSection(
        spec.builtinFunctionLines ?? _builtinFunctionLines,
        custom,
        toolCalls,
        charts: charts,
        tables: tables,
      ),
    ]);
  } else if (custom.isNotEmpty) {
    parts.addAll(['', '## Built-in Functions\n\n${custom.join('\n')}']);
  }
  if (toolCalls) parts.addAll(['', _query(run)]);
  if (run) parts.addAll(['', _mutationSection]);
  final customActions = [
    for (final a in actions) '- ${functionLine(scope.entry(a.value))}',
  ];
  if (usesActionExpression) {
    parts.addAll([
      '',
      _actionSection([
        for (final s in steps) '- ${functionLine(s.value)}',
        ...customActions,
      ], offered),
    ]);
  } else if (customActions.isNotEmpty) {
    parts.addAll([
      '',
      '$_actionHeader\n\nPass one step, or Action([...]) with several steps, as a button\'s action.\n\nAvailable steps:\n${customActions.join('\n')}',
    ]);
  }
  if (toolCalls && bindings) {
    parts.addAll([
      '',
      _filters(forms: forms, run: run, mutationExample: mutationExample),
    ]);
  }
  if (toolCalls) {
    parts.addAll([
      '',
      _workflow(run: run, mutationExample: mutationExample, charts: charts),
    ]);
  }
  if (hasTools) {
    parts.addAll(['', _toolsSection(spec.toolNames, spec.tools, run)]);
  }
  if (spec.records.isNotEmpty) {
    final bound = describeBoundRecords(spec.records);
    parts.addAll([
      '',
      offered.containsAll(const ['Set', 'Reset'])
          ? bound
          : bound.replaceFirst('never @Set, @Reset or bind', 'never bind'),
    ]);
  }
  if (hasState) parts.addAll(['', _stateSection(spec.state)]);
  parts.addAll([
    '',
    _streamingRules(
      root,
      supportsExpressions: supportsExpressions,
      toolCalls: toolCalls,
    ),
  ]);
  final examples = [...spec.examples, ...spec.toolExamples];
  if (examples.isNotEmpty) {
    parts.addAll(['', '## Examples', '']);
    for (final ex in examples) {
      parts.addAll([ex, '']);
    }
  }
  if (spec.editMode) parts.addAll(['', _editModeSection]);
  if (spec.inlineMode) parts.addAll(['', _inlineModeSection]);
  parts.add(
    _importantRules(
      root,
      toolCalls: toolCalls,
      bindings: bindings,
      uses: [
        if (tables) 'tables for comparisons',
        if (charts) 'charts for trends',
        if (forms) 'forms for input',
      ],
    ),
  );
  if (spec.additionalRules.isNotEmpty) {
    parts.add('');
    parts.addAll(spec.additionalRules.map((r) => '- $r'));
  }
  return parts.join('\n');
}
