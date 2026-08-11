import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'cancellation.dart';
import '../messages/model_message.dart';
import '../output/output.dart';
import '../stop_conditions/stop_conditions.dart';
import '../telemetry/telemetry.dart';
import '../tools/tool.dart';
import 'retry_helper.dart';
import 'shared/common_helpers.dart';
import 'shared/output_instruction.dart';
import 'shared/tool_selection.dart';
import 'timeout_configuration.dart';
import 'timeout_helpers.dart';

/// Callback invoked after each step finishes in multi-step generation.
typedef GenerateTextOnStepFinish =
    void Function(GenerateTextStepFinishEvent event);

/// Callback invoked when the full generation is complete.
typedef GenerateTextOnFinish<TOutput> =
    void Function(GenerateTextFinishEvent<TOutput> event);

/// Callback to prepare each step; can override model, tools, messages, etc.
typedef GenerateTextPrepareStep =
    FutureOr<GenerateTextPrepareStepResult?> Function(
      GenerateTextPrepareStepContext context,
    );

/// Experimental callback invoked once when generation starts.
typedef GenerateTextExperimentalOnStart =
    void Function(GenerateTextExperimentalStartEvent event);

/// Experimental callback invoked before each step starts.
typedef GenerateTextExperimentalOnStepStart =
    void Function(GenerateTextExperimentalStepStartEvent event);

/// Experimental callback invoked right before a tool's execute runs.
typedef GenerateTextExperimentalOnToolCallStart =
    void Function(GenerateTextExperimentalToolCallStartEvent event);

/// Experimental callback invoked right after a tool's execute completes.
typedef GenerateTextExperimentalOnToolCallFinish =
    void Function(GenerateTextExperimentalToolCallFinishEvent event);

/// Context passed to [GenerateTextPrepareStep] for step-level overrides.
///
/// Use this to change the model, tool choice, active tools, messages, or
/// provider options for the upcoming step.
class GenerateTextPrepareStepContext {
  const GenerateTextPrepareStepContext({
    required this.model,
    required this.stepNumber,
    required this.steps,
    required this.messages,
    required this.stopConditions,
    this.runtimeContext,
  });

  final LanguageModelV4 model;
  final int stepNumber;
  final List<GenerateTextStep> steps;
  final List<LanguageModelV4Message> messages;
  final List<StopCondition> stopConditions;
  final Map<String, Object?>? runtimeContext;
}

/// Result from [GenerateTextPrepareStep]; overrides for the upcoming step.
///
/// Return non-null values to override model, tool choice, active tools,
/// messages, or provider options for the next generation step.
class GenerateTextPrepareStepResult {
  const GenerateTextPrepareStepResult({
    this.model,
    this.toolChoice,
    this.activeTools,
    this.messages,
    this.providerOptions,
  });

  final LanguageModelV4? model;
  final LanguageModelV4ToolChoice? toolChoice;
  final List<String>? activeTools;
  final List<LanguageModelV4Message>? messages;
  final ProviderOptions? providerOptions;
}

/// Event passed to [GenerateTextOnStepFinish] when a step completes.
class GenerateTextStepFinishEvent {
  const GenerateTextStepFinishEvent({
    required this.stepNumber,
    required this.text,
    required this.toolCalls,
    required this.toolResults,
    required this.finishReason,
    this.usage,
  });

  final int stepNumber;
  final String text;
  final List<LanguageModelV4ToolCallPart> toolCalls;
  final List<LanguageModelV4ToolResultPart> toolResults;
  final LanguageModelV4FinishReason finishReason;
  final LanguageModelV4Usage? usage;
}

/// Event passed to [GenerateTextOnFinish] when generation completes.
class GenerateTextFinishEvent<TOutput> {
  const GenerateTextFinishEvent({
    required this.text,
    required this.output,
    required this.steps,
    required this.usage,
    required this.totalUsage,
    required this.finishReason,
    required this.response,
  });

  final String text;
  final TOutput output;
  final List<GenerateTextStep> steps;
  final LanguageModelV4Usage? usage;
  final LanguageModelV4Usage? totalUsage;
  final LanguageModelV4FinishReason? finishReason;
  final GenerateTextResponse response;
}

/// Request envelope for the generation call.
class GenerateTextRequest {
  const GenerateTextRequest({
    required this.system,
    required this.messages,
    this.body,
  });

