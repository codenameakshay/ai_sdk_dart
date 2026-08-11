import 'dart:convert';
import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'cancellation.dart';
import '../messages/model_message.dart';
import '../output/output.dart';
import '../stop_conditions/stop_conditions.dart';
import '../telemetry/telemetry.dart';
import '../tools/tool.dart';
import 'generate_text.dart';
import 'partial_json.dart';
import 'retry_helper.dart';
import 'shared/common_helpers.dart';
import 'shared/output_instruction.dart';
import 'shared/tool_selection.dart';
import 'streaming/stream_text_types.dart';
import 'streaming/structured_output.dart';
import 'streaming/terminal_streams.dart';
import 'streaming/tool_execution.dart';
import 'timeout_configuration.dart';
import 'timeout_helpers.dart';

export 'streaming/stream_text_types.dart';

/// Streams text from a given prompt and model.
///
/// Mirrors `streamText` from the JS AI SDK v6. Ideal for interactive use cases
/// (chatbots, real-time apps) where users expect immediate responses.
/// Supports [Output], tools, multi-step generation, and lifecycle callbacks.
///
/// Example:
/// ```dart
/// final result = await streamText(
///   model: model,
///   prompt: 'Invent a new holiday and describe its traditions.',
/// );
/// await for (final chunk in result.textStream) {
///   print(chunk);
/// }
/// ```
Future<StreamTextResult<TOutput>> streamText<TOutput>({
  required LanguageModelV4 model,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  Output<TOutput>? output,
  ProviderOptions? providerOptions,
  LanguageModelV4Reasoning reasoning = LanguageModelV4Reasoning.providerDefault,
  bool includeRawChunks = false,
  ToolSet tools = const {},
  List<LanguageModelV4ProviderDefinedTool> providerDefinedTools = const [],
  LanguageModelV4ToolChoice? toolChoice,
  int maxSteps = 1,
  List<StopCondition> stopConditions = const [],
  Object? stopWhen, // StopCondition | List<StopCondition>
  List<LanguageModelV4ToolApprovalResponse> toolApprovalResponses = const [],
  CancellationToken? abortSignal,
  Map<String, Object?>? runtimeContext,
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
  StreamTextOnChunk? onChunk,
  StreamTextOnError? onError,
  StreamTextOnAbort? onAbort,
  StreamTextOnFinish<TOutput>? onFinish,
  GenerateTextOnStepFinish? onStepFinish,
  GenerateTextPrepareStep? prepareStep,
  StreamTextOnInputStart? onInputStart,
  StreamTextOnInputDelta? onInputDelta,
  StreamTextOnInputAvailable? onInputAvailable,
  StreamTextTransform? experimentalTransform,
  TimeoutConfiguration? timeout,
  GenerateTextExperimentalOnStart? experimentalOnStart,
  GenerateTextExperimentalOnStepStart? experimentalOnStepStart,
  GenerateTextExperimentalOnToolCallStart? experimentalOnToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? experimentalOnToolCallFinish,
  TelemetrySettings? telemetry,
}) async {
  final telemetrySpan = startTelemetrySpan(
    telemetry,
    spanName: 'ai.streamText',
    attributes: {
      'ai.model.provider': model.provider,
      'ai.model.id': model.modelId,
      'ai.prompt': ?prompt,
    },
  );

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
    for (final approval in toolApprovalResponses) approval.approvalId: approval,
  };

  final rawController = StreamController<LanguageModelV4StreamPart>.broadcast();
  final textController = StreamController<String>.broadcast();
  final fullController = StreamController<StreamTextEvent>.broadcast();
  final partialController = StreamController<Object?>.broadcast();
  final elementController = StreamController<Object?>.broadcast();

  final textCompleter = Completer<String>();
  final outputCompleter = Completer<TOutput>();
  final finishCompleter = Completer<StreamPartFinish?>();
  final contentCompleter = Completer<List<LanguageModelV4ContentPart>>();
  final reasoningCompleter = Completer<List<LanguageModelV4ReasoningPart>>();
  final reasoningTextCompleter = Completer<String>();
  final filesCompleter = Completer<List<LanguageModelV4FilePart>>();
  final sourcesCompleter = Completer<List<LanguageModelV4SourcePart>>();
  final toolCallsCompleter = Completer<List<LanguageModelV4ToolCallPart>>();
  final toolResultsCompleter = Completer<List<LanguageModelV4ToolResultPart>>();
  final finishReasonCompleter = Completer<LanguageModelV4FinishReason?>();
  final rawFinishReasonCompleter = Completer<String?>();
  final usageCompleter = Completer<LanguageModelV4Usage?>();
  final totalUsageCompleter = Completer<LanguageModelV4Usage?>();
  final warningsCompleter = Completer<List<LanguageModelV4Warning>>();
  final stepsCompleter = Completer<List<GenerateTextStep>>();
  final requestCompleter = Completer<GenerateTextRequest>();
  final responseCompleter = Completer<GenerateTextResponse>();
  final providerMetadataCompleter = Completer<ProviderMetadata?>();
  var isTerminal = false;
  Object? terminalError;
  StackTrace? terminalStackTrace;
  StreamTextErrorEvent? terminalFullStreamErrorEvent;

  observeFutureError(textCompleter.future);
  observeFutureError(outputCompleter.future);
  observeFutureError(contentCompleter.future);
  observeFutureError(reasoningCompleter.future);
  observeFutureError(reasoningTextCompleter.future);
  observeFutureError(filesCompleter.future);
  observeFutureError(sourcesCompleter.future);
  observeFutureError(toolCallsCompleter.future);
  observeFutureError(toolResultsCompleter.future);
  observeFutureError(finishReasonCompleter.future);
  observeFutureError(rawFinishReasonCompleter.future);
  observeFutureError(usageCompleter.future);
  observeFutureError(totalUsageCompleter.future);
  observeFutureError(warningsCompleter.future);
  observeFutureError(stepsCompleter.future);
  observeFutureError(requestCompleter.future);
  observeFutureError(responseCompleter.future);
  observeFutureError(providerMetadataCompleter.future);
  observeFutureError(finishCompleter.future);

  // Wire onAbort: fire when the caller cancels via abortSignal.
  if (abortSignal != null && onAbort != null) {
    unawaited(
      abortSignal.onCancelled.then((_) {
        if (!isTerminal) {
          safeInvoke(onAbort);
        }
      }),
    );
  }

  final runFuture = Future<void>(() async {
    final overallStopwatch = Stopwatch()..start();
    final steps = <GenerateTextStep>[];
    final overallTextBuffer = StringBuffer();
    final partialJsonTracker = PartialJsonTracker();
    final partialArrayTracker = outputSpec is ArrayOutput
        ? PartialJsonArrayTracker()
        : null;
    final partialArrayValues = <dynamic>[];
    var lastArraySnapshotLength = -1;
    String? lastPartialFingerprint;
    StreamPartFinish? lastFinishPart;
    var lastContent = <LanguageModelV4ContentPart>[];
    Object? lastRequestBody;
    Object? lastResponseBody;
    LanguageModelV4ResponseMetadata? lastResponseMetadata;
    var lastWarnings = <LanguageModelV4Warning>[];

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

    try {
      throwIfCancelled(abortSignal);
      fullController.add(const StreamTextStartEvent());

      final allStopConditions = resolveStopConditions(stopWhen, stopConditions);
      final totalSteps = resolveStepBudget(
        hasTools: tools.isNotEmpty,
        stopWhen: stopWhen,
        maxSteps: maxSteps,
      );
      for (var stepNumber = 0; stepNumber < totalSteps; stepNumber++) {
        throwIfCancelled(abortSignal);
        fullController.add(StreamTextStartStepEvent(stepNumber: stepNumber));

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

        final streamCallOptions = LanguageModelV4CallOptions(
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
          includeRawChunks: includeRawChunks,
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
            final call = stepModel.doStream(streamCallOptions);
            return attemptTimeout != null ? call.timeout(attemptTimeout) : call;
          },
        );
        lastRequestBody = response.request?.body;
        lastResponseBody = response.response?.body;
        lastWarnings = List<LanguageModelV4Warning>.from(response.warnings);
        lastResponseMetadata = response.response;

        final stepTextById = <String, StringBuffer>{};
        final stepToolCalls = <LanguageModelV4ToolCallPart>[];
        final stepToolResults = <LanguageModelV4ToolResultPart>[];
        final stepApprovalRequests = <LanguageModelV4ToolApprovalRequestPart>[];
        final stepContent = <LanguageModelV4ContentPart>[];
        final toolInputBuffers = <String, StringBuffer>{};
        final toolInputNames = <String, String>{};
        final reasoningBuffers = <String, StringBuffer>{};
        StreamPartFinish? stepFinishPart;

        final iterator = StreamIterator<LanguageModelV4StreamPart>(
          response.stream,
        );
        var sawStreamPart = false;
        try {
          while (await _moveNextWithStreamTimeout(
            iterator,
            abortSignal: abortSignal,
            timeout: sawStreamPart ? timeout?.chunk : timeout?.firstChunk,
            totalTimeout: timeout?.total,
            overallStopwatch: overallStopwatch,
          )) {
            final part = iterator.current;
            sawStreamPart = true;
            rawController.add(part);
            if (part case StreamPartRaw(:final rawValue)) {
              fullController.add(StreamTextRawEvent(rawValue: rawValue));
              onChunk?.call(StreamTextRawChunk(rawValue: rawValue));
            }

            switch (part) {
              case StreamPartTextStart(:final id):
                stepTextById[id] = StringBuffer();
                fullController.add(StreamTextTextStartEvent(id: id));
              case StreamPartTextDelta(:final id, :final delta):
                final transformedStream =
                    experimentalTransform?.call(delta) ?? Stream.value(delta);
                final transformedIterator = StreamIterator<String>(
                  transformedStream,
                );
                try {
                  while (await moveNextOrCancellation(
                    transformedIterator,
                    abortSignal,
                  )) {
                    final transformedDelta = transformedIterator.current;
                    final textBuffer = stepTextById.putIfAbsent(
                      id,
                      StringBuffer.new,
                    );
                    textBuffer.write(transformedDelta);
                    overallTextBuffer.write(transformedDelta);
                    textController.add(transformedDelta);
                    fullController.add(
                      StreamTextTextDeltaEvent(id: id, delta: transformedDelta),
                    );
                    onChunk?.call(
                      StreamTextTextChunk(id: id, text: transformedDelta),
                    );

                    if (outputSpec is! TextOutput &&
                        partialArrayTracker != null) {
                      final update = partialArrayTracker.append(
                        transformedDelta,
                        phase: PartialJsonParsePhase.streamTextArrayElements,
                        trigger: PartialJsonParseTrigger.arrayElementBoundary,
                      );

                      if (update.newElements.isNotEmpty) {
                        final acceptedCount = emitTrackedArrayElements(
                          output: outputSpec as ArrayOutput<dynamic>,
                          elements: update.newElements,
                          partialValues: partialArrayValues,
                          onElement: elementController.add,
                        );
                        if (acceptedCount > 0) {
                          lastArraySnapshotLength = partialArrayValues.length;
                          partialController.add(
                            createTrackedImmutableSnapshot(partialArrayValues),
                          );
                        }
                      } else if (update.isClosed &&
                          lastArraySnapshotLength !=
                              partialArrayValues.length) {
                        lastArraySnapshotLength = partialArrayValues.length;
                        partialController.add(
                          createTrackedImmutableSnapshot(partialArrayValues),
                        );
                      }
                    } else if (outputSpec is! TextOutput) {
                      final cadence = partialJsonTracker.append(
                        transformedDelta,
                      );
                      final fullText = overallTextBuffer.toString();

                      if (cadence.shouldAttemptValue) {
                        final partial = tryParseStreamingPartialOutput(
                          outputSpec,
                          fullText,
                        );
                        if (partial != null) {
                          final fingerprint = partialJsonFingerprint(partial);
                          if (fingerprint != lastPartialFingerprint) {
                            lastPartialFingerprint = fingerprint;
                            partialController.add(partial);
                          }
                        }
                      }
                    }
                  }
                } finally {
                  await transformedIterator.cancel();
                }
              case StreamPartTextEnd(:final id):
                final text = stepTextById[id]?.toString() ?? '';
                stepContent.add(LanguageModelV4TextPart(text: text));
                fullController.add(StreamTextTextEndEvent(id: id));
              case StreamPartReasoningStart(:final id):
                reasoningBuffers[id] = StringBuffer();
                fullController.add(StreamTextReasoningStartEvent(id: id));
              case StreamPartReasoningDelta(:final id, :final delta):
                final buffer = reasoningBuffers.putIfAbsent(id, () {
                  fullController.add(StreamTextReasoningStartEvent(id: id));
                  return StringBuffer();
                });
                buffer.write(delta);
                fullController.add(
                  StreamTextReasoningDeltaEvent(id: id, delta: delta),
                );
                onChunk?.call(StreamTextReasoningChunk(delta: delta));
              case StreamPartReasoningEnd(:final id):
                final text = reasoningBuffers.remove(id)?.toString() ?? '';
                stepContent.add(LanguageModelV4ReasoningPart(text: text));
                fullController.add(StreamTextReasoningEndEvent(id: id));
              case StreamPartSource(:final source):
                stepContent.add(source);
                fullController.add(StreamTextSourceEvent(source: source));
                onChunk?.call(StreamTextSourceChunk(source: source));
              case StreamPartFile(:final file):
                stepContent.add(file);
                fullController.add(StreamTextFileEvent(file: file));
                onChunk?.call(StreamTextFileChunk(file: file));
              case StreamPartToolInputStart(:final id, :final toolName):
                toolInputBuffers[id] = StringBuffer();
                toolInputNames[id] = toolName;
                final event = StreamTextToolInputStartEvent(
                  toolCallId: id,
                  toolName: toolName,
                );
                fullController.add(event);
                onInputStart?.call(event);
                onChunk?.call(
                  StreamTextToolInputStartChunk(
                    toolCallId: id,
                    toolName: toolName,
                  ),
                );
              case StreamPartToolInputDelta(:final id, :final delta):
                final buffer = toolInputBuffers.putIfAbsent(
                  id,
                  StringBuffer.new,
                );
                buffer.write(delta);
                final event = StreamTextToolInputDeltaEvent(
                  toolCallId: id,
                  toolName: toolInputNames[id] ?? '',
                  delta: delta,
                  inputBuffer: buffer.toString(),
                );
                fullController.add(event);
                onInputDelta?.call(event);
                onChunk?.call(
                  StreamTextToolInputDeltaChunk(
                    toolCallId: id,
                    toolName: toolInputNames[id] ?? '',
                    delta: delta,
                    inputBuffer: buffer.toString(),
                  ),
                );
              case StreamPartToolInputEnd(:final id):
                final inputBuffer = toolInputBuffers[id]?.toString() ?? '';
                final toolName = toolInputNames[id] ?? '';
                final input = _safeParseStreamToolInput(inputBuffer);
                final inputEvent = StreamTextToolInputEndEvent(
                  toolCallId: id,
                  toolName: toolName,
                  input: input,
                  inputBuffer: inputBuffer,
                );
                fullController.add(inputEvent);
                onInputAvailable?.call(inputEvent);
              case StreamPartToolCall(:final toolCall):
                toolInputNames[toolCall.toolCallId] = toolCall.toolName;
                stepToolCalls.add(toolCall);
                stepContent.add(toolCall);
                onChunk?.call(StreamTextToolCallChunk(toolCall: toolCall));
              case StreamPartToolResult(:final toolResult, :final preliminary):
                if (!preliminary) {
                  stepToolResults.add(toolResult);
                  stepContent.add(toolResult);
                }
                fullController.add(
                  StreamTextToolResultEvent(
                    toolResult: toolResult,
                    preliminary: preliminary,
                  ),
                );
                onChunk?.call(
                  StreamTextToolResultChunk(
                    toolResult: toolResult,
                    preliminary: preliminary,
                  ),
                );
              case StreamPartToolApprovalRequest(:final approvalRequest):
                stepApprovalRequests.add(approvalRequest);
                stepContent.add(approvalRequest);
              case StreamPartStreamStart(:final warnings):
                lastWarnings = List<LanguageModelV4Warning>.from(warnings);
              case StreamPartResponseMetadata(:final metadata):
                lastResponseMetadata = metadata;
                lastResponseBody = metadata.body;
              case StreamPartRaw():
                // Raw chunks are surfaced above and do not affect parsed state.
                break;
              case StreamPartError(:final error):
                throw error;
              case StreamPartFinish():
                fullController.add(StreamTextUsageEvent(usage: part.usage));
                onChunk?.call(StreamTextUsageChunk(usage: part.usage));
                stepFinishPart = part;
                lastFinishPart = part;
            }
          }
        } finally {
          await iterator.cancel();
        }

        for (final entry in reasoningBuffers.entries) {
          stepContent.add(
            LanguageModelV4ReasoningPart(text: entry.value.toString()),
          );
          fullController.add(StreamTextReasoningEndEvent(id: entry.key));
        }

        validateToolChoiceForCalls(
          toolCalls: stepToolCalls,
          tools: toolSelection.exposedTools,
          toolChoice: toolSelection.toolChoice,
          stepNumber: stepNumber,
        );

        normalizedMessages = [
          ...stepMessages,
          LanguageModelV4Message(
            role: LanguageModelV4Role.assistant,
            content: stepContent,
          ),
        ];

        if (stepToolCalls.isNotEmpty) {
          for (final call in stepToolCalls) {
            throwIfCancelled(abortSignal);
            final execution = await executeStreamingToolCall(
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
              onPreliminaryResult: (preliminary) {
                final result = LanguageModelV4ToolResultPart(
                  toolCallId: call.toolCallId,
                  toolName: call.toolName,
                  output: ToolResultOutputText(
                    stringifyToolOutput(preliminary),
                  ),
                );
                fullController.add(
                  StreamTextToolResultEvent(
                    toolResult: result,
                    preliminary: true,
                  ),
                );
                onChunk?.call(
                  StreamTextToolResultChunk(
                    toolResult: result,
                    preliminary: true,
                  ),
                );
              },
            );
            if (execution.approvalRequest != null) {
              stepApprovalRequests.add(execution.approvalRequest!);
              stepContent.add(execution.approvalRequest!);
            }
            if (execution.toolResult != null) {
              stepToolResults.add(execution.toolResult!);
              fullController.add(
                StreamTextToolResultEvent(
                  toolResult: execution.toolResult!,
                  preliminary: false,
                ),
              );
              onChunk?.call(
                StreamTextToolResultChunk(
                  toolResult: execution.toolResult!,
                  preliminary: false,
                ),
              );
            }
            if (execution.toolError != null) {
              fullController.add(
                StreamTextToolErrorEvent(
                  toolCallId: call.toolCallId,
                  toolName: call.toolName,
                  error: execution.toolError!,
                ),
              );
            }
          }
        }

        if (stepToolResults.isNotEmpty) {
          normalizedMessages = [
            ...normalizedMessages,
            LanguageModelV4Message(
              role: LanguageModelV4Role.tool,
              content: stepToolResults,
            ),
          ];
        }

        final stepText = stepContent
            .whereType<LanguageModelV4TextPart>()
            .map((part) => part.text)
            .join();
        final resolvedFinish =
            stepFinishPart ??
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.unknown,
            );
        final stepFinish = GenerateTextStepFinishEvent(
          stepNumber: stepNumber,
          text: stepText,
          toolCalls: List.unmodifiable(stepToolCalls),
          toolResults: List.unmodifiable(stepToolResults),
          finishReason: resolvedFinish.finishReason,
          usage: resolvedFinish.usage,
        );

        final step = GenerateTextStep(
          stepNumber: stepNumber,
          content: stepContent,
          toolCalls: stepToolCalls,
          toolResults: stepToolResults,
          toolApprovalRequests: stepApprovalRequests,
          response: LanguageModelV4GenerateResult(
            content: stepContent,
            finishReason: resolvedFinish.finishReason,
            usage: resolvedFinish.usage,
            providerMetadata: resolvedFinish.providerMetadata,
            rawFinishReason: resolvedFinish.rawFinishReason,
          ),
          text: stepText,
          finishReason: resolvedFinish.finishReason,
          usage: resolvedFinish.usage,
        );
        steps.add(step);
        lastContent = stepContent;

        safeInvoke(() => onStepFinish?.call(stepFinish));
        fullController.add(StreamTextFinishStepEvent(step: stepFinish));

        final shouldStop = shouldStopAfterStep(
          toolResultsEmpty: stepToolResults.isEmpty,
          hasApprovalRequests: stepApprovalRequests.isNotEmpty,
          snapshot: StepSnapshot(
            stepCount: stepNumber + 1,
            toolCallNames: stepToolCalls.map((call) => call.toolName).toList(),
            finishReason: stepFinish.finishReason,
          ),
          conditions: allStopConditions,
        );
        if (shouldStop) {
          break;
        }
      }

      final finalText = lastContent
          .whereType<LanguageModelV4TextPart>()
          .map((part) => part.text)
          .join();
      final finalOutput = parseStreamingOutputWithNoObjectError(
        output: outputSpec,
        text: finalText,
        usage: lastFinishPart?.usage,
        response: lastResponseMetadata,
      );
      final totalUsage = sumUsage(steps.map((step) => step.usage));
      final reasoningParts = lastContent
          .whereType<LanguageModelV4ReasoningPart>()
          .toList();
      final resolvedReasoningText = lastContent
          .where(
            (part) =>
                part is LanguageModelV4ReasoningPart ||
                part is LanguageModelV4RedactedReasoningPart,
          )
          .map(
            (part) =>
                part is LanguageModelV4ReasoningPart ? part.text : '[REDACTED]',
          )
          .join();
      final sources = lastContent
          .whereType<LanguageModelV4SourcePart>()
          .toList();
      final files = lastContent.whereType<LanguageModelV4FilePart>().toList();
      final responseMessages = normalizedMessages
          .where(
            (message) =>
                message.role == LanguageModelV4Role.assistant ||
                message.role == LanguageModelV4Role.tool,
          )
          .toList(growable: false);
      final requestInfo = GenerateTextRequest(
        system: systemInstruction,
        messages: List.unmodifiable(
          normalizedMessages
              .where(
                (message) =>
                    message.role == LanguageModelV4Role.user ||
                    message.role == LanguageModelV4Role.system,
              )
              .toList(),
        ),
        body: lastRequestBody,
      );
      final responseInfo = GenerateTextResponse(
        messages: List.unmodifiable(responseMessages),
        body: lastResponseBody,
        metadata: lastResponseMetadata,
      );
      final resolvedFinish =
          lastFinishPart ??
          const StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.unknown,
          );

      final finishEvent = StreamTextFinishEvent<TOutput>(
        text: finalText,
        output: finalOutput,
        finishReason: resolvedFinish.finishReason,
        rawFinishReason: resolvedFinish.rawFinishReason,
        usage: resolvedFinish.usage,
        totalUsage: totalUsage,
        providerMetadata: resolvedFinish.providerMetadata,
        steps: List.unmodifiable(steps),
        reasoning: List.unmodifiable(reasoningParts),
        reasoningText: resolvedReasoningText,
        sources: List.unmodifiable(sources),
        files: List.unmodifiable(files),
        responseMessages: List.unmodifiable(responseMessages),
        request: requestInfo,
        response: responseInfo,
        warnings: List.unmodifiable(lastWarnings),
      );

      isTerminal = true;
      fullController.add(finishEvent);
      safeInvoke(() => onFinish?.call(finishEvent));

      textCompleter.completeIfPending(finalText);
      outputCompleter.completeIfPending(finalOutput);
      finishCompleter.completeIfPending(lastFinishPart);
      contentCompleter.completeIfPending(List.unmodifiable(lastContent));
      reasoningCompleter.completeIfPending(List.unmodifiable(reasoningParts));
      reasoningTextCompleter.completeIfPending(resolvedReasoningText);
      filesCompleter.completeIfPending(List.unmodifiable(files));
      sourcesCompleter.completeIfPending(List.unmodifiable(sources));
      toolCallsCompleter.completeIfPending(
        List.unmodifiable(
          lastContent.whereType<LanguageModelV4ToolCallPart>().toList(),
        ),
      );
      toolResultsCompleter.completeIfPending(
        List.unmodifiable(
          lastContent.whereType<LanguageModelV4ToolResultPart>().toList(),
        ),
      );
      finishReasonCompleter.completeIfPending(resolvedFinish.finishReason);
      rawFinishReasonCompleter.completeIfPending(
        resolvedFinish.rawFinishReason,
      );
      usageCompleter.completeIfPending(resolvedFinish.usage);
      totalUsageCompleter.completeIfPending(totalUsage);
      warningsCompleter.completeIfPending(List.unmodifiable(lastWarnings));
      stepsCompleter.completeIfPending(List.unmodifiable(steps));
      requestCompleter.completeIfPending(requestInfo);
      responseCompleter.completeIfPending(responseInfo);
      providerMetadataCompleter.completeIfPending(
        resolvedFinish.providerMetadata,
      );
    } catch (error, stackTrace) {
      isTerminal = true;
      terminalError = error;
      terminalStackTrace = stackTrace;
      terminalFullStreamErrorEvent = StreamTextErrorEvent(error: error);
      safeInvoke(() => onError?.call(error));
      fullController.add(terminalFullStreamErrorEvent!);

      textCompleter.completeErrorIfPending(error, stackTrace);
      outputCompleter.completeErrorIfPending(error, stackTrace);
      finishCompleter.completeErrorIfPending(error, stackTrace);
      contentCompleter.completeErrorIfPending(error, stackTrace);
      reasoningCompleter.completeErrorIfPending(error, stackTrace);
      reasoningTextCompleter.completeErrorIfPending(error, stackTrace);
      filesCompleter.completeErrorIfPending(error, stackTrace);
      sourcesCompleter.completeErrorIfPending(error, stackTrace);
      toolCallsCompleter.completeErrorIfPending(error, stackTrace);
      toolResultsCompleter.completeErrorIfPending(error, stackTrace);
      finishReasonCompleter.completeErrorIfPending(error, stackTrace);
      rawFinishReasonCompleter.completeErrorIfPending(error, stackTrace);
      usageCompleter.completeErrorIfPending(error, stackTrace);
      totalUsageCompleter.completeErrorIfPending(error, stackTrace);
      warningsCompleter.completeErrorIfPending(error, stackTrace);
      stepsCompleter.completeErrorIfPending(error, stackTrace);
      requestCompleter.completeErrorIfPending(error, stackTrace);
      responseCompleter.completeErrorIfPending(error, stackTrace);
      providerMetadataCompleter.completeErrorIfPending(error, stackTrace);

      if (rawController.hasListener) {
        rawController.addError(error, stackTrace);
      }
      if (textController.hasListener) {
        textController.addError(error, stackTrace);
      }
      if (fullController.hasListener) {
        fullController.addError(error, stackTrace);
      }
      if (partialController.hasListener) {
        partialController.addError(error, stackTrace);
      }
      if (elementController.hasListener) {
        elementController.addError(error, stackTrace);
      }
    } finally {
      await rawController.close();
      await textController.close();
      await fullController.close();
      await partialController.close();
      await elementController.close();
    }
  });
  observeFutureError(runFuture);
  unawaited(runFuture);

  // End the telemetry span when the stream fully finishes.
  finishCompleter.future.then(
    (_) {
      totalUsageCompleter.future.then((usage) {
        telemetrySpan
          ..setAttribute('ai.usage.promptTokens', usage?.inputTokens.total ?? 0)
          ..setAttribute(
            'ai.usage.completionTokens',
            usage?.outputTokens.total ?? 0,
          )
          ..end();
        // Defensive: totalUsageCompleter never completes with an error.
      }, onError: (_) => telemetrySpan.end()); // coverage:ignore-line
    },
    // Defensive: finishCompleter never completes with an error.
    // coverage:ignore-start
    onError: (Object e, StackTrace st) {
      telemetrySpan
        ..recordException(e, stackTrace: st)
        ..end(error: e);
    },
    // coverage:ignore-end
  );

  return StreamTextResult<TOutput>(
    stream: terminalAwareBroadcastStream(
      source: rawController.stream,
      isTerminal: () => isTerminal,
      terminalError: () => terminalError,
      terminalStackTrace: () => terminalStackTrace,
    ),
    fullStream: terminalAwareBroadcastStream(
      source: fullController.stream,
      isTerminal: () => isTerminal,
      terminalError: () => terminalError,
      terminalStackTrace: () => terminalStackTrace,
      replayOnError: () => terminalFullStreamErrorEvent == null
          ? const <StreamTextEvent>[]
          : <StreamTextEvent>[terminalFullStreamErrorEvent!],
    ),
    textStream: terminalAwareBroadcastStream(
      source: textController.stream,
      isTerminal: () => isTerminal,
      terminalError: () => terminalError,
      terminalStackTrace: () => terminalStackTrace,
    ),
    partialOutputStream: terminalAwareBroadcastStream(
      source: partialController.stream,
      isTerminal: () => isTerminal,
      terminalError: () => terminalError,
      terminalStackTrace: () => terminalStackTrace,
    ),
    elementStream: terminalAwareBroadcastStream(
      source: elementController.stream,
      isTerminal: () => isTerminal,
      terminalError: () => terminalError,
      terminalStackTrace: () => terminalStackTrace,
    ),
    text: textCompleter.future,
    output: outputCompleter.future,
    content: contentCompleter.future,
    reasoning: reasoningCompleter.future,
    reasoningText: reasoningTextCompleter.future,
    files: filesCompleter.future,
    sources: sourcesCompleter.future,
    toolCalls: toolCallsCompleter.future,
    toolResults: toolResultsCompleter.future,
    finishReason: finishReasonCompleter.future,
    rawFinishReason: rawFinishReasonCompleter.future,
    usage: usageCompleter.future,
    totalUsage: totalUsageCompleter.future,
    warnings: warningsCompleter.future,
    steps: stepsCompleter.future,
    request: requestCompleter.future,
    response: responseCompleter.future,
    providerMetadata: providerMetadataCompleter.future,
    finish: finishCompleter.future,
  );
}

Future<bool> _moveNextWithStreamTimeout(
  StreamIterator<LanguageModelV4StreamPart> iterator, {
  CancellationToken? abortSignal,
  Duration? timeout,
  Duration? totalTimeout,
  required Stopwatch overallStopwatch,
}) {
  final moveNext = moveNextOrCancellation(iterator, abortSignal);
  final effectiveTimeout = minTimeout(
    remainingTimeout(timeout: totalTimeout, elapsed: overallStopwatch.elapsed),
    timeout,
  );
  if (effectiveTimeout == null) return moveNext;
  return moveNext.timeout(effectiveTimeout);
}

Object _safeParseStreamToolInput(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const {};
  }
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return trimmed;
  }
}
