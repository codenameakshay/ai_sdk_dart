import 'dart:convert';

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
  return List<T>.unmodifiable(List<T>.of(values));
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
