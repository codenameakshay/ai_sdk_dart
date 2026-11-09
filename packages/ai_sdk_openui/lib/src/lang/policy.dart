import 'dart:convert';

import '../runtime/builtins.dart' show builtinStepSpecs;
import 'ast.dart';
import 'js.dart';
import 'parser.dart';
import 'validation.dart';

/// What to do with a component the library does not define.
enum UnknownComponentPolicy { drop, fail }

/// Limits a server applies to a program before it runs it.
final class ValidationPolicy {
  const ValidationPolicy({
    this.maxNodes,
    this.maxDepth,
    this.maxStringLength,
    this.unknownComponents = UnknownComponentPolicy.drop,
    this.allowedActions,
  });

  final int? maxNodes;
  final int? maxDepth;
  final int? maxStringLength;
  final UnknownComponentPolicy unknownComponents;

  /// Built-in steps (`ToAssistant`, `OpenUrl`, `Set`, `Reset`, `Run`) and
  /// library actions a program may call; null allows all.
  final Set<String>? allowedActions;

  /// Reads [toJson]'s form. A missing key leaves that cap off; an unknown
  /// `unknownComponents` value throws an [ArgumentError].
  factory ValidationPolicy.fromJson(Map<String, Object?> json) {
    final unknown = json['unknownComponents'] as String?;
    return ValidationPolicy(
      maxNodes: json['maxNodes'] as int?,
      maxDepth: json['maxDepth'] as int?,
      maxStringLength: json['maxStringLength'] as int?,
      unknownComponents: unknown == null
          ? UnknownComponentPolicy.drop
          : UnknownComponentPolicy.values.byName(unknown),
      allowedActions: (json['allowedActions'] as List?)?.cast<String>().toSet(),
    );
  }

  /// The policy as JSON: the caps that are set, `unknownComponents` as
  /// `"drop"` or `"fail"`, and `allowedActions` sorted.
  Map<String, Object?> toJson() => {
    'maxNodes': ?maxNodes,
    'maxDepth': ?maxDepth,
    'maxStringLength': ?maxStringLength,
    'unknownComponents': unknownComponents.name,
    if (allowedActions != null)
      'allowedActions': allowedActions!.toList()..sort(),
  };
}

/// [value] as canonical JSON text: object keys sorted, arrays in their own
/// order, two-space indents and a final newline. The members of a JSON Schema
/// `properties` object keep their order, because that order is the positional
/// order of a component's or call's arguments. Equal values give equal bytes
/// whatever order their other maps were built in, so a regenerated
/// `spec.json` only diffs when the library changes.
String canonicalJson(Object? value) =>
    '${const JsonEncoder.withIndent('  ').convert(_canonical(value, false))}\n';

Object? _canonical(Object? value, bool keepOrder) {
  if (value is List) return [for (final v in value) _canonical(v, false)];
  if (value is! Map) return value;
  final keys = [for (final k in value.keys) '$k'];
  if (!keepOrder) keys.sort();
  return {
    for (final key in keys)
      key: _canonical(value[key], !keepOrder && key == 'properties'),
  };
}

final class ValidationIssue {
  const ValidationIssue({
    required this.code,
    required this.message,
    this.isWarning = false,
    this.statementId,
    this.component,
    this.path,
  });

  final String code;
  final String message;
  final bool isWarning;
  final String? statementId;
  final String? component;
  final String? path;

  Map<String, Object?> toJson() => {
    'code': code,
    'severity': isWarning ? 'warning' : 'error',
    'message': message,
    'statementId': ?statementId,
    'component': ?component,
    'path': ?path,
  };
}

final class ValidationReport {
  const ValidationReport({
    required this.issues,
    required this.hasRoot,
    required this.nodes,
    required this.depth,
    required this.statements,
  });

  final List<ValidationIssue> issues;
  final bool hasRoot;
  final int nodes;
  final int depth;
  final int statements;

