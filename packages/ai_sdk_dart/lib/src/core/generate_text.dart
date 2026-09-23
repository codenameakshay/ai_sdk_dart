import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'cancellation.dart';
import 'body_inclusion.dart';
import '../messages/model_message.dart';
import '../output/output.dart';
import '../stop_conditions/stop_conditions.dart';
import '../telemetry/telemetry.dart';
import '../tools/tool.dart';
import 'retry_helper.dart';
import 'shared/common_helpers.dart';
import 'shared/output_instruction.dart';
import 'shared/tool_selection.dart';
import 'shared/tool_concurrency.dart';
import 'shared/operation_scope.dart';
import 'streaming/structured_output.dart';
import 'streaming/tool_execution.dart';
import 'timeout_configuration.dart';
import 'timeout_helpers.dart';

/// Callback invoked after each step finishes in multi-step generation.
typedef GenerateTextOnStepFinish =
    void Function(GenerateTextStepFinishEvent event);

/// Callback invoked when the full generation is complete.
typedef GenerateTextOnFinish<TOutput> =
    void Function(GenerateTextFinishEvent<TOutput> event);
typedef GenerateTextOnStepEnd = GenerateTextOnStepFinish;
typedef GenerateTextOnEnd<TOutput> = GenerateTextOnFinish<TOutput>;

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
    required this.instructions,
    this.runtimeContext,
    this.generationContext,
  });

  final LanguageModelV4 model;
  final int stepNumber;
  final List<GenerateTextStep> steps;
  final List<LanguageModelV4Message> messages;
  final List<StopCondition> stopConditions;
  final String? instructions;
  final Map<String, Object?>? runtimeContext;
  final Object? generationContext;
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
    this.instructions,
  });

  final LanguageModelV4? model;
  final LanguageModelV4ToolChoice? toolChoice;
  final List<String>? activeTools;
  final List<LanguageModelV4Message>? messages;
  final ProviderOptions? providerOptions;
  final String? instructions;
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
    this.instructions,
    required this.messages,
    this.body,
  });

  final String? system;
  final String? instructions;
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
    this.instructions,
    this.runtimeContext,
    this.generationContext,
  });

  final LanguageModelV4 model;
  final String? system;
  final String? instructions;
  final String? prompt;
  final List<LanguageModelV4Message> messages;
  final Map<String, Object?>? runtimeContext;
  final Object? generationContext;
}

/// Event emitted before each step starts (experimental_onStepStart).
class GenerateTextExperimentalStepStartEvent {
  const GenerateTextExperimentalStepStartEvent({
    required this.stepNumber,
    required this.model,
    required this.messages,
    required this.steps,
    this.instructions,
    this.generationContext,
  });

  final int stepNumber;
  final LanguageModelV4 model;
  final List<LanguageModelV4Message> messages;
  final List<GenerateTextStep> steps;
  final String? instructions;
  final Object? generationContext;
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
    this.responseMessages = const [],
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
  final List<LanguageModelV4Message> responseMessages;

  String? get rawFinishReason => response.rawFinishReason;
  List<LanguageModelV4ReasoningPart> get reasoning =>
      content.whereType<LanguageModelV4ReasoningPart>().toList(growable: false);
  String get reasoningText => reasoning.map((part) => part.text).join();

  List<LanguageModelV4SourcePart> get sources =>
      content.whereType<LanguageModelV4SourcePart>().toList(growable: false);
  List<LanguageModelV4DocumentSourcePart> get documentSources => content
      .whereType<LanguageModelV4DocumentSourcePart>()
      .toList(growable: false);
  List<LanguageModelV4FilePart> get files =>
      content.whereType<LanguageModelV4FilePart>().toList(growable: false);
  List<LanguageModelV4ReasoningFilePart> get reasoningFiles => content
      .whereType<LanguageModelV4ReasoningFilePart>()
      .toList(growable: false);
  List<LanguageModelV4Warning> get warnings => response.warnings;
  LanguageModelV4RequestMetadata? get request => response.request;
  LanguageModelV4ResponseMetadata? get responseMetadata => response.response;
  ProviderMetadata? get providerMetadata => response.providerMetadata;
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
    required this.documentSources,
    required this.files,
    required this.reasoningFiles,
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
  final List<LanguageModelV4DocumentSourcePart> documentSources;
  final List<LanguageModelV4FilePart> files;
  final List<LanguageModelV4ReasoningFilePart> reasoningFiles;
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