  final String? system;
  final List<LanguageModelV4Message> messages;
  final Object? body;
}

/// Response envelope with messages, body, and metadata.
class GenerateTextResponse {
  const GenerateTextResponse({
    required this.messages,
    required this.body,
    required this.metadata,
  });

  final List<LanguageModelV4Message> messages;
  final Object? body;
  final LanguageModelV4ResponseMetadata? metadata;
}

/// Event emitted when generation starts (experimental_onStart).
class GenerateTextExperimentalStartEvent {
  const GenerateTextExperimentalStartEvent({
    required this.model,
    required this.system,
    required this.prompt,
    required this.messages,
    this.runtimeContext,
  });

  final LanguageModelV4 model;
  final String? system;
  final String? prompt;
  final List<LanguageModelV4Message> messages;
  final Map<String, Object?>? runtimeContext;
}

/// Event emitted before each step starts (experimental_onStepStart).
class GenerateTextExperimentalStepStartEvent {
  const GenerateTextExperimentalStepStartEvent({
    required this.stepNumber,
    required this.model,
    required this.messages,
    required this.steps,
  });

  final int stepNumber;
  final LanguageModelV4 model;
  final List<LanguageModelV4Message> messages;
  final List<GenerateTextStep> steps;
}

/// Event emitted before a tool executes (experimental_onToolCallStart).
class GenerateTextExperimentalToolCallStartEvent {
  const GenerateTextExperimentalToolCallStartEvent({
    required this.toolCall,
    required this.messages,
    required this.options,
  });

  final LanguageModelV4ToolCallPart toolCall;
  final List<LanguageModelV4Message> messages;
  final ToolExecutionOptions options;
}

/// Event emitted after a tool executes (experimental_onToolCallFinish).
class GenerateTextExperimentalToolCallFinishEvent {
  const GenerateTextExperimentalToolCallFinishEvent({
    required this.toolCall,
    required this.durationMs,
    required this.success,
    this.output,
    this.error,
  });

  final LanguageModelV4ToolCallPart toolCall;
  final int durationMs;
  final bool success;
  final Object? output;
  final Object? error;
}

/// Per-step details from [generateText] multi-step execution.
///
/// Each step contains the content, tool calls, tool results, response,
/// text, finish reason, and usage for that generation step.
class GenerateTextStep {
  const GenerateTextStep({
    required this.stepNumber,
    required this.content,
    required this.toolCalls,
    required this.toolResults,
    required this.toolApprovalRequests,
    required this.response,
    required this.text,
    required this.finishReason,
    this.usage,
  });

  final int stepNumber;
  final List<LanguageModelV4ContentPart> content;
  final List<LanguageModelV4ToolCallPart> toolCalls;
  final List<LanguageModelV4ToolResultPart> toolResults;
  final List<LanguageModelV4ToolApprovalRequestPart> toolApprovalRequests;
  final LanguageModelV4GenerateResult response;
  final String text;
  final LanguageModelV4FinishReason finishReason;
  final LanguageModelV4Usage? usage;
}

/// Result returned by [generateText].
///
/// Contains the generated text, parsed output, steps, tool calls/results,
/// usage, finish reason, request/response envelopes, and provider metadata.
/// Mirrors the result object from the JS AI SDK v6.
class GenerateTextResult<TOutput> {
  const GenerateTextResult({
    required this.text,
    required this.output,
    required this.content,
    required this.toolCalls,
    required this.toolResults,
    required this.toolApprovalRequests,
    required this.steps,
    required this.sources,
    required this.files,
    required this.reasoning,
    required this.reasoningText,
    required this.requestMessages,
    required this.responseMessages,
    required this.request,
    required this.responseInfo,
    this.response,
    this.usage,
    this.totalUsage,
    this.finishReason,
    this.rawFinishReason,
    this.warnings = const [],
    this.providerMetadata,
  });

