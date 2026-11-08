import '../runtime/builtins.dart';
import 'ast.dart';
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
      return defs.containsKey(ref) ? _inlineRefs(defs[ref], defs) : node;
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

final class QueryStatementInfo {
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
}

final class MutationStatementInfo {
  const MutationStatementInfo({
    required this.statementId,
    this.toolAst,
    this.argsAst,
  });
  final String statementId;
  final Ast? toolAst;
  final Ast? argsAst;
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
  }) : super(componentNames: schema.components.keys.toSet());
  final Map<String, Ast> syms;
  final CompiledSchema schema;
  final List<String> unresolved = [];
  final Set<String> visited = {};
  final Set<String> unreached;
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

void _nameRawCallArgs(List<Ast> args, _Ctx ctx, String statementId) {
  final previous = ctx.currentStatementId;
  ctx.currentStatementId = statementId;
  final seen = Set<CompNode>.identity();
  for (final arg in args) {
    walkAst(arg, (node) {
      if (node is! CompNode || !seen.add(node)) return;
      final def = ctx.schema.calls[node.name];
      if (def == null || def.lazy) return;
      node.mappedProps =
          (def.builtin ? null : _mapCallArgs(node.name, node.args, def, ctx)) ??
          _nameArgs(node.args, def.params);
    });
  }
  ctx.currentStatementId = previous;
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
  return node.copyWith(
    args: [
      for (var i = 0; i < node.args.length; i++)
        i == 1 ? node.args[i] : _materializeExpr(node.args[i], ctx, nextScoped),
    ],
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
        return node.copyWith(args: args, mappedProps: _nameArgs(args, params));
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
      return AssignNode(target, m(value));
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
      return <String, Object?>{
        for (final (k, v) in entries) k: _materializeValue(v, ctx),
      };
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
        var next = validateSchemaValue(
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
        stateDeclarations[id] = _materializeValue(init, ctx);
      case QueryStatement(:final id, :final expr, :final deps):
        _nameRawCallArgs(expr.args, ctx, id);
        queries.add(
          QueryStatementInfo(
            statementId: id,
            toolAst: arg(expr.args, 0),
            argsAst: arg(expr.args, 1),
            defaultsAst: arg(expr.args, 2),
            refreshAst: arg(expr.args, 3),
            deps: deps,
          ),
        );
      case MutationStatement(:final id, :final expr):
        _nameRawCallArgs(expr.args, ctx, id);
        mutations.add(
          MutationStatementInfo(
            statementId: id,
            toolAst: arg(expr.args, 0),
            argsAst: arg(expr.args, 1),
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
  );
}

/// lang-core's streaming parser: caches completed statements and re-parses
/// only the pending tail on each update.
final class StreamParser {
  StreamParser(this.schema, {this.rootName});
  final CompiledSchema schema;
  final String? rootName;

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
    return result(complete: complete);
  }

  /// Sets the full text so far; restarts when it is not an extension.
  ParseResult set(String fullText, {bool complete = false}) {
    if (fullText.length < _buf.length || !fullText.startsWith(_buf)) reset();
    _buf += fullText.substring(_buf.length);
    return result(complete: complete);
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

  ParseResult result({bool complete = false}) {
    final next = preprocess(_buf);
    if (!next.startsWith(_cleaned.substring(0, _completedEnd))) {
      _completedEnd = 0;
      _completed.clear();
      _completedCount = 0;
    }
    _cleaned = next;
    final pendingStart = _scanCompleted();
    final pendingText = _cleaned.substring(pendingStart).trim();
    if (pendingText.isEmpty) {
      if (_completedCount == 0) return ParseResult.empty();
      return _buildResult(
        {..._completed},
        false,
        _completedCount,
        schema,
        rootName,
      );
    }
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
    );
  }
}
