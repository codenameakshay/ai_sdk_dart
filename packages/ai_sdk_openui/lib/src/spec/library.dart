import 'dart:convert';

import '../lang/parser.dart';
import '../lang/policy.dart';
import '../runtime/host_actions.dart';
import 'bound.dart';
import 'prompt.dart';
import 'schema.dart';

/// A component the model can call. Prop order is positional order.
abstract interface class ComponentSpec {
  String get typeName;

  /// Prompt description; empty for none.
  String get description;
  Map<String, Schema> get props;
}

/// A component's description and props, as a library file defines them.
final class ComponentDef {
  const ComponentDef({this.description = '', required this.props});
  final String description;
  final Map<String, Schema> props;
}

final class ComponentGroup {
  const ComponentGroup(this.name, this.components, {this.notes = const []});
  final String name;
  final List<ComponentSpec> components;
  final List<String> notes;
}

/// A library `@function`. [fn] receives validated args; a throw makes the
/// call evaluate to null.
final class FunctionSpec {
  const FunctionSpec(
    this.name, {
    required this.description,
    required this.params,
    this.returns,
    required this.fn,
    this.localized,
  });
  final String name;
  final String description;
  final Map<String, Schema> params;
  final Schema? returns;
  final Object? Function(Map<String, Object?> args) fn;

  /// Runs instead of [fn] when the session has a locale (an intl name such as
  /// `de` or `en_IN`).
  final Object? Function(Map<String, Object?> args, String locale)? localized;
}

/// A library action step such as `@CopyToClipboard`. The host runs it.
final class ActionSpec {
  const ActionSpec(
    this.name, {
    required this.description,
    required this.params,
    this.handler,
    this.confirm,
    this.disableAfterSuccess = false,
  });
  final String name;
  final String description;
  final Map<String, Schema> params;

  /// Runs the step in the session instead of sending it to the host as an event.
  final ActionHandler? handler;

  /// Ask this before running; the session runs nothing until `confirmed: true`.
  final String? confirm;

  /// Stop repeats once a run succeeds.
  final bool disableAfterSuccess;

  /// A slot schema that takes only this action: `S.union([copy.ref, Steps.openUrl])`.
  Schema get ref => S.actionRef(name, params);
}

/// A tool `Query` and `Mutation` can call. The same list prints the prompt's
/// tool section and serves the runtime.
final class OpenUiTool {
  const OpenUiTool({
    required this.name,
    this.description,
    this.inputSchema,
    this.outputSchema,
    required this.call,
  });
  final String name;
  final String? description;
  final Map<String, Object?>? inputSchema;
  final Map<String, Object?>? outputSchema;
  final Future<Object?> Function(Map<String, Object?> args) call;
}

/// lang-core `PromptOptions`.
final class PromptOptions {
  const PromptOptions({
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
  });
  final String? preamble;
  final bool? bindings;
  final bool? toolCalls;
  final bool? builtinFunctions;
  final List<OpenUiTool> tools;

  /// Tools listed by name only, without a signature (lang-core string tools).
  final List<String> toolNames;
  final List<String> examples;
  final List<String> toolExamples;
  final List<String> additionalRules;
  final bool editMode;
  final bool inlineMode;

  /// Host-bound read-only `$variables`, listed in a "Bound Data" section.
  final List<BoundRecord> records;

  /// Seeded `$variables` with their values, listed in a "Current State" section.
  final Map<String, Object?> state;
}

const _actionExpression = 'ActionExpression';

/// The action prop schema: one `@step` or `Action([...])`.
final Schema actionSchema = S.ref(_actionExpression);

