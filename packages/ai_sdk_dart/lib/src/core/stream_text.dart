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
  required LanguageModelV3 model,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  Output<TOutput>? output,
  ProviderOptions? providerOptions,
  ToolSet tools = const {},
  List<LanguageModelV3ProviderDefinedTool> providerDefinedTools = const [],
  LanguageModelV3ToolChoice? toolChoice,
  int maxSteps = 1,
  List<StopCondition> stopConditions = const [],
  Object? stopWhen, // StopCondition | List<StopCondition>
  List<LanguageModelV3ToolApprovalResponse> toolApprovalResponses = const [],
  CancellationToken? abortSignal,
  Map<String, Object?>? experimentalContext,
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
  Duration? timeout,
  GenerateTextExperimentalOnStart? experimentalOnStart,
  GenerateTextExperimentalOnStepStart? experimentalOnStepStart,
  GenerateTextExperimentalOnToolCallStart? experimentalOnToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? experimentalOnToolCallFinish,
  TelemetrySettings? experimentalTelemetry,
}) async {
  final telemetrySpan = startTelemetrySpan(
    experimentalTelemetry,
    spanName: 'ai.streamText',
    attributes: {
      'ai.model.provider': model.provider,
      'ai.model.id': model.modelId,
      if (prompt != null) 'ai.prompt': prompt,
    },
  );

  final outputSpec = output ?? (Output.text() as Output<TOutput>);
  var normalizedMessages = <LanguageModelV3Message>[
    if (prompt != null)
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [LanguageModelV3TextPart(text: prompt)],
      ),
    ...?messages?.map(toLanguageModelMessage),
  ];

  final systemInstruction = buildOutputSystemInstruction(system, outputSpec);
  final approvalById = {
    for (final approval in toolApprovalResponses) approval.approvalId: approval,
  };

  final rawController = StreamController<LanguageModelV3StreamPart>.broadcast();
  final textController = StreamController<String>.broadcast();
  final fullController = StreamController<StreamTextEvent>.broadcast();
  final partialController = StreamController<Object?>.broadcast();
  final elementController = StreamController<Object?>.broadcast();

  final textCompleter = Completer<String>();
  final outputCompleter = Completer<TOutput>();
  final finishCompleter = Completer<StreamPartFinish?>();
  final contentCompleter = Completer<List<LanguageModelV3ContentPart>>();
  final reasoningCompleter = Completer<List<LanguageModelV3ReasoningPart>>();
  final reasoningTextCompleter = Completer<String>();
  final filesCompleter = Completer<List<LanguageModelV3FilePart>>();
  final sourcesCompleter = Completer<List<LanguageModelV3SourcePart>>();
  final toolCallsCompleter = Completer<List<LanguageModelV3ToolCallPart>>();
  final toolResultsCompleter = Completer<List<LanguageModelV3ToolResultPart>>();
  final finishReasonCompleter = Completer<LanguageModelV3FinishReason?>();
  final rawFinishReasonCompleter = Completer<String?>();
  final usageCompleter = Completer<LanguageModelV3Usage?>();
  final totalUsageCompleter = Completer<LanguageModelV3Usage?>();
  final warningsCompleter = Completer<List<String>>();
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
    var lastContent = <LanguageModelV3ContentPart>[];
    Object? lastRequestBody;
    Object? lastResponseBody;
    LanguageModelV3ResponseMetadata? lastResponseMetadata;
    var lastWarnings = <String>[];
    Map<Object?, Object?>? rawEnvelope;

    void refreshEnvelopeFromRaw() {
      final raw = rawEnvelope;
      if (raw == null) return;
      lastRequestBody = raw['requestBody'];
      lastResponseBody = raw['body'];
      final rawWarnings = raw['warnings'];
      if (rawWarnings is List) {
        lastWarnings = rawWarnings.map((e) => e.toString()).toList();
      }
      final meta = raw['responseMetadata'];
      if (meta is Map) {
        final map = meta.cast<Object?, Object?>();
        final ts = map['timestamp']?.toString();
        lastResponseMetadata = LanguageModelV3ResponseMetadata(
          id: map['id']?.toString(),
          modelId: map['modelId']?.toString(),
          timestamp: ts == null ? null : DateTime.tryParse(ts),
          headers: null,
          body: lastResponseBody,
          requestBody: lastRequestBody,
        );
      }
    }

    safeInvoke(
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

    try {
      throwIfCancelled(abortSignal);
      fullController.add(const StreamTextStartEvent());

      final _allStopConditions = resolveStopConditions(
        stopWhen,
        stopConditions,
      );
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
              stopConditions: _allStopConditions,
              experimentalContext: experimentalContext,
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

        final streamCallOptions = LanguageModelV3CallOptions(
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
          topK: topK,
          presencePenalty: presencePenalty,
          frequencyPenalty: frequencyPenalty,
          stopSequences: stopSequences,
          seed: seed,
          headers: headers,
          providerOptions: stepProviderOptions,
        );
        final response = await withRetry(
          maxRetries: maxRetries,
          timeout: timeout,
          abortSignal: abortSignal,
          fn: (attemptTimeout) {
            final call = stepModel.doStream(streamCallOptions);
            return attemptTimeout != null ? call.timeout(attemptTimeout) : call;
          },
        );
        if (response.rawResponse is Map) {
          rawEnvelope = (response.rawResponse as Map).cast<Object?, Object?>();
          refreshEnvelopeFromRaw();
        }

        final stepTextById = <String, StringBuffer>{};
        final stepToolCalls = <LanguageModelV3ToolCallPart>[];
        final stepToolResults = <LanguageModelV3ToolResultPart>[];
        final stepApprovalRequests = <LanguageModelV3ToolApprovalRequestPart>[];
        final stepContent = <LanguageModelV3ContentPart>[];
        final toolInputBuffers = <String, StringBuffer>{};
        var inReasoning = false;
        var reasoningClosed = false;
        const reasoningId = 'reasoning-0';
        final reasoningBuffer = StringBuffer();
        StreamPartFinish? stepFinishPart;

        final iterator = StreamIterator<LanguageModelV3StreamPart>(
          response.stream,
        );
        try {
          while (await moveNextOrCancellation(iterator, abortSignal)) {
            final part = iterator.current;
            rawController.add(part);
            fullController.add(StreamTextRawEvent(part: part));
            onChunk?.call(StreamTextRawChunk(part: part));

            if (inReasoning &&
                part is! StreamPartReasoningDelta &&
                !reasoningClosed) {
              stepContent.add(
                LanguageModelV3ReasoningPart(text: reasoningBuffer.toString()),
              );
              fullController.add(
                const StreamTextReasoningEndEvent(id: reasoningId),
              );
              reasoningClosed = true;
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
                stepContent.add(LanguageModelV3TextPart(text: text));
                fullController.add(StreamTextTextEndEvent(id: id));
              case StreamPartReasoningDelta(:final delta):
                if (!inReasoning) {
                  inReasoning = true;
                  fullController.add(
                    const StreamTextReasoningStartEvent(id: reasoningId),
                  );
                }
                reasoningBuffer.write(delta);
                fullController.add(
                  StreamTextReasoningDeltaEvent(id: reasoningId, delta: delta),
                );
                onChunk?.call(StreamTextReasoningChunk(delta: delta));
              case StreamPartSource(:final source):
                stepContent.add(source);
                fullController.add(StreamTextSourceEvent(source: source));
                onChunk?.call(StreamTextSourceChunk(source: source));
              case StreamPartFile(:final file):
                stepContent.add(file);
                fullController.add(StreamTextFileEvent(file: file));
                onChunk?.call(StreamTextFileChunk(file: file));
              case StreamPartToolCallStart(:final toolCallId, :final toolName):
                toolInputBuffers[toolCallId] = StringBuffer();
                final event = StreamTextToolInputStartEvent(
                  toolCallId: toolCallId,
                  toolName: toolName,
                );
                fullController.add(event);
                onInputStart?.call(event);
                onChunk?.call(
                  StreamTextToolInputStartChunk(
                    toolCallId: toolCallId,
                    toolName: toolName,
                  ),
                );
              case StreamPartToolCallDelta(
                :final toolCallId,
                :final toolName,
                :final argsTextDelta,
              ):
                final buffer = toolInputBuffers.putIfAbsent(
                  toolCallId,
                  StringBuffer.new,
                );
                buffer.write(argsTextDelta);
                final event = StreamTextToolInputDeltaEvent(
                  toolCallId: toolCallId,
                  toolName: toolName,
                  delta: argsTextDelta,
                  inputBuffer: buffer.toString(),
                );
                fullController.add(event);
                onInputDelta?.call(event);
                onChunk?.call(
                  StreamTextToolInputDeltaChunk(
                    toolCallId: toolCallId,
                    toolName: toolName,
                    delta: argsTextDelta,
                    inputBuffer: buffer.toString(),
                  ),
                );
              case StreamPartToolCallEnd(
                :final toolCallId,
                :final toolName,
                :final input,
              ):
                final inputBuffer =
                    toolInputBuffers[toolCallId]?.toString() ?? '';
                final inputEvent = StreamTextToolInputEndEvent(
                  toolCallId: toolCallId,
                  toolName: toolName,
                  input: input,
                  inputBuffer: inputBuffer,
                );
                final toolCall = LanguageModelV3ToolCallPart(
                  toolCallId: toolCallId,
                  toolName: toolName,
                  input: input,
                );
                stepToolCalls.add(toolCall);
                stepContent.add(toolCall);
                fullController.add(inputEvent);
                onInputAvailable?.call(inputEvent);
                onChunk?.call(StreamTextToolCallChunk(toolCall: toolCall));
              case StreamPartError(:final error):
                throw error;
              case StreamPartFinish():
                if (part.usage != null) {
                  fullController.add(StreamTextUsageEvent(usage: part.usage!));
                  onChunk?.call(StreamTextUsageChunk(usage: part.usage!));
                }
                stepFinishPart = part;
                lastFinishPart = part;
            }
          }
        } finally {
          await iterator.cancel();
        }

        if (inReasoning && !reasoningClosed) {
          stepContent.add(
            LanguageModelV3ReasoningPart(text: reasoningBuffer.toString()),
          );
          fullController.add(
            const StreamTextReasoningEndEvent(id: reasoningId),
          );
        }

        validateToolChoiceForCalls(
          toolCalls: stepToolCalls,
          tools: toolSelection.exposedTools,
          toolChoice: toolSelection.toolChoice,
          stepNumber: stepNumber,
        );

        normalizedMessages = [
          ...stepMessages,
          LanguageModelV3Message(
            role: LanguageModelV3Role.assistant,
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
              experimentalContext: experimentalContext,
              onToolCallStart: experimentalOnToolCallStart,
              onToolCallFinish: experimentalOnToolCallFinish,
              onPreliminaryResult: (preliminary) {
                final result = LanguageModelV3ToolResultPart(
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
            LanguageModelV3Message(
              role: LanguageModelV3Role.tool,
              content: stepToolResults,
            ),
          ];
        }

        final stepText = stepContent
            .whereType<LanguageModelV3TextPart>()
            .map((part) => part.text)
            .join();
        final resolvedFinish =
            stepFinishPart ??
            const StreamPartFinish(
              finishReason: LanguageModelV3FinishReason.unknown,
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
          response: LanguageModelV3GenerateResult(
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
          conditions: _allStopConditions,
        );
        if (shouldStop) {
          break;
        }
      }

      final finalText = lastContent
          .whereType<LanguageModelV3TextPart>()
          .map((part) => part.text)
          .join();
      refreshEnvelopeFromRaw();
      final finalOutput = parseStreamingOutputWithNoObjectError(
        output: outputSpec,
        text: finalText,
        usage: lastFinishPart?.usage,
        response: lastResponseMetadata,
      );
      final totalUsage = sumUsage(steps.map((step) => step.usage));
      final reasoning = lastContent
          .whereType<LanguageModelV3ReasoningPart>()
          .toList();
      final resolvedReasoningText = lastContent
          .where(
            (part) =>
                part is LanguageModelV3ReasoningPart ||
                part is LanguageModelV3RedactedReasoningPart,
          )
          .map(
            (part) =>
                part is LanguageModelV3ReasoningPart ? part.text : '[REDACTED]',
          )
          .join();
      final sources = lastContent
          .whereType<LanguageModelV3SourcePart>()
          .toList();
      final files = lastContent.whereType<LanguageModelV3FilePart>().toList();
      final responseMessages = normalizedMessages
          .where(
            (message) =>
                message.role == LanguageModelV3Role.assistant ||
                message.role == LanguageModelV3Role.tool,
          )
          .toList(growable: false);
      final requestInfo = GenerateTextRequest(
        system: systemInstruction,
        messages: List.unmodifiable(
          normalizedMessages
              .where(
                (message) =>
                    message.role == LanguageModelV3Role.user ||
                    message.role == LanguageModelV3Role.system,
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
            finishReason: LanguageModelV3FinishReason.unknown,
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
        reasoning: List.unmodifiable(reasoning),
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
      reasoningCompleter.completeIfPending(List.unmodifiable(reasoning));
      reasoningTextCompleter.completeIfPending(resolvedReasoningText);
      filesCompleter.completeIfPending(List.unmodifiable(files));
      sourcesCompleter.completeIfPending(List.unmodifiable(sources));
      toolCallsCompleter.completeIfPending(
        List.unmodifiable(
          lastContent.whereType<LanguageModelV3ToolCallPart>().toList(),
        ),
      );
      toolResultsCompleter.completeIfPending(
        List.unmodifiable(
          lastContent.whereType<LanguageModelV3ToolResultPart>().toList(),
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
      refreshEnvelopeFromRaw();
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
          ..setAttribute('ai.usage.promptTokens', usage?.inputTokens ?? 0)
          ..setAttribute('ai.usage.completionTokens', usage?.outputTokens ?? 0)
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
