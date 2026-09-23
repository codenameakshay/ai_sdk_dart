import 'dart:convert';
import 'dart:collection';

enum PartialJsonParsePhase {
  streamTextPartial,
  streamTextArrayElements,
  streamObjectSnapshot,
}

enum PartialJsonParseTrigger { candidateClosed, arrayElementBoundary }

class PartialJsonDebugCounters {
  int parseAttempts = 0;
  int decodeAttempts = 0;
  int snapshotCount = 0;
  int snapshotElementsCopied = 0;
  int snapshotStructuralNodes = 0;
  int snapshotStructuralReferences = 0;

  final Map<PartialJsonParsePhase, int> _parseAttemptsByPhase = {};
  final Map<PartialJsonParseTrigger, int> _parseAttemptsByTrigger = {};

  void recordParseAttempt({
    required PartialJsonParsePhase phase,
    required PartialJsonParseTrigger trigger,
  }) {
    parseAttempts++;
    _parseAttemptsByPhase.update(
      phase,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    _parseAttemptsByTrigger.update(
      trigger,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void recordDecodeAttempt() {
    decodeAttempts++;
  }

  void recordSnapshotCopy(int elementCount) {
    snapshotCount++;
    snapshotElementsCopied += elementCount;
  }

  void recordStructuralNode() => snapshotStructuralNodes++;

  void recordStructuralReferences(int count) =>
      snapshotStructuralReferences += count;

  void recordStructuralSnapshot(int references) {
    snapshotCount++;
    recordStructuralReferences(references);
  }

  int parseAttemptsFor(PartialJsonParsePhase phase) {
    return _parseAttemptsByPhase[phase] ?? 0;
  }

  int parseAttemptsForTrigger(PartialJsonParseTrigger trigger) {
    return _parseAttemptsByTrigger[trigger] ?? 0;
  }
}

PartialJsonDebugCounters? partialJsonDebugCounters;

class PartialJsonCadence {
  const PartialJsonCadence({
    this.shouldAttemptValue = false,
    this.shouldAttemptArrayElements = false,
  });

  final bool shouldAttemptValue;
  final bool shouldAttemptArrayElements;
}

class PartialJsonArrayUpdate {
  const PartialJsonArrayUpdate({
    required this.newElements,
    required this.sawBoundary,
    required this.isClosed,
  });

  final List<Object?> newElements;
  final bool sawBoundary;
  final bool isClosed;
}

class PartialJsonTracker {
  bool _inString = false;
  bool _escaped = false;
  bool _trackingCandidate = false;
  String? _rootDelimiter;
  var _depth = 0;

  PartialJsonCadence append(String delta) {
    var shouldAttemptValue = false;
    var shouldAttemptArrayElements = false;

    for (final codeUnit in delta.codeUnits) {
      final char = String.fromCharCode(codeUnit);

      if (_escaped) {
        _escaped = false;
        continue;
      }

      if (char == '\\' && _inString) {
        _escaped = true;
        continue;
      }

      if (char == '"') {
        _inString = !_inString;
        continue;
      }

      if (_inString) {
        continue;
      }

      if (!_trackingCandidate) {
        if (char == '{' || char == '[') {
          _trackingCandidate = true;
          _rootDelimiter = char;
          _depth = 1;
        }
        continue;
      }

      if (char == '{' || char == '[') {
        _depth++;
        continue;
      }

      if (char == '}' || char == ']') {
        if (_depth > 0) {
          _depth--;
        }
        if (_rootDelimiter == '[' && char == ']' && _depth == 0) {
          shouldAttemptArrayElements = true;
        }
        if (_depth == 0) {
          shouldAttemptValue = true;
          _trackingCandidate = false;
          _rootDelimiter = null;
        }
        continue;
      }

      if (_rootDelimiter == '[' && char == ',' && _depth == 1) {
        shouldAttemptArrayElements = true;
      }
    }

    return PartialJsonCadence(
      shouldAttemptValue: shouldAttemptValue,
      shouldAttemptArrayElements: shouldAttemptArrayElements,
    );
  }
}

class PartialJsonArrayTracker {
  StringBuffer _currentToken = StringBuffer();

  bool _seenRootArray = false;
  bool _closed = false;
  bool _inString = false;
  bool _escaped = false;
  var _nestedDepth = 0;

  PartialJsonArrayUpdate append(
    String delta, {
    required PartialJsonParsePhase phase,
    required PartialJsonParseTrigger trigger,
  }) {
    final newElements = <Object?>[];
    var sawBoundary = false;

    for (final codeUnit in delta.codeUnits) {
      final char = String.fromCharCode(codeUnit);

      if (_closed) {
        continue;
      }

      if (!_seenRootArray) {
        if (char == '[') {
          _seenRootArray = true;
        }
        continue;
      }

      if (_escaped) {
        _currentToken.write(char);
        _escaped = false;
        continue;
      }

      if (char == '\\' && _inString) {
        _currentToken.write(char);
        _escaped = true;
        continue;
      }

      if (char == '"') {
        _currentToken.write(char);
        _inString = !_inString;
        continue;
      }

      if (_inString) {
        _currentToken.write(char);
        continue;
      }

      if (char == ',' && _nestedDepth == 0) {
        final decoded = _flushCurrentToken(phase: phase, trigger: trigger);
        if (decoded != null) {
          newElements.add(decoded);
        }
        sawBoundary = true;
        continue;
      }

      if (char == ']' && _nestedDepth == 0) {
        final decoded = _flushCurrentToken(phase: phase, trigger: trigger);
        if (decoded != null) {
          newElements.add(decoded);
        }
        sawBoundary = true;
        _closed = true;
        continue;
      }

      if (char == '{' || char == '[') {
        _nestedDepth++;
      } else if ((char == '}' || char == ']') && _nestedDepth > 0) {
        _nestedDepth--;
      }

      _currentToken.write(char);
    }

    return PartialJsonArrayUpdate(
      newElements: newElements.isEmpty
          ? const <Object?>[]
          : List<Object?>.unmodifiable(newElements),
      sawBoundary: sawBoundary,
      isClosed: _closed,
    );
  }

  Object? _flushCurrentToken({
    required PartialJsonParsePhase phase,
    required PartialJsonParseTrigger trigger,
  }) {
    final token = _currentToken.toString().trim();
    _currentToken = StringBuffer();
    if (token.isEmpty) {
      return null;
    }

    partialJsonDebugCounters?.recordParseAttempt(
      phase: phase,
      trigger: trigger,
    );

    final decoded = _tryJsonDecode(token);
    return decoded;
  }
}

Object? tryParsePartialJsonValue(
  String text, {
  required PartialJsonParsePhase phase,
  required PartialJsonParseTrigger trigger,
  String? fallbackCandidate,
}) {
  partialJsonDebugCounters?.recordParseAttempt(phase: phase, trigger: trigger);
  return _tryParsePartialJsonValue(text, fallbackCandidate: fallbackCandidate);
}

String? extractJsonCandidate(String text) {
  final startObject = text.indexOf('{');
  final startArray = text.indexOf('[');
  final starts = [
    if (startObject >= 0) startObject,
    if (startArray >= 0) startArray,
  ];
  if (starts.isEmpty) {
    return null;
  }
  final start = starts.reduce((a, b) => a < b ? a : b);
  final open = text[start];
  final close = open == '{' ? '}' : ']';

  var inString = false;
  var escaped = false;
  var depth = 0;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == '\\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char == open) {
      depth++;
      continue;
    }
    if (char == close) {
      depth--;
      if (depth == 0) {
        return text.substring(start, i + 1);
      }
    }
  }
  return null;
}

String? extractLastJsonObject(String text) {
  var depth = 0;
  var inString = false;
  var escaped = false;
  int? topLevelStart;
  String? lastComplete;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == '\\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }

    if (char == '{') {
      if (depth == 0) {
        topLevelStart = i;
      }
      depth++;
      continue;
    }

    if (char == '}') {
      depth--;
      if (depth == 0 && topLevelStart != null) {
        lastComplete = text.substring(topLevelStart, i + 1);
        topLevelStart = null;
      }
    }
  }

