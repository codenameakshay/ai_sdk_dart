import 'dart:convert';

import '../runtime/builtins.dart';
import '../runtime/evaluator.dart' show actionSteps;
import '../spec/schema.dart' show boundKeyword;
import 'ast.dart';
import 'js.dart';
import 'lexer.dart';
import 'statements.dart';
import 'validation.dart';

enum CallKind { function, action }

final class CallDef {
  const CallDef(
    this.kind,
    this.params, {
    this.builtin = false,
    this.lazy = false,
  });
  final CallKind kind;
  final List<ParamDef> params;
  final bool builtin;
  final bool lazy;
}

/// Built-in functions, steps and `Action`: the base of every call registry.
final Map<String, CallDef> builtinCalls = {
  for (final f in builtinFunctionSpecs)
    f.name: CallDef(
      CallKind.function,
      _paramNames(f.params.keys),
      builtin: true,
      lazy: lazyCalls.contains(f.name),
    ),
  for (final s in builtinStepSpecs)
    s.name: CallDef(
      CallKind.action,
      _paramNames(s.params.keys),
      builtin: true,
      lazy: lazyCalls.contains(s.name),
    ),
  'Action': const CallDef(
    CallKind.action,
    [ParamDef(name: 'steps', required: true, schema: null)],
    builtin: true,
    lazy: true,
  ),
};

List<ParamDef> _paramNames(Iterable<String> names) => [
  for (final n in names) ParamDef(name: n, required: false, schema: null),
];

const reservedCalls = {'Query', 'Mutation'};

/// The library schema compiled for parsing: component params by name, and
/// the call registry (built-ins plus library functions and actions).
final class CompiledSchema {
  CompiledSchema(this.components, this.calls);
  final Map<String, List<ParamDef>> components;
  final Map<String, CallDef> calls;

  /// lang-core `compileSchema`, from a library JSON Schema document.
  factory CompiledSchema.fromJsonSchema(JsonSchema schema) {
    final defsJson = (schema[r'$defs'] as Map?)?.cast<String, Object?>() ?? {};
    final componentNames = (schema['properties'] as Map?)?.keys
        .cast<String>()
        .toSet();
    final actionsJson =
        (schema['actions'] as Map?)?.cast<String, Object?>() ?? {};
    final inline = <String, Object?>{};
    for (final name in [
      'ActionExpression',
      'OpenUrl',
      'ToAssistant',
      'Set',
      'Reset',
      ...actionsJson.keys,
    ]) {
      final body = defsJson[name];
      if (body != null && !(componentNames?.contains(name) ?? false)) {
        inline['#/\$defs/$name'] = body;
      }
    }
    final components = <String, List<ParamDef>>{};
    for (final MapEntry(:key, :value) in defsJson.entries) {
      final skip = componentNames != null
          ? !componentNames.contains(key)
          : inline.containsKey('#/\$defs/$key');
      if (skip) continue;
      components[key] = _compileParams(value as Map, inline);
    }
    final calls = {...builtinCalls};
    final fns = (schema['functions'] as Map?)?.cast<String, Object?>() ?? {};
    for (final MapEntry(:key, :value) in fns.entries) {
      calls[key] = CallDef(
        CallKind.function,
        _compileParams((value as Map)['params'] as Map, inline),
      );
    }
    for (final MapEntry(:key, :value) in actionsJson.entries) {
      calls[key] = CallDef(
        CallKind.action,
        _compileParams((value as Map)['params'] as Map, inline),
      );
    }
    return CompiledSchema(components, calls);
  }
}

Object? _inlineRefs(Object? node, Map<String, Object?> defs) {
  if (node is Map) {
    final ref = node[r'$ref'];
    if (ref is String) {
      if (!defs.containsKey(ref)) return node;
      final resolved = _inlineRefs(defs[ref], defs);
      if (node[boundKeyword] == true && resolved is Map) {
        return {...resolved, boundKeyword: true};
      }
      return resolved;
    }
    return {
      for (final MapEntry(:key, :value) in node.entries)
        key: _inlineRefs(value, defs),
    };
  }
  if (node is List) return [for (final v in node) _inlineRefs(v, defs)];
  return node;
}

List<ParamDef> _compileParams(Map def, Map<String, Object?> defs) {
  final properties = (def['properties'] as Map?) ?? const {};
  final required = (def['required'] as List?) ?? const [];
  return [
    for (final MapEntry(:key, :value) in properties.entries)
      ParamDef(
        name: key as String,
        required: required.contains(key),
        defaultValue: schemaDefault(value),
        schema: defs.isEmpty ? value : _inlineRefs(value, defs),
      ),
  ];
}

sealed class Statement {
  const Statement(this.id);
  final String id;
}

final class ValueStatement extends Statement {
  const ValueStatement(super.id, this.expr);
  final Ast expr;
}

final class StateStatement extends Statement {
  const StateStatement(super.id, this.init);
  final Ast init;
}

final class QueryStatement extends Statement {
  const QueryStatement(super.id, this.expr, this.deps);
  final CompNode expr;
  final List<String>? deps;
}

final class MutationStatement extends Statement {
  const MutationStatement(super.id, this.expr);
  final CompNode expr;
}

final class QueryStatementInfo implements JsFields {
  const QueryStatementInfo({
    required this.statementId,
    this.toolAst,
    this.argsAst,
    this.defaultsAst,
    this.refreshAst,
    this.deps,
    this.complete = true,
  });
  final String statementId;
  final Ast? toolAst;
  final Ast? argsAst;
  final Ast? defaultsAst;
  final Ast? refreshAst;
  final List<String>? deps;
  final bool complete;

