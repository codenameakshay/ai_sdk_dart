import 'ast.dart';
import 'lexer.dart';
import 'statements.dart';

/// lang-core `mergeStatements`: patch statements replace existing ones by name, `name = null` deletes
/// one, and statements no longer reachable from [rootId] are dropped (`$state` is always kept).
String mergeStatements(
  String existing,
  String patch, [
  String rootId = 'root',
]) {
  final existingStmts = _parseStatements(existing);
  final patchStmts = _parseStatements(stripFences(patch));
  if (existingStmts.isEmpty) {
    return patchStmts.map((s) => s.raw).join('\n');
  }
  if (patchStmts.isEmpty) return existing;

  final merged = <String, String>{};
  final asts = <String, Ast>{};
  final order = <String>[];
  for (final s in existingStmts) {
    merged[s.id] = s.raw;
    asts[s.id] = s.ast;
    order.add(s.id);
  }
  for (final s in patchStmts) {
    if (s.ast is NullNode) {
      merged.remove(s.id);
      asts.remove(s.id);
      final idx = order.indexOf(s.id);
      if (idx != -1) order.removeAt(idx);
      continue;
    }
    if (!merged.containsKey(s.id)) order.add(s.id);
    merged[s.id] = s.raw;
    asts[s.id] = s.ast;
  }
  _gcUnreachable(order, merged, asts, rootId);
  return [
    for (final id in order)
      if (merged.containsKey(id)) merged[id]!,
  ].join('\n');
}

List<({String id, Ast ast, String raw})> _parseStatements(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return const [];
  final out = <({String id, Ast ast, String raw})>[];
  for (final raw in _splitStatementSource(trimmed)) {
    final stmts = split(tokenize(raw));
    if (stmts.isEmpty) continue;
    final first = stmts.first;
    out.add((id: first.id, ast: parseExpression(first.tokens), raw: raw));
  }
  return out;
}

List<String> _splitStatementSource(String input) {
  final stmts = <String>[];
  var depth = 0;
  String? inStr;
  var esc = false;
  var start = 0;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
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
    } else if (c == '\n' && depth <= 0) {
      final stmt = input.substring(start, i).trim();
      if (stmt.isNotEmpty) stmts.add(stmt);
      start = i + 1;
    }
  }
  final tail = input.substring(start).trim();
  if (tail.isNotEmpty) stmts.add(tail);
  return stmts;
}

Set<String> _refs(Ast ast) {
  final out = <String>{};
  walkAst(ast, (node) {
    if (node is RefNode) out.add(node.name);
    if (node is RuntimeRefNode) out.add(node.name);
  });
  return out;
}

void _gcUnreachable(
  List<String> order,
  Map<String, String> merged,
  Map<String, Ast> asts,
  String rootId,
) {
  if (!asts.containsKey(rootId)) return;
  final reachable = {rootId};
  final queue = [rootId];
  while (queue.isNotEmpty) {
    final ast = asts[queue.removeLast()]!;
    for (final ref in _refs(ast)) {
      if (!reachable.contains(ref) && asts.containsKey(ref)) {
        reachable.add(ref);
        queue.add(ref);
      }
    }
  }
  for (final id in order) {
    if (id.startsWith('\$')) reachable.add(id);
  }
  for (var i = order.length - 1; i >= 0; i--) {
    if (!reachable.contains(order[i])) {
      merged.remove(order[i]);
      order.removeAt(i);
    }
  }
}