  /// Has a root and no error-severity issue.
  bool get ok => hasRoot && issues.every((i) => i.isWarning);

  Map<String, Object?> toJson() => {
    'ok': ok,
    'issues': [for (final i in issues) i.toJson()],
    'stats': {'nodes': nodes, 'depth': depth, 'statements': statements},
  };

  /// [toJson] as text: two-space JSON and a final newline.
  String toJsonString() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

/// Checks [program] against [schema] and [policy] without running it. Works
/// from a spec's JSON Schema alone, so a server needs no library object.
ValidationReport validateProgram(
  String program,
  CompiledSchema schema, {
  String? rootName,
  ValidationPolicy policy = const ValidationPolicy(),
  Set<String> boundNames = const {},
}) {
  final result = parseProgram(
    program,
    schema,
    rootName: rootName,
    boundNames: boundNames,
  );
  final issues = <ValidationIssue>[
    for (final e in result.meta.errors)
      ValidationIssue(
        code: e.code.wire,
        message: e.message,
        isWarning:
            e.isWarning ||
            (e.code == ValidationCode.unknownComponent &&
                policy.unknownComponents == UnknownComponentPolicy.drop),
        statementId: e.statementId,
        component: e.component.isEmpty ? null : e.component,
        path: e.path.isEmpty ? null : e.path,
      ),
    if (result.meta.incomplete)
      const ValidationIssue(
        code: 'incomplete',
        message: 'The program ends inside an unfinished statement',
      ),
    for (final name in result.meta.unresolved.toSet())
      ValidationIssue(
        code: 'unresolved',
        message: 'Reference "$name" is never defined',
        isWarning: true,
      ),
    for (final name in result.meta.orphaned)
      ValidationIssue(
        code: 'orphaned',
        message: 'Statement "$name" is not reachable from root',
        isWarning: true,
        statementId: name,
      ),
  ];
  final walk = _Walk(policy, schema, issues, result.stateDeclarations);
  final root = result.root;
  final entry = root?.statementId ?? 'root';
  if (root != null) {
    walk.element(root, entry, '', 1);
  } else if (result.rootExpression != null) {
    walk.ast(result.rootExpression!, entry, '', 0, null);
  }
  for (final query in result.queryStatements) {
    walk.query(query);
  }
  for (final mutation in result.mutationStatements) {
    walk.mutation(mutation);
  }
  for (final MapEntry(:key, :value) in result.stateDeclarations.entries) {
    walk.value(value, key, '', 0, null);
  }
  final max = policy.maxNodes;
  if (max != null && walk.nodes > max) {
    issues.add(
      ValidationIssue(
        code: 'too-many-nodes',
        message: 'The program has ${walk.nodes} components; the limit is $max',
        statementId: entry,
      ),
    );
  }
  return ValidationReport(
    issues: issues,
    hasRoot: root != null || result.rootExpression != null,
    nodes: walk.nodes,
    depth: walk.depth,
    statements: result.meta.statementCount,
  );
}

final _steps = {for (final s in builtinStepSpecs) s.name};

final class _Walk {
  _Walk(this.policy, this.schema, this.issues, this.stateDeclarations);

  final ValidationPolicy policy;
  final CompiledSchema schema;
  final List<ValidationIssue> issues;
  final Map<String, Object?> stateDeclarations;
  final Set<String> _checkingStates = {};
  final Set<Ast> _resolvingStatePaths = {};
  final Set<Ast> _resolvingKnownValues = {};
  final Set<Ast> _resolvingLegacySteps = {};
  final Map<String, List<Object?>> _actionAliases = {};
  int nodes = 0;
  int depth = 0;
  var _deep = false;

  void element(ElementNode el, String id, String path, int level) {
    final sid = el.statementId ?? id;
    final base = el.statementId != null ? '' : path; // paths are per statement
    _component(el.typeName, sid, base, level);
    final params = schema.components[el.typeName] ?? const <ParamDef>[];
    for (final MapEntry(:key, :value) in el.props.entries) {
      final param = params.where((p) => p.name == key).firstOrNull;
      if (param != null && _isActionSlot(param.schema)) {
        _scanLegacyActions(value, sid, '$base/$key', el.typeName);
      }
      this.value(value, sid, '$base/$key', level, el.typeName);
    }
  }