  @override
  Map<String, Object?> get jsFields => {
    'statementId': statementId,
    'toolAST': toolAst,
    'argsAST': argsAst,
    'defaultsAST': defaultsAst,
    'refreshAST': refreshAst,
    'deps': ?deps,
    'complete': complete,
  };
}

final class MutationStatementInfo implements JsFields {
  const MutationStatementInfo({
    required this.statementId,
    this.toolAst,
    this.argsAst,
  });
  final String statementId;
  final Ast? toolAst;
  final Ast? argsAst;

  @override
  Map<String, Object?> get jsFields => {
    'statementId': statementId,
    'toolAST': toolAst,
    'argsAST': argsAst,
  };
}

final class ParseMeta {
  const ParseMeta({
    required this.incomplete,
    required this.unresolved,
    required this.orphaned,
    required this.statementCount,
    required this.errors,
  });
  final bool incomplete;
  final List<String> unresolved;
  final List<String> orphaned;
  final int statementCount;
  final List<ValidationError> errors;
}

final class ParseResult {
  const ParseResult({
    required this.root,
    required this.meta,
    this.rootExpression,
    this.stateDeclarations = const {},
    this.queryStatements = const [],
    this.mutationStatements = const [],
  });
  final ElementNode? root;
  final Ast? rootExpression;
  final ParseMeta meta;
  final Map<String, Object?> stateDeclarations;
  final List<QueryStatementInfo> queryStatements;
  final List<MutationStatementInfo> mutationStatements;

  /// lang-core's `ParseResult` as JSON, as `JSON.stringify` writes it.
  Map<String, Object?> toJson() =>
      jsonDecode(
            Js.stringify({
              'root': root,
              'rootExpression': ?rootExpression,
              'meta': {
                'incomplete': meta.incomplete,
                'unresolved': meta.unresolved,
                'orphaned': meta.orphaned,
                'statementCount': meta.statementCount,
                'errors': meta.errors,
              },
              'stateDeclarations': stateDeclarations,
              'queryStatements': queryStatements,
              'mutationStatements': mutationStatements,
            }),
          )
          as Map<String, Object?>;

  static ParseResult empty({bool incomplete = true}) => ParseResult(
    root: null,
    meta: ParseMeta(
      incomplete: incomplete,
      unresolved: const [],
      orphaned: const [],
      statementCount: 0,
      errors: const [],
    ),
  );
}

List<String> _stateRefs(Ast? node) {
  if (node == null) return const [];
  final refs = <String>{};
  walkAst(node, (n) {
    if (n is StateRefNode) refs.add(n.name);
  });
  return refs.toList();
}

Statement classify(RawStatement raw, Ast expr) {
  if (expr is CompNode && expr.name == 'Query') {
    final deps = _stateRefs(expr.args.length > 1 ? expr.args[1] : null);
    return QueryStatement(raw.id, expr, deps.isEmpty ? null : deps);
  }
  if (expr is CompNode && expr.name == 'Mutation') {
    return MutationStatement(raw.id, expr);
  }
  if (raw.idTokenType == T.stateVar) return StateStatement(raw.id, expr);
  return ValueStatement(raw.id, expr);
}

final class _Ctx extends ValidationContext {
  _Ctx({
    required this.syms,
    required this.schema,
    required super.partial,
    required this.unreached,
    required this.boundNames,
    required this.boundSchemas,
  }) : super(componentNames: schema.components.keys.toSet());
  final Map<String, Ast> syms;
  final CompiledSchema schema;
  final List<String> unresolved = [];
  final Set<String> visited = {};
  final Set<String> unreached;
  final Set<String> boundNames;
  final Set<String> boundLoopVars = {};

  /// JSON Schemas of bound records by `$name`; a record without one is unchecked.
  final Map<String, Object?> boundSchemas;

  /// The item schema of each bound loop variable, when its source has one.
  final Map<String, Object?> boundLoopSchemas = {};
  int syntheticValueDepth = 0;
}

/// Whether [schema] marks itself, or any field or item inside it, bound-only.
bool _hasBound(Object? schema) => switch (schema) {
  Map() => schema[boundKeyword] == true || schema.values.any(_hasBound),
  List() => schema.any(_hasBound),
  _ => false,
};

/// The part of [schema] for a value of JSON type [type]: itself, or the one
/// `anyOf`/`oneOf` option of that type (null when there is not exactly one).
Map? _schemaFor(Map schema, String type) {
  if (schema['type'] == type) return schema;
  final options = schema['anyOf'] ?? schema['oneOf'];
  if (options is! List) return null;
  final matching = [
    for (final o in options)
      if (o is Map && o['type'] == type) o,
  ];
  return matching.length == 1 ? matching.single : null;
}

/// The fields of an object value or the items of a list value, keyed as a
/// path segment; null for anything else.
List<(String, Object?)>? _children(Object? value) => switch (value) {
  Map() => [
    for (final MapEntry(:key, :value) in value.entries) ('$key', value),
  ],
  ObjNode(:final entries) => entries,
  List() => [for (var i = 0; i < value.length; i++) ('$i', value[i])],
  ArrNode(:final elements) => [
    for (var i = 0; i < elements.length; i++) ('$i', elements[i]),
  ],
  _ => null,
};

/// A path into a bound record: `$name`, then `.field` or `[index]`, or a loop
/// variable over one. An index must be a literal or a bound path itself: a
/// computed one (`$order[$k]`) lets the program pick the field.
bool _isBoundPath(Object? v, _Ctx ctx) => switch (v) {
  StateRefNode(:final name) =>
    !(ctx.syntheticValueDepth > 0 && name == r'$value') &&
        ctx.boundNames.contains(name),
  RefNode(:final name) => ctx.boundLoopVars.contains(name),
  MemberNode(:final object) => _isBoundPath(object, ctx),
  IndexNode(:final object, :final index) =>
    _isBoundPath(object, ctx) &&
        (literalValue(index).found || _isBoundPath(index, ctx)),
  _ => false,
};

