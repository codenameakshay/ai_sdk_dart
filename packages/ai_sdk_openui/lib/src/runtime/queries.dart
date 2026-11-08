import 'dart:async';
import 'dart:convert';

import '../lang/js.dart';

/// Calls a tool by name: what `Query` and `Mutation` run.
typedef ToolCaller =
    Future<Object?> Function(String name, Map<String, Object?> args);

/// Thrown by a [ToolCaller] that has no tool of that name.
final class ToolNotFound implements Exception {
  const ToolNotFound(this.toolName, [this.available = const []]);
  final String toolName;
  final List<String> available;
  @override
  String toString() =>
      'No handler for tool "$toolName". Available: ${available.isEmpty ? '(none)' : available.join(', ')}';
}

final class QueryError {
  const QueryError({
    required this.statementId,
    required this.toolName,
    required this.message,
    required this.isMutation,
  });
  final String statementId;
  final String toolName;
  final String message;
  final bool isMutation;
}

/// A Query statement evaluated against the current state.
final class QueryNode {
  const QueryNode({
    required this.statementId,
    required this.toolName,
    required this.args,
    required this.defaults,
    this.refreshSeconds,
    this.deps,
  });
  final String statementId;
  final String toolName;
  final Object? args;
  final Object? defaults;
  final num? refreshSeconds;
  final Map<String, Object?>? deps;
}

final class _CacheEntry {
  Object? data = _none;
  bool inFlight = false;
  bool get settled => !identical(data, _none) && !inFlight;
}

const Object _none = Object();

final class _Query {
  _Query(this.node, this.cacheKey);
  QueryNode node;
  String cacheKey;
  String? prevCacheKey;
  bool loading = false;
  bool everFetched = false;
  bool needsRefetch = false;
  num refreshSeconds = 0;
  Timer? timer;
  QueryError? error;
}

final class _Mutation {
  _Mutation(this.toolName);
  String toolName;
  Map<String, Object?> result = {'status': 'idle'};
  QueryError? error;
}

String _stable(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final k in value.keys.map((k) => '$k').toList()..sort())
      k: _sorted(value[k]),
  },
  List() => [for (final v in value) _sorted(v)],
  num() when value.isNaN => '__NaN__',
  num() when value.isInfinite => value > 0 ? '__Inf__' : '__-Inf__',
  double() when value == value.truncateToDouble() => value.toInt(),
  num() || String() || bool() || null => value,
  _ => null,
};

/// lang-core `createQueryManager`: fetches Query tools, caches by
/// tool + args + state deps, serves defaults until data arrives, and runs
/// Mutations on demand.
final class QueryManager {
  QueryManager(this._call);
  final ToolCaller? _call;

  final Map<String, _Query> _queries = {};
  final Map<String, _Mutation> _mutations = {};
  final Map<String, _CacheEntry> _cache = {};
  final List<void Function()> _listeners = [];
  String _snapshotKey = '';
  bool _disposed = false;
  int _generation = 0;