  return lastComplete;
}

String partialJsonFingerprint(Object? value) {
  try {
    return jsonEncode(value);
  } catch (_) {
    return value.toString();
  }
}

List<T> createTrackedImmutableSnapshot<T>(List<T> values) {
  partialJsonDebugCounters?.recordSnapshotCopy(values.length);
  return List<T>.unmodifiable(values);
}

/// An append-only immutable array snapshot builder.
///
/// Each append creates a persistent balanced forest. Existing snapshots retain
/// their exact contents and share tree nodes with later snapshots; no mutable
/// list is exposed. Indexing is logarithmic in the number of appended values.
class ImmutableArraySnapshotBuilder<T> {
  final List<_PersistentArrayNode<T>?> _forest = [];
  var _length = 0;

  int get length => _length;

  void add(T value) {
    var node = _PersistentArrayNode<T>.leaf(value);
    partialJsonDebugCounters?.recordStructuralNode();
    var rank = 0;
    while (rank < _forest.length && _forest[rank] != null) {
      node = _PersistentArrayNode<T>.branch(_forest[rank]!, node);
      partialJsonDebugCounters?.recordStructuralNode();
      _forest[rank] = null;
      rank++;
    }
    if (rank == _forest.length) {
      _forest.add(node);
    } else {
      _forest[rank] = node;
    }
    _length++;
  }