/// The schema at bound path [node]: a schema map, [absent] when the record
/// schema has no such path, or null when it is not known.
Object? _boundSchemaAt(Ast node, _Ctx ctx) => switch (node) {
  StateRefNode(:final name) => ctx.boundSchemas[name],
  RefNode(:final name) => ctx.boundLoopSchemas[name],
  MemberNode(:final object, :final field) => _fieldSchema(
    _boundSchemaAt(object, ctx),
    field,
  ),
  IndexNode(:final object, :final index) => _fieldSchema(
    _boundSchemaAt(object, ctx),
    switch (literalValue(index)) {
      (found: true, :final value) => Js.string(value),
      _ => null,
    },
  ),
  _ => null,
};

/// The schema of field or item [key] in [schema]; a null [key] (a bound index)
/// is any item or field. A field is known when `properties` lists it or
/// `additionalProperties` is a schema or true.
Object? _fieldSchema(Object? schema, String? key) {
  if (schema is! Map) return schema;
  final type = schema['type'];
  if (key == 'length' && (type == 'array' || type == 'string')) {
    return const {'type': 'number'};
  }
  if (type == 'array') {
    if (key != null && !Js.isArrayIndex(key)) return absent;
    return schema['items'] is Map ? schema['items'] : null;
  }
  if (type == 'object') {
    final props = schema['properties'];
    if (key != null && props is Map && props[key] is Map) return props[key];
    final extra = schema['additionalProperties'];
    if (extra is Map) return extra;
    if (extra == true || key == null || (props == null && extra == null)) {
      return null;
    }
    return absent;
  }
  return type is String ? absent : null;
}

/// The JSON types [schema] allows (`integer` counts as `number`), or null
/// when it allows any.
Set<String>? _jsonTypes(Map schema) {
  final options = schema['anyOf'] ?? schema['oneOf'];
  if (options is List) {
    final types = <String>{};
    for (final o in options) {
      final t = o is Map ? _jsonTypes(o) : null;
      if (t == null) return null;
      types.addAll(t);
    }
    return types;
  }
  final type = schema['type'];
  final list = type is String ? [type] : type;
  if (list is! List) return null;
  return {for (final t in list) t == 'integer' ? 'number' : '$t'};
}

/// `$order.items[0].price`, for a message.
String _pathText(Ast node) => switch (node) {
  MemberNode(:final object, :final field) => '${_pathText(object)}.$field',
  IndexNode(:final object, :final index) =>
    '${_pathText(object)}[${switch (literalValue(index)) {
      (found: true, :final value) => jsonEncode(value),
      _ => _pathText(index),
    }}]',
  StateRefNode(:final name) => name,
  _ => (node as RefNode).name,
};

/// Checks bound path [arg] against the record schemas: it must exist, and its
/// type must fit [schema]. Reports and returns true when it does not.
bool _violatesBoundSchema(
  Object? schema,
  Ast arg,
  String component,
  String path,
  _Ctx ctx,
) {
  final at = _boundSchemaAt(arg, ctx);
  if (identical(at, absent)) {
    pushIssue(ctx, component, path, UnknownBoundPath(_pathText(arg)));
    return true;
  }
  if (at is! Map || schema is! Map) return false;
  final want = _jsonTypes(schema), got = _jsonTypes(at);
  if (want == null || got == null || want.intersection(got).isNotEmpty) {
    return false;
  }
  pushIssue(
    ctx,
    component,
    path,
    TypeMismatch(want.join('|'), '${_pathText(arg)} (${got.join('|')})'),
  );
  return true;
}

/// Reports each place in [arg] where a bound-only part of [schema] gets
/// something other than a bound path, at any depth of object fields and list
/// items, and each bound path the record schemas reject. Returns true when it
/// reported any.
///
/// A container that holds bound-only parts must be a bound path itself, an
/// object or list written out in the program, or null: a computed one (state,
/// a ternary, a call) fails, because its fields cannot be checked here.
bool _violatesBound(
  Object? schema,
  Object? arg,
  String component,
  String path,
  _Ctx ctx,
) {
  if (arg == null || arg is NullNode) return false;
  if (_isBoundPath(arg, ctx)) {
    return _violatesBoundSchema(schema, arg as Ast, component, path, ctx);
  }
  final bound = _hasBound(schema);
  if (!bound && ctx.boundSchemas.isEmpty) return false;
  final s = schema is Map ? schema : const {};
  if (s[boundKeyword] != true) {
    final children = _children(arg);
    if (children != null) {
      final isObject = arg is Map || arg is ObjNode;
      final sub = _schemaFor(s, isObject ? 'object' : 'array');
      if (sub != null || !bound) {
        final props = sub?['properties'];
        var violated = false;
        for (final (key, value) in children) {
          final child = sub == null
              ? null
              : !isObject
              ? sub['items']
              : props is Map && props.containsKey(key)
              ? props[key]
              : sub['additionalProperties'];
          if (_violatesBound(child, value, component, '$path/$key', ctx)) {
            violated = true;
          }
        }
        return violated;
      }
    } else if (!bound || arg is! Ast || literalValue(arg).found) {
      // A scalar has no fields; the type check reports the mismatch.
      return false;
    }
  }
  pushIssue(ctx, component, path, const BoundOnly());
  return true;
}

/// Built-in step names by runtime step type (`set` is `Set`).
final _stepNames = {
  for (final MapEntry(:key, :value) in actionSteps.entries) value: key,
};