  final String text;
  final TOutput output;
  final List<LanguageModelV4ContentPart> content;
  final List<LanguageModelV4ToolCallPart> toolCalls;
  final List<LanguageModelV4ToolResultPart> toolResults;
  final List<LanguageModelV4ToolApprovalRequestPart> toolApprovalRequests;
  final List<GenerateTextStep> steps;
  final List<LanguageModelV4SourcePart> sources;
  final List<LanguageModelV4FilePart> files;
  final List<LanguageModelV4ReasoningPart> reasoning;
  final String reasoningText;
  final List<LanguageModelV4Message> requestMessages;
  final List<LanguageModelV4Message> responseMessages;
  final GenerateTextRequest request;
  final GenerateTextResponse responseInfo;
  final LanguageModelV4GenerateResult? response;
  final LanguageModelV4Usage? usage;
  final LanguageModelV4Usage? totalUsage;
  final LanguageModelV4FinishReason? finishReason;
  final String? rawFinishReason;
  final List<LanguageModelV4Warning> warnings;
  final ProviderMetadata? providerMetadata;
}

/// Generates text for non-interactive use cases and agents with tools.
///
/// Mirrors `generateText` from the JS AI SDK v6. Supports structured output
/// via [Output], tool calling, multi-step generation, and lifecycle callbacks.
///
/// Example:
/// ```dart
/// final result = await generateText(
///   model: model,
///   prompt: 'Write a vegetarian lasagna recipe for 4 people.',
/// );
/// print(result.text);
/// ```
///
/// With structured output:
/// ```dart
/// final result = await generateText(
///   model: model,
///   output: Output.object(schema: mySchema),
///   prompt: 'Generate a recipe.',
/// );
/// print(result.output);
/// ```
///
/// Parameters:
/// - [model] – The language model to use.
/// - [system] – Optional system instruction.
/// - [prompt] – User prompt (or use [messages] for multi-turn).
/// - [messages] – Conversation messages for multi-turn.
/// - [output] – Structured output spec (default: [Output.text]).
/// - [tools] – Tools the model can call.
/// - [stopWhen] – Primary stop condition (or list). When absent, [maxSteps]
///   and [stopConditions] govern stopping.
/// - [maxSteps] – Max tool-call steps (default: 1). Ignored when [stopWhen]
///   fully controls stopping.
/// - [stopConditions] – Additional stop conditions merged with [stopWhen].
/// - [prepareStep] – Per-step overrides.
/// - [onStepFinish] – Called after each step.
/// - [onFinish] – Called when generation completes.
Future<GenerateTextResult<TOutput>> generateText<TOutput>({
  required LanguageModelV4 model,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  int? maxOutputTokens,
  double? temperature,
  double? topP,
  int? topK,
  double? presencePenalty,
  double? frequencyPenalty,
  List<String> stopSequences = const [],
  int? seed,
  Map<String, String>? headers,
  int maxRetries = 2,
  List<String> activeToolNames = const [],
  ProviderOptions? providerOptions,
  LanguageModelV4Reasoning reasoning = LanguageModelV4Reasoning.providerDefault,
  Output<TOutput>? output,
  ToolSet tools = const {},
  List<LanguageModelV4ProviderDefinedTool> providerDefinedTools = const [],
  int maxSteps = 1,
  List<StopCondition> stopConditions = const [],
  Object? stopWhen, // StopCondition | List<StopCondition>
  LanguageModelV4ToolChoice? toolChoice,
  List<LanguageModelV4ToolApprovalResponse> toolApprovalResponses = const [],
  CancellationToken? abortSignal,
  TimeoutConfiguration? timeout,
  Map<String, Object?>? runtimeContext,
  GenerateTextOnStepFinish? onStepFinish,
  GenerateTextOnFinish<TOutput>? onFinish,
  GenerateTextPrepareStep? prepareStep,
  GenerateTextExperimentalOnStart? experimentalOnStart,
  GenerateTextExperimentalOnStepStart? experimentalOnStepStart,
  GenerateTextExperimentalOnToolCallStart? experimentalOnToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? experimentalOnToolCallFinish,
  TelemetrySettings? telemetry,
}) async {
  final telemetrySpan = startTelemetrySpan(
    telemetry,
    spanName: 'ai.generateText',
    attributes: {
      'ai.model.provider': model.provider,
      'ai.model.id': model.modelId,
      'ai.prompt': ?prompt,
    },
  );

  try {
    final overallStopwatch = Stopwatch()..start();
    final outputSpec = output ?? (Output.text() as Output<TOutput>);
    var normalizedMessages = <LanguageModelV4Message>[
      if (prompt != null)
        LanguageModelV4Message(
          role: LanguageModelV4Role.user,
          content: [LanguageModelV4TextPart(text: prompt)],
        ),
      ...?messages?.map(toLanguageModelMessage),
    ];

    final systemInstruction = buildOutputSystemInstruction(system, outputSpec);
    final approvalById = {
      for (final approval in toolApprovalResponses)
        approval.approvalId: approval,
    };

    safeInvoke(
      () => experimentalOnStart?.call(
        GenerateTextExperimentalStartEvent(
          model: model,
          system: systemInstruction,
          prompt: prompt,
          messages: List.unmodifiable(normalizedMessages),
          runtimeContext: runtimeContext,
        ),
      ),
    );

    final steps = <GenerateTextStep>[];
    var lastContent = <LanguageModelV4ContentPart>[];
    List<LanguageModelV4Message>? firstRequestMessages;
    LanguageModelV4GenerateResult? lastResponse;

    final allStopConditions = resolveStopConditions(stopWhen, stopConditions);
    final totalSteps = resolveStepBudget(
      hasTools: tools.isNotEmpty,
      stopWhen: stopWhen,
      maxSteps: maxSteps,
    );

    for (var stepNumber = 0; stepNumber < totalSteps; stepNumber++) {
      throwIfCancelled(abortSignal);
      final prepareResult = await Future.value(
        prepareStep?.call(
          GenerateTextPrepareStepContext(
            model: model,
            stepNumber: stepNumber,
            steps: List.unmodifiable(steps),
            messages: List.unmodifiable(normalizedMessages),
            stopConditions: allStopConditions,
            runtimeContext: runtimeContext,
          ),
        ),
      );

      final stepModel = prepareResult?.model ?? model;
      final stepToolChoice = prepareResult?.toolChoice ?? toolChoice;
      final stepMessages = prepareResult?.messages ?? normalizedMessages;
      firstRequestMessages ??= List<LanguageModelV4Message>.from(stepMessages);
      final stepProviderOptions =
          prepareResult?.providerOptions ?? providerOptions;
      final activeTools = selectActiveTools(
        tools,
        prepareResult?.activeTools ??
            (activeToolNames.isNotEmpty ? activeToolNames : null),
      );
      final toolSelection = resolveToolSelection(
        tools: activeTools,
        toolChoice: stepToolChoice,
      );

      safeInvoke(
        () => experimentalOnStepStart?.call(
          GenerateTextExperimentalStepStartEvent(
            stepNumber: stepNumber,
            model: stepModel,
            messages: List.unmodifiable(stepMessages),
            steps: List.unmodifiable(steps),
          ),
        ),
      );

      final callOptions = LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          system: systemInstruction,
          messages: stepMessages,
        ),
        tools: [
          ...toolSelection.exposedTools.entries.map(
            (entry) => LanguageModelV4FunctionTool(
              name: entry.key,
              description: entry.value.description,
              inputSchema: entry.value.inputSchema.jsonSchema,
              strict: entry.value.strict,
              inputExamples: entry.value.inputExamples
                  .map((example) => example.input)
                  .toList(),
            ),
          ),
          ...providerDefinedTools,
        ],
        toolChoice: toolSelection.toolChoice,
        maxOutputTokens: maxOutputTokens,
        temperature: temperature,
        topP: topP,
        topK: topK,
        presencePenalty: presencePenalty,
        frequencyPenalty: frequencyPenalty,
        stopSequences: stopSequences,
        seed: seed,
        headers: headers,
        providerOptions: stepProviderOptions,
        responseFormat: buildResponseFormat(outputSpec),
        abortSignal: abortSignal,
        reasoning: reasoning,
      );
      final response = await withRetry(
        maxRetries: maxRetries,
        totalTimeout: remainingTimeout(
          timeout: timeout?.total,
          elapsed: overallStopwatch.elapsed,
        ),
        stepTimeout: timeout?.step,
        abortSignal: abortSignal,
        fn: (attemptTimeout) {
          final call = stepModel.doGenerate(callOptions);
          return attemptTimeout != null ? call.timeout(attemptTimeout) : call;
        },
      );

      validateToolChoiceForCalls(
        toolCalls: response.content.whereType<LanguageModelV4ToolCallPart>(),
        tools: toolSelection.exposedTools,
        toolChoice: toolSelection.toolChoice,
        stepNumber: stepNumber,
      );

      lastResponse = response;
      final toolCalls = response.content
          .whereType<LanguageModelV4ToolCallPart>();
      final toolResults = <LanguageModelV4ToolResultPart>[];
      final approvalRequests = <LanguageModelV4ToolApprovalRequestPart>[];
      final stepContent = <LanguageModelV4ContentPart>[...response.content];

      normalizedMessages = [
        ...stepMessages,
        LanguageModelV4Message(
          role: LanguageModelV4Role.assistant,
          content: response.content,
        ),
      ];

      if (toolCalls.isNotEmpty) {
        for (final call in toolCalls) {
          throwIfCancelled(abortSignal);
          final execution = await _executeToolCall(
            tools: toolSelection.exposedTools,
            call: call,
            messages: normalizedMessages,
            approvalById: approvalById,
            abortSignal: abortSignal,
            timeout: minTimeout(
              remainingTimeout(
                timeout: timeout?.total,
                elapsed: overallStopwatch.elapsed,
              ),
              timeout?.toolTimeoutFor(call.toolName),
            ),
            runtimeContext: runtimeContext,
            onToolCallStart: experimentalOnToolCallStart,
            onToolCallFinish: experimentalOnToolCallFinish,
          );
          if (execution.approvalRequest != null) {
            approvalRequests.add(execution.approvalRequest!);
            stepContent.add(execution.approvalRequest!);
          }
          if (execution.toolResult != null) {
            toolResults.add(execution.toolResult!);
          }
        }
      }

      if (toolResults.isNotEmpty) {
        normalizedMessages = [
          ...normalizedMessages,
          LanguageModelV4Message(
            role: LanguageModelV4Role.tool,
            content: toolResults,
          ),
        ];
      }

      final stepText = _contentToText(stepContent);
      final step = GenerateTextStep(
        stepNumber: stepNumber,
        content: stepContent,
        toolCalls: toolCalls.toList(),
        toolResults: toolResults,
        toolApprovalRequests: approvalRequests,
        response: response,
        text: stepText,
        finishReason: response.finishReason,
        usage: response.usage,
      );
      steps.add(step);

      safeInvoke(
        () => onStepFinish?.call(
          GenerateTextStepFinishEvent(
            stepNumber: stepNumber,
            text: stepText,
            toolCalls: step.toolCalls,
            toolResults: step.toolResults,
            finishReason: step.finishReason,
            usage: step.usage,
          ),
        ),
      );

      lastContent = stepContent;
      final snapshot = StepSnapshot(
        stepCount: stepNumber + 1,
        toolCallNames: toolCalls.map((call) => call.toolName).toList(),
        finishReason: response.finishReason,
      );
      final shouldStop = shouldStopAfterStep(
        toolResultsEmpty: toolResults.isEmpty,
        hasApprovalRequests: approvalRequests.isNotEmpty,
        snapshot: snapshot,
        conditions: allStopConditions,
      );
      if (shouldStop) {
        break;
      }
    }

    final text = _contentToText(lastContent);
    final parsedOutput = _parseOutputWithNoObjectError(
      output: outputSpec,
      text: text,
      response: lastResponse,
    );
    final totalUsage = sumUsage(steps.map((step) => step.usage));
    final responseMessages = normalizedMessages
        .where(
          (message) =>
              message.role == LanguageModelV4Role.assistant ||
              message.role == LanguageModelV4Role.tool,
        )
        .toList(growable: false);
    final request = GenerateTextRequest(
      system: systemInstruction,
      messages: List.unmodifiable(firstRequestMessages ?? normalizedMessages),
      body: lastResponse?.request?.body,
    );
    final responseInfo = GenerateTextResponse(
      messages: List.unmodifiable(responseMessages),
      body: lastResponse?.response?.body,
      metadata: lastResponse?.response,
    );

    final result = GenerateTextResult<TOutput>(
      text: text,
      output: parsedOutput,
      content: lastContent,
      toolCalls: lastContent.whereType<LanguageModelV4ToolCallPart>().toList(),
      toolResults: lastContent
          .whereType<LanguageModelV4ToolResultPart>()
          .toList(),
      toolApprovalRequests: lastContent
          .whereType<LanguageModelV4ToolApprovalRequestPart>()
          .toList(),
      steps: steps,
      sources: lastContent.whereType<LanguageModelV4SourcePart>().toList(),
      files: lastContent.whereType<LanguageModelV4FilePart>().toList(),
      reasoning: lastContent.whereType<LanguageModelV4ReasoningPart>().toList(),
      reasoningText: lastContent
          .where(
            (part) =>
                part is LanguageModelV4ReasoningPart ||
                part is LanguageModelV4RedactedReasoningPart,
          )
          .map(
            (part) =>
                part is LanguageModelV4ReasoningPart ? part.text : '[REDACTED]',
          )
          .join(),
      requestMessages: List.unmodifiable(
        firstRequestMessages ?? normalizedMessages,
      ),
      responseMessages: List.unmodifiable(responseMessages),
      request: request,
      responseInfo: responseInfo,
      response: lastResponse,
      usage: lastResponse?.usage,
      totalUsage: totalUsage,
      finishReason: lastResponse?.finishReason,
      rawFinishReason: lastResponse?.rawFinishReason,
      warnings: List.unmodifiable(lastResponse?.warnings ?? const []),
      providerMetadata: lastResponse?.providerMetadata,
    );

    safeInvoke(
      () => onFinish?.call(
        GenerateTextFinishEvent<TOutput>(
          text: result.text,
          output: result.output,
          steps: List.unmodifiable(result.steps),
          usage: result.usage,
          totalUsage: result.totalUsage,
          finishReason: result.finishReason,
          response: result.responseInfo,
        ),
      ),
    );

    telemetrySpan
      ..setAttribute(
        'ai.usage.promptTokens',
        result.totalUsage?.inputTokens.total ?? 0,
      )
      ..setAttribute(
        'ai.usage.completionTokens',
        result.totalUsage?.outputTokens.total ?? 0,
      )
      ..setAttribute('ai.finishReason', result.finishReason?.name ?? 'unknown')
      ..end();

    return result;
  } catch (e, st) {
    telemetrySpan
      ..recordException(e, stackTrace: st)
      ..end(error: e);
    rethrow;
  }
}

