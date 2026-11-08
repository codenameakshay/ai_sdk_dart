import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../lang/js.dart';
import 'errors.dart';
import 'mcp.dart';

/// Calls a tool by name: what `Query` and `Mutation` run.
typedef ToolCaller =
    Future<Object?> Function(String name, Map<String, Object?> args);

/// Thrown by a [ToolCaller] that has no tool of that name (lang-core `ToolNotFoundError`).
final class ToolNotFoundError implements Exception {
  const ToolNotFoundError(this.toolName, [this.availableTools = const []]);
  final String toolName;
  final List<String> availableTools;
  String get message =>
      '[openui] No handler for tool "$toolName". Available: ${availableTools.isEmpty ? '(none)' : availableTools.join(', ')}';
  @override
  String toString() => message;
}

/// A Query statement evaluated against the current state.
final class QueryNode {
  const QueryNode({
    required this.statementId,
    required this.toolName,
    required this.args,
    required this.defaults,
    this.refreshInterval,
    this.deps,
    this.complete = true,
  });
  final String statementId;
  final String toolName;
  final Object? args;
  final Object? defaults;

  /// The evaluated refresh value, in seconds, as the program gave it.
  final Object? refreshInterval;
  final Map<String, Object?>? deps;

  /// False while the statement still streams; such a node is not fetched.
  final bool complete;
}

/// lang-core `QuerySnapshot`: every statement's data plus loading, refetching and error lists.
final class QuerySnapshot {
  const QuerySnapshot({
    this.data = const {},
    this.loading = const [],
    this.refetching = const [],
    this.errors = const [],
  });

  /// Query results and mutation results by statement id.
  final Map<String, Object?> data;

  /// Statement ids that are loading.
  final List<String> loading;

  /// Loading statement ids that have fetched before.
  final List<String> refetching;

  /// Queries first, then mutations.
  final List<OpenUiError> errors;
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
  Object? refreshInterval = 0;
  Timer? timer;
  OpenUiError? error;
}

final class _Mutation {
  _Mutation(this.toolName);
  String toolName;
  Map<String, Object?> result = {'status': 'idle'};
  OpenUiError? error;
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
  double()
      when value >= -9223372036854775808.0 &&
          value < 9223372036854775808.0 &&
          value == value.truncateToDouble() =>
    value.toInt(),
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
  QuerySnapshot _snapshot = const QuerySnapshot();
  String _snapshotKey = '';
  bool _disposed = false;
  int _generation = 0;

