import 'dart:convert';

import 'package:ai_sdk_dart/src/core/partial_json.dart';

void main(List<String> arguments) {
  const sizes = [('1KiB', 1024), ('64KiB', 64 * 1024), ('1MiB', 1024 * 1024)];
  final results = <Map<String, Object>>[];

  const warmups = 3;
  const samples = 30;
  for (final (label, targetBytes) in sizes) {
    final objectPayload = _buildObjectPayload(targetBytes);
    final arrayPayload = _buildArrayPayload(targetBytes);
    final cases = <_BenchmarkResult Function()>[
      () => _runObjectBenchmark(objectPayload),
      () => _runArrayBenchmark(arrayPayload, structural: false),
      () => _runArrayBenchmark(arrayPayload, structural: true),
    ];
    final observations = List.generate(
      cases.length,
      (_) => <_BenchmarkResult>[],
    );
    for (var iteration = 0; iteration < warmups + samples; iteration++) {
      for (var offset = 0; offset < cases.length; offset++) {
        final index = (iteration + offset) % cases.length;
        final result = cases[index]();
        _assertParseBudget(result);
        if (iteration >= warmups) observations[index].add(result);
      }
    }
    for (final runs in observations) {
      final sorted = [
        ...runs,
      ]..sort((a, b) => a.elapsedMicroseconds.compareTo(b.elapsedMicroseconds));
      int percentile(double fraction) =>
          sorted[(samples * fraction).ceil() - 1].elapsedMicroseconds;
      results.add({
        ...sorted[(samples * .5).ceil() - 1].toJson(label),
        'fixtureVersion': 1,
        'warmupRuns': warmups,
        'sampleCount': samples,
        'percentileMethod': 'nearest-rank',
        'p50Microseconds': percentile(.5),
        'p95Microseconds': percentile(.95),
        'p99Microseconds': percentile(.99),
        'minMicroseconds': sorted.first.elapsedMicroseconds,
        'maxMicroseconds': sorted.last.elapsedMicroseconds,
        'samplesMicroseconds': runs
            .map((run) => run.elapsedMicroseconds)
            .toList(),
      });
    }
  }

  if (arguments.contains('--json')) {
    print(jsonEncode(results));
    return;
  }
  for (final result in results) {
    print(_BenchmarkResult.describeJson(result));
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
    snapshotCount: counters.snapshotCount,
    snapshotElementsCopied: counters.snapshotElementsCopied,
    snapshotStructuralNodes: counters.snapshotStructuralNodes,
    snapshotStructuralReferences: counters.snapshotStructuralReferences,
    elements: 0,
    elapsedMicroseconds: stopwatch.elapsedMicroseconds,
  );
}

_BenchmarkResult _runArrayBenchmark(
  String payload, {
  required bool structural,
}) {
  final previousCounters = partialJsonDebugCounters;
  final counters = PartialJsonDebugCounters();
  partialJsonDebugCounters = counters;

  final tracker = PartialJsonArrayTracker();
  final partialValues = <Object?>[];
  final builder = structural ? ImmutableArraySnapshotBuilder<Object?>() : null;
  var elements = 0;
  final stopwatch = Stopwatch()..start();

  try {
    for (final char in payload.split('')) {
      final update = tracker.append(
        char,
        phase: PartialJsonParsePhase.streamTextArrayElements,
        trigger: PartialJsonParseTrigger.arrayElementBoundary,
      );
      if (update.newElements.isNotEmpty) {
        partialValues.addAll(update.newElements);
        elements += update.newElements.length;
        if (structural) {
          builder!.addAll(update.newElements);
          builder.snapshot();
        } else {
          createTrackedImmutableSnapshot(partialValues);
        }
      }
    }
  } finally {
    stopwatch.stop();
    partialJsonDebugCounters = previousCounters;
  }

  return _BenchmarkResult(
    kind: structural ? 'array-structural' : 'array-copy',
    bytes: payload.length,
    parseAttempts: counters.parseAttempts,
    decodeAttempts: counters.decodeAttempts,
    snapshotCount: counters.snapshotCount,
    snapshotElementsCopied: counters.snapshotElementsCopied,
    snapshotStructuralNodes: counters.snapshotStructuralNodes,
    snapshotStructuralReferences: counters.snapshotStructuralReferences,
    elements: elements,
    elapsedMicroseconds: stopwatch.elapsedMicroseconds,
  );
}

void _assertParseBudget(_BenchmarkResult result) {
  final maxAttempts = switch (result.kind) {
    'object' => 1,
    'array-copy' || 'array-structural' => result.elements + 1,
    _ => throw StateError('Unknown benchmark kind: ${result.kind}'),
  };
  final maxSnapshotCount = switch (result.kind) {
    'object' => 0,
    'array-copy' || 'array-structural' => result.elements,
    _ => throw StateError('Unknown benchmark kind: ${result.kind}'),
  };
  final maxSnapshotElementsCopied = switch (result.kind) {
    'object' => 0,
    'array-copy' => result.elements * (result.elements + 1) ~/ 2,
    'array-structural' => 0,
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
  if (result.snapshotCount > maxSnapshotCount) {
    throw StateError(
      '${result.kind} snapshot count grew nonlinearly: '
      '${result.snapshotCount} > $maxSnapshotCount',
    );
  }
  if (result.snapshotElementsCopied > maxSnapshotElementsCopied) {
    throw StateError(
      '${result.kind} snapshot element copies grew nonlinearly: '
      '${result.snapshotElementsCopied} > $maxSnapshotElementsCopied',
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
    required this.snapshotCount,
    required this.snapshotElementsCopied,
    required this.snapshotStructuralNodes,
    required this.snapshotStructuralReferences,
    required this.elements,
    required this.elapsedMicroseconds,
  });

  final String kind;
  final int bytes;
  final int parseAttempts;
  final int decodeAttempts;
  final int snapshotCount;
  final int snapshotElementsCopied;
  final int snapshotStructuralNodes;
  final int snapshotStructuralReferences;
  final int elements;
  final int elapsedMicroseconds;

  Map<String, Object> toJson(String label) => {
    'kind': kind,
    'size': label,
    'bytes': bytes,
    'parseAttempts': parseAttempts,
    'decodeAttempts': decodeAttempts,
    'snapshotCount': snapshotCount,
    'snapshotElementsCopied': snapshotElementsCopied,
    'snapshotStructuralNodes': snapshotStructuralNodes,
    'snapshotStructuralReferences': snapshotStructuralReferences,
    'elements': elements,
    'elapsedMicroseconds': elapsedMicroseconds,
  };

  static String describeJson(Map<String, Object> result) {
    return '${result['kind']} ${result['size']} bytes=${result['bytes']} '
        'parseAttempts=${result['parseAttempts']} '
        'decodeAttempts=${result['decodeAttempts']} '
        'snapshotCount=${result['snapshotCount']} '
        'snapshotElementsCopied=${result['snapshotElementsCopied']} '
        'snapshotStructuralNodes=${result['snapshotStructuralNodes']} '
        'snapshotStructuralReferences=${result['snapshotStructuralReferences']} '
        'elements=${result['elements']} '
        'elapsedMs=${(result['elapsedMicroseconds'] as int) / 1000}';
  }
}
