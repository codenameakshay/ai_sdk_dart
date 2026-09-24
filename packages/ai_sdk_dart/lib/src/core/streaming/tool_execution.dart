import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:meta/meta.dart';

import '../cancellation.dart';
import '../generate_text.dart';
import '../shared/common_helpers.dart';
import '../shared/stream_outcome.dart';
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

/// Indexes approval responses without allowing ambiguous duplicate IDs.
@internal
Map<String, LanguageModelV4ToolApprovalResponse> indexApprovalResponses(
  List<LanguageModelV4ToolApprovalResponse> responses,
) {
  final indexed = <String, LanguageModelV4ToolApprovalResponse>{};
  for (final response in responses) {
    if (indexed.containsKey(response.approvalId)) {
      throw ArgumentError(
        'Duplicate tool approval response ID: ${response.approvalId}',
      );
    }
    indexed[response.approvalId] = response;
  }
  return indexed;
}

@internal
bool approvalMatchesToolCall(
  LanguageModelV4ToolApprovalResponse response, {
  required LanguageModelV4ToolApprovalRequestPart request,
}) =>
    response.approvalId == request.approvalId &&
    response.toolCallId == request.toolCall.toolCallId &&
    response.toolName == request.toolCall.toolName &&
    request.argumentsFingerprint ==
        _argumentsFingerprint(request.toolCall.input) &&
    response.argumentsFingerprint ==
        _argumentsFingerprint(request.toolCall.input) &&
    response.policyRevision == request.policyRevision;

@internal
Future<ToolExecutionResult> executeToolCall({
  required ToolSet tools,
  required LanguageModelV4ToolCallPart call,
  required List<LanguageModelV4Message> messages,
  required Map<String, LanguageModelV4ToolApprovalResponse> approvalById,
  String? approvalId,
  CancellationToken? abortSignal,
  Duration? timeout,
  ToolApprovalPolicy? approvalPolicy,
  String policyRevision = 'default',
  Object? generationContext,
  Map<String, Object?>? runtimeContext,
  bool requireExactApprovalBinding = false,
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

  final effectiveApprovalId = approvalId ?? 'approval_${call.toolCallId}';
  final rawInput = call.input;

  try {
    final timeoutStopwatch = Stopwatch()..start();
    final parsedInput = parseToolInput(tool: tool, rawInput: rawInput);
    final options = ToolExecutionOptions(
      toolCallId: call.toolCallId,
      messages: messages,
      abortSignal: abortSignal,
      runtimeContext: runtimeContext,
      generationContext: generationContext,
      toolContext: tool.toolContextIsBound
          ? ToolExecutionContext<Object?>(tool.toolContext)
          : runtimeContext == null
          ? null
          : ToolExecutionContext<Map<String, Object?>>(runtimeContext),
    );

    final approvalEvaluator = tool.needsApprovalDynamic;
    final rawApprovalResponse = approvalById[effectiveApprovalId];
    final approvalResponse = _matchingApproval(
      rawApprovalResponse,
      call: call,
      policyRevision: policyRevision,
      requireExactBinding: requireExactApprovalBinding,
    );
    throwIfCancelled(abortSignal);
    final needsApproval = switch (approvalPolicy ?? tool.approvalPolicy) {
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
    if (requireExactApprovalBinding &&
        rawApprovalResponse != null &&
        approvalResponse == null) {
      return ToolExecutionResult(
        approvalRequest: LanguageModelV4ToolApprovalRequestPart(
          approvalId: effectiveApprovalId,
          toolCall: call,
          policyRevision: policyRevision,
          argumentsFingerprint: _argumentsFingerprint(call.input),
        ),
      );
    }
    if (needsApproval && approvalResponse == null) {
      return ToolExecutionResult(
        approvalRequest: LanguageModelV4ToolApprovalRequestPart(
          approvalId: effectiveApprovalId,
          toolCall: call,
          policyRevision: policyRevision,
          argumentsFingerprint: _argumentsFingerprint(call.input),
        ),
      );
    }
    if (approvalResponse != null && !approvalResponse.approved) {
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
    final iterator = StreamIterator<StreamOutcome<Object?>>(
      captureStreamErrors(output.cast<Object?>()),
    );
    Object? primaryError;
    StackTrace? primaryStack;
    try {
      while (await _moveNextWithToolTimeout(
        iterator,
        abortSignal: abortSignal,
        timeout: timeout,
        timeoutStopwatch: timeoutStopwatch,
      )) {
        final item = iterator.current.unwrap();
        if (seenAny) {
          onPreliminaryResult?.call(previous);
        }
        previous = item;
        seenAny = true;
      }
    } catch (error, stackTrace) {
      primaryError = error;
      primaryStack = stackTrace;
    } finally {
      try {
        await iterator.cancel();
      } catch (cleanupError, cleanupStack) {
        if (primaryError == null) {
          primaryError = cleanupError;
          primaryStack = cleanupStack;
        }
      }
    }
    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStack!);
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
    onTimeout: () {
      if (abortSignal case final signal?) scheduleMicrotask(signal.cancel);
      throw TimeoutException('Tool "$toolName" timed out.', timeout);
    },
  );
}

Duration? _remainingToolTimeout(Duration? timeout, Stopwatch stopwatch) {
  return remainingTimeout(timeout: timeout, elapsed: stopwatch.elapsed);
}

LanguageModelV4ToolApprovalResponse? _matchingApproval(
  LanguageModelV4ToolApprovalResponse? response, {
  required LanguageModelV4ToolCallPart call,
  required String policyRevision,
  bool requireExactBinding = false,
}) {
  if (response == null) return null;
  if (requireExactBinding &&
      (response.toolCallId == null ||
          response.toolName == null ||
          response.argumentsFingerprint == null ||
          response.policyRevision == null)) {
    return null;
  }
  if (response.toolCallId != null && response.toolCallId != call.toolCallId) {
    return null;
  }
  if (response.toolName != null && response.toolName != call.toolName) {
    return null;
  }
  if (response.policyRevision != null &&
      response.policyRevision != policyRevision) {
    return null;
  }
  if (response.argumentsFingerprint != null &&
      response.argumentsFingerprint != _argumentsFingerprint(call.input)) {
    return null;
  }
  return response;
}

String _argumentsFingerprint(Object input) => jsonEncode(_canonical(input));

Object? _canonical(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return {
      for (final entry in entries)
        entry.key.toString(): _canonical(entry.value),
    };
  }
  if (value is Iterable) return value.map(_canonical).toList(growable: false);
  return value;
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
    onTimeout: () {
      if (abortSignal case final signal?) scheduleMicrotask(signal.cancel);
      throw TimeoutException('Tool stream timed out.', remaining);
    },
  );
}
