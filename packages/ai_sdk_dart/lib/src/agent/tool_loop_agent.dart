import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../core/generate_text.dart';
import '../core/stream_text.dart';
import '../core/streaming/tool_execution.dart';
import '../core/timeout_configuration.dart';
import '../core/shared/common_helpers.dart';
import '../messages/model_message.dart';
import '../stop_conditions/stop_conditions.dart';
import '../tools/tool.dart';

/// The conversation state needed to resume a paused approval turn.
///
/// [messages] contains the assistant/tool messages produced during the paused
/// turn, without the client-only approval request parts. [requests] keeps each
/// stable approval ID associated with the exact tool call that requested it.
class ToolApprovalReplay {
  const ToolApprovalReplay({required this.messages, required this.requests});

  final List<ModelMessage> messages;
  final List<LanguageModelV4ToolApprovalRequestPart> requests;
}

/// Agent that runs tools in a loop to accomplish tasks.
///
/// Mirrors `ToolLoopAgent` from the JS AI SDK v6. Handles the tool-call loop,
/// context management, and stop conditions. Use [generate] or [stream].
///
/// Example:
/// ```dart
/// final agent = ToolLoopAgent(
///   model: model,
///   tools: {...},
///   maxSteps: 5,
/// );
/// final result = await agent.generate(prompt: 'What is the weather?');
/// ```
class ToolLoopAgent {
  ToolLoopAgent({
    required this.model,
    this.instructions,
    this.tools = const {},
    this.maxSteps = 1,
    this.stopConditions = const [],
  });

  final LanguageModelV4 model;
  final String? instructions;
  final ToolSet tools;
  final int maxSteps;
  final List<StopCondition> stopConditions;

  /// Runs the agent in non-streaming mode.
  Future<GenerateTextResult> generate({
    String? prompt,
    List<ModelMessage>? messages,
    CancellationToken? abortSignal,
    TimeoutConfiguration? timeout,
  }) {
    return generateText(
      model: model,
      system: instructions,
      prompt: prompt,
      messages: messages,
      tools: tools,
      maxSteps: maxSteps,
      stopConditions: stopConditions,
      abortSignal: abortSignal,
      timeout: timeout,
    );
  }

  /// Runs the agent in streaming mode.
  ///
  /// Pass [toolApprovalResponses] to supply pre-collected tool-approval
  /// decisions (mirrors the JS SDK `addToolApprovalResponse` / `useChat` flow).
  Future<StreamTextResult> stream({
    String? prompt,
    List<ModelMessage>? messages,
    List<LanguageModelV4ToolApprovalResponse> toolApprovalResponses = const [],
    CancellationToken? abortSignal,
    TimeoutConfiguration? timeout,
  }) {
    return streamText(
      model: model,
      system: instructions,
      prompt: prompt,
      messages: messages,
      tools: tools,
      maxSteps: maxSteps,
      stopConditions: stopConditions,
      toolApprovalResponses: toolApprovalResponses,
      abortSignal: abortSignal,
      timeout: timeout,
    );
  }

  /// Resumes a stream after the caller has answered a paused tool approval.
  ///
  /// The approved calls are executed against the preserved tool-call IDs
  /// before the provider sees the reconstructed conversation. This lets a
  /// provider continue from the exact pending assistant turn instead of
  /// needing to repeat the tool call with the same ID.
  Future<StreamTextResult> resume({
    required ToolApprovalReplay replay,
    List<ModelMessage>? messages,
    List<LanguageModelV4ToolApprovalResponse> toolApprovalResponses = const [],
    CancellationToken? abortSignal,
    TimeoutConfiguration? timeout,
  }) async {
    final replayMessages = <ModelMessage>[...?messages, ...replay.messages];
    final approvalById = {
      for (final response in toolApprovalResponses)
        response.approvalId: response,
    };
    final missingApprovalIds = replay.requests
        .map((request) => request.approvalId)
        .where((approvalId) => !approvalById.containsKey(approvalId))
        .toSet();
    if (missingApprovalIds.isNotEmpty) {
      throw ArgumentError(
        'Missing tool approval response for approval ID(s): '
        '${missingApprovalIds.join(', ')}',
      );
    }
    final providerMessages = replayMessages
        .map(toLanguageModelMessage)
        .toList(growable: true);
    final results = <LanguageModelV4ToolResultPart>[];
    for (final request in replay.requests) {
      final execution = await executeToolCall(
        tools: tools,
        call: request.toolCall,
        messages: providerMessages,
        approvalById: approvalById,
        approvalId: request.approvalId,
        abortSignal: abortSignal,
        timeout: timeout?.toolTimeoutFor(request.toolCall.toolName),
      );
      if (execution.toolResult case final result?) {
        results.add(result);
      }
    }
    if (results.isNotEmpty) {
      replayMessages.add(
        ModelMessage.parts(role: ModelMessageRole.tool, parts: results),
      );
    }
    return streamText(
      model: model,
      system: instructions,
      messages: replayMessages,
      tools: tools,
      maxSteps: maxSteps,
      stopConditions: stopConditions,
      toolApprovalResponses: const [],
      abortSignal: abortSignal,
      timeout: timeout,
    );
  }
}
