import 'dart:convert';

import '../spec/library.dart';
import 'ast.dart';
import 'js.dart';
import 'validation.dart';

/// lang-core `jsonToOpenUI`: an element tree (a parse result's root) back to program text that
/// `mergeStatements` accepts.
String jsonToOpenUI(
  ElementNode json,
  OpenUiLibrary library, {
  Map<String, Object?>? stateDeclarations,
}) {
  final collector = _Collector(
    library.compiled.components,
    library.compiled.calls.keys.toSet(),
  );
  final rootExpr = collector.elementExpr(json);
  final rootId = (json.statementId ?? '').isEmpty ? 'root' : json.statementId!;
  final lines = ['$rootId = $rootExpr'];
  for (final entry in collector.statements.entries) {
    if (entry.key != rootId) lines.add(entry.value);
  }
  if (stateDeclarations != null) {
    for (final entry in stateDeclarations.entries) {
      if (entry.value != null) {
        lines.add('${entry.key} = ${collector.value(entry.value)}');
      }
    }
  }
  return lines.join('\n');
}

const _precedence = {
  '||': 2,
  '&&': 3,
  '==': 4,
  '!=': 4,
  '>': 5,
  '<': 5,
  '>=': 5,
  '<=': 5,
  '+': 6,
  '-': 6,
  '*': 7,
  '/': 7,
  '%': 7,
};

/// Statements in registration order, keyed by id; the first registration of an id wins.
final class _Collector {
  _Collector(this.components, this.calls);

  final Map<String, List<ParamDef>> components;
  final Set<String> calls;
  final Map<String, String> statements = {};

  String value(Object? v) {
    if (v == null) return 'null';
    if (v is String) return jsonEncode(v);
    if (v is num) return Js.numberToString(v);
    if (v is bool) return v ? 'true' : 'false';
    if (v is ElementNode) return elementValue(v);
    if (v is Ast) return _ast(v, calls);
    if (v is List) return '[${v.map(value).join(', ')}]';
    if (v is Map) {
      return '{${v.entries.map((e) => '${e.key}: ${value(e.value)}').join(', ')}}';
    }
    return 'null'; // coverage:ignore-line
  }

  String elementValue(ElementNode node) {
    final id = node.statementId;
    if (id == null || id.isEmpty) return elementExpr(node);
    if (!statements.containsKey(id)) {
      final expr = elementExpr(node);
      statements.putIfAbsent(id, () => '$id = $expr');
    }
    return id;
  }

  String elementExpr(ElementNode node) {
    final params = components[node.typeName];
    if (params == null) {
      final fallback = node.props.values.map(value);
      return '${node.typeName}(${fallback.join(', ')})';
    }
    final args = [for (final p in params) value(node.props[p.name])];
    while (args.isNotEmpty &&
        args.last == 'null' &&
        !params[args.length - 1].required) {
      args.removeLast();
    }
    return '${node.typeName}(${args.join(', ')})';
  }
}

String _ast(Ast node, Set<String> calls) {
  if (node is StrNode) return jsonEncode(node.value);
  if (node is NumNode) return Js.numberToString(node.value);
  if (node is BoolNode) return node.value ? 'true' : 'false';
  if (node is NullNode) return 'null';
  if (node is PlaceholderNode) return node.name;
  if (node is StateRefNode) return node.name;
  if (node is RuntimeRefNode) return node.name;
  if (node is RefNode) return node.name;
  if (node is ArrNode) {
    return '[${node.elements.map((e) => _ast(e, calls)).join(', ')}]';
  }
  if (node is ObjNode) {
    return '{${node.entries.map((e) => '${e.$1}: ${_ast(e.$2, calls)}').join(', ')}}';
  }
  if (node is BinOpNode) {
    return '${_binChild(node.left, node.op, calls)} ${node.op} '
        '${_binChild(node.right, node.op, calls)}';
  }
  if (node is UnaryOpNode) return '${node.op}${_ast(node.operand, calls)}';
  if (node is TernaryNode) {
    return '${_ast(node.condition, calls)} ? ${_ast(node.then, calls)} : '
        '${_ast(node.otherwise, calls)}';
  }
  if (node is MemberNode) return '${_ast(node.object, calls)}.${node.field}';
  if (node is IndexNode) {
    return '${_ast(node.object, calls)}[${_ast(node.index, calls)}]';
  }
  if (node is AssignNode) return '${node.target} = ${_ast(node.value, calls)}';
  if (node is CompNode) {
    final args = node.args.map((a) => _ast(a, calls)).join(', ');
    if (calls.contains(node.name) && node.name != 'Action') {
      return '@${node.name}($args)';
    }
    return '${node.name}($args)';
  }
  return 'null'; // coverage:ignore-line
}

/// Wraps a BinOp child in parentheses when its precedence is lower than the parent's.
String _binChild(Ast child, String parentOp, Set<String> calls) {
  final inner = _ast(child, calls);
  if (child is! BinOpNode) return inner;
  final parentPrec = _precedence[parentOp] ?? 0;
  if ((_precedence[child.op] ?? 0) < parentPrec) return '($inner)';
  return inner;
}
