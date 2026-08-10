import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../cancellation.dart';
import '../generate_text.dart';
import '../shared/common_helpers.dart';
import '../../tools/tool.dart';

class StreamingToolExecutionResult {
  const StreamingToolExecutionResult({
    this.toolResult,
    this.approvalRequest,
    this.toolError,
  });

  final LanguageModelV3ToolResultPart? toolResult;
  final LanguageModelV3ToolApprovalRequestPart? approvalRequest;
  final Object? toolError;
}

Future<StreamingToolExecutionResult> executeStreamingToolCall({
  required ToolSet tools,
  required LanguageModelV3ToolCallPart call,
  required List<LanguageModelV3Message> messages,
  required Map<String, LanguageModelV3ToolApprovalResponse> approvalById,
  required void Function(Object? value) onPreliminaryResult,
  CancellationToken? abortSignal,
  Map<String, Object?>? experimentalContext,
  GenerateTextExperimentalOnToolCallStart? onToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? onToolCallFinish,
}) async {
  final tool = tools[call.toolName];
  // Defensive: unknown tool names are rejected by tool-choice validation
  // before any call reaches here.
  // coverage:ignore-start
  if (tool == null) {
    final error = 'Tool not found.';
    return StreamingToolExecutionResult(
      toolResult: LanguageModelV3ToolResultPart(
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
    final parsedInput = parseToolInput(tool: tool, rawInput: rawInput);
    final options = ToolExecutionOptions(
      toolCallId: call.toolCallId,
      messages: messages,
      abortSignal: abortSignal,
      experimentalContext: experimentalContext,
    );

    final approvalEvaluator = tool.needsApprovalDynamic;
    final approvalResponse = approvalById[approvalId];
    throwIfCancelled(abortSignal);
    if (tool.requiresApproval && approvalResponse == null) {
      return StreamingToolExecutionResult(
        approvalRequest: LanguageModelV3ToolApprovalRequestPart(
          approvalId: approvalId,
          toolCall: call,
        ),
      );
    }

    var needsApproval = false;
    if (approvalEvaluator != null) {
      needsApproval = await raceWithCancellation(
        Future.value(approvalEvaluator(parsedInput, options)),
        abortSignal,
      );
    }
    if (tool.requiresApproval &&
        approvalResponse != null &&
        !approvalResponse.approved) {
      return StreamingToolExecutionResult(
        toolResult: LanguageModelV3ToolResultPart(
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

    // Defensive: an approval-requiring tool with no response is already
    // short-circuited by the earlier `approvalResponse == null` guard.
    // coverage:ignore-start
    if (tool.requiresApproval && needsApproval && approvalResponse == null) {
      return StreamingToolExecutionResult(
        approvalRequest: LanguageModelV3ToolApprovalRequestPart(
          approvalId: approvalId,
          toolCall: call,
        ),
      );
    }
    // coverage:ignore-end

    final executor = tool.executeDynamic;
    if (executor == null) {
      const error = 'Tool has no executor.';
      return StreamingToolExecutionResult(
        toolResult: LanguageModelV3ToolResultPart(
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
      final output = await raceWithCancellation(
        executor(parsedInput, options),
        abortSignal,
      );
      final finalOutput = await _resolveFinalStreamingToolOutput(
        output,
        onPreliminaryResult: onPreliminaryResult,
        abortSignal: abortSignal,
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
      return StreamingToolExecutionResult(
        toolResult: LanguageModelV3ToolResultPart(
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
    if (error is AiOperationCancelledError) {
      rethrow;
    }
    return StreamingToolExecutionResult(
      toolResult: LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: ToolResultOutputText(error.toString()),
      ),
      toolError: error,
    );
  }
}

Future<Object?> _resolveFinalStreamingToolOutput(
  Object? output, {
  required void Function(Object? value) onPreliminaryResult,
  CancellationToken? abortSignal,
}) async {
  if (output is Stream) {
    Object? previous;
    var seenAny = false;
    final iterator = StreamIterator<Object?>(output.cast<Object?>());
    try {
      while (await moveNextOrCancellation(iterator, abortSignal)) {
        final item = iterator.current;
        if (seenAny) {
          onPreliminaryResult(previous);
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