/// The steps the action slot [schema] takes, by name, or null when it is no
/// restricted slot. A restricted slot is a step shape (an object whose `type`
/// property is a const, as `Steps` and `S.actionRef` emit) or a union of them,
/// optionally with null.
Set<String>? _slotSteps(Object? schema) {
  if (schema is! Map) return null;
  final options = schema['anyOf'] ?? schema['oneOf'];
  if (options is List) {
    final names = <String>{};
    for (final o in options) {
      if (o is Map && o['type'] == 'null') continue;
      final steps = _slotSteps(o);
      if (steps == null) return null;
      names.addAll(steps);
    }
    return names.isEmpty ? null : names;
  }
  final props = schema['properties'];
  final type = props is Map ? props['type'] : null;
  final value = type is Map ? type['const'] : null;
  return value is String ? {_stepNames[value] ?? value} : null;
}

/// The `@` steps [node] runs: itself, each step in `Action([...])`, and those
/// of both branches of a ternary.
List<String> _steps(Object? node, _Ctx ctx) => switch (node) {
  CompNode(name: 'Action', :final args) when args.firstOrNull is ArrNode => [
    for (final e in (args.first as ArrNode).elements) ..._steps(e, ctx),
  ],
  CompNode(:final name) when ctx.schema.calls[name]?.kind == CallKind.action =>
    [name],
  TernaryNode(:final then, :final otherwise) => [
    ..._steps(then, ctx),
    ..._steps(otherwise, ctx),
  ],
  _ => const [],
};

/// Reports a step in [arg] that the action slot [schema] does not take.
bool _violatesSlot(
  Object? schema,
  Object? arg,
  String component,
  String path,
  _Ctx ctx,
) {
  final allowed = _slotSteps(schema);
  if (allowed == null) return false;
  final outside = {
    for (final step in _steps(arg, ctx))
      if (!allowed.contains(step)) '@$step',
  };
  if (outside.isEmpty) return false;
  pushIssue(
    ctx,
    component,
    path,
    TypeMismatch(allowed.map((s) => '@$s').join(' | '), outside.join(', ')),
  );
  return true;
}

/// [_violatesBound] and [_violatesSlot] for a prop or param: reports both.
bool _violatesProp(
  Object? schema,
  Object? arg,
  String component,
  String path,
  _Ctx ctx,
) =>
    _violatesBound(schema, arg, component, path, ctx) |
    _violatesSlot(schema, arg, component, path, ctx);

/// Runs [body] with loop variable [name] over [source] in scope: bound, with
/// the item schema, when [source] is a bound path.
T _withLoopVar<T>(String? name, Ast source, _Ctx ctx, T Function() body) {
  if (name == null) return body();
  final wasBound = ctx.boundLoopVars.contains(name);
  final hadSchema = ctx.boundLoopSchemas.containsKey(name);
  final previousSchema = ctx.boundLoopSchemas[name];
  if (_isBoundPath(source, ctx)) {
    ctx.boundLoopVars.add(name);
    ctx.boundLoopSchemas[name] = _fieldSchema(
      _boundSchemaAt(source, ctx),
      null,
    );
  } else {
    ctx.boundLoopVars.remove(name);
    ctx.boundLoopSchemas.remove(name);
  }
  try {
    return body();
  } finally {
    if (wasBound) {
      ctx.boundLoopVars.add(name);
    } else {
      ctx.boundLoopVars.remove(name);
    }
    if (hadSchema) {
      ctx.boundLoopSchemas[name] = previousSchema;
    } else {
      ctx.boundLoopSchemas.remove(name);
    }
  }
}

bool _isRuntimeCall(String name, _Ctx ctx) =>
    ctx.schema.calls.containsKey(name) || reservedCalls.contains(name);

Object? _resolveRef(String name, _Ctx ctx, {required bool asExpr}) {
  if (ctx.visited.contains(name) || !ctx.syms.containsKey(name)) {
    ctx.unresolved.add(name);
    return asExpr ? PlaceholderNode(name) : null;
  }
  final target = ctx.syms[name]!;
  ctx.unreached.remove(name);
  if (target is CompNode && reservedCalls.contains(target.name)) {
    return RuntimeRefNode(
      name,
      target.name == 'Mutation'
          ? RuntimeRefType.mutation
          : RuntimeRefType.query,
    );
  }
  ctx.visited.add(name);
  final previous = ctx.currentStatementId;
  ctx.currentStatementId = name;
  try {
    if (asExpr) return _materializeExpr(target, ctx, const {});
    final result = _materializeValue(target, ctx);
    if (result is ElementNode) result.statementId = name;
    return result;
  } finally {
    ctx.currentStatementId = previous;
    ctx.visited.remove(name);
  }
}

Map<String, Ast> _nameArgs(List<Ast> args, List<ParamDef> params) => {
  for (var i = 0; i < params.length && i < args.length; i++)
    params[i].name: args[i],
};

Map<String, Ast>? _mapCallArgs(
  String name,
  List<Ast> args,
  CallDef def,
  _Ctx ctx,
) {
  final params = def.params;
  if (args.length > params.length) {
    pushIssue(ctx, name, '', ExcessArgs(params.length, args.length));
  }
  final mapped = _nameArgs(args, params);
  var isInvalid = false;
  final errorsBefore = ctx.errors.length;
  for (final p in params) {
    final arg = mapped[p.name];
    if (_violatesProp(p.schema, arg, name, '/${p.name}', ctx)) {
      isInvalid = true;
      continue;
    }
    final lit = arg != null ? literalValue(arg) : (found: true, value: null);
    if (!lit.found) continue;
    if (lit.value == null) {
      if (!p.required || !identical(p.defaultValue, absent)) continue;
      pushIssue(
        ctx,
        name,
        '/${p.name}',
        Missing(
          present: arg != null,
          signature: buildParamsSignature(name, params),
        ),
      );
      isInvalid = true;
      continue;
    }
    var next = validateSchemaValue(
      lit.value,
      p.schema,
      name,
      '/${p.name}',
      ctx,
    );
    if (identical(next, invalid)) {
      next = resolveInvalidValue(p.required, p.defaultValue);
    }
    if (identical(next, invalid)) {
      isInvalid = true;
    } else if (identical(next, absent)) {
      mapped.remove(p.name);
    } else if (!identical(next, lit.value)) {
      mapped[p.name] = literalAst(next);
    }
  }
  if (def.kind == CallKind.action && ctx.errors.length > errorsBefore) {
    isInvalid = true;
  }
  return isInvalid ? null : mapped;
}