  /// The last generated step, including its request, response and content.
  GenerateTextStep get finalStep => steps.last;
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
/// - [maxToolConcurrency] – Maximum number of tool calls admitted at once
///   (default: 1, preserving serial execution).
/// - [stopConditions] – Additional stop conditions merged with [stopWhen].
/// - [prepareStep] – Per-step overrides.
/// - [onStepFinish] – Called after each step.
/// - [onFinish] – Called when generation completes.
Future<GenerateTextResult<TOutput>> generateText<TOutput>({
  required LanguageModelV4 model,
  String? instructions,
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
  ToolApprovalPolicy? approvalPolicy,
  ToolApprovalPolicySelector? approvalPolicyFor,
  String approvalPolicyRevision = 'default',
  List<LanguageModelV4ProviderDefinedTool> providerDefinedTools = const [],
  int maxSteps = 1,
  int maxToolConcurrency = 1,
  List<StopCondition> stopConditions = const [],
  Object? stopWhen, // StopCondition | List<StopCondition>
  LanguageModelV4ToolChoice? toolChoice,
  List<LanguageModelV4ToolApprovalResponse> toolApprovalResponses = const [],
  CancellationToken? abortSignal,
  TimeoutConfiguration? timeout,
  Map<String, Object?>? runtimeContext,
  Object? generationContext,
  bool allowSystemInMessages = false,
  GenerateTextOnStepEnd? onStepEnd,
  GenerateTextOnEnd<TOutput>? onEnd,
  GenerateTextExperimentalOnStart? onStart,
  GenerateTextExperimentalOnStepStart? onStepStart,
  GenerateTextExperimentalOnToolCallStart? onToolExecutionStart,
  GenerateTextExperimentalOnToolCallFinish? onToolExecutionEnd,
  GenerateTextOnStepFinish? onStepFinish,
  GenerateTextOnFinish<TOutput>? onFinish,
  GenerateTextPrepareStep? prepareStep,
  GenerateTextExperimentalOnStart? experimentalOnStart,
  GenerateTextExperimentalOnStepStart? experimentalOnStepStart,
  GenerateTextExperimentalOnToolCallStart? experimentalOnToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? experimentalOnToolCallFinish,
  TelemetrySettings? telemetry,
  BodyInclusionPolicy bodyInclusion = const BodyInclusionPolicy.none(),
}) async {
  if (maxToolConcurrency < 1) {
    throw ArgumentError.value(
      maxToolConcurrency,
      'maxToolConcurrency',
      'must be positive',
    );
  }
  final telemetrySpan = startTelemetrySpan(
    telemetry,
    spanName: 'ai.generateText',
    attributes: {
      AiTelemetryKeys.modelProvider: model.provider,
      AiTelemetryKeys.modelId: model.modelId,
      if (telemetry?.captureInputs == true && prompt != null)
        'ai.prompt': prompt,
    },
  );
  final scope = OperationScope(
    abortSignal: abortSignal,
    timeout: timeout?.total,
  );
  final metricStopwatch = Stopwatch()..start();
  var retryCount = 0;
  var metricProvider = model.provider;
  var metricModelId = model.modelId;
  void recordMetric(
    String name,
    num value, {
    Map<String, TelemetryAttributeValue> attributes = const {},
  }) {
    recordTelemetryMetric(
      telemetry,
      TelemetryMetric(
        name: name,
        value: value,
        attributes: {
          AiTelemetryKeys.modelProvider: metricProvider,
          AiTelemetryKeys.modelId: metricModelId,
          AiTelemetryKeys.operation: 'generateText',
          ...attributes,
        },
      ),
    );
  }

  try {
    final overallStopwatch = Stopwatch()..start();
    final outputSpec = output ?? (Output.text() as Output<TOutput>);
    final responseMessages = <LanguageModelV4Message>[];
    var normalizedMessages = <LanguageModelV4Message>[
      if (prompt != null)
        LanguageModelV4Message(
          role: LanguageModelV4Role.user,
          content: [LanguageModelV4TextPart(text: prompt)],
        ),
      ...?messages?.map(toLanguageModelMessage),
    ];

    rejectSystemMessages(
      messages ?? const [],
      allowSystemInMessages: allowSystemInMessages,
    );

    var currentInstructions = instructions ?? system;
    final initialInstructions = currentInstructions;
    final approvalById = indexApprovalResponses(toolApprovalResponses);

    safeInvoke(
      () => (onStart ?? experimentalOnStart)?.call(
        GenerateTextExperimentalStartEvent(
          model: model,
          system: buildOutputSystemInstruction(currentInstructions, outputSpec),
          instructions: currentInstructions,
          prompt: prompt,
          messages: List.unmodifiable(normalizedMessages),
          runtimeContext: runtimeContext,
          generationContext: generationContext,
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
      final responseMessageStart = responseMessages.length;
      throwIfCancelled(scope.signal);
      final prepareResult = await scope.run(
        () async => prepareStep?.call(
          GenerateTextPrepareStepContext(
            model: model,
            stepNumber: stepNumber,
            steps: List.unmodifiable(steps),
            messages: List.unmodifiable(normalizedMessages),
            stopConditions: allStopConditions,
            instructions: currentInstructions,
            runtimeContext: runtimeContext,
            generationContext: generationContext,
          ),
        ),
        raceCancellation: true,
      );

      if (prepareResult?.instructions case final override?) {
        currentInstructions = override;
      }

      final stepModel = prepareResult?.model ?? model;
      metricProvider = stepModel.provider;
      metricModelId = stepModel.modelId;
      final stepToolChoice = prepareResult?.toolChoice ?? toolChoice;
      final stepMessages = prepareResult?.messages ?? normalizedMessages;
      if (!allowSystemInMessages &&
          stepMessages.any(
            (message) => message.role == LanguageModelV4Role.system,
          )) {
        throw ArgumentError(
          'System-role messages are rejected by default. Set '
          'allowSystemInMessages: true for trusted legacy histories.',
        );
      }
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
        () => (onStepStart ?? experimentalOnStepStart)?.call(
          GenerateTextExperimentalStepStartEvent(
            stepNumber: stepNumber,
            model: stepModel,
            messages: List.unmodifiable(stepMessages),
            steps: List.unmodifiable(steps),
            instructions: currentInstructions,
          ),
        ),
      );

      final callOptions = LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          system: buildOutputSystemInstruction(currentInstructions, outputSpec),
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
        abortSignal: scope.signal,
        reasoning: reasoning,
      );
      final response = await scope.run(
        () => withRetry(
          maxRetries: maxRetries,
          totalTimeout: remainingTimeout(
            timeout: timeout?.total,
            elapsed: overallStopwatch.elapsed,
          ),
          stepTimeout: timeout?.step,
          abortSignal: scope.signal,
          onRetry: () => retryCount++,
          fn: (attemptTimeout) {
            final call = stepModel.doGenerate(callOptions);
            unawaited(call.then((_) {}, onError: (_) {}));
            if (attemptTimeout == null) return call;
            return call.timeout(
              attemptTimeout,
              onTimeout: () {
                scheduleMicrotask(scope.signal.cancel);
                throw TimeoutException('Model step timed out.', attemptTimeout);
              },
            );
          },
        ),
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
      final providerToolResults = response.content
          .whereType<LanguageModelV4ToolResultPart>()
          .toList(growable: false);
      final toolResults = <LanguageModelV4ToolResultPart>[];
      final approvalRequests = <LanguageModelV4ToolApprovalRequestPart>[];
      final stepContent = <LanguageModelV4ContentPart>[...response.content];

      normalizedMessages = [
        ...stepMessages,
        LanguageModelV4Message(
          role: LanguageModelV4Role.assistant,
          content: stepContent,
        ),
      ];
      responseMessages.add(normalizedMessages.last);

      if (toolCalls.isNotEmpty) {
        final executableCalls = toolCalls
            .where((call) => !isProviderExecutedToolCall(call))
            .toList(growable: false);
        final executions = await executeToolCallsBounded(
          calls: executableCalls,
          maxConcurrency: maxToolConcurrency,
          abortSignal: scope.signal,
          execute: (call) => executeToolCall(
            tools: toolSelection.exposedTools,
            call: call,
            messages: normalizedMessages,
            approvalById: approvalById,
            abortSignal: scope.signal,
            timeout: minTimeout(
              remainingTimeout(
                timeout: timeout?.total,
                elapsed: overallStopwatch.elapsed,
              ),
              timeout?.toolTimeoutFor(call.toolName),
            ),
            approvalPolicy:
                approvalPolicyFor?.call(call.toolName, call.input) ??
                approvalPolicy,
            policyRevision: approvalPolicyRevision,
            generationContext: generationContext ?? runtimeContext,
            runtimeContext: runtimeContext,
            requireExactApprovalBinding: true,
            onToolCallStart:
                onToolExecutionStart ?? experimentalOnToolCallStart,
            onToolCallFinish:
                onToolExecutionEnd ?? experimentalOnToolCallFinish,
          ),
        );
        for (final execution in executions) {
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
        responseMessages.add(normalizedMessages.last);
      }

      final stepText = _contentToText(stepContent);
      final publicResponse = _bodyFilteredResult(response, bodyInclusion);
      final step = GenerateTextStep(
        stepNumber: stepNumber,
        content: stepContent,
        toolCalls: toolCalls.toList(),
        toolResults: [...providerToolResults, ...toolResults],
        toolApprovalRequests: approvalRequests,
        response: publicResponse,
        responseMessages: List.unmodifiable(
          responseMessages.skip(responseMessageStart),
        ),
        text: stepText,
        finishReason: response.finishReason,
        usage: response.usage,
      );
      steps.add(step);

      safeInvoke(
        () => (onStepEnd ?? onStepFinish)?.call(
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
        toolResultsEmpty: providerToolResults.isEmpty && toolResults.isEmpty,
        hasApprovalRequests: approvalRequests.isNotEmpty,
        snapshot: snapshot,
        conditions: allStopConditions,
      );
      if (shouldStop) {
        break;
      }
    }

    final text = _contentToText(lastContent);
    throwIfCancelled(scope.signal);
    scope.checkDeadline();
    final parsedOutput = parseOutputWithNoObjectError(
      output: outputSpec,
      text: text,
      usage: lastResponse?.usage,
      response: lastResponse?.response,
    );
    scope.checkDeadline();
    final totalUsage = sumUsage(steps.map((step) => step.usage));
    final aggregateContent = steps
        .expand((step) => step.content)
        .toList(growable: false);
    final aggregateToolCalls = steps
        .expand((step) => step.toolCalls)
        .toList(growable: false);
    final aggregateToolResults = steps
        .expand((step) => step.toolResults)
        .toList(growable: false);
    final aggregateSources = steps
        .expand((step) => step.sources)
        .toList(growable: false);
    final aggregateFiles = steps
        .expand((step) => step.files)
        .toList(growable: false);
    final aggregateWarnings = steps
        .expand((step) => step.warnings)
        .toList(growable: false);
    final request = GenerateTextRequest(
      system: buildOutputSystemInstruction(initialInstructions, outputSpec),
      messages: List.unmodifiable(firstRequestMessages ?? normalizedMessages),
      body: bodyInclusion.requestBody ? lastResponse?.request?.body : null,
    );
    final responseInfo = GenerateTextResponse(
      messages: List.unmodifiable(responseMessages),
      body: bodyInclusion.responseBody ? lastResponse?.response?.body : null,
      metadata: _filteredResponseMetadata(
        lastResponse?.response,
        bodyInclusion,
      ),
    );

    final result = GenerateTextResult<TOutput>(
      text: text,
      output: parsedOutput,
      content: List.unmodifiable(aggregateContent),
      toolCalls: List.unmodifiable(aggregateToolCalls),
      toolResults: List.unmodifiable(aggregateToolResults),
      toolApprovalRequests: List.unmodifiable(
        aggregateContent.whereType<LanguageModelV4ToolApprovalRequestPart>(),
      ),
      steps: steps,
      sources: List.unmodifiable(aggregateSources),
      documentSources: List.unmodifiable(
        steps.expand((step) => step.documentSources),
      ),
      files: List.unmodifiable(aggregateFiles),
      reasoningFiles: List.unmodifiable(
        steps.expand((step) => step.reasoningFiles),
      ),
      reasoning: List.unmodifiable(
        lastContent.whereType<LanguageModelV4ReasoningPart>(),
      ),
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
      response: lastResponse == null
          ? null
          : _bodyFilteredResult(lastResponse, bodyInclusion),
      usage: totalUsage,
      totalUsage: totalUsage,
      finishReason: lastResponse?.finishReason,
      rawFinishReason: lastResponse?.rawFinishReason,
      warnings: List.unmodifiable(aggregateWarnings),
      providerMetadata: lastResponse?.providerMetadata,
    );

    safeInvoke(
      () => (onEnd ?? onFinish)?.call(
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
    throwIfCancelled(scope.signal);
    scope.checkDeadline();

    telemetrySpan
      ..setAttribute(
        AiTelemetryKeys.promptTokens,
        result.totalUsage?.inputTokens.total,
      )
      ..setAttribute(
        AiTelemetryKeys.completionTokens,
        result.totalUsage?.outputTokens.total,
      );
    telemetrySpan
      ..setAttribute(AiTelemetryKeys.stepCount, result.steps.length)
      ..setAttribute('ai.finishReason', result.finishReason?.name ?? 'unknown')
      ..end();
    recordMetric(
      AiTelemetryMetrics.totalMs,
      metricStopwatch.elapsedMicroseconds / 1000,
      attributes: {AiTelemetryKeys.operationStatus: 'success'},
    );
    recordMetric(AiTelemetryMetrics.stepCount, result.steps.length);
    recordMetric(AiTelemetryMetrics.toolCount, result.toolCalls.length);
    recordMetric(AiTelemetryMetrics.retryCount, retryCount);
    recordMetric(
      AiTelemetryMetrics.usageKnown,
      result.totalUsage == null ? 0 : 1,
    );
    recordMetric(AiTelemetryMetrics.success, 1);

    return result;
  } catch (e, st) {
    final filtered = filterBodyBearingError(e, bodyInclusion);
    final cancelled = scope.signal.isCancelled;
    recordMetric(
      AiTelemetryMetrics.totalMs,
      metricStopwatch.elapsedMicroseconds / 1000,
      attributes: {
        AiTelemetryKeys.operationStatus: cancelled ? 'cancelled' : 'failure',
      },
    );
    recordMetric(
      cancelled ? AiTelemetryMetrics.cancelled : AiTelemetryMetrics.failure,
      1,
    );
    telemetrySpan
      ..recordException(filtered, stackTrace: st)
      ..end(error: filtered);
    Error.throwWithStackTrace(filtered, st);
  } finally {
    scope.close();
  }
}

LanguageModelV4GenerateResult _bodyFilteredResult(
  LanguageModelV4GenerateResult result,
  BodyInclusionPolicy policy,
) => LanguageModelV4GenerateResult(
  content: result.content,
  finishReason: result.finishReason,
  rawFinishReason: result.rawFinishReason,
  usage: result.usage,
  warnings: result.warnings,
  request: result.request == null
      ? null
      : LanguageModelV4RequestMetadata(
          body: policy.requestBody ? result.request!.body : null,
        ),
  response: result.response == null
      ? null
      : LanguageModelV4ResponseMetadata(
          id: result.response!.id,
          modelId: result.response!.modelId,
          timestamp: result.response!.timestamp,
          headers: result.response!.headers,
          body: policy.responseBody ? result.response!.body : null,
        ),
  providerMetadata: result.providerMetadata,
);

LanguageModelV4ResponseMetadata? _filteredResponseMetadata(
  LanguageModelV4ResponseMetadata? metadata,
  BodyInclusionPolicy policy,
) => metadata == null
    ? null
    : LanguageModelV4ResponseMetadata(
        id: metadata.id,
        modelId: metadata.modelId,
        timestamp: metadata.timestamp,
        headers: metadata.headers,
        body: policy.responseBody ? metadata.body : null,
      );

String _contentToText(List<LanguageModelV4ContentPart> content) {
  return content.whereType<LanguageModelV4TextPart>().map((p) => p.text).join();
}
