import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../core/generate_text.dart';
import '../core/body_inclusion.dart';
import '../core/stream_text.dart';
import '../core/streaming/tool_execution.dart';
import '../core/timeout_configuration.dart';
import '../core/shared/common_helpers.dart';
import '../core/shared/operation_scope.dart';
import '../core/timeout_helpers.dart';
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

/// Signals that a replayed approval no longer authorizes its exact call.
///
/// Callers should present [requests] as a fresh pending approval and collect a
/// new bound response. No tool or provider call is made before this error.
class ToolApprovalRenewalRequiredError extends ArgumentError {
  ToolApprovalRenewalRequiredError({required this.requests})
    : super('Tool approval binding changed; renewal is required.');

  final List<LanguageModelV4ToolApprovalRequestPart> requests;
}

/// Signals that an approval replay contains a provider-executed tool call.
///
/// Hosted calls cannot be resumed through the local tool executor. The whole
/// replay is rejected before any client-owned tool is run.
class ToolApprovalProviderExecutedError extends ArgumentError {
  ToolApprovalProviderExecutedError({
    required List<LanguageModelV4ToolApprovalRequestPart> requests,
  }) : super(
         'Cannot resume provider-executed tool approval through local tools.',
       ) {
    this.requests = List.unmodifiable(requests);
  }