Ast _materializeCall(
  CompNode node,
  _Ctx ctx,
  Ast Function(Ast) materializeArg,
) {
  final args = node.args.map(materializeArg).toList();
  final def = ctx.schema.calls[node.name];
  if (def == null || def.lazy) return node.copyWith(args: args);
  final mapped = def.builtin
      ? _nameArgs(args, def.params)
      : _mapCallArgs(node.name, args, def, ctx);
  if (mapped != null) return node.copyWith(args: args, mappedProps: mapped);
  return def.kind == CallKind.action
      ? CompNode('Action', [const ArrNode([])])
      : const NullNode();
}

List<Ast> _nameRawCallArgs(List<Ast> args, _Ctx ctx, String statementId) {
  final previous = ctx.currentStatementId;
  ctx.currentStatementId = statementId;
  try {
    return [for (final arg in args) _nameRawCalls(arg, ctx)];
  } finally {
    ctx.currentStatementId = previous;
  }
}

Ast _nameRawCalls(Ast node, _Ctx ctx) {
  Ast map(Ast child) => _nameRawCalls(child, ctx);
  switch (node) {
    case CompNode():
      final def = ctx.schema.calls[node.name];
      final mappedArgs = <Ast>[];
      if (def?.lazy == true && node.name == 'Each' && node.args.length >= 3) {
        mappedArgs.add(map(node.args[0]));
        mappedArgs.add(map(node.args[1]));
        _withLoopVar(loopVarName(node.args[1]), node.args[0], ctx, () {
          for (var i = 2; i < node.args.length; i++) {
            mappedArgs.add(map(node.args[i]));
          }
        });
      } else {
        mappedArgs.addAll(node.args.map(map));
      }
      if (def == null || def.lazy) return node.copyWith(args: mappedArgs);
      final errorsBefore = ctx.errors.length;
      final mapped = def.builtin
          ? _nameArgs(mappedArgs, def.params)
          : _mapCallArgs(node.name, mappedArgs, def, ctx);
      if (mapped != null) {
        return node.copyWith(args: mappedArgs, mappedProps: mapped);
      }
      final hasBoundOnlyError = ctx.errors
          .skip(errorsBefore)
          .any((error) => error.code == ValidationCode.boundOnly);
      if (hasBoundOnlyError) return const NullNode();
      return node.copyWith(
        args: mappedArgs,
        mappedProps: _nameArgs(mappedArgs, def.params),
      );
    case AssignNode(:final target, :final value):
      ctx.syntheticValueDepth++;
      try {
        return AssignNode(target, map(value));
      } finally {
        ctx.syntheticValueDepth--;
      }
    case ArrNode(:final elements):
      return ArrNode(elements.map(map).toList());
    case ObjNode(:final entries):
      return ObjNode([for (final (key, value) in entries) (key, map(value))]);
    case BinOpNode(:final op, :final left, :final right):
      return BinOpNode(op, map(left), map(right));
    case UnaryOpNode(:final op, :final operand):
      return UnaryOpNode(op, map(operand));
    case TernaryNode(:final condition, :final then, :final otherwise):
      return TernaryNode(map(condition), map(then), map(otherwise));
    case MemberNode(:final object, :final field):
      return MemberNode(map(object), field);
    case IndexNode(:final object, :final index):
      return IndexNode(map(object), map(index));
    default:
      return node;
  }
}

String? loopVarName(Ast arg) => switch (arg) {
  RefNode(:final name) => name,
  StrNode(:final value) => value,
  _ => null,
};

Ast? _materializeLazyBuiltin(CompNode node, _Ctx ctx, Set<String> scoped) {
  final def = ctx.schema.calls[node.name];
  if (def?.kind != CallKind.function || !def!.lazy || node.args.length < 3) {
    return null;
  }
  final varName = loopVarName(node.args[1]);
  if (varName == null) return null;
  final nextScoped = {...scoped, varName};
  final list = _materializeExpr(node.args[0], ctx, nextScoped);
  return _withLoopVar(
    varName,
    list,
    ctx,
    () => node.copyWith(
      args: [
        list,
        node.args[1],
        for (var i = 2; i < node.args.length; i++)
          _materializeExpr(node.args[i], ctx, nextScoped),
      ],
    ),
  );
}