  void Function() listen(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify() {
    for (final l in [..._listeners]) {
      l();
    }
  }

  /// Whether anything observable changed since the last rebuild.
  bool _rebuild() {
    final key = _stable({
      for (final MapEntry(:key, :value) in _queries.entries)
        key: [Js.stringify(result(key)), value.loading, value.error?.message],
      for (final MapEntry(:key, :value) in _mutations.entries)
        key: [value.result, value.error?.message],
    });
    if (key == _snapshotKey) return false;
    _snapshotKey = key;
    return true;
  }

  Object? result(String statementId) {
    final m = _mutations[statementId];
    if (m != null) return m.result;
    final q = _queries[statementId];
    if (q == null) return null;
    final entry = _cache[q.cacheKey];
    if (entry != null && !identical(entry.data, _none)) return entry.data;
    final prev = q.prevCacheKey == null ? null : _cache[q.prevCacheKey];
    if (prev != null && !identical(prev.data, _none)) return prev.data;
    return q.node.defaults;
  }

  bool get isLoading => _queries.values.any((q) => q.loading);

  List<QueryError> get errors => [
    for (final q in _queries.values)
      if (q.error != null) q.error!,
    for (final m in _mutations.values)
      if (m.error != null) m.error!,
  ];

  QueryError _error(
    String sid,
    String tool,
    Object err, {
    required bool mutation,
  }) {
    final kind = mutation ? 'Mutation' : 'Query';
    return QueryError(
      statementId: sid,
      toolName: tool,
      isMutation: mutation,
      message: err is ToolNotFound
          ? '$kind tool "$tool" not found'
          : '$kind "$tool" failed: $err',
    );
  }

  Future<void> _fetch(String cacheKey, String statementId) async {
    final call = _call;
    final q = _queries[statementId];
    if (call == null || q == null) return;
    final toolName = q.node.toolName;
    final args = q.node.args;
    final entry = _cache.putIfAbsent(cacheKey, _CacheEntry.new)
      ..inFlight = true;
    q.loading = true;
    _rebuild();
    _notify();
    try {
      final data = await call(
        toolName,
        args is Map ? args.cast<String, Object?>() : const {},
      );
      if (_disposed) return;
      final current = _queries[statementId];
      if (current == null || current.cacheKey != cacheKey) return;
      entry.data = data;
      current
        ..everFetched = true
        ..error = null;
      final prev = current.prevCacheKey;
      if (prev != null && prev != cacheKey) {
        current.prevCacheKey = null;
        _cleanup(prev);
      }
    } catch (err) {
      final current = _queries[statementId];
      if (current != null && current.cacheKey == cacheKey) {
        current.error = _error(statementId, toolName, err, mutation: false);
      }
    } finally {
      entry.inFlight = false;
      final current = _queries[statementId];
      if (!_disposed) {
        if (current != null && current.cacheKey == cacheKey) {
          current.loading = false;
          if (_rebuild()) _notify();
          if (current.needsRefetch) {
            current.needsRefetch = false;
            unawaited(_fetch(current.cacheKey, statementId));
          }
        }
      }
    }
  }

  void _cleanup(String cacheKey) {
    if (_queries.values.any(
      (q) => q.cacheKey == cacheKey || q.prevCacheKey == cacheKey,
    )) {
      return;
    }
    _cache.remove(cacheKey);
  }

  /// Reconciles the active queries with the program's Query statements.
  void evaluate(List<QueryNode> nodes) {
    if (_disposed) return;
    final active = {for (final n in nodes) n.statementId};
    for (final sid
        in _queries.keys.where((k) => !active.contains(k)).toList()) {
      final q = _queries.remove(sid)!;
      q.timer?.cancel();
      _cleanup(q.cacheKey);
      if (q.prevCacheKey != null) _cleanup(q.prevCacheKey!);
    }
    for (final node in nodes) {
      final cacheKey =
          '${node.toolName}::${_stable(node.args)}${node.deps != null ? '::${_stable(node.deps)}' : ''}';
      final existing = _queries[node.statementId];
      if (existing != null) {
        if (existing.cacheKey != cacheKey) {
          existing.prevCacheKey = existing.cacheKey;
        }
        existing
          ..node = node
          ..cacheKey = cacheKey;
      } else {
        _queries[node.statementId] = _Query(node, cacheKey);
      }
      final q = _queries[node.statementId]!;
      final entry = _cache[cacheKey];
      if (_call != null &&
          !(entry?.settled ?? false) &&
          !(entry?.inFlight ?? false)) {
        unawaited(_fetch(cacheKey, node.statementId));
      }
      final interval = node.refreshSeconds ?? 0;
      if (interval != q.refreshSeconds) {
        q.timer?.cancel();
        q.timer = null;
        if (interval > 0) {
          q.timer = Timer.periodic(
            Duration(milliseconds: (interval * 1000).round()),
            (_) {
              if (_disposed || _call == null) return;
              if (!(_cache[q.cacheKey]?.inFlight ?? false)) {
                unawaited(_fetch(q.cacheKey, node.statementId));
              }
            },
          );
        }
        q.refreshSeconds = interval;
      }
    }
    if (_rebuild()) _notify();
  }

  /// `@Run(query)`: refetch (all queries when [statementIds] is empty).
  void invalidate([List<String> statementIds = const []]) {
    if (_disposed || _call == null) return;
    final targets = statementIds.isEmpty
        ? _queries.keys.toList()
        : statementIds.where(_queries.containsKey).toList();
    for (final sid in targets) {
      final q = _queries[sid]!;
      if (_cache[q.cacheKey]?.inFlight ?? false) {
        q.needsRefetch = true;
      } else {
        unawaited(_fetch(q.cacheKey, sid));
      }
    }
  }

  void registerMutations(Map<String, String> toolsById) {
    _mutations.removeWhere((sid, _) => !toolsById.containsKey(sid));
    for (final MapEntry(key: sid, value: tool) in toolsById.entries) {
      final existing = _mutations[sid];
      if (existing == null) {
        _mutations[sid] = _Mutation(tool);
      } else if (existing.toolName != tool) {
        existing
          ..toolName = tool
          ..result = {'status': 'idle', 'data': null, 'error': null}
          ..error = null;
      }
    }
    if (_rebuild()) _notify();
  }

  /// `@Run(mutation)`: returns whether it succeeded, so a plan can halt.
  Future<bool> fireMutation(
    String statementId,
    Map<String, Object?> args,
  ) async {
    final call = _call;
    final m = _mutations[statementId];
    if (_disposed ||
        call == null ||
        m == null ||
        m.result['status'] == 'loading') {
      return false;
    }
    final gen = _generation;
    m.result = {'status': 'loading'};
    _rebuild();
    _notify();
    var ok = false;
    try {
      final data = await call(m.toolName, args);
      if (_disposed || gen != _generation) return false;
      m
        ..result = {'status': 'success', 'data': data}
        ..error = null;
      ok = true;
    } catch (err) {
      if (_disposed || gen != _generation) return false;
      m
        ..result = {'status': 'error', 'error': '$err'}
        ..error = _error(statementId, m.toolName, err, mutation: true);
    }
    _rebuild();
    _notify();
    return ok;
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _listeners.clear();
    for (final q in _queries.values) {
      q.timer?.cancel();
      q
        ..timer = null
        ..refreshSeconds = 0
        ..loading = false
        ..needsRefetch = false;
    }
    _mutations.clear();
  }
}
