import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../errors/ai_errors.dart';
import '../messages/model_message.dart';
import '../output/output.dart';
import '../stop_conditions/stop_conditions.dart';
import '../tools/tool.dart';

typedef GenerateTextOnStepFinish =
    void Function(GenerateTextStepFinishEvent event);
typedef GenerateTextOnFinish<TOutput> =
    void Function(GenerateTextFinishEvent<TOutput> event);
typedef GenerateTextPrepareStep =
    FutureOr<GenerateTextPrepareStepResult?> Function(
      GenerateTextPrepareStepContext context,
    );
typedef GenerateTextExperimentalOnStart =
    void Function(GenerateTextExperimentalStartEvent event);
typedef GenerateTextExperimentalOnStepStart =
    void Function(GenerateTextExperimentalStepStartEvent event);
typedef GenerateTextExperimentalOnToolCallStart =
    void Function(GenerateTextExperimentalToolCallStartEvent event);
typedef GenerateTextExperimentalOnToolCallFinish =
    void Function(GenerateTextExperimentalToolCallFinishEvent event);

class GenerateTextPrepareStepContext {
  const GenerateTextPrepareStepContext({
    required this.model,
    required this.stepNumber,
    required this.steps,
    required this.messages,
    required this.stopConditions,
    this.experimentalContext,
  });

  final LanguageModelV3 model;
  final int stepNumber;
  final List<GenerateTextStep> steps;
  final List<LanguageModelV3Message> messages;
  final List<StopCondition> stopConditions;
  final Object? experimentalContext;
}

class GenerateTextPrepareStepResult {
  const GenerateTextPrepareStepResult({
    this.model,
    this.toolChoice,
    this.activeTools,
    this.messages,
    this.providerOptions,
  });

  final LanguageModelV3? model;
  final LanguageModelV3ToolChoice? toolChoice;
  final List<String>? activeTools;
  final List<LanguageModelV3Message>? messages;
  final ProviderOptions? providerOptions;
}

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
  final List<LanguageModelV3ToolCallPart> toolCalls;
  final List<LanguageModelV3ToolResultPart> toolResults;
  final LanguageModelV3FinishReason finishReason;
  final LanguageModelV3Usage? usage;
}

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
  final LanguageModelV3Usage? usage;
  final LanguageModelV3Usage? totalUsage;
  final LanguageModelV3FinishReason? finishReason;
  final GenerateTextResponse response;
}

class GenerateTextRequest {
  const GenerateTextRequest({
    required this.system,
    required this.messages,
    this.body,
  });

  final String? system;
  final List<LanguageModelV3Message> messages;
  final Object? body;
}

class GenerateTextResponse {
  const GenerateTextResponse({
    required this.messages,
    required this.body,
    required this.metadata,
  });

  final List<LanguageModelV3Message> messages;
  final Object? body;
  final LanguageModelV3ResponseMetadata? metadata;
}

class GenerateTextExperimentalStartEvent {
  const GenerateTextExperimentalStartEvent({
    required this.model,
    required this.system,
    required this.prompt,
    required this.messages,
    this.experimentalContext,
  });

  final LanguageModelV3 model;
  final String? system;
  final String? prompt;
  final List<LanguageModelV3Message> messages;
  final Object? experimentalContext;
}

class GenerateTextExperimentalStepStartEvent {
  const GenerateTextExperimentalStepStartEvent({
    required this.stepNumber,
    required this.model,
    required this.messages,
    required this.steps,
  });

  final int stepNumber;
  final LanguageModelV3 model;
  final List<LanguageModelV3Message> messages;
  final List<GenerateTextStep> steps;
}

class GenerateTextExperimentalToolCallStartEvent {
  const GenerateTextExperimentalToolCallStartEvent({
    required this.toolCall,
    required this.messages,
    required this.options,
  });

  final LanguageModelV3ToolCallPart toolCall;
  final List<LanguageModelV3Message> messages;
  final ToolExecutionOptions options;
}