Ast _materializeExpr(Ast node, _Ctx ctx, Set<String> scoped) {
  Ast m(Ast a) => _materializeExpr(a, ctx, scoped);
  switch (node) {
    case RefNode(:final name):
      return scoped.contains(name)
          ? node
          : _resolveRef(name, ctx, asExpr: true) as Ast;
    case PlaceholderNode():
      return node;
    case CompNode():
      if (node.isAtCall && !_isRuntimeCall(node.name, ctx)) {
        pushIssue(ctx, node.name, '', const UnknownFunction());
        return const NullNode();
      }
      final lazy = _materializeLazyBuiltin(node, ctx, scoped);
      if (lazy != null) return lazy;
      if (_isRuntimeCall(node.name, ctx)) return _materializeCall(node, ctx, m);
      final args = node.args.map(m).toList();
      final params = ctx.schema.components[node.name];
      if (params != null) {
        final checked = [
          for (var i = 0; i < args.length; i++)
            i < params.length &&
                    _violatesProp(
                      params[i].schema,
                      args[i],
                      node.name,
                      '/${params[i].name}',
                      ctx,
                    )
                ? const NullNode()
                : args[i],
        ];
        return node.copyWith(
          args: checked,
          mappedProps: _nameArgs(checked, params),
        );
      }
      pushIssue(
        ctx,
        node.name,
        '',
        UnknownComponent(ctx.schema.components.keys.toList()),
      );
      return node.copyWith(args: args);
    case ArrNode(:final elements):
      return ArrNode(elements.map(m).toList());
    case ObjNode(:final entries):
      return ObjNode([for (final (k, v) in entries) (k, m(v))]);
    case BinOpNode(:final op, :final left, :final right):
      return BinOpNode(op, m(left), m(right));
    case UnaryOpNode(:final op, :final operand):
      return UnaryOpNode(op, m(operand));
    case TernaryNode(:final condition, :final then, :final otherwise):
      return TernaryNode(m(condition), m(then), m(otherwise));
    case MemberNode(:final object, :final field):
      return MemberNode(m(object), field);
    case IndexNode(:final object, :final index):
      return IndexNode(m(object), m(index));
    case AssignNode(:final target, :final value):
      ctx.syntheticValueDepth++;
      try {
        return AssignNode(target, m(value));
      } finally {
        ctx.syntheticValueDepth--;
      }
    default:
      return node;
  }
}

bool _containsDynamic(Object? v) {
  if (v == null) return false;
  if (v is Ast) return true;
  if (v is List) return v.any(_containsDynamic);
  if (v is ElementNode) return v.props.values.any(_containsDynamic);
  if (v is Map) return v['steps'] is List || v.values.any(_containsDynamic);
  return false;
}

Object? _materializeValue(Ast node, _Ctx ctx) {
  switch (node) {
    case RefNode(:final name):
      return _resolveRef(name, ctx, asExpr: false);
    case StrNode(:final value):
      return value;
    case NumNode(:final value):
      return value;
    case BoolNode(:final value):
      return value;
    case NullNode() || PlaceholderNode():
      return null;
    case ArrNode(:final elements):
      final items = <Object?>[];
      for (final e in elements) {
        if (e is PlaceholderNode) continue;
        final value = _materializeValue(e, ctx);
        if (value == null && (e is CompNode || e is RefNode)) continue;
        items.add(value);
      }
      return items;
    case ObjNode(:final entries):
      return Js.object([
        for (final (k, v) in entries) MapEntry(k, _materializeValue(v, ctx)),
      ]);
    case CompNode(:final name, :final args):
      if (node.isAtCall && !_isRuntimeCall(name, ctx)) {
        pushIssue(ctx, name, '', const UnknownFunction());
        return null;
      }
      if (reservedCalls.contains(name)) {
        pushIssue(ctx, name, '', const InlineReserved());
        return null;
      }
      if (_isRuntimeCall(name, ctx)) {
        return _materializeLazyBuiltin(node, ctx, const {}) ??
            _materializeCall(
              node,
              ctx,
              (a) => _materializeExpr(a, ctx, const {}),
            );
      }
      final params = ctx.schema.components[name];
      if (params == null) {
        pushIssue(
          ctx,
          name,
          '',
          UnknownComponent(ctx.schema.components.keys.toList()),
        );
        return null;
      }
      final props = <String, Object?>{};
      var drop = false;
      for (var i = 0; i < params.length && i < args.length; i++) {
        final param = params[i];
        final value = _materializeValue(args[i], ctx);
        props[param.name] = value;
        if (param.schema == null) continue;
        var next =
            _violatesProp(param.schema, value, name, '/${param.name}', ctx)
            ? invalid
            : validateSchemaValue(
                value,
                param.schema,
                name,
                '/${param.name}',
                ctx,
              );
        if (identical(next, invalid)) {
          next = resolveInvalidValue(param.required, param.defaultValue);
          if (identical(next, invalid)) {
            drop = true;
          } else if (identical(next, absent)) {
            props.remove(param.name);
          }
        }
        if (!identical(next, invalid) && !identical(next, absent)) {
          props[param.name] = next;
        }
      }
      if (args.length > params.length) {
        pushIssue(ctx, name, '', ExcessArgs(params.length, args.length));
      }
      final missing = params.where(
        (p) =>
            p.required && (!props.containsKey(p.name) || props[p.name] == null),
      );
      final stillInvalid = <ParamDef>[];
      for (final p in missing.toList()) {
        if (!identical(p.defaultValue, absent)) {
          props[p.name] = p.defaultValue;
        } else {
          stillInvalid.add(p);
        }
      }
      if (stillInvalid.isNotEmpty) {
        for (final p in stillInvalid) {
          pushIssue(
            ctx,
            name,
            '/${p.name}',
            Missing(
              present: props.containsKey(p.name),
              signature: buildParamsSignature(name, params),
            ),
          );
        }
        return null;
      }
      if (drop) return null;
      return ElementNode(
        typeName: name,
        props: props,
        partial: ctx.partial,
        hasDynamicProps: props.values.any(_containsDynamic),
      );
    default:
      return isRuntimeExpr(node) ? _materializeExpr(node, ctx, const {}) : node;
  }
}

bool _isComponentCall(Ast? node) =>
    node is CompNode &&
    !node.isAtCall &&
    !builtinNames.contains(node.name) &&
    !reservedCalls.contains(node.name);

({String id, bool fallback})? _pickEntry(
  Map<String, Statement> stmts,
  String? rootName,
) {
  if (stmts.containsKey('root')) return (id: 'root', fallback: false);
  for (final s in stmts.values) {
    if (s is ValueStatement &&
        _isComponentCall(s.expr) &&
        (s.expr as CompNode).name == rootName) {
      return (id: s.id, fallback: true);
    }
  }
  return null;
}