  void query(QueryStatementInfo query) {
    for (final (name, ast) in [
      ('tool', query.toolAst),
      ('args', query.argsAst),
      ('defaults', query.defaultsAst),
      ('refresh', query.refreshAst),
    ]) {
      if (ast != null) {
        this.ast(ast, query.statementId, '/$name', 0, null);
      }
    }
  }

  void mutation(MutationStatementInfo mutation) {
    for (final (name, ast) in [
      ('tool', mutation.toolAst),
      ('args', mutation.argsAst),
    ]) {
      if (ast != null) {
        this.ast(ast, mutation.statementId, '/$name', 0, null);
      }
    }
  }

  void _component(String name, String sid, String path, int level) {
    nodes++;
    if (level > depth) depth = level;
    final max = policy.maxDepth;
    if (max == null || level <= max || _deep) return;
    _deep = true;
    issues.add(
      ValidationIssue(
        code: 'too-deep',
        message: 'Component $name is nested $level deep; the limit is $max',
        statementId: sid,
        component: name,
        path: path.isEmpty ? null : path,
      ),
    );
  }

  void value(Object? v, String sid, String path, int level, String? component) {
    switch (v) {
      case ElementNode():
        element(v, sid, path, level + 1);
      case String():
        _string(v, sid, path, component);
      case List():
        for (var i = 0; i < v.length; i++) {
          value(v[i], sid, '$path/$i', level, component);
        }
      case Map():
        for (final e in v.entries) {
          value(e.value, sid, '$path/${e.key}', level, component);
        }
      case Ast():
        ast(v, sid, path, level, component);
    }
  }

  void ast(Ast node, String sid, String path, int level, String? component) {
    void walk(Ast a) => ast(a, sid, path, level, component);
    switch (node) {
      case StrNode(:final value):
        _string(value, sid, path, component);
      case CompNode(:final name, :final args):
        final allowed = policy.allowedActions;
        final def = schema.calls[name];
        final isAction =
            _steps.contains(name) ||
            (def != null && def.kind == CallKind.action && !def.builtin);
        if (isAction && allowed != null && !allowed.contains(name)) {
          issues.add(
            ValidationIssue(
              code: 'action-not-allowed',
              message: 'Action @$name is not allowed',
              statementId: sid,
              component: component,
              path: path.isEmpty ? null : path,
            ),
          );
        }
        if (!node.isAtCall && schema.components.containsKey(name)) {
          _component(name, sid, path, level + 1);
          final params = schema.components[name] ?? const <ParamDef>[];
          for (var index = 0; index < args.length; index++) {
            final a = args[index];
            final param = index < params.length ? params[index] : null;
            if (param != null && _isActionSlot(param.schema)) {
              _scanLegacyActions(a, sid, path, name);
            }
            ast(a, sid, path, level + 1, name);
          }
        } else if (name == 'Each' && args.length >= 3) {
          walk(args[0]);
          walk(args[1]);
          final alias = switch (args[1]) {
            RefNode(:final name) => name,
            StrNode(:final value) => value,
            _ => null,
          };
          final values = _eachValues(args[0]);
          final previous = alias == null ? null : _actionAliases[alias];
          if (alias != null) {
            if (values == null) {
              _actionAliases.remove(alias);
            } else {
              _actionAliases[alias] = values;
            }
          }
          try {
            for (var i = 2; i < args.length; i++) {
              walk(args[i]);
            }
          } finally {
            if (alias != null) {
              if (previous == null) {
                _actionAliases.remove(alias);
              } else {
                _actionAliases[alias] = previous;
              }
            }
          }
        } else {
          args.forEach(walk);
        }
      case ArrNode(:final elements):
        elements.forEach(walk);
      case ObjNode(:final entries):
        for (final (_, v) in entries) {
          walk(v);
        }
      case BinOpNode(:final left, :final right):
        walk(left);
        walk(right);
      case UnaryOpNode(:final operand):
        walk(operand);
      case TernaryNode(:final condition, :final then, :final otherwise):
        walk(condition);
        walk(then);
        walk(otherwise);
      case MemberNode(:final object):
        walk(object);
      case IndexNode(:final object, :final index):
        walk(object);
        walk(index);
      case AssignNode(:final value):
        walk(value);
      default:
    }
  }