Map<String, Object?> _actionExpressionBody() => {
  'anyOf': [
    {
      'type': 'object',
      'properties': {
        'type': {'type': 'string', 'const': 'open_url'},
        'url': {'type': 'string'},
      },
      'required': ['type', 'url'],
      'additionalProperties': false,
    },
    {
      'type': 'object',
      'properties': {
        'type': {'type': 'string', 'const': 'continue_conversation'},
        'context': {'type': 'string'},
      },
      'required': ['type'],
      'additionalProperties': false,
    },
    {
      'type': 'object',
      'properties': {
        'type': {'type': 'string'},
        'params': {
          'type': 'object',
          'propertyNames': {'type': 'string'},
          'additionalProperties': <String, Object?>{},
        },
      },
      'required': ['type'],
      'additionalProperties': false,
    },
  ],
};

/// A component library: what the model may write, and how it is described.
final class OpenUiLibrary {
  OpenUiLibrary({
    required ComponentSpec root,
    required List<ComponentSpec> components,
    this.groups = const [],
    this.functions = const [],
    this.actions = const [],
    this.id,
  }) : rootName = root.typeName,
       components = {for (final c in components) c.typeName: c} {
    if (!this.components.containsKey(rootName)) {
      throw ArgumentError('Root component "$rootName" is not in components.');
    }
    final names = {...this.components.keys};
    for (final name in [
      ...functions.map((f) => f.name),
      ...actions.map((a) => a.name),
    ]) {
      if (builtinCalls.containsKey(name) ||
          reservedCalls.contains(name) ||
          !names.add(name)) {
        throw ArgumentError(
          '"$name" collides with a built-in, component, function or action.',
        );
      }
    }
  }

  final String rootName;
  final Map<String, ComponentSpec> components;
  final List<ComponentGroup> groups;
  final List<FunctionSpec> functions;
  final List<ActionSpec> actions;

  /// lang-core library `id`; [toSpec] includes it when set.
  final String? id;

  late final Map<String, Object?> _jsonSchema = _buildJsonSchema();
  late final CompiledSchema compiled = CompiledSchema.fromJsonSchema(
    _jsonSchema,
  );

  /// Whether `component.prop` is a `$binding` prop.
  bool isReactive(String component, String prop) =>
      components[component]?.props[prop]?.isReactive ?? false;

  /// The library JSON Schema, as lang-core's `toJSONSchema()` emits it.
  Map<String, Object?> toJsonSchema() => _jsonSchema;

  Map<String, Object?> _buildJsonSchema() {
    late final JsonSchemaEmitter emitter;
    emitter = JsonSchemaEmitter((name) {
      if (name == _actionExpression) return _actionExpressionBody();
      final spec = components[name];
      if (spec == null) throw StateError('No component "$name" to reference.');
      final body = emitter.emitObject(spec.props);
      if (spec.description.isNotEmpty) body['description'] = spec.description;
      return body;
    });
    final properties = {
      for (final name in components.keys) name: emitter.emit(S.ref(name)),
    };
    Map<String, Object?> call(
      Map<String, Schema> params,
      String description,
      Schema? returns,
    ) {
      final callEmitter = JsonSchemaEmitter(
        (name) => throw StateError('Call schemas cannot reference "$name".'),
      );
      return {
        'description': description,
        'params': callEmitter.emitObject(params),
        if (returns != null) 'returns': callEmitter.emit(returns),
      };
    }

    return {
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'type': 'object',
      'properties': properties,
      'required': components.keys.toList(),
      'additionalProperties': false,
      r'$defs': emitter.defs,
      if (functions.isNotEmpty)
        'functions': {
          for (final f in functions)
            f.name: call(f.params, f.description, f.returns),
        },
      if (actions.isNotEmpty)
        'actions': {
          for (final a in actions) a.name: call(a.params, a.description, null),
        },
    };
  }

  Map<String, PromptEntry> get _componentEntries => {
    for (final c in components.values)
      c.typeName: PromptEntry(signature(c.typeName, c.props), c.description),
  };