bool _resolvesToComponentCall(Ast? node, Map<String, Ast> syms) {
  final seen = <String>{};
  while (node is RefNode && seen.add(node.name)) {
    node = syms[node.name];
  }
  return _isComponentCall(node);
}

bool _containsComponent(Ast node) {
  var found = false;
  walkAst(node, (n) {
    if (_isComponentCall(n)) found = true;
  });
  return found;
}

ParseResult _buildResult(
  Map<String, Statement> stmtMap,
  bool wasIncomplete,
  int stmtCount,
  CompiledSchema schema,
  String? rootName, {
  ({String name, Set<Statement> stmts})? partialRef,
  Set<String> boundNames = const {},
  Map<String, Object?> boundSchemas = const {},
}) {
  final entry = _pickEntry(stmtMap, rootName);
  final syms = <String, Ast>{
    for (final MapEntry(:key, :value) in stmtMap.entries)
      key: switch (value) {
        StateStatement(:final init) => init,
        ValueStatement(:final expr) => expr,
        QueryStatement(:final expr) => expr,
        MutationStatement(:final expr) => expr,
      },
  };
  final unreached = <String>{
    for (final MapEntry(:key, :value) in stmtMap.entries)
      if (key != entry?.id && value is ValueStatement) key,
  };
  final ctx = _Ctx(
    syms: syms,
    schema: schema,
    partial: wasIncomplete,
    unreached: unreached,
    boundNames: {...boundNames, ...boundSchemas.keys},
    boundSchemas: boundSchemas,
  )..currentStatementId = entry?.id;
  ElementNode? root;
  Ast? rootExpression;
  if (entry != null) {
    final materialized = _materializeValue(syms[entry.id]!, ctx);
    if (materialized is ElementNode) {
      root = materialized..statementId = entry.id;
    } else if (materialized is Ast && _containsComponent(materialized)) {
      rootExpression = materialized;
    }
  }

  final stateDeclarations = <String, Object?>{};
  final queries = <QueryStatementInfo>[];
  final mutations = <MutationStatementInfo>[];
  Ast? arg(List<Ast> args, int i) => i < args.length ? args[i] : null;
  for (final stmt in stmtMap.values) {
    switch (stmt) {
      case StateStatement(:final id, :final init):
        final previous = ctx.currentStatementId;
        ctx.currentStatementId = id;
        try {
          stateDeclarations[id] = _materializeValue(init, ctx);
        } finally {
          ctx.currentStatementId = previous;
        }
      case QueryStatement(:final id, :final expr, :final deps):
        final args = _nameRawCallArgs(expr.args, ctx, id);
        queries.add(
          QueryStatementInfo(
            statementId: id,
            toolAst: arg(args, 0),
            argsAst: arg(args, 1),
            defaultsAst: arg(args, 2),
            refreshAst: arg(args, 3),
            deps: deps,
          ),
        );
      case MutationStatement(:final id, :final expr):
        final args = _nameRawCallArgs(expr.args, ctx, id);
        mutations.add(
          MutationStatementInfo(
            statementId: id,
            toolAst: arg(args, 0),
            argsAst: arg(args, 1),
          ),
        );
      case ValueStatement():
    }
  }
  for (final stmt in stmtMap.values) {
    final nodes = switch (stmt) {
      StateStatement(:final init) => [init],
      ValueStatement(:final expr) => [expr],
      QueryStatement(:final expr) => expr.args,
      MutationStatement(:final expr) => expr.args,
    };
    for (final node in nodes) {
      for (final dep in _stateRefs(node)) {
        if (dep == partialRef?.name && partialRef!.stmts.contains(stmt)) {
          continue;
        }
        stateDeclarations.putIfAbsent(dep, () => null);
      }
    }
  }

  ctx.currentStatementId = entry?.id;
  final component = rootName ?? '';
  if (entry == null) {
    pushIssue(ctx, component, '', const NoRoot(NoRootReason.missing));
  } else if (root == null &&
      rootExpression == null &&
      !_resolvesToComponentCall(syms[entry.id], syms)) {
    pushIssue(ctx, component, '', const NoRoot(NoRootReason.notComponent));
  } else if (entry.fallback) {
    pushIssue(
      ctx,
      component,
      '',
      NoRoot(root != null ? NoRootReason.fallback : NoRootReason.missing),
    );
  }
  return ParseResult(
    root: root,
    rootExpression: rootExpression,
    meta: ParseMeta(
      incomplete: wasIncomplete,
      unresolved: ctx.unresolved,
      orphaned: entry != null ? unreached.toList() : const [],
      statementCount: stmtCount,
      errors: ctx.errors,
    ),
    stateDeclarations: stateDeclarations,
    queryStatements: queries,
    mutationStatements: mutations,
  );
}

Map<String, Statement> _statements(String text) {
  final map = <String, Statement>{};
  for (final s in split(tokenize(text))) {
    map[s.id] = classify(s, parseExpression(s.tokens));
  }
  return map;
}

/// Parses a complete (or partial) program in one pass.
ParseResult parseProgram(
  String input,
  CompiledSchema schema, {
  String? rootName,
  Set<String> boundNames = const {},
  Map<String, JsonSchema> boundSchemas = const {},
}) {
  final trimmed = preprocess(input);
  if (trimmed.isEmpty) return ParseResult.empty();
  final closed = autoClose(trimmed);
  final stmts = _statements(closed.text);
  if (stmts.isEmpty) return ParseResult.empty(incomplete: closed.wasIncomplete);
  return _buildResult(
    stmts,
    closed.wasIncomplete,
    stmts.length,
    schema,
    rootName,
    boundNames: boundNames,
    boundSchemas: boundSchemas,
  );
}