  void _scanLegacyActions(
    Object? value,
    String sid,
    String path,
    String? component, {
    bool requireStringUrl = false,
  }) {
    switch (value) {
      case Map():
        _scanLegacyMap(
          value,
          sid,
          path,
          component,
          requireStringUrl: requireStringUrl,
        );
      case List():
        for (var i = 0; i < value.length; i++) {
          _scanLegacyActions(
            value[i],
            sid,
            '$path/$i',
            component,
            requireStringUrl: requireStringUrl,
          );
        }
      case Ast():
        switch (value) {
          case ObjNode(:final entries):
            final literal = literalValue(value);
            if (literal.found) {
              _scanLegacyActions(
                literal.value,
                sid,
                path,
                component,
                requireStringUrl: requireStringUrl,
              );
              break;
            }
            final steps = _lastField(entries, 'steps');
            final planSteps = steps == null ? null : _statePathValues(steps);
            if (planSteps != null &&
                planSteps.any((value) => value is List || value is ArrNode)) {
              for (final value in planSteps) {
                if (value is List) {
                  _scanLegacyPlanSteps(value, sid, path, component);
                } else if (value is ArrNode) {
                  _scanLegacyPlanSteps(value.elements, sid, path, component);
                }
              }
            } else {
              _scanLegacyStepAst(
                value,
                sid,
                path,
                component,
                requireStringUrl: requireStringUrl,
              );
            }
          case ArrNode(:final elements):
            for (var i = 0; i < elements.length; i++) {
              _scanLegacyActions(
                elements[i],
                sid,
                '$path/$i',
                component,
                requireStringUrl: requireStringUrl,
              );
            }
          case CompNode(name: 'Action', args: final args):
            if (args.isNotEmpty) {
              _scanLegacyActions(
                args.first,
                sid,
                '$path/steps',
                component,
                requireStringUrl: true,
              );
            }
          case RefNode(:final name):
            for (final item in _actionAliases[name] ?? const <Object?>[]) {
              _scanLegacyActions(
                item,
                sid,
                path,
                component,
                requireStringUrl: requireStringUrl,
              );
            }
          case TernaryNode(:final then, :final otherwise):
            _scanLegacyActions(
              then,
              sid,
              path,
              component,
              requireStringUrl: requireStringUrl,
            );
            _scanLegacyActions(
              otherwise,
              sid,
              path,
              component,
              requireStringUrl: requireStringUrl,
            );
          case MemberNode() || IndexNode():
            if (_resolvingStatePaths.add(value)) {
              try {
                final resolvedValues = _statePathValues(value);
                if (resolvedValues != null) {
                  for (final resolved in resolvedValues) {
                    _scanLegacyActions(
                      resolved,
                      sid,
                      path,
                      component,
                      requireStringUrl: requireStringUrl,
                    );
                  }
                }
              } finally {
                _resolvingStatePaths.remove(value);
              }
            }
          case StateRefNode(:final name):
            if (_checkingStates.add(name) &&
                stateDeclarations.containsKey(name)) {
              _scanLegacyActions(
                stateDeclarations[name],
                sid,
                '$path/\$$name',
                component,
                requireStringUrl: requireStringUrl,
              );
              _checkingStates.remove(name);
            }
          default:
        }
    }
  }

