import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_dart/src/core/shared/tool_concurrency.dart';
import 'package:ai_sdk_dart/src/core/streaming/tool_execution.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

Future<void> main(List<String> arguments) async {
  const callCount = 12;
  const delay = Duration(milliseconds: 25);
  const boundedConcurrency = 4;

  final serial = await _run(
    callCount: callCount,
    delay: delay,
    maxConcurrency: 1,
  );
  final bounded = await _run(
    callCount: callCount,
    delay: delay,
    maxConcurrency: boundedConcurrency,
  );
  final result = <String, Object>{
    'callCount': callCount,
    'perCallDelayMilliseconds': delay.inMilliseconds,
    'boundedConcurrency': boundedConcurrency,
    'serial': serial.toJson(),
    'bounded': bounded.toJson(),
    'wallClockSpeedup':
        serial.elapsedMicroseconds / bounded.elapsedMicroseconds,
    'caveat':
        'Measures scheduler-controlled local I/O futures; no provider or network is used.',
  };

  if (arguments.contains('--json')) {
    print(jsonEncode(result));
  } else {
    print('Tool concurrency benchmark');
    print('serial: ${serial.describe()}');
    print('bounded: ${bounded.describe()}');
    print(
      'wall-clock speedup: '
      '${(result['wallClockSpeedup'] as double).toStringAsFixed(2)}x',
    );
    print(result['caveat']);
  }
}

Future<_RunResult> _run({
  required int callCount,
  required Duration delay,
  required int maxConcurrency,
}) async {
  var active = 0;
  var peak = 0;
  final calls = [
    for (var index = 0; index < callCount; index++)
      LanguageModelV4ToolCallPart(
        toolCallId: 'benchmark-$index',
        toolName: 'local-delay',
        input: const {},
      ),
  ];
  final stopwatch = Stopwatch()..start();
  final results = await executeToolCallsBounded(
    calls: calls,
    maxConcurrency: maxConcurrency,
    abortSignal: null,
    execute: (_) async {
      active++;
      if (active > peak) peak = active;
      try {
        await Future<void>.delayed(delay);
        return const ToolExecutionResult();
      } finally {
        active--;
      }
    },
  );
  stopwatch.stop();
  if (results.length != callCount || peak != maxConcurrency) {
    throw StateError('Benchmark scheduler invariant failed.');
  }
  return _RunResult(
    elapsedMicroseconds: stopwatch.elapsedMicroseconds,
    peakConcurrency: peak,
  );
}

class _RunResult {
  const _RunResult({
    required this.elapsedMicroseconds,
    required this.peakConcurrency,
  });

  final int elapsedMicroseconds;
  final int peakConcurrency;

  Map<String, Object> toJson() => {
    'elapsedMicroseconds': elapsedMicroseconds,
    'peakConcurrency': peakConcurrency,
  };

  String describe() =>
      '${elapsedMicroseconds / 1000} ms, peak concurrency $peakConcurrency';
}
