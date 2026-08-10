import 'package:ai_sdk_dart/src/core/partial_json.dart';

void main() {
  const sizes = [('1KiB', 1024), ('64KiB', 64 * 1024), ('1MiB', 1024 * 1024)];

  for (final (label, targetBytes) in sizes) {
    for (final scenario in [
      ('object', _buildObjectPayload(targetBytes)),
      ('array', _buildArrayPayload(targetBytes)),
    ]) {
      final (kind, payload) = scenario;
      final result = _runBenchmark(payload);
      print(
        '$kind $label bytes=${result.bytes} '
        'parseAttempts=${result.parseAttempts} '
        'decodeAttempts=${result.decodeAttempts} '
        'elements=${result.elements} '
        'elapsedMs=${result.elapsedMicroseconds / 1000}',
      );
    }
  }
}

_BenchmarkResult _runBenchmark(String payload) {
  final previousCounters = partialJsonDebugCounters;
  final counters = PartialJsonDebugCounters();
  partialJsonDebugCounters = counters;

  final tracker = PartialJsonTracker();
  final buffer = StringBuffer();
  var elements = 0;
  final stopwatch = Stopwatch()..start();

  try {
    for (final char in payload.split('')) {
      buffer.write(char);
      final cadence = tracker.append(char);
      if (cadence.shouldAttemptArrayElements) {
        elements = parsePartialArrayElements(
          buffer.toString(),
          phase: PartialJsonParsePhase.streamTextArrayElements,
          trigger: PartialJsonParseTrigger.arrayElementBoundary,
        ).length;
      }
      if (cadence.shouldAttemptValue) {
        tryParsePartialJsonValue(
          buffer.toString(),
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
    bytes: payload.length,
    parseAttempts: counters.parseAttempts,
    decodeAttempts: counters.decodeAttempts,
    elements: elements,
    elapsedMicroseconds: stopwatch.elapsedMicroseconds,
  );
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
    required this.bytes,
    required this.parseAttempts,
    required this.decodeAttempts,
    required this.elements,
    required this.elapsedMicroseconds,
  });

  final int bytes;
  final int parseAttempts;
  final int decodeAttempts;
  final int elements;
  final int elapsedMicroseconds;
}