  List<Object?>? _statePathValues(Ast node) {
    if (!_resolvingKnownValues.add(node)) return null;
    try {
      final literal = literalValue(node);
      if (literal.found) return [literal.value];
      switch (node) {
        case StateRefNode(:final name):
          if (!stateDeclarations.containsKey(name)) return null;
          final value = stateDeclarations[name];
          if (value is Ast &&
              (value is StateRefNode ||
                  value is MemberNode ||
                  value is IndexNode)) {
            return _statePathValues(value);
          }
          return [value];
        case RefNode(:final name):
          return _actionAliases[name];
        case MemberNode(:final object, :final field):
          final objects = _statePathValues(object);
          return _projectStateValues(objects, field);
        case IndexNode(:final object, :final index):
          final literalIndex = literalValue(index);
          if (!literalIndex.found) return null;
          final objects = _statePathValues(object);
          return _projectStateValues(objects, Js.string(literalIndex.value));
        case ObjNode() || ArrNode():
          return [node];
        default:
          return null;
      }
    } finally {
      _resolvingKnownValues.remove(node);
    }
  }

  List<Object?>? _projectStateValues(List<Object?>? objects, String key) {
    if (objects == null) return null;
    final values = <Object?>[];
    for (final object in objects) {
      final value = _stateProperty(object, key);
      if (value is Ast) {
        final literal = literalValue(value);
        if (literal.found) {
          values.add(literal.value);
        } else if (value is StateRefNode ||
            value is MemberNode ||
            value is IndexNode) {
          values.addAll(_statePathValues(value) ?? [value]);
        } else {
          values.add(value);
        }
      } else {
        values.add(value);
      }
    }
    return values;
  }

  Object? _stateProperty(Object? object, String key) {
    if (object is ObjNode) return _lastField(object.entries, key);
    if (object is ArrNode) {
      if (key == 'length') return NumNode(object.elements.length);
      if (Js.isArrayIndex(key) && int.parse(key) < object.elements.length) {
        return object.elements[int.parse(key)];
      }
      return null;
    }
    return Js.property(object, key);
  }

  List<Object?>? _eachValues(Ast source) {
    if (source case ArrNode(:final elements)) {
      final values = <Object?>[];
      for (final element in elements) {
        final elementValues = _statePathValues(element);
        if (elementValues == null) return null;
        values.addAll(elementValues);
      }
      return values;
    }
    final sourceValues = _statePathValues(source);
    if (sourceValues == null) return null;
    final values = <Object?>[];
    for (final value in sourceValues) {
      if (value is List) {
        values.addAll(value);
      } else if (value is ArrNode) {
        values.addAll(value.elements);
      } else {
        return null;
      }
    }
    return values;
  }

  bool _mayBeString(Object? value) {
    if (value is String) return true;
    if (value is! Ast) return false;
    final knownValues = _statePathValues(value);
    return knownValues == null || knownValues.any((known) => known is String);
  }

  Ast? _lastField(List<(String, Ast)> entries, String name) =>
      entries.reversed.where((entry) => entry.$1 == name).firstOrNull?.$2;

  void _scanLegacyMap(
    Map value,
    String sid,
    String path,
    String? component, {
    required bool requireStringUrl,
  }) {
    final steps = value['steps'];
    if (steps is List) {
      _scanLegacyPlanSteps(steps, sid, path, component);
    } else if (steps is Ast) {
      final planSteps = _statePathValues(steps);
      if (planSteps != null &&
          planSteps.any((value) => value is List || value is ArrNode)) {
        for (final value in planSteps) {
          if (value is List) {
            _scanLegacyPlanSteps(value, sid, path, component);
          } else if (value is ArrNode) {
            _scanLegacyPlanSteps(value.elements, sid, path, component);
          }
        }
      } else {
        _scanLegacyStep(
          value,
          sid,
          path,
          component,
          requireStringUrl: requireStringUrl,
        );
      }
    } else {
      _scanLegacyStep(
        value,
        sid,
        path,
        component,
        requireStringUrl: requireStringUrl,
      );
    }
  }