  late final List<LanguageModelV4ToolApprovalRequestPart> requests;
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
    this.maxToolConcurrency = 1,
    this.stopConditions = const [],
    this.approvalPolicy,
    this.approvalPolicyFor,
    this.approvalPolicyRevision = 'default',
    this.generationContext,
  }) {
    if (maxToolConcurrency < 1) {
      throw ArgumentError.value(
        maxToolConcurrency,
        'maxToolConcurrency',
        'must be positive',
      );
    }
  }

  final LanguageModelV4 model;
  final String? instructions;
  final ToolSet tools;
  final int maxSteps;

  /// Maximum number of tool calls admitted concurrently for each step.
  final int maxToolConcurrency;
  final List<StopCondition> stopConditions;
  final ToolApprovalPolicy? approvalPolicy;
  final ToolApprovalPolicySelector? approvalPolicyFor;
  final String approvalPolicyRevision;
  final Object? generationContext;

  /// Runs the agent in non-streaming mode.
  Future<GenerateTextResult> generate({
    String? prompt,
    List<ModelMessage>? messages,
    CancellationToken? abortSignal,
    TimeoutConfiguration? timeout,
    bool allowSystemInMessages = false,
    GenerateTextExperimentalOnStart? onStart,
    GenerateTextExperimentalOnStepStart? onStepStart,
    GenerateTextExperimentalOnToolCallStart? onToolExecutionStart,
    GenerateTextExperimentalOnToolCallFinish? onToolExecutionEnd,
    GenerateTextOnEnd? onEnd,
    GenerateTextOnStepEnd? onStepEnd,
    GenerateTextPrepareStep? prepareStep,
    List<LanguageModelV4ToolApprovalResponse> toolApprovalResponses = const [],
    ToolApprovalPolicy? approvalPolicy,
    ToolApprovalPolicySelector? approvalPolicyFor,
    String? approvalPolicyRevision,
    Object? generationContext,
    BodyInclusionPolicy bodyInclusion = const BodyInclusionPolicy.none(),
  }) {
    return generateText(
      model: model,
      instructions: instructions,
      prompt: prompt,
      messages: messages,
      tools: tools,
      maxSteps: maxSteps,
      maxToolConcurrency: maxToolConcurrency,
      stopConditions: stopConditions,
      abortSignal: abortSignal,
      timeout: timeout,
      allowSystemInMessages: allowSystemInMessages,
      onStart: onStart,
      onStepStart: onStepStart,
      onToolExecutionStart: onToolExecutionStart,
      onToolExecutionEnd: onToolExecutionEnd,
      onEnd: onEnd,
      onStepEnd: onStepEnd,
      prepareStep: prepareStep,
      toolApprovalResponses: toolApprovalResponses,
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      approvalPolicyFor: approvalPolicyFor ?? this.approvalPolicyFor,
      approvalPolicyRevision:
          approvalPolicyRevision ?? this.approvalPolicyRevision,
      generationContext: generationContext ?? this.generationContext,
      bodyInclusion: bodyInclusion,
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
    ToolApprovalPolicy? approvalPolicy,
    ToolApprovalPolicySelector? approvalPolicyFor,
    String? approvalPolicyRevision,
    Object? generationContext,
    CancellationToken? abortSignal,
    TimeoutConfiguration? timeout,
    bool allowSystemInMessages = false,
    GenerateTextExperimentalOnStart? onStart,
    GenerateTextExperimentalOnStepStart? onStepStart,
    GenerateTextExperimentalOnToolCallStart? onToolExecutionStart,
    GenerateTextExperimentalOnToolCallFinish? onToolExecutionEnd,
    StreamTextOnEnd? onEnd,
    StreamTextOnStepEnd? onStepEnd,
    GenerateTextPrepareStep? prepareStep,
    StreamTextOnChunk? onChunk,
    BodyInclusionPolicy bodyInclusion = const BodyInclusionPolicy.none(),
  }) {
    return streamText(
      model: model,
      instructions: instructions,
      prompt: prompt,
      messages: messages,
      tools: tools,
      maxSteps: maxSteps,
      maxToolConcurrency: maxToolConcurrency,
      stopConditions: stopConditions,
      toolApprovalResponses: toolApprovalResponses,
      approvalPolicy: approvalPolicy ?? this.approvalPolicy,
      approvalPolicyFor: approvalPolicyFor ?? this.approvalPolicyFor,
      approvalPolicyRevision:
          approvalPolicyRevision ?? this.approvalPolicyRevision,
      generationContext: generationContext ?? this.generationContext,
      abortSignal: abortSignal,
      timeout: timeout,
      allowSystemInMessages: allowSystemInMessages,
      onStart: onStart,
      onStepStart: onStepStart,
      onToolExecutionStart: onToolExecutionStart,
      onToolExecutionEnd: onToolExecutionEnd,
      onEnd: onEnd,
      onStepEnd: onStepEnd,
      prepareStep: prepareStep,
      onChunk: onChunk,
      bodyInclusion: bodyInclusion,
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
    ToolApprovalPolicy? approvalPolicy,
    ToolApprovalPolicySelector? approvalPolicyFor,
    String? approvalPolicyRevision,
    Object? generationContext,
    CancellationToken? abortSignal,
    TimeoutConfiguration? timeout,
    bool allowSystemInMessages = false,
    GenerateTextExperimentalOnStart? onStart,
    GenerateTextExperimentalOnStepStart? onStepStart,
    GenerateTextExperimentalOnToolCallStart? onToolExecutionStart,
    GenerateTextExperimentalOnToolCallFinish? onToolExecutionEnd,
    StreamTextOnEnd? onEnd,
    StreamTextOnStepEnd? onStepEnd,
    GenerateTextPrepareStep? prepareStep,
    BodyInclusionPolicy bodyInclusion = const BodyInclusionPolicy.none(),
  }) async {
    final effectivePolicy = approvalPolicy ?? this.approvalPolicy;
    final effectiveSelector = approvalPolicyFor ?? this.approvalPolicyFor;
    final effectiveRevision =
        approvalPolicyRevision ?? this.approvalPolicyRevision;
    final approvalById = indexApprovalResponses(toolApprovalResponses);
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
    final invalidBindings = <String>[];
    final seenCallIds = <String>{};
    for (final request in replay.requests) {
      final response = approvalById[request.approvalId]!;
      if (!seenCallIds.add(request.toolCall.toolCallId) ||
          request.policyRevision != effectiveRevision ||
          !approvalMatchesToolCall(response, request: request)) {
        invalidBindings.add(request.approvalId);
      }
    }
    if (invalidBindings.isNotEmpty) {
      throw ToolApprovalRenewalRequiredError(
        requests: List.unmodifiable(replay.requests),
      );
    }
    final providerExecuted = replay.requests
        .where((request) => request.toolCall.providerExecuted)
        .toList(growable: false);
    if (providerExecuted.isNotEmpty) {
      throw ToolApprovalProviderExecutedError(requests: providerExecuted);
    }
    final scope = OperationScope(
      abortSignal: abortSignal,
      timeout: timeout?.total,
    );
    var handedOff = false;
    try {
      final replayMessages = <ModelMessage>[...?messages, ...replay.messages];
      final providerMessages = replayMessages
          .map(toLanguageModelMessage)
          .toList(growable: true);
      final results = <LanguageModelV4ToolResultPart>[];
      for (final request in replay.requests) {
        final execution = await scope.run(
          () => executeToolCall(
            tools: tools,
            call: request.toolCall,
            messages: providerMessages,
            approvalById: approvalById,
            approvalId: request.approvalId,
            abortSignal: scope.signal,
            timeout: timeout?.toolTimeoutFor(request.toolCall.toolName),
            approvalPolicy:
                effectiveSelector?.call(
                  request.toolCall.toolName,
                  request.toolCall.input,
                ) ??
                effectivePolicy,
            policyRevision: request.policyRevision ?? effectiveRevision,
            generationContext: generationContext ?? this.generationContext,
            requireExactApprovalBinding: true,
          ),
        );
        if (execution.approvalRequest != null) {
          throw ToolApprovalRenewalRequiredError(
            requests: [execution.approvalRequest!],
          );
        }
        if (execution.toolResult case final result?) {
          results.add(result);
        }
      }
      if (results.isNotEmpty) {
        replayMessages.add(
          ModelMessage.parts(role: ModelMessageRole.tool, parts: results),
        );
      }
      final remainingTotal = remainingTimeout(
        timeout: timeout?.total,
        elapsed: scope.elapsed,
      );
      final result = await streamText(
        model: model,
        instructions: instructions,
        messages: replayMessages,
        tools: tools,
        maxSteps: maxSteps,
        maxToolConcurrency: maxToolConcurrency,
        stopConditions: stopConditions,
        toolApprovalResponses: const [],
        abortSignal: scope.signal,
        timeout: timeout == null
            ? null
            : TimeoutConfiguration(
                total: remainingTotal,
                step: timeout.step,
                firstChunk: timeout.firstChunk,
                chunk: timeout.chunk,
                tool: timeout.tool,
                tools: timeout.tools,
              ),
        approvalPolicy: effectivePolicy,
        approvalPolicyFor: effectiveSelector,
        approvalPolicyRevision: effectiveRevision,
        generationContext: generationContext ?? this.generationContext,
        allowSystemInMessages: allowSystemInMessages,
        onStart: onStart,
        onStepStart: onStepStart,
        onToolExecutionStart: onToolExecutionStart,
        onToolExecutionEnd: onToolExecutionEnd,
        onEnd: onEnd,
        onStepEnd: onStepEnd,
        prepareStep: prepareStep,
        bodyInclusion: bodyInclusion,
      );
      handedOff = true;
      result.finish.whenComplete(scope.close).ignore();
      return result;
    } finally {
      if (!handedOff) scope.close();
    }
  }
}
