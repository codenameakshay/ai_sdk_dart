import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../../tools/tool.dart';
import '../cancellation.dart';
import '../streaming/tool_execution.dart';

/// Executes a step's calls with an explicit bounded concurrency policy.
///
/// Calls are admitted in input order and results are returned in that same
/// order. A cancellation or terminal execution error stops queued calls from
/// starting while already admitted calls are allowed to settle.
Future<List<ToolExecutionResult>> executeToolCallsBounded({
  required List<LanguageModelV4ToolCallPart> calls,
  required int maxConcurrency,
  required CancellationToken? abortSignal,
  required Future<ToolExecutionResult> Function(
    LanguageModelV4ToolCallPart call,
  )
  execute,
}) async {
  if (maxConcurrency < 1) {
    throw ArgumentError.value(
      maxConcurrency,
      'maxConcurrency',
      'must be positive',
    );
  }
  if (calls.isEmpty) return const [];
  throwIfCancelled(abortSignal);

  final results = List<ToolExecutionResult?>.filled(calls.length, null);
  final completer = Completer<List<ToolExecutionResult>>();
  var nextIndex = 0;
  var active = 0;
  var completed = 0;
  Object? firstError;
  StackTrace? firstStack;

  void completeIfReady() {
    if (active != 0 || completer.isCompleted) return;
    if (firstError != null) {
      completer.completeError(firstError!, firstStack ?? StackTrace.current);
      return;
    }
    if (abortSignal?.isCancelled ?? false) {
      completer.completeError(const AiOperationCancelledError());
      return;
    }
    if (completed == calls.length) {
      completer.complete([for (final result in results) result!]);
    }
  }

  void pump() {
    if (completer.isCompleted) return;
    if (firstError != null || (abortSignal?.isCancelled ?? false)) {
      completeIfReady();
      return;
    }
    while (active < maxConcurrency &&
        nextIndex < calls.length &&
        !(abortSignal?.isCancelled ?? false)) {
      final index = nextIndex++;
      active++;
      Future<ToolExecutionResult>.sync(() => execute(calls[index])).then(
        (result) {
          results[index] = result;
          active--;
          completed++;
          pump();
        },
        onError: (Object error, StackTrace stack) {
          active--;
          firstError ??= error;
          firstStack ??= stack;
          pump();
        },
      );
    }
    completeIfReady();
  }

  pump();
  return completer.future;
}