  void addAll(Iterable<T> values) {
    for (final value in values) {
      add(value);
    }
  }

  List<T> snapshot() {
    partialJsonDebugCounters?.recordStructuralSnapshot(
      _forest.whereType<_PersistentArrayNode<T>>().length,
    );
    return _PersistentArraySnapshot<T>._(
      _forest.whereType<_PersistentArrayNode<T>>().toList(growable: false),
      _length,
    );
  }
}

class _PersistentArrayNode<T> {
  _PersistentArrayNode.leaf(this.value) : left = null, right = null, size = 1;

  _PersistentArrayNode.branch(this.left, this.right)
    : value = null,
      size = left!.size + right!.size;

  final T? value;
  final _PersistentArrayNode<T>? left;
  final _PersistentArrayNode<T>? right;
  final int size;
}

class _PersistentArraySnapshot<T> extends ListBase<T> {
  _PersistentArraySnapshot._(this._forest, this._length);

  final List<_PersistentArrayNode<T>> _forest;
  final int _length;

  @override
  int get length => _length;

  @override
  set length(int value) => throw UnsupportedError('Immutable snapshot');

  @override
  T operator [](int index) {
    if (index < 0 || index >= _length) throw RangeError.index(index, this);
    var offset = index;
    for (final root in _forest.reversed) {
      if (offset < root.size) return _at(root, offset);
      offset -= root.size;
    }
    throw StateError('Snapshot index out of bounds');
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Immutable snapshot');

  @override
  Iterator<T> get iterator => _iterable().iterator;

  Iterable<T> _iterable() sync* {
    for (final root in _forest.reversed) {
      yield* _values(root);
    }
  }

  static Iterable<T> _values<T>(_PersistentArrayNode<T> node) sync* {
    if (node.left == null) {
      yield node.value as T;
      return;
    }
    yield* _values(node.left!);
    yield* _values(node.right!);
  }

  static T _at<T>(_PersistentArrayNode<T> node, int index) {
    if (node.left == null) return node.value as T;
    if (index < node.left!.size) return _at(node.left!, index);
    return _at(node.right!, index - node.left!.size);
  }
}

Object? _tryParsePartialJsonValue(String text, {String? fallbackCandidate}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final fullJson = _tryJsonDecode(trimmed);
  if (fullJson != null) {
    return fullJson;
  }

  final fenceMatch = RegExp(
    r'```(?:json)?\s*([\s\S]+?)\s*```',
  ).firstMatch(text);
  if (fenceMatch != null) {
    final fenced = fenceMatch.group(1);
    if (fenced != null) {
      final fencedJson = _tryJsonDecode(fenced);
      if (fencedJson != null) {
        return fencedJson;
      }
    }
  }

  final candidate = fallbackCandidate ?? extractJsonCandidate(text);
  if (candidate == null) {
    return null;
  }
  return _tryJsonDecode(candidate);
}

Object? _tryJsonDecode(String text) {
  partialJsonDebugCounters?.recordDecodeAttempt();
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}