class _ToolExecutionResult {
  const _ToolExecutionResult({this.toolResult, this.approvalRequest});

  final LanguageModelV4ToolResultPart? toolResult;
  final LanguageModelV4ToolApprovalRequestPart? approvalRequest;
}

class _ToolOutputResolution {
  const _ToolOutputResolution({required this.finalOutput});

  final Object? finalOutput;
}

Future<_ToolExecutionResult> _executeToolCall({
  required ToolSet tools,
  required LanguageModelV4ToolCallPart call,
  required List<LanguageModelV4Message> messages,
  required Map<String, LanguageModelV4ToolApprovalResponse> approvalById,
  CancellationToken? abortSignal,
  Duration? timeout,
  Map<String, Object?>? runtimeContext,
  GenerateTextExperimentalOnToolCallStart? onToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? onToolCallFinish,
}) async {
  final tool = tools[call.toolName];
  // Defensive: unknown tool names are rejected by tool-choice validation
  // before any call reaches here.
  // coverage:ignore-start
  if (tool == null) {
    return _ToolExecutionResult(
      toolResult: LanguageModelV4ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: const ToolResultOutputText('Tool not found.'),
      ),
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
                () => Future.value(approvalEvaluator(parsedInput, options)),
                toolName: call.toolName,
                abortSignal: abortSignal,
                timeout: _remainingToolTimeout(timeout, timeoutStopwatch),
              ),
    };
    if (needsApproval && approvalResponse == null) {
      return _ToolExecutionResult(
        approvalRequest: LanguageModelV4ToolApprovalRequestPart(
          approvalId: approvalId,
          toolCall: call,
        ),
      );
    }
    if (needsApproval &&
        approvalResponse != null &&
        !approvalResponse.approved) {
      return _ToolExecutionResult(
        toolResult: LanguageModelV4ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: ToolResultOutputText(
            approvalResponse.reason ?? 'Tool execution denied.',
          ),
        ),
      );
    }

    final executor = tool.executeDynamic;
    if (executor == null) {
      return _ToolExecutionResult(
        toolResult: LanguageModelV4ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: const ToolResultOutputText('Tool has no executor.'),
        ),
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
      final resolved = await _resolveFinalToolOutput(
        output,
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
            output: resolved.finalOutput,
          ),
        ),
      );
      return _ToolExecutionResult(
        toolResult: LanguageModelV4ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          output: ToolResultOutputText(
            stringifyToolOutput(resolved.finalOutput),
          ),
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
    return _ToolExecutionResult(
      toolResult: LanguageModelV4ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: ToolResultOutputText(error.toString()),
      ),
    );
  }
}

