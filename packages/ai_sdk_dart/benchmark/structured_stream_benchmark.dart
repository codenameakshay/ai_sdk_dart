import 'package:ai_sdk_dart/src/core/partial_json.dart';

void main() {
  const sizes = [('1KiB', 1024), ('64KiB', 64 * 1024), ('1MiB', 1024 * 1024)];

  for (final (label, targetBytes) in sizes) {
    final objectResult = _runObjectBenchmark(_buildObjectPayload(targetBytes));
    _assertLinear(objectResult);
    print(objectResult.describe(label));

    final arrayResult = _runArrayBenchmark(_buildArrayPayload(targetBytes));
    _assertLinear(arrayResult);
    print(arrayResult.describe(label));
  }
}

_BenchmarkResult _runObjectBenchmark(String payload) {
  final previousCounters = partialJsonDebugCounters;
  final counters = PartialJsonDebugCounters();
  partialJsonDebugCounters = counters;

  final tracker = PartialJsonTracker();
  final stopwatch = Stopwatch()..start();

  try {
    for (final char in payload.split('')) {
      final cadence = tracker.append(char);
      if (cadence.shouldAttemptValue) {
        tryParsePartialJsonValue(
          payload,
          phase: PartialJsonParsePhase.streamTextPartial,
          trigger: PartialJsonParseTrigger.candidateClosed,
        );
      }
    }
  } finally {
    stopwatch.stop();
    partialJsonDebugCounters = previousCounters;
  }

  return _BenchmarkResult(
    kind: 'object',
    bytes: payload.length,
    parseAttempts: counters.parseAttempts,
    decodeAttempts: counters.decodeAttempts,
    elements: 0,
    elapsedMicroseconds: stopwatch.elapsedMicroseconds,
  );
}

_BenchmarkResult _runArrayBenchmark(String payload) {
  final previousCounters = partialJsonDebugCounters;
  final counters = PartialJsonDebugCounters();
  partialJsonDebugCounters = counters;

  final tracker = PartialJsonArrayTracker();
  var elements = 0;
  final stopwatch = Stopwatch()..start();

  try {
    for (final char in payload.split('')) {
      final update = tracker.append(
        char,
        phase: PartialJsonParsePhase.streamTextArrayElements,
        trigger: PartialJsonParseTrigger.arrayElementBoundary,
      );
      if (update.sawBoundary) {
        elements = update.elements.length;
      }
    }
  } finally {
    stopwatch.stop();
    partialJsonDebugCounters = previousCounters;
  }

  return _BenchmarkResult(
    kind: 'array',
    bytes: payload.length,
    parseAttempts: counters.parseAttempts,
    decodeAttempts: counters.decodeAttempts,
    elements: elements,
    elapsedMicroseconds: stopwatch.elapsedMicroseconds,
  );
}

void _assertLinear(_BenchmarkResult result) {
  final maxAttempts = switch (result.kind) {
    'object' => 1,
    'array' => result.elements + 1,
    _ => throw StateError('Unknown benchmark kind: ${result.kind}'),
  };

  if (result.parseAttempts > maxAttempts) {
    throw StateError(
      '${result.kind} parse attempts grew nonlinearly: '
      '${result.parseAttempts} > $maxAttempts',
    );
  }
  if (result.decodeAttempts > maxAttempts) {
    throw StateError(
      '${result.kind} decode attempts grew nonlinearly: '
      '${result.decodeAttempts} > $maxAttempts',
    );
  }
}

String _buildObjectPayload(int targetBytes) {
  const prefix = '{"items":[';
  const suffix = '],"done":true}';
  final buffer = StringBuffer(prefix);
  var index = 0;
  while (buffer.length + suffix.length < targetBytes) {
    if (index > 0) {
      buffer.write(',');
    }
    buffer.write(
      '{"id":$index,"name":"Item $index","nested":{"flag":true,"text":"quote \\"value\\" slash \\\\","emoji":"\\uD83D\\uDE00","values":[1,2,3,4]}}',
    );
    index++;
  }
  buffer.write(suffix);
  return buffer.toString();
}

String _buildArrayPayload(int targetBytes) {
  const blob =
      'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
      'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
      'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
      'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
      'yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy'
      'yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy';
  final buffer = StringBuffer('[');
  var index = 0;
  while (buffer.length + 1 < targetBytes) {
    if (index > 0) {
      buffer.write(',');
    }
    buffer.write(
      '{"id":$index,"text":"quote \\"value\\" slash \\\\","emoji":"\\uD83D\\uDE00","blob":"$blob"}',
    );
    index++;
  }
  buffer.write(']');
  return buffer.toString();
}

class _BenchmarkResult {
  const _BenchmarkResult({
    required this.kind,
    required this.bytes,
    required this.parseAttempts,
    required this.decodeAttempts,
    required this.elements,
    required this.elapsedMicroseconds,
  });

  final String kind;
  final int bytes;
  final int parseAttempts;
  final int decodeAttempts;
  final int elements;
  final int elapsedMicroseconds;

  String describe(String label) {
    return '$kind $label bytes=$bytes '
        'parseAttempts=$parseAttempts '
        'decodeAttempts=$decodeAttempts '
        'elements=$elements '
        'elapsedMs=${elapsedMicroseconds / 1000}';
  }
}
