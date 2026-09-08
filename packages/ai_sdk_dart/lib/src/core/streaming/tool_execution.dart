import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:meta/meta.dart';

import '../cancellation.dart';
import '../generate_text.dart';
import '../shared/common_helpers.dart';
import '../timeout_helpers.dart';
import '../../tools/tool.dart';

@internal
class ToolExecutionResult {
  const ToolExecutionResult({
    this.toolResult,
    this.approvalRequest,
    this.toolError,
  });

  final LanguageModelV4ToolResultPart? toolResult;
  final LanguageModelV4ToolApprovalRequestPart? approvalRequest;
  final Object? toolError;
}

@internal
Future<ToolExecutionResult> executeToolCall({
  required ToolSet tools,
  required LanguageModelV4ToolCallPart call,
  required List<LanguageModelV4Message> messages,
  required Map<String, LanguageModelV4ToolApprovalResponse> approvalById,
  CancellationToken? abortSignal,
  Duration? timeout,
  Map<String, Object?>? runtimeContext,
  void Function(Object? value)? onPreliminaryResult,
  GenerateTextExperimentalOnToolCallStart? onToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? onToolCallFinish,
}) async {
  final tool = tools[call.toolName];
  // Defensive: unknown tool names are rejected by tool-choice validation
  // before any call reaches here.
  // coverage:ignore-start
  if (tool == null) {
    final error = 'Tool not found.';
    return ToolExecutionResult(
      toolResult: LanguageModelV4ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: ToolResultOutputText(error),
      ),
      toolError: error,
    );
  }
  // coverage:ignore-end

  final approvalId = 'approval_${call.toolCallId}';
  final rawInput = call.input;

  try {
    final timeoutStopwatch = Stopwatch()..start();
    final parsedInput = parseToolInput(tool: tool, rawInput: rawInput);
    final options = ToolExecutionOptions(
      toolCallId: call.toolCallId,
      messages: messages,
      abortSignal: abortSignal,
      runtimeContext: runtimeContext,
    );

    final approvalEvaluator = tool.needsApprovalDynamic;
    final approvalResponse = approvalById[approvalId];
    throwIfCancelled(abortSignal);
    final needsApproval = switch (tool.approvalPolicy) {
      ToolApprovalPolicy.never => false,
      ToolApprovalPolicy.always => true,
      ToolApprovalPolicy.conditional =>
        approvalEvaluator == null
            ? false
            : await _awaitToolOperation(
                () => approvalEvaluator(parsedInput, options),
                toolName: call.toolName,
                abortSignal: abortSignal,
                timeout: _remainingToolTimeout(timeout, timeoutStopwatch),
              ),
    };
    if (needsApproval && approvalResponse == null) {
      return ToolExecutionResult(
        approvalRequest: LanguageModelV4ToolApprovalRequestPart(
          approvalId: approvalId,
          toolCall: call,
        ),
      );
    }
    if (needsApproval &&
        approvalResponse != null &&
        !approvalResponse.approved) {
      return ToolExecutionResult(
        toolResult: LanguageModelV4ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: ToolResultOutputText(
            approvalResponse.reason ?? 'Tool execution denied.',
          ),
        ),
        toolError: approvalResponse.reason ?? 'Tool execution denied.',
      );
    }

    final executor = tool.executeDynamic;
    if (executor == null) {
      const error = 'Tool has no executor.';
      return ToolExecutionResult(
        toolResult: LanguageModelV4ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: ToolResultOutputText(error),
        ),
        toolError: error,
      );
    }

    safeInvoke(
      () => onToolCallStart?.call(
        GenerateTextExperimentalToolCallStartEvent(
          toolCall: call,
          messages: List.unmodifiable(messages),
          options: options,
        ),
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final output = await _awaitToolOperation(
        () => executor(parsedInput, options),
        toolName: call.toolName,
        abortSignal: abortSignal,
        timeout: _remainingToolTimeout(timeout, timeoutStopwatch),
      );
      final finalOutput = await _resolveFinalToolOutput(
        output,
        onPreliminaryResult: onPreliminaryResult,
        abortSignal: abortSignal,
        timeout: timeout,
        timeoutStopwatch: timeoutStopwatch,
      );
      stopwatch.stop();
      safeInvoke(
        () => onToolCallFinish?.call(
          GenerateTextExperimentalToolCallFinishEvent(
            toolCall: call,
            durationMs: stopwatch.elapsedMilliseconds,
            success: true,
            output: finalOutput,
          ),
        ),
      );
      return ToolExecutionResult(
        toolResult: LanguageModelV4ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          output: ToolResultOutputText(stringifyToolOutput(finalOutput)),
        ),
      );
    } catch (error) {
      stopwatch.stop();
      safeInvoke(
        () => onToolCallFinish?.call(
          GenerateTextExperimentalToolCallFinishEvent(
            toolCall: call,
            durationMs: stopwatch.elapsedMilliseconds,
            success: false,
            error: error,
          ),
        ),
      );
      rethrow;
    }
  } catch (error) {
    if (error is AiOperationCancelledError || error is TimeoutException) {
      rethrow;
    }
    return ToolExecutionResult(
      toolResult: LanguageModelV4ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: ToolResultOutputText(error.toString()),
      ),
      toolError: error,
    );
  }
}

Future<Object?> _resolveFinalToolOutput(
  Object? output, {
  void Function(Object? value)? onPreliminaryResult,
  CancellationToken? abortSignal,
  Duration? timeout,
  Stopwatch? timeoutStopwatch,
}) async {
  if (output is Stream) {
    Object? previous;
    var seenAny = false;
    final iterator = StreamIterator<Object?>(output.cast<Object?>());
    try {
      while (await _moveNextWithToolTimeout(
        iterator,
        abortSignal: abortSignal,
        timeout: timeout,
        timeoutStopwatch: timeoutStopwatch,
      )) {
        final item = iterator.current;
        if (seenAny) {
          onPreliminaryResult?.call(previous);
        }
        previous = item;
        seenAny = true;
      }
    } finally {
      await iterator.cancel();
    }
    if (!seenAny) {
      return null;
    }
    return previous;
  }
  return output;
}

Future<T> _awaitToolOperation<T>(
  FutureOr<T> Function() operation, {
  required String toolName,
  CancellationToken? abortSignal,
  Duration? timeout,
}) {
  final guarded = raceWithCancellation(Future.sync(operation), abortSignal);
  if (timeout == null) return guarded;
  return guarded.timeout(
    timeout,
    onTimeout: () =>
        throw TimeoutException('Tool "$toolName" timed out.', timeout),
  );
}

Duration? _remainingToolTimeout(Duration? timeout, Stopwatch stopwatch) {
  return remainingTimeout(timeout: timeout, elapsed: stopwatch.elapsed);
}

Future<bool> _moveNextWithToolTimeout(
  StreamIterator<Object?> iterator, {
  CancellationToken? abortSignal,
  Duration? timeout,
  Stopwatch? timeoutStopwatch,
}) {
  final moveNext = raceWithCancellation(iterator.moveNext(), abortSignal);
  final remaining = timeoutStopwatch == null
      ? timeout
      : _remainingToolTimeout(timeout, timeoutStopwatch);
  if (remaining == null) return moveNext;
  return moveNext.timeout(
    remaining,
    onTimeout: () =>
        throw TimeoutException('Tool stream timed out.', remaining),
  );
}