class GenerateTextExperimentalToolCallFinishEvent {
  const GenerateTextExperimentalToolCallFinishEvent({
    required this.toolCall,
    required this.durationMs,
    required this.success,
    this.output,
    this.error,
  });

  final LanguageModelV3ToolCallPart toolCall;
  final int durationMs;
  final bool success;
  final Object? output;
  final Object? error;
}

/// Per-step details from `generateText` multi-step execution.
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
  final List<LanguageModelV3ContentPart> content;
  final List<LanguageModelV3ToolCallPart> toolCalls;
  final List<LanguageModelV3ToolResultPart> toolResults;
  final List<LanguageModelV3ToolApprovalRequestPart> toolApprovalRequests;
  final LanguageModelV3GenerateResult response;
  final String text;
  final LanguageModelV3FinishReason finishReason;
  final LanguageModelV3Usage? usage;
}

/// Result for `generateText`.
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
  final List<LanguageModelV3ContentPart> content;
  final List<LanguageModelV3ToolCallPart> toolCalls;
  final List<LanguageModelV3ToolResultPart> toolResults;
  final List<LanguageModelV3ToolApprovalRequestPart> toolApprovalRequests;
  final List<GenerateTextStep> steps;
  final List<LanguageModelV3SourcePart> sources;
  final List<LanguageModelV3FilePart> files;
  final List<LanguageModelV3ReasoningPart> reasoning;
  final String reasoningText;
  final List<LanguageModelV3Message> requestMessages;
  final List<LanguageModelV3Message> responseMessages;
  final GenerateTextRequest request;
  final GenerateTextResponse responseInfo;
  final LanguageModelV3GenerateResult? response;
  final LanguageModelV3Usage? usage;
  final LanguageModelV3Usage? totalUsage;
  final LanguageModelV3FinishReason? finishReason;
  final String? rawFinishReason;
  final List<String> warnings;
  final ProviderMetadata? providerMetadata;
}