Future<_ToolOutputResolution> _resolveFinalToolOutput(
  Object? output, {
  CancellationToken? abortSignal,
  Duration? timeout,
  Stopwatch? timeoutStopwatch,
}) async {
  if (output is Stream) {
    Object? last;
    var seenAny = false;
    final iterator = StreamIterator<Object?>(output.cast<Object?>());
    try {
      while (await _moveNextWithToolTimeout(
        iterator,
        abortSignal: abortSignal,
        timeout: timeout,
        timeoutStopwatch: timeoutStopwatch,
      )) {
        seenAny = true;
        last = iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
    return _ToolOutputResolution(finalOutput: seenAny ? last : null);
  }
  return _ToolOutputResolution(finalOutput: output);
}

Future<T> _awaitToolOperation<T>(
  Future<T> Function() operation, {
  required String toolName,
  CancellationToken? abortSignal,
  Duration? timeout,
}) {
  final guarded = raceWithCancellation(operation(), abortSignal);
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
  final moveNext = moveNextOrCancellation(iterator, abortSignal);
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

String _contentToText(List<LanguageModelV4ContentPart> content) {
  return content.whereType<LanguageModelV4TextPart>().map((p) => p.text).join();
}

TOutput _parseOutput<TOutput>(Output<TOutput> output, String text) {
  switch (output) {
    case TextOutput():
      return text as TOutput;
    case ObjectOutput<TOutput>(:final schema):
      final jsonMap = _extractJsonObject(text);
      return schema.fromJson(jsonMap);
    case ArrayOutput(:final element):
      final jsonValue = _extractJsonValue(text);
      if (jsonValue is! List) {
        throw AiInvalidToolInputError(
          'Model did not return a JSON array: $text',
        );
      }
      final list = <dynamic>[];
      for (final item in jsonValue) {
        if (item is Map<String, dynamic>) {
          list.add(element.fromJson(item));
          // Defensive: jsonDecode always yields Map<String, dynamic> objects.
          // coverage:ignore-start
        } else if (item is Map) {
          list.add(element.fromJson(item.cast<String, dynamic>()));
          // coverage:ignore-end
        } else {
          throw AiInvalidToolInputError(
            'Array element is not a JSON object: $item',
          );
        }
      }
      return list as TOutput;
    case ChoiceOutput(:final options):
      final parsed = _safeParseJson(text.trim());
      final value = switch (parsed) {
        String s => s,
        _ => text.trim(),
      };
      if (!options.contains(value)) {
        throw AiInvalidToolInputError(
          'Model did not return a valid choice: $value',
        );
      }
      return value as TOutput;
    case JsonOutput():
      return _extractJsonValue(text) as TOutput;
  }
}

TOutput _parseOutputWithNoObjectError<TOutput>({
  required Output<TOutput> output,
  required String text,
  required LanguageModelV4GenerateResult? response,
}) {
  try {
    return _parseOutput(output, text);
  } catch (error) {
    if (output is TextOutput) {
      rethrow;
    }
    throw AiNoObjectGeneratedError(
      message: 'Failed to generate a valid structured output.',
      text: text,
      response: response?.response,
      usage: response?.usage,
      cause: error,
    );
  }
}

Map<String, dynamic> _extractJsonObject(String text) {
  final parsed = _extractJsonValue(text);
  if (parsed is Map<String, dynamic>) {
    return parsed;
  }
  // Defensive: jsonDecode always yields Map<String, dynamic> for objects.
  // coverage:ignore-start
  if (parsed is Map) {
    return parsed.cast<String, dynamic>();
  }
  // coverage:ignore-end
  throw AiInvalidToolInputError('Model did not return a JSON object: $text');
}

Object _extractJsonValue(String text) {
  if (text.trim().isEmpty) {
    throw const AiNoContentGeneratedError('No content was generated.');
  }
  final parsed = _safeParseJson(text.trim());
  if (parsed == null) {
    throw AiInvalidToolInputError('Model did not return valid JSON: $text');
  }
  return parsed;
}

Object? _safeParseJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    final fenceMatch = RegExp(
      r'```(?:json)?\s*([\s\S]+?)\s*```',
    ).firstMatch(text);
    if (fenceMatch != null) {
      final fenced = fenceMatch.group(1);
      if (fenced != null) {
        try {
          return jsonDecode(fenced);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }
}