  void _scanLegacyPlanSteps(
    Iterable<Object?> steps,
    String sid,
    String path,
    String? component,
  ) {
    var index = 0;
    for (final step in steps) {
      if (step is Ast) {
        _scanLegacyStepAst(
          step,
          sid,
          '$path/steps/$index',
          component,
          requireStringUrl: true,
        );
      } else {
        _scanLegacyStep(
          step,
          sid,
          '$path/steps/$index',
          component,
          requireStringUrl: true,
        );
      }
      index++;
    }
  }

  void _scanLegacyStep(
    Object? value,
    String sid,
    String path,
    String? component, {
    required bool requireStringUrl,
  }) {
    if (value is! Map) return;
    final type = value['type'];
    if (type is String) {
      _legacyActionType(
        type,
        sid,
        path,
        component,
        openUrlIsValid: !requireStringUrl || _mayBeString(value['url']),
      );
    }
  }

  void _scanLegacyStepAst(
    Ast value,
    String sid,
    String path,
    String? component, {
    required bool requireStringUrl,
  }) {
    if (value is! ObjNode) {
      if (value is! RefNode &&
          value is! StateRefNode &&
          value is! MemberNode &&
          value is! IndexNode) {
        return;
      }
      if (!_resolvingLegacySteps.add(value)) return;
      try {
        for (final candidate in _statePathValues(value) ?? const <Object?>[]) {
          if (candidate is Map) {
            _scanLegacyStep(
              candidate,
              sid,
              path,
              component,
              requireStringUrl: requireStringUrl,
            );
          } else if (candidate is ObjNode) {
            _scanLegacyStepAst(
              candidate,
              sid,
              path,
              component,
              requireStringUrl: requireStringUrl,
            );
          }
        }
      } finally {
        _resolvingLegacySteps.remove(value);
      }
      return;
    }
    final type = _lastField(value.entries, 'type');
    if (type != null) {
      final typeValues = _statePathValues(type);
      for (final typeValue in typeValues ?? const <Object?>[]) {
        if (typeValue is! String) continue;
        _legacyActionType(
          typeValue,
          sid,
          path,
          component,
          openUrlIsValid:
              !requireStringUrl ||
              _mayBeString(_lastField(value.entries, 'url')),
        );
      }
    }
  }

  bool _isActionSlot(Object? schemaNode) {
    bool hasStepShape(Object? node) {
      if (node is Map) {
        final properties = node['properties'];
        final typeSchema = properties is Map ? properties['type'] : null;
        if (typeSchema is Map &&
            const {
              'open_url',
              'continue_conversation',
            }.contains(typeSchema['const'])) {
          return true;
        }
        return ['anyOf', 'oneOf'].any(
          (key) => node[key] is List && (node[key] as List).any(hasStepShape),
        );
      }
      return false;
    }

    return hasStepShape(schemaNode);
  }

  void _legacyActionType(
    String type,
    String sid,
    String path,
    String? component, {
    bool openUrlIsValid = true,
  }) {
    final action = switch (type) {
      'open_url' when openUrlIsValid => 'OpenUrl',
      'continue_conversation' => 'ToAssistant',
      _ => null,
    };
    final allowed = policy.allowedActions;
    if (action != null && allowed != null && !allowed.contains(action)) {
      issues.add(
        ValidationIssue(
          code: 'action-not-allowed',
          message: 'Action @$action is not allowed',
          statementId: sid,
          component: component,
          path: path.isEmpty ? null : path,
        ),
      );
    }
  }

  void _string(String s, String sid, String path, String? component) {
    final max = policy.maxStringLength;
    if (max == null || s.length <= max) return;
    issues.add(
      ValidationIssue(
        code: 'string-too-long',
        message: 'A string of ${s.length} characters is over the limit of $max',
        statementId: sid,
        component: component,
        path: path.isEmpty ? null : path,
      ),
    );
  }
}