/// lang-core's streaming parser: caches completed statements and re-parses
/// only the pending tail on each update.
final class StreamParser {
  StreamParser(this.schema, {this.rootName, this.boundNames = const {}});
  final CompiledSchema schema;
  final String? rootName;

  /// Host-bound `$names` (with the `$`): paths into them pass bound-only props.
  final Set<String> boundNames;

  String _buf = '';
  String _cleaned = '';
  int _completedEnd = 0;
  final Map<String, Statement> _completed = {};
  int _completedCount = 0;

  void reset() {
    _buf = '';
    _cleaned = '';
    _completedEnd = 0;
    _completed.clear();
    _completedCount = 0;
  }

  ParseResult push(String chunk, {bool complete = false}) {
    _buf += chunk;
    return getResult(complete: complete);
  }

  /// Sets the full text so far; restarts when it is not an extension.
  ParseResult set(String fullText, {bool complete = false}) {
    if (fullText.length < _buf.length || !fullText.startsWith(_buf)) reset();
    _buf += fullText.substring(_buf.length);
    return getResult(complete: complete);
  }

  void _addStatement(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    for (final s in split(tokenize(t))) {
      _completed[s.id] = classify(s, parseExpression(s.tokens));
      _completedCount++;
    }
  }

  int _scanCompleted() {
    var depth = 0, ternaryDepth = 0;
    String? inStr;
    var esc = false;
    var stmtStart = _completedEnd;
    final s = _cleaned;
    for (var i = _completedEnd; i < s.length; i++) {
      final c = s[i];
      if (esc) {
        esc = false;
        continue;
      }
      if (c == r'\' && inStr != null) {
        esc = true;
        continue;
      }
      if (inStr != null) {
        if (c == inStr) inStr = null;
        continue;
      }
      if (c == '"' || c == "'") {
        inStr = c;
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth++;
      } else if (c == ')' || c == ']' || c == '}') {
        depth = depth > 0 ? depth - 1 : 0;
      } else if (c == '?' && depth == 0) {
        ternaryDepth++;
      } else if (c == ':' && depth == 0 && ternaryDepth > 0) {
        ternaryDepth--;
      } else if (c == '\n' && depth <= 0 && ternaryDepth <= 0) {
        var peek = i + 1;
        while (peek < s.length && ' \t\r\n'.contains(s[peek])) {
          peek++;
        }
        if (peek < s.length &&
            (s[peek] == '?' || (s[peek] == ':' && ternaryDepth > 0))) {
          continue;
        }
        final t = s.substring(stmtStart, i).trim();
        if (t.isNotEmpty) _addStatement(t);
        stmtStart = i + 1;
        _completedEnd = i + 1;
      }
    }
    return stmtStart;
  }

  ParseResult getResult({bool complete = false}) {
    final next = preprocess(_buf);
    if (!next.startsWith(_cleaned.substring(0, _completedEnd))) {
      _completedEnd = 0;
      _completed.clear();
      _completedCount = 0;
    }
    _cleaned = next;
    final pendingStart = _scanCompleted();
    final pendingText = _cleaned.substring(pendingStart).trim();
    // A trimmed text never ends right after a completed statement.
    if (pendingText.isEmpty) return ParseResult.empty();
    final closed = autoClose(pendingText);
    final stmts = split(tokenize(closed.text));
    if (stmts.isEmpty) {
      if (_completedCount == 0) {
        return ParseResult.empty(incomplete: closed.wasIncomplete);
      }
      return _buildResult(
        {..._completed},
        closed.wasIncomplete,
        _completedCount,
        schema,
        rootName,
        boundNames: boundNames,
      );
    }
    final all = {..._completed};
    final pending = Set<Statement>.identity();
    for (final s in stmts) {
      if (_completed.containsKey(s.id) && closed.wasIncomplete) continue;
      final stmt = classify(s, parseExpression(s.tokens));
      all[s.id] = stmt;
      pending.add(stmt);
    }
    String? tailName;
    if (!complete) {
      final tail = RegExp(r'\$\w+$').firstMatch(_buf)?.group(0);
      if (tail != null &&
          pendingText.endsWith(tail) &&
          !RegExp('${RegExp.escape(tail)}(?!\\w)').hasMatch(
            pendingText.substring(0, pendingText.length - tail.length),
          )) {
        tailName = tail;
      }
    }
    return _buildResult(
      all,
      closed.wasIncomplete,
      _completedCount + stmts.length,
      schema,
      rootName,
      partialRef: tailName == null ? null : (name: tailName, stmts: pending),
      boundNames: boundNames,
    );
  }
}

/// lang-core `Parser`: parses whole programs against one library schema.
final class Parser {
  Parser._(this._schema, this._rootName);
  final CompiledSchema _schema;
  final String? _rootName;

  ParseResult parse(String input) =>
      parseProgram(input, _schema, rootName: _rootName);
}

/// lang-core `parse`: one complete (or partial) program against a compiled
/// schema (`CompiledSchema.fromJsonSchema(library.toJsonSchema())`).
ParseResult parse(String input, CompiledSchema schema, [String? rootName]) =>
    parseProgram(input, schema, rootName: rootName);

/// lang-core `createParser`; pass `library.toJsonSchema()`.
Parser createParser(JsonSchema schema, {String? rootName}) =>
    Parser._(CompiledSchema.fromJsonSchema(schema), rootName);

/// lang-core `createStreamingParser`; pass `library.toJsonSchema()`.
StreamParser createStreamingParser(JsonSchema schema, {String? rootName}) =>
    StreamParser(CompiledSchema.fromJsonSchema(schema), rootName: rootName);