/// Provider-agnostic text generation with output/tool support.
Future<GenerateTextResult<TOutput>> generateText<TOutput>({
  required LanguageModelV3 model,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  int? maxOutputTokens,
  double? temperature,
  double? topP,
  ProviderOptions? providerOptions,
  Output<TOutput>? output,
  ToolSet tools = const {},
  List<LanguageModelV3ProviderDefinedTool> providerDefinedTools = const [],
  int maxSteps = 1,
  List<StopCondition> stopConditions = const [],
  LanguageModelV3ToolChoice? toolChoice,
  List<LanguageModelV3ToolApprovalResponse> toolApprovalResponses = const [],
  Object? abortSignal,
  Object? experimentalContext,
  GenerateTextOnStepFinish? onStepFinish,
  GenerateTextOnFinish<TOutput>? onFinish,
  GenerateTextPrepareStep? prepareStep,
  GenerateTextExperimentalOnStart? experimentalOnStart,
  GenerateTextExperimentalOnStepStart? experimentalOnStepStart,
  GenerateTextExperimentalOnToolCallStart? experimentalOnToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? experimentalOnToolCallFinish,
}) async {
  final outputSpec = output ?? (Output.text() as Output<TOutput>);
  var normalizedMessages = <LanguageModelV3Message>[
    if (prompt != null)
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [LanguageModelV3TextPart(text: prompt)],
      ),
    ...?messages?.map(_toLanguageModelMessage),
  ];

  final systemInstruction = _buildOutputSystemInstruction(system, outputSpec);
  final approvalById = {
    for (final approval in toolApprovalResponses) approval.approvalId: approval,
  };

  _safeInvoke(
    () => experimentalOnStart?.call(
      GenerateTextExperimentalStartEvent(
        model: model,
        system: systemInstruction,
        prompt: prompt,
        messages: List.unmodifiable(normalizedMessages),
        experimentalContext: experimentalContext,
      ),
    ),
  );

  final steps = <GenerateTextStep>[];
  var lastContent = <LanguageModelV3ContentPart>[];
  List<LanguageModelV3Message>? firstRequestMessages;
  LanguageModelV3GenerateResult? lastResponse;

  final totalSteps = tools.isEmpty ? 1 : (maxSteps < 1 ? 1 : maxSteps);
  for (var stepNumber = 0; stepNumber < totalSteps; stepNumber++) {
    final prepareResult = await Future.value(
      prepareStep?.call(
        GenerateTextPrepareStepContext(
          model: model,
          stepNumber: stepNumber,
          steps: List.unmodifiable(steps),
          messages: List.unmodifiable(normalizedMessages),
          stopConditions: stopConditions,
          experimentalContext: experimentalContext,
        ),
      ),
    );

    final stepModel = prepareResult?.model ?? model;
    final stepToolChoice = prepareResult?.toolChoice ?? toolChoice;
    final stepMessages = prepareResult?.messages ?? normalizedMessages;
    firstRequestMessages ??= List<LanguageModelV3Message>.from(stepMessages);
    final stepProviderOptions =
        prepareResult?.providerOptions ?? providerOptions;
    final activeTools = _selectActiveTools(tools, prepareResult?.activeTools);
    final toolSelection = _resolveToolSelection(
      tools: activeTools,
      toolChoice: stepToolChoice,
    );

    _safeInvoke(
      () => experimentalOnStepStart?.call(
        GenerateTextExperimentalStepStartEvent(
          stepNumber: stepNumber,
          model: stepModel,
          messages: List.unmodifiable(stepMessages),
          steps: List.unmodifiable(steps),
        ),
      ),
    );

    final response = await stepModel.doGenerate(
      LanguageModelV3CallOptions(
        prompt: LanguageModelV3Prompt(
          system: systemInstruction,
          messages: stepMessages,
        ),
        tools: toolSelection.exposedTools.entries
            .map(
              (entry) => LanguageModelV3FunctionTool(
                name: entry.key,
                description: entry.value.description,
                inputSchema: entry.value.inputSchema.jsonSchema,
                strict: entry.value.strict,
                inputExamples: entry.value.inputExamples
                    .map((example) => example.input)
                    .toList(),
              ),
            )
            .toList(),
        providerDefinedTools: providerDefinedTools,
        toolChoice: toolSelection.toolChoice,
        maxOutputTokens: maxOutputTokens,
        temperature: temperature,
        topP: topP,
        providerOptions: stepProviderOptions,
      ),
    );

    _validateToolChoiceInResponse(
      response: response,
      tools: toolSelection.exposedTools,
      toolChoice: toolSelection.toolChoice,
      stepNumber: stepNumber,
    );

    lastResponse = response;
    final toolCalls = response.content.whereType<LanguageModelV3ToolCallPart>();
    final toolResults = <LanguageModelV3ToolResultPart>[];
    final approvalRequests = <LanguageModelV3ToolApprovalRequestPart>[];
    final stepContent = <LanguageModelV3ContentPart>[...response.content];

    normalizedMessages = [
      ...stepMessages,
      LanguageModelV3Message(
        role: LanguageModelV3Role.assistant,
        content: response.content,
      ),
    ];

    if (toolCalls.isNotEmpty) {
      for (final call in toolCalls) {
        final execution = await _executeToolCall(
          tools: toolSelection.exposedTools,
          call: call,
          messages: normalizedMessages,
          approvalById: approvalById,
          abortSignal: abortSignal,
          experimentalContext: experimentalContext,
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
        LanguageModelV3Message(
          role: LanguageModelV3Role.tool,
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

    _safeInvoke(
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
    );
    final shouldStop =
        toolResults.isEmpty ||
        approvalRequests.isNotEmpty ||
        stopConditions.any((condition) => condition(snapshot));
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
  final totalUsage = _sumUsage(steps.map((step) => step.usage));
  final responseMessages = normalizedMessages
      .where(
        (message) =>
            message.role == LanguageModelV3Role.assistant ||
            message.role == LanguageModelV3Role.tool,
      )
      .toList(growable: false);
  final request = GenerateTextRequest(
    system: systemInstruction,
    messages: List.unmodifiable(firstRequestMessages ?? normalizedMessages),
    body: lastResponse?.response?.requestBody,
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
    toolCalls: lastContent.whereType<LanguageModelV3ToolCallPart>().toList(),
    toolResults: lastContent
        .whereType<LanguageModelV3ToolResultPart>()
        .toList(),
    toolApprovalRequests: lastContent
        .whereType<LanguageModelV3ToolApprovalRequestPart>()
        .toList(),
    steps: steps,
    sources: lastContent.whereType<LanguageModelV3SourcePart>().toList(),
    files: lastContent.whereType<LanguageModelV3FilePart>().toList(),
    reasoning: lastContent.whereType<LanguageModelV3ReasoningPart>().toList(),
    reasoningText: lastContent
        .where(
          (part) =>
              part is LanguageModelV3ReasoningPart ||
              part is LanguageModelV3RedactedReasoningPart,
        )
        .map(
          (part) =>
              part is LanguageModelV3ReasoningPart ? part.text : '[REDACTED]',
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
    warnings: lastResponse?.warnings ?? const [],
    providerMetadata: lastResponse?.providerMetadata,
  );

  _safeInvoke(
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

  return result;
}

class _ToolSelection {
  const _ToolSelection({required this.exposedTools, required this.toolChoice});

  final ToolSet exposedTools;
  final LanguageModelV3ToolChoice? toolChoice;
}

class _ToolExecutionResult {
  const _ToolExecutionResult({this.toolResult, this.approvalRequest});

  final LanguageModelV3ToolResultPart? toolResult;
  final LanguageModelV3ToolApprovalRequestPart? approvalRequest;
}

class _ToolOutputResolution {
  const _ToolOutputResolution({required this.finalOutput});

  final Object? finalOutput;
}

ToolSet _selectActiveTools(ToolSet tools, List<String>? activeToolNames) {
  if (activeToolNames == null) {
    return tools;
  }
  final selected = <String, Tool<dynamic, dynamic>>{};
  for (final toolName in activeToolNames) {
    final tool = tools[toolName];
    if (tool == null) {
      throw AiNoSuchToolError('Active tool "$toolName" was not found.');
    }
    selected[toolName] = tool;
  }
  return selected;
}

_ToolSelection _resolveToolSelection({
  required ToolSet tools,
  required LanguageModelV3ToolChoice? toolChoice,
}) {
  final choice = toolChoice;
  if (choice == null || choice is ToolChoiceAuto) {
    return _ToolSelection(exposedTools: tools, toolChoice: choice);
  }
  if (choice is ToolChoiceNone) {
    return const _ToolSelection(exposedTools: {}, toolChoice: ToolChoiceNone());
  }
  if (choice is ToolChoiceRequired) {
    if (tools.isEmpty) {
      throw const AiNoSuchToolError(
        'toolChoice "required" cannot be used without tools.',
      );
    }
    return _ToolSelection(exposedTools: tools, toolChoice: choice);
  }
  if (choice is ToolChoiceSpecific) {
    final tool = tools[choice.toolName];
    if (tool == null) {
      throw AiNoSuchToolError(
        'toolChoice requested unknown tool "${choice.toolName}".',
      );
    }
    return _ToolSelection(
      exposedTools: {choice.toolName: tool},
      toolChoice: choice,
    );
  }
  return _ToolSelection(exposedTools: tools, toolChoice: choice);
}

void _validateToolChoiceInResponse({
  required LanguageModelV3GenerateResult response,
  required ToolSet tools,
  required LanguageModelV3ToolChoice? toolChoice,
  required int stepNumber,
}) {
  final toolCalls = response.content.whereType<LanguageModelV3ToolCallPart>();
  if (toolChoice is ToolChoiceNone && toolCalls.isNotEmpty) {
    throw AiApiCallError(
      'Step $stepNumber produced tool calls while toolChoice is none.',
    );
  }
  if (toolChoice is ToolChoiceRequired && toolCalls.isEmpty) {
    throw AiApiCallError(
      'Step $stepNumber produced no tool calls while toolChoice is required.',
    );
  }
  if (toolChoice is ToolChoiceSpecific) {
    for (final call in toolCalls) {
      if (call.toolName != toolChoice.toolName) {
        throw AiApiCallError(
          'Step $stepNumber called "${call.toolName}" but toolChoice '
          'requires "${toolChoice.toolName}".',
        );
      }
    }
  }
  for (final call in toolCalls) {
    if (!tools.containsKey(call.toolName)) {
      throw AiNoSuchToolError(
        'Step $stepNumber called unknown tool "${call.toolName}".',
      );
    }
  }
}

Future<_ToolExecutionResult> _executeToolCall({
  required ToolSet tools,
  required LanguageModelV3ToolCallPart call,
  required List<LanguageModelV3Message> messages,
  required Map<String, LanguageModelV3ToolApprovalResponse> approvalById,
  Object? abortSignal,
  Object? experimentalContext,
  GenerateTextExperimentalOnToolCallStart? onToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? onToolCallFinish,
}) async {
  final tool = tools[call.toolName];
  if (tool == null) {
    return _ToolExecutionResult(
      toolResult: LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: const ToolResultOutputText('Tool not found.'),
      ),
    );
  }

  final approvalId = 'approval_${call.toolCallId}';
  final rawInput = call.input;

  try {
    final parsedInput = _parseToolInput(tool: tool, rawInput: rawInput);
    final options = ToolExecutionOptions(
      toolCallId: call.toolCallId,
      messages: messages,
      abortSignal: abortSignal,
      experimentalContext: experimentalContext,
    );

    final approvalEvaluator = tool.needsApprovalDynamic;
    final approvalResponse = approvalById[approvalId];
    if (tool.requiresApproval && approvalResponse == null) {
      return _ToolExecutionResult(
        approvalRequest: LanguageModelV3ToolApprovalRequestPart(
          approvalId: approvalId,
          toolCall: call,
        ),
      );
    }

    var needsApproval = false;
    if (approvalEvaluator != null) {
      needsApproval = await Future.value(
        approvalEvaluator(parsedInput, options),
      );
    }
    if (tool.requiresApproval &&
        approvalResponse != null &&
        !approvalResponse.approved) {
      return _ToolExecutionResult(
        toolResult: LanguageModelV3ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: ToolResultOutputText(
            approvalResponse.reason ?? 'Tool execution denied.',
          ),
        ),
      );
    }

    if (tool.requiresApproval && needsApproval && approvalResponse == null) {
      return _ToolExecutionResult(
        approvalRequest: LanguageModelV3ToolApprovalRequestPart(
          approvalId: approvalId,
          toolCall: call,
        ),
      );
    }

    final executor = tool.executeDynamic;
    if (executor == null) {
      return _ToolExecutionResult(
        toolResult: LanguageModelV3ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: const ToolResultOutputText('Tool has no executor.'),
        ),
      );
    }

    _safeInvoke(
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
      final output = await executor(parsedInput, options);
      final resolved = await _resolveFinalToolOutput(output);
      stopwatch.stop();
      _safeInvoke(
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
        toolResult: LanguageModelV3ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          output: ToolResultOutputText(
            _stringifyToolOutput(resolved.finalOutput),
          ),
        ),
      );
    } catch (error) {
      stopwatch.stop();
      _safeInvoke(
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
    return _ToolExecutionResult(
      toolResult: LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: ToolResultOutputText(error.toString()),
      ),
    );
  }
}

Future<_ToolOutputResolution> _resolveFinalToolOutput(Object? output) async {
  if (output is Stream) {
    Object? last;
    var seenAny = false;
    await for (final item in output) {
      seenAny = true;
      last = item;
    }
    return _ToolOutputResolution(finalOutput: seenAny ? last : null);
  }
  return _ToolOutputResolution(finalOutput: output);
}

dynamic _parseToolInput({
  required Tool<dynamic, dynamic> tool,
  required Object rawInput,
}) {
  if (tool.dynamic) {
    if (tool.strict == true && rawInput is! Map) {
      throw const AiInvalidToolInputError(
        'Strict dynamic tools require JSON object input.',
      );
    }
    return rawInput;
  }
  if (rawInput is! Map) {
    throw const AiInvalidToolInputError('Tool input is not a JSON object.');
  }
  return tool.inputSchema.fromJson(rawInput.cast<String, dynamic>());
}

LanguageModelV3Message _toLanguageModelMessage(ModelMessage message) {
  return LanguageModelV3Message(
    role: switch (message.role) {
      ModelMessageRole.system => LanguageModelV3Role.system,
      ModelMessageRole.user => LanguageModelV3Role.user,
      ModelMessageRole.assistant => LanguageModelV3Role.assistant,
      ModelMessageRole.tool => LanguageModelV3Role.tool,
    },
    content:
        message.parts ?? [LanguageModelV3TextPart(text: message.content ?? '')],
  );
}

void _safeInvoke(void Function() action) {
  try {
    action();
  } catch (_) {}
}

String _contentToText(List<LanguageModelV3ContentPart> content) {
  return content.whereType<LanguageModelV3TextPart>().map((p) => p.text).join();
}

String _stringifyToolOutput(Object? output) {
  if (output == null) return 'null';
  if (output is String) return output;
  if (output is num || output is bool) return output.toString();
  try {
    return jsonEncode(output);
  } catch (_) {
    return output.toString();
  }
}

String _buildOutputSystemInstruction<T>(String? system, Output<T> output) {
  switch (output) {
    case TextOutput():
      return system ?? '';
    case ObjectOutput<T>(:final schema):
      return [
        if (system != null && system.isNotEmpty) system,
        'Return a single JSON object that matches this schema exactly:',
        jsonEncode(schema.jsonSchema),
        'Do not include markdown fences or extra text.',
      ].join('\n');
    case ArrayOutput(:final element):
      return [
        if (system != null && system.isNotEmpty) system,
        'Return a single JSON array where each element matches this schema exactly:',
        jsonEncode(element.jsonSchema),
        'Do not include markdown fences or extra text.',
      ].join('\n');
    case ChoiceOutput(:final options):
      return [
        if (system != null && system.isNotEmpty) system,
        'Return exactly one of these values:',
        options.join(', '),
        'Do not include markdown fences or extra text.',
      ].join('\n');
    case JsonOutput():
      return [
        if (system != null && system.isNotEmpty) system,
        'Return valid JSON only. Do not include markdown fences or extra text.',
      ].join('\n');
  }
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
        } else if (item is Map) {
          list.add(element.fromJson(item.cast<String, dynamic>()));
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
  required LanguageModelV3GenerateResult? response,
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
  if (parsed is Map) {
    return parsed.cast<String, dynamic>();
  }
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

LanguageModelV3Usage? _sumUsage(Iterable<LanguageModelV3Usage?> usages) {
  var input = 0;
  var output = 0;
  var total = 0;
  var hasAny = false;

  for (final usage in usages) {
    if (usage == null) {
      continue;
    }
    hasAny = true;
    input += usage.inputTokens ?? 0;
    output += usage.outputTokens ?? 0;
    total += usage.totalTokens ?? 0;
  }

  if (!hasAny) {
    return null;
  }

  return LanguageModelV3Usage(
    inputTokens: input == 0 ? null : input,
    outputTokens: output == 0 ? null : output,
    totalTokens: total == 0 ? null : total,
  );
}