  /// Calls [listener] after every snapshot change; returns a cancel.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _notify() {
    for (final l in [..._listeners]) {
      l();
    }
  }

  /// Builds the next snapshot; returns whether anything observable changed.
  bool _rebuild() {
    final data = <String, Object?>{};
    final loading = <String>[];
    final refetching = <String>[];
    final errors = <OpenUiError>[];
    for (final MapEntry(:key, :value) in _queries.entries) {
      data[key] = getResult(key);
      if (value.loading) {
        loading.add(key);
        if (value.everFetched) refetching.add(key);
      }
      if (value.error != null) errors.add(value.error!);
    }
    for (final MapEntry(:key, :value) in _mutations.entries) {
      data[key] = value.result;
      if (value.error != null) errors.add(value.error!);
    }
    final key = _stable({
      'data': data,
      'loading': loading,
      'refetching': refetching,
      'errors': [for (final e in errors) e.toJson()],
    });
    if (key == _snapshotKey) return false;
    _snapshotKey = key;
    _snapshot = QuerySnapshot(
      data: data,
      loading: loading,
      refetching: refetching,
      errors: errors,
    );
    return true;
  }

  /// The data a Query statement shows: its cached result, else the previous key's, else its defaults.
  Object? getResult(String statementId) {
    final q = _queries[statementId];
    if (q == null) return null;
    final entry = _cache[q.cacheKey];
    if (entry != null && !identical(entry.data, _none)) return entry.data;
    final prev = q.prevCacheKey == null ? null : _cache[q.prevCacheKey];
    if (prev != null && !identical(prev.data, _none)) return prev.data;
    return q.node.defaults;
  }

  /// The last result of a Mutation, or null when [statementId] is not one.
  Map<String, Object?>? getMutationResult(String statementId) =>
      _mutations[statementId]?.result;

  /// Whether the Query [statementId] is loading.
  bool isLoading(String statementId) => _queries[statementId]?.loading ?? false;

  /// Whether any Query is loading.
  bool isAnyLoading() => _queries.values.any((q) => q.loading);

  /// The latest snapshot of every statement.
  QuerySnapshot getSnapshot() => _snapshot;

  OpenUiError _error(
    String sid,
    String tool,
    Object err, {
    required bool mutation,
  }) {
    final kind = mutation ? 'Mutation' : 'Query';
    final source = mutation
        ? OpenUiErrorSource.mutation
        : OpenUiErrorSource.query;
    if (err is ToolNotFoundError) {
      return OpenUiError(
        source: source,
        code: OpenUiErrorCode.toolNotFound,
        message: '$kind tool "$tool" not found',
        statementId: sid,
        component: kind,
        toolName: tool,
        hint: err.availableTools.isEmpty
            ? null
            : 'Available tools: ${err.availableTools.join(', ')}',
      );
    }
    if (err is McpToolError) {
      return OpenUiError(
        source: source,
        code: OpenUiErrorCode.mcpError,
        message: '$kind "$tool" returned an error: ${err.toolErrorText}',
        statementId: sid,
        component: kind,
        toolName: tool,
      );
    }
    return OpenUiError(
      source: source,
      code: OpenUiErrorCode.toolError,
      message: '$kind "$tool" failed: ${errorMessage(err)}',
      statementId: sid,
      component: kind,
      toolName: tool,
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
      final data = Js.normalize(
        await call(
          toolName,
          args is Map
              ? Js.normalize(args, json: true)! as Map<String, Object?>
              : const {},
        ),
      );
      if (_disposed) return;
      if (!identical(_cache[cacheKey], entry) ||
          !_queries.values.any((q) => q.cacheKey == cacheKey)) {
        return;
      }
      entry.data = data;
      // Every statement on this key gets the data, not just the one that started the fetch.
      for (final current in _queries.values.where(
        (q) => q.cacheKey == cacheKey,
      )) {
        current
          ..everFetched = true
          ..error = null;
        final prev = current.prevCacheKey;
        if (prev != null && prev != cacheKey) {
          current.prevCacheKey = null;
          _cleanup(prev);
        }
      }
    } catch (err) {
      if (!_disposed && identical(_cache[cacheKey], entry)) {
        for (final current in _queries.values.where(
          (q) => q.cacheKey == cacheKey,
        )) {
          current.error = _error(
            current.node.statementId,
            toolName,
            err,
            mutation: false,
          );
        }
      }
    } finally {
      entry.inFlight = false;
      if (!_disposed && identical(_cache[cacheKey], entry)) {
        String? refetch;
        for (final current in _queries.values.where(
          (q) => q.cacheKey == cacheKey,
        )) {
          current.loading = false;
          if (current.needsRefetch) {
            current.needsRefetch = false;
            refetch ??= current.node.statementId;
          }
        }
        if (_rebuild()) _notify();
        if (refetch != null) unawaited(_fetch(cacheKey, refetch));
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
  void evaluateQueries(List<QueryNode> nodes) {
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
      if (!node.complete) continue;
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
      q.loading = entry?.inFlight ?? false;
      if (_call != null &&
          !(entry?.settled ?? false) &&
          !(entry?.inFlight ?? false)) {
        unawaited(_fetch(cacheKey, node.statementId));
      }
      final interval = node.refreshInterval ?? 0;
      if (!Js.strictEquals(interval, q.refreshInterval)) {
        q.timer?.cancel();
        q.timer = null;
        final seconds = Js.number(interval);
        if (seconds > 0 && (seconds * 1000).isFinite) {
          q.timer = Timer.periodic(
            Duration(milliseconds: math.max(1, (seconds * 1000).round())),
            (_) {
              if (_disposed || _call == null) return;
              if (!(_cache[q.cacheKey]?.inFlight ?? false)) {
                unawaited(_fetch(q.cacheKey, node.statementId));
              }
            },
          );
        }
        q.refreshInterval = interval;
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
        _mutations[sid] = _Mutation(tool)
          ..result = {'status': 'idle', 'data': null, 'error': null};
      }
    }
    if (_rebuild()) _notify();
  }

  /// `@Run(mutation)`: returns whether it succeeded, so a plan can halt.
  /// After a success, [refreshQueryIds] are refetched.
  Future<bool> fireMutation(
    String statementId,
    Map<String, Object?> args, [
    List<String>? refreshQueryIds,
  ]) async {
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
      final data = Js.normalize(
        await call(
          m.toolName,
          Js.normalize(args, json: true)! as Map<String, Object?>,
        ),
      );
      if (_disposed ||
          gen != _generation ||
          !identical(_mutations[statementId], m)) {
        return false;
      }
      m
        ..result = {'status': 'success', 'data': data}
        ..error = null;
      ok = true;
    } catch (err) {
      if (_disposed ||
          gen != _generation ||
          !identical(_mutations[statementId], m)) {
        return false;
      }
      m
        ..result = {'status': 'error', 'error': errorMessage(err)}
        ..error = _error(statementId, m.toolName, err, mutation: true);
    }
    _rebuild();
    _notify();
    if (ok && refreshQueryIds != null && refreshQueryIds.isNotEmpty) {
      invalidate(refreshQueryIds);
    }
    return ok;
  }

  /// Makes a disposed manager fetch again.
  void activate() => _disposed = false;

  void dispose() {
    _disposed = true;
    _generation++;
    _listeners.clear();
    for (final q in _queries.values) {
      q.timer?.cancel();
      q
        ..timer = null
        ..refreshInterval = 0
        ..loading = false
        ..needsRefetch = false;
    }
    _mutations.clear();
  }
}