  /// The library spec, as lang-core's `toSpec()` emits it (`spec.json`).
  Map<String, Object?> toSpec() => {
    'root': rootName,
    'components': {
      for (final MapEntry(:key, :value) in _componentEntries.entries)
        key: {'signature': value.signature, 'description': value.description},
    },
    if (groups.isNotEmpty)
      'componentGroups': [
        for (final g in groups)
          {
            'name': g.name,
            'components': [for (final c in g.components) c.typeName],
            if (g.notes.isNotEmpty) 'notes': g.notes,
          },
      ],
    if (functions.isNotEmpty)
      'functions': {
        for (final f in functions)
          f.name: {
            'signature': signature(f.name, f.params, f.returns),
            'description': f.description,
          },
      },
    if (actions.isNotEmpty)
      'actions': {
        for (final a in actions)
          a.name: {
            'signature': signature(a.name, a.params),
            'description': a.description,
          },
      },
    'schema': _jsonSchema,
    if (id != null) 'id': id,
  };

  /// [toSpec] as `spec.json` text: two-space JSON and a final newline.
  String toSpecJson() =>
      '${const JsonEncoder.withIndent('  ').convert(toSpec())}\n';

  /// The system prompt for [options] (lang-core `generateSystemPrompt`).
  String systemPrompt([PromptOptions options = const PromptOptions()]) =>
      generatePrompt(
        PromptSpec(
          root: rootName,
          components: _componentEntries,
          groups: [
            for (final g in groups)
              PromptGroup(g.name, [
                for (final c in g.components) c.typeName,
              ], g.notes),
          ],
          functions: {
            for (final f in functions)
              f.name: PromptEntry(
                signature(f.name, f.params, f.returns),
                f.description,
              ),
          },
          actions: {
            for (final a in actions)
              a.name: PromptEntry(signature(a.name, a.params), a.description),
          },
          preamble: options.preamble,
          bindings: options.bindings,
          toolCalls: options.toolCalls,
          builtinFunctions: options.builtinFunctions,
          tools: [
            for (final t in options.tools)
              PromptTool(
                t.name,
                description: t.description,
                inputSchema: t.inputSchema,
                outputSchema: t.outputSchema,
              ),
          ],
          toolNames: options.toolNames,
          examples: options.examples,
          toolExamples: options.toolExamples,
          additionalRules: options.additionalRules,
          editMode: options.editMode,
          inlineMode: options.inlineMode,
          records: options.records,
          state: options.state,
        ),
      );

  /// Parses a complete program without running it: a server-side check.
  ParseReport parse(String program, {Set<String> bound = const {}}) =>
      ParseReport._(
        parseProgram(program, compiled, rootName: rootName, boundNames: bound),
      );

  /// [parse] plus the [policy] limits, with each issue's statement id.
  ValidationReport validate(
    String program, {
    ValidationPolicy policy = const ValidationPolicy(),
    Set<String> bound = const {},
  }) => validateProgram(
    program,
    compiled,
    rootName: rootName,
    policy: policy,
    boundNames: bound,
  );
}

/// lang-core `generateSystemPrompt` for a library: [OpenUiLibrary.systemPrompt].
/// For OpenUI Cloud's config block use `cloudSystemPrompt`.
String generateSystemPrompt(
  OpenUiLibrary library, [
  PromptOptions options = const PromptOptions(),
]) => library.systemPrompt(options);

/// What a server needs to know about a program without running it.
final class ParseReport {
  ParseReport._(this._result);
  final ParseResult _result;

  bool get hasRoot => _result.root != null || _result.rootExpression != null;
  List<String> get errors => [
    for (final e in _result.meta.errors)
      if (!e.isWarning) e.message,
  ];
  List<String> get warnings => [
    for (final e in _result.meta.errors)
      if (e.isWarning) e.message,
  ];
  List<String> get unresolved => List.unmodifiable(_result.meta.unresolved);
  List<String> get orphaned => List.unmodifiable(_result.meta.orphaned);
  bool get isClean =>
      hasRoot &&
      _result.meta.errors.isEmpty &&
      unresolved.isEmpty &&
      orphaned.isEmpty;
}
