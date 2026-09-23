import 'streaming/reasoning_buffer.dart';
import 'dart:convert';
import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'cancellation.dart';
import 'body_inclusion.dart';
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
import 'shared/stream_outcome.dart';
import 'shared/operation_scope.dart';
import 'shared/tool_selection.dart';
import 'shared/tool_concurrency.dart';
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
  String? instructions,
  String? system,
  String? prompt,
  List<ModelMessage>? messages,
  Output<TOutput>? output,
  ProviderOptions? providerOptions,
  LanguageModelV4Reasoning reasoning = LanguageModelV4Reasoning.providerDefault,
  bool includeRawChunks = false,
  BodyInclusionPolicy bodyInclusion = const BodyInclusionPolicy.none(),
  ToolSet tools = const {},
  ToolApprovalPolicy? approvalPolicy,
  ToolApprovalPolicySelector? approvalPolicyFor,
  String approvalPolicyRevision = 'default',
  List<LanguageModelV4ProviderDefinedTool> providerDefinedTools = const [],
  LanguageModelV4ToolChoice? toolChoice,
  int maxSteps = 1,
  int maxToolConcurrency = 1,
  List<StopCondition> stopConditions = const [],
  Object? stopWhen, // StopCondition | List<StopCondition>
  List<LanguageModelV4ToolApprovalResponse> toolApprovalResponses = const [],
  CancellationToken? abortSignal,
  Map<String, Object?>? runtimeContext,
  Object? generationContext,
  bool allowSystemInMessages = false,
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
  StreamTextOnEnd<TOutput>? onEnd,
  GenerateTextOnStepFinish? onStepFinish,
  StreamTextOnStepEnd? onStepEnd,
  GenerateTextPrepareStep? prepareStep,
  StreamTextOnInputStart? onInputStart,
  StreamTextOnInputDelta? onInputDelta,
  StreamTextOnInputAvailable? onInputAvailable,
  StreamTextTransform? experimentalTransform,
  TimeoutConfiguration? timeout,
  GenerateTextExperimentalOnStart? experimentalOnStart,
  GenerateTextExperimentalOnStart? onStart,
  GenerateTextExperimentalOnStepStart? experimentalOnStepStart,
  GenerateTextExperimentalOnStepStart? onStepStart,
  GenerateTextExperimentalOnToolCallStart? experimentalOnToolCallStart,
  GenerateTextExperimentalOnToolCallStart? onToolExecutionStart,
  GenerateTextExperimentalOnToolCallFinish? experimentalOnToolCallFinish,
  GenerateTextExperimentalOnToolCallFinish? onToolExecutionEnd,
  TelemetrySettings? telemetry,
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
    spanName: 'ai.streamText',
    attributes: {
      AiTelemetryKeys.modelProvider: model.provider,
      AiTelemetryKeys.modelId: model.modelId,
      if (telemetry?.captureInputs == true && prompt != null)
        'ai.prompt': prompt,
    },
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
          AiTelemetryKeys.operation: 'streamText',
          ...attributes,
        },
      ),
    );
  }

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
  final scope = OperationScope(
    abortSignal: abortSignal,
    timeout: timeout?.total,
  );
  final approvalById = indexApprovalResponses(toolApprovalResponses);

  final rawController = StreamController<LanguageModelV4StreamPart>.broadcast();
  final textController = StreamController<String>.broadcast();
  final fullController = StreamController<StreamTextEvent>.broadcast();
  final partialController = StreamController<Object?>.broadcast();
  final elementController = StreamController<Object?>.broadcast();

  final textCompleter = Completer<String>();
  final outputCompleter = Completer<TOutput>();
  final finishCompleter = Completer<StreamPartFinish?>();
  final finalStepCompleter = Completer<GenerateTextStep>();
  final contentCompleter = Completer<List<LanguageModelV4ContentPart>>();
  final reasoningCompleter = Completer<List<LanguageModelV4ReasoningPart>>();
  final reasoningTextCompleter = Completer<String>();
  final filesCompleter = Completer<List<LanguageModelV4FilePart>>();
  final reasoningFilesCompleter =
      Completer<List<LanguageModelV4ReasoningFilePart>>();
  final sourcesCompleter = Completer<List<LanguageModelV4SourcePart>>();
  final documentSourcesCompleter =
      Completer<List<LanguageModelV4DocumentSourcePart>>();
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
  AbortSignalObservation? abortObservation;

  Future<void> disposeAbortObservation() async {
    final observation = abortObservation;
    abortObservation = null;
    await observation?.dispose();
  }

  for (final future in [
    textCompleter.future,
    outputCompleter.future,
    contentCompleter.future,
    reasoningCompleter.future,
    reasoningTextCompleter.future,
    filesCompleter.future,
    reasoningFilesCompleter.future,
    sourcesCompleter.future,
    documentSourcesCompleter.future,
    toolCallsCompleter.future,
    toolResultsCompleter.future,
    finishReasonCompleter.future,
    rawFinishReasonCompleter.future,
    usageCompleter.future,
    totalUsageCompleter.future,
    warningsCompleter.future,
    stepsCompleter.future,
    requestCompleter.future,
    responseCompleter.future,
    providerMetadataCompleter.future,
    finishCompleter.future,
  ]) {
    future.ignore();
  }

  // Wire onAbort: fire when the caller cancels via abortSignal.
  if (abortSignal != null && onAbort != null) {
    abortObservation = AbortSignalObservation.attach(abortSignal, () {
      if (!isTerminal) {
        safeInvoke(onAbort);
      }
    });
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
    var firstMeaningfulRecorded = false;
    Object? lastRequestBody;
    Object? lastResponseBody;
    LanguageModelV4ResponseMetadata? lastResponseMetadata;
    var lastWarnings = <LanguageModelV4Warning>[];

    safeInvoke(
      () => (onStart ?? experimentalOnStart)?.call(
        GenerateTextExperimentalStartEvent(
          model: model,
          system: buildOutputSystemInstruction(currentInstructions, outputSpec),
          instructions: currentInstructions,
          prompt: prompt,
          messages: List.unmodifiable(normalizedMessages),
          runtimeContext: runtimeContext,
        ),
      ),
    );

    try {
      throwIfCancelled(scope.signal);
      fullController.add(const StreamTextStartEvent());

      final allStopConditions = resolveStopConditions(stopWhen, stopConditions);
      final totalSteps = resolveStepBudget(
        hasTools: tools.isNotEmpty,
        stopWhen: stopWhen,
        maxSteps: maxSteps,
      );
      for (var stepNumber = 0; stepNumber < totalSteps; stepNumber++) {
        final responseMessageStart = responseMessages.length;
        throwIfCancelled(scope.signal);
        fullController.add(StreamTextStartStepEvent(stepNumber: stepNumber));

        final prepareResult = await scope.run(
          () async => prepareStep?.call(
            GenerateTextPrepareStepContext(
              model: model,
              stepNumber: stepNumber,
              steps: List.unmodifiable(steps),
              instructions: currentInstructions,
              messages: List.unmodifiable(normalizedMessages),
              stopConditions: allStopConditions,
              runtimeContext: runtimeContext,
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
            ),
          ),
        );

        final streamCallOptions = LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            system: buildOutputSystemInstruction(
              currentInstructions,
              outputSpec,
            ),
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
          includeRawChunks: includeRawChunks || bodyInclusion.rawChunks,
          abortSignal: scope.signal,
          reasoning: reasoning,
        );
        final stepStopwatch = Stopwatch()..start();
        final acquisitionStopwatch = Stopwatch()..start();
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
              final call = stepModel.doStream(streamCallOptions);
              unawaited(
                call.then((lateResponse) async {
                  if (!scope.signal.isCancelled) return;
                  try {
                    final subscription = lateResponse.stream.listen(
                      (_) {},
                      onError: (_, _) {},
                    );
                    await subscription.cancel();
                  } catch (_) {}
                }, onError: (_) {}),
              );
              final acquisitionTimeout = minTimeout(
                attemptTimeout,
                timeout?.firstChunk,
              );
              if (acquisitionTimeout == null) return call;
              return call.timeout(
                acquisitionTimeout,
                onTimeout: () {
                  scheduleMicrotask(scope.signal.cancel);
                  throw TimeoutException(
                    'Model stream acquisition timed out.',
                    acquisitionTimeout,
                  );
                },
              );
            },
          ),
        );
        lastRequestBody = bodyInclusion.requestBody
            ? response.request?.body
            : null;
        lastResponseBody = bodyInclusion.responseBody
            ? response.response?.body
            : null;
        lastWarnings = List<LanguageModelV4Warning>.from(response.warnings);
        lastResponseMetadata = response.response;

        final stepTextById = <String, StringBuffer>{};
        final stepToolCalls = <LanguageModelV4ToolCallPart>[];
        final stepToolResults = <LanguageModelV4ToolResultPart>[];
        final stepApprovalRequests = <LanguageModelV4ToolApprovalRequestPart>[];
        final stepContent = <LanguageModelV4ContentPart>[];
        final toolInputBuffers = <String, StringBuffer>{};
        final toolInputNames = <String, String>{};
        final reasoningBuffers = <String, ReasoningBuffer>{};
        ImmutableArraySnapshotBuilder<dynamic>? arraySnapshotBuilder;
        var arraySnapshotLength = 0;
        List<dynamic> arraySnapshot() {
          final builder = arraySnapshotBuilder ??=
              ImmutableArraySnapshotBuilder<dynamic>();
          builder.addAll(partialArrayValues.skip(arraySnapshotLength));
          arraySnapshotLength = partialArrayValues.length;
          return builder.snapshot();
        }

        StreamPartFinish? stepFinishPart;

        final iterator =
            StreamIterator<StreamOutcome<LanguageModelV4StreamPart>>(
              captureStreamErrors(response.stream),
            );
        var sawStreamPart = false;
        try {
          while (await scope.run(
            () => _moveNextWithStreamTimeout(
              iterator,
              abortSignal: scope.signal,
              timeout: sawStreamPart
                  ? timeout?.chunk
                  : remainingTimeout(
                      timeout: timeout?.firstChunk,
                      elapsed: acquisitionStopwatch.elapsed,
                    ),
              stepTimeout: timeout?.step,
              stepStopwatch: stepStopwatch,
              totalTimeout: timeout?.total,
              overallStopwatch: overallStopwatch,
            ),
          )) {
            final part = _filterStreamPart(
              iterator.current.unwrap(),
              bodyInclusion,
            );
            if (!firstMeaningfulRecorded &&
                _hasMeaningfulTelemetryPayload(part)) {
              firstMeaningfulRecorded = true;
              recordMetric(
                AiTelemetryMetrics.firstMeaningfulMs,
                metricStopwatch.elapsedMicroseconds / 1000,
              );
            }
            if (bodyInclusion.rawChunks ||
                includeRawChunks ||
                part is! StreamPartRaw) {
              rawController.add(part);
            }
            if (part case StreamPartRaw(:final rawValue)) {
              if (bodyInclusion.rawChunks || includeRawChunks) {
                fullController.add(StreamTextRawEvent(rawValue: rawValue));
                onChunk?.call(StreamTextRawChunk(rawValue: rawValue));
              }
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
                  while (await raceWithCancellation(
                    transformedIterator.moveNext(),
                    scope.signal,
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
                          if (partialController.hasListener) {
                            partialController.add(arraySnapshot());
                          }
                        }
                      } else if (update.isClosed &&
                          lastArraySnapshotLength !=
                              partialArrayValues.length) {
                        lastArraySnapshotLength = partialArrayValues.length;
                        if (partialController.hasListener) {
                          partialController.add(arraySnapshot());
                        }
                      }
                    } else if (outputSpec is! TextOutput) {
                      final cadence = partialJsonTracker.append(
                        transformedDelta,
                      );
                      final fullText = overallTextBuffer.toString();

                      if (cadence.shouldAttemptValue) {
                        final partial = tryParsePartialOutput(
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
              case StreamPartReasoningStart(:final id, :final providerMetadata):
                reasoningBuffers
                    .putIfAbsent(id, ReasoningBuffer.new)
                    .mergeMetadata(providerMetadata);
                fullController.add(
                  StreamTextReasoningStartEvent(
                    id: id,
                    providerMetadata: providerMetadata,
                  ),
                );
              case StreamPartReasoningDelta(
                :final id,
                :final delta,
                :final providerMetadata,
              ):
                final buffer = reasoningBuffers.putIfAbsent(id, () {
                  fullController.add(StreamTextReasoningStartEvent(id: id));
                  return ReasoningBuffer();
                });
                buffer.write(delta, providerMetadata);
                fullController.add(
                  StreamTextReasoningDeltaEvent(
                    id: id,
                    delta: delta,
                    providerMetadata: providerMetadata,
                  ),
                );
                onChunk?.call(StreamTextReasoningChunk(delta: delta));
              case StreamPartReasoningEnd(
                :final id,
                :final providerMetadata,
                :final signature,
              ):
                final buffer = reasoningBuffers.remove(id) ?? ReasoningBuffer();
                stepContent.add(
                  buffer.finish(
                    metadata: providerMetadata,
                    signature: signature,
                  ),
                );
                fullController.add(
                  StreamTextReasoningEndEvent(
                    id: id,
                    providerMetadata: providerMetadata,
                    signature: signature,
                  ),
                );
              case StreamPartSource(:final source):
                stepContent.add(source);
                fullController.add(StreamTextSourceEvent(source: source));
                onChunk?.call(StreamTextSourceChunk(source: source));
              case StreamPartDocumentSource(:final source):
                stepContent.add(source);
                fullController.add(
                  StreamTextDocumentSourceEvent(source: source),
                );
                onChunk?.call(StreamTextDocumentSourceChunk(source: source));
              case StreamPartFile(:final file):
                stepContent.add(file);
                fullController.add(StreamTextFileEvent(file: file));
                onChunk?.call(StreamTextFileChunk(file: file));
              case StreamPartReasoningFile(:final file):
                stepContent.add(file);
                fullController.add(StreamTextReasoningFileEvent(file: file));
                onChunk?.call(StreamTextReasoningFileChunk(file: file));
              case StreamPartOpaque(:final opaque):
                stepContent.add(opaque);
                fullController.add(StreamTextOpaqueEvent(opaque: opaque));
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
            if (part is! StreamPartStreamStart &&
                part is! StreamPartRaw &&
                part is! StreamPartResponseMetadata) {
              sawStreamPart = true;
            }
            _throwIfStreamDeadline(
              scope.signal,
              stepTimeout: timeout?.step,
              stepStopwatch: stepStopwatch,
            );
          }
        } finally {
          try {
            await iterator.cancel();
          } catch (_) {}
        }
        _throwIfStreamDeadline(
          scope.signal,
          stepTimeout: timeout?.step,
          stepStopwatch: stepStopwatch,
        );

        for (final entry in reasoningBuffers.entries) {
          stepContent.add(entry.value.finish());
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
        responseMessages.add(normalizedMessages.last);

        if (stepToolCalls.isNotEmpty) {
          final executableCalls = stepToolCalls
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
            ),
          );
          for (
            var executionIndex = 0;
            executionIndex < executions.length;
            executionIndex++
          ) {
            final call = executableCalls[executionIndex];
            final execution = executions[executionIndex];
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
          responseMessages.add(normalizedMessages.last);
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
          responseMessages: List.unmodifiable(
            responseMessages.skip(responseMessageStart),
          ),
          response: LanguageModelV4GenerateResult(
            content: stepContent,
            finishReason: resolvedFinish.finishReason,
            usage: resolvedFinish.usage,
            warnings: List.unmodifiable(lastWarnings),
            providerMetadata: resolvedFinish.providerMetadata,
            rawFinishReason: resolvedFinish.rawFinishReason,
            request: LanguageModelV4RequestMetadata(
              body: bodyInclusion.requestBody ? lastRequestBody : null,
            ),
            response: _streamFilteredResponseMetadata(
              lastResponseMetadata,
              bodyInclusion,
            ),
          ),
          text: stepText,
          finishReason: resolvedFinish.finishReason,
          usage: resolvedFinish.usage,
        );
        steps.add(step);
        lastContent = stepContent;

        safeInvoke(() => (onStepEnd ?? onStepFinish)?.call(stepFinish));
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
      throwIfCancelled(scope.signal);
      scope.checkDeadline();
      final finalOutput = parseOutputWithNoObjectError(
        output: outputSpec,
        text: finalText,
        usage: lastFinishPart?.usage,
        response: lastResponseMetadata,
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
      final aggregateReasoningFiles = steps
          .expand((step) => step.reasoningFiles)
          .toList(growable: false);
      final aggregateDocumentSources = steps
          .expand((step) => step.documentSources)
          .toList(growable: false);
      final aggregateWarnings = steps
          .expand((step) => step.warnings)
          .toList(growable: false);
      final finalStep = steps.last;
      final reasoningParts = finalStep.reasoning;
      final resolvedReasoningText = finalStep.content
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
      final requestInfo = GenerateTextRequest(
        system: buildOutputSystemInstruction(initialInstructions, outputSpec),
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
        metadata: _streamFilteredResponseMetadata(
          lastResponseMetadata,
          bodyInclusion,
        ),
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
        usage: totalUsage,
        totalUsage: totalUsage,
        providerMetadata: resolvedFinish.providerMetadata,
        steps: List.unmodifiable(steps),
        reasoning: List.unmodifiable(reasoningParts),
        reasoningText: resolvedReasoningText,
        sources: List.unmodifiable(aggregateSources),
        documentSources: List.unmodifiable(aggregateDocumentSources),
        files: List.unmodifiable(aggregateFiles),
        reasoningFiles: List.unmodifiable(aggregateReasoningFiles),
        responseMessages: List.unmodifiable(responseMessages),
        request: requestInfo,
        response: responseInfo,
        finalStep: finalStep,
        warnings: List.unmodifiable(aggregateWarnings),
      );

      isTerminal = true;
      await disposeAbortObservation();
      fullController.add(finishEvent);
      safeInvoke(() => (onEnd ?? onFinish)?.call(finishEvent));
      throwIfCancelled(scope.signal);
      scope.checkDeadline();

      textCompleter.completeIfPending(finalText);
      outputCompleter.completeIfPending(finalOutput);
      finishCompleter.completeIfPending(lastFinishPart);
      contentCompleter.completeIfPending(List.unmodifiable(aggregateContent));
      reasoningCompleter.completeIfPending(List.unmodifiable(reasoningParts));
      reasoningTextCompleter.completeIfPending(resolvedReasoningText);
      filesCompleter.completeIfPending(List.unmodifiable(aggregateFiles));
      reasoningFilesCompleter.completeIfPending(
        List.unmodifiable(aggregateReasoningFiles),
      );
      sourcesCompleter.completeIfPending(List.unmodifiable(aggregateSources));
      documentSourcesCompleter.completeIfPending(
        List.unmodifiable(aggregateDocumentSources),
      );
      toolCallsCompleter.completeIfPending(
        List.unmodifiable(aggregateToolCalls),
      );
      toolResultsCompleter.completeIfPending(
        List.unmodifiable(aggregateToolResults),
      );
      finishReasonCompleter.completeIfPending(resolvedFinish.finishReason);
      rawFinishReasonCompleter.completeIfPending(
        resolvedFinish.rawFinishReason,
      );
      usageCompleter.completeIfPending(totalUsage);
      totalUsageCompleter.completeIfPending(totalUsage);
      warningsCompleter.completeIfPending(List.unmodifiable(aggregateWarnings));
      stepsCompleter.completeIfPending(List.unmodifiable(steps));
      finalStepCompleter.completeIfPending(finalStep);
      requestCompleter.completeIfPending(requestInfo);
      responseCompleter.completeIfPending(responseInfo);
      providerMetadataCompleter.completeIfPending(
        resolvedFinish.providerMetadata,
      );
    } catch (error, stackTrace) {
      final filteredError = filterBodyBearingError(error, bodyInclusion);
      isTerminal = true;
      await disposeAbortObservation();
      terminalError = filteredError;
      terminalStackTrace = stackTrace;
      terminalFullStreamErrorEvent = StreamTextErrorEvent(error: filteredError);
      safeInvoke(() => onError?.call(filteredError));
      fullController.add(terminalFullStreamErrorEvent!);

      textCompleter.completeErrorIfPending(filteredError, stackTrace);
      outputCompleter.completeErrorIfPending(filteredError, stackTrace);
      finishCompleter.completeErrorIfPending(filteredError, stackTrace);
      contentCompleter.completeErrorIfPending(filteredError, stackTrace);
      reasoningCompleter.completeErrorIfPending(filteredError, stackTrace);
      reasoningTextCompleter.completeErrorIfPending(filteredError, stackTrace);
      filesCompleter.completeErrorIfPending(filteredError, stackTrace);
      reasoningFilesCompleter.completeErrorIfPending(filteredError, stackTrace);
      sourcesCompleter.completeErrorIfPending(filteredError, stackTrace);
      documentSourcesCompleter.completeErrorIfPending(
        filteredError,
        stackTrace,
      );
      toolCallsCompleter.completeErrorIfPending(filteredError, stackTrace);
      toolResultsCompleter.completeErrorIfPending(filteredError, stackTrace);
      finishReasonCompleter.completeErrorIfPending(filteredError, stackTrace);
      rawFinishReasonCompleter.completeErrorIfPending(
        filteredError,
        stackTrace,
      );
      usageCompleter.completeErrorIfPending(filteredError, stackTrace);
      totalUsageCompleter.completeErrorIfPending(filteredError, stackTrace);
      warningsCompleter.completeErrorIfPending(filteredError, stackTrace);
      stepsCompleter.completeErrorIfPending(filteredError, stackTrace);
      requestCompleter.completeErrorIfPending(filteredError, stackTrace);
      responseCompleter.completeErrorIfPending(filteredError, stackTrace);
      providerMetadataCompleter.completeErrorIfPending(
        filteredError,
        stackTrace,
      );

      if (rawController.hasListener) {
        rawController.addError(filteredError, stackTrace);
      }
      if (textController.hasListener) {
        textController.addError(filteredError, stackTrace);
      }
      if (fullController.hasListener) {
        fullController.addError(filteredError, stackTrace);
      }
      if (partialController.hasListener) {
        partialController.addError(filteredError, stackTrace);
      }
      if (elementController.hasListener) {
        elementController.addError(filteredError, stackTrace);
      }
    } finally {
      await rawController.close();
      await textController.close();
      await fullController.close();
      await partialController.close();
      await elementController.close();
      await disposeAbortObservation();
    }
  });
  runFuture.whenComplete(scope.close).ignore();

  // End the telemetry span when the stream fully finishes or fails. Both
  // completers are settled together, so once finish succeeds totalUsage has
  // succeeded as well.
  finishCompleter.future.then(
    (_) => totalUsageCompleter.future.then(
      (usage) => stepsCompleter.future.then((steps) {
        telemetrySpan
          ..setAttribute(AiTelemetryKeys.promptTokens, usage?.inputTokens.total)
          ..setAttribute(
            AiTelemetryKeys.completionTokens,
            usage?.outputTokens.total,
          )
          ..setAttribute(AiTelemetryKeys.stepCount, steps.length)
          ..end();
        recordMetric(
          AiTelemetryMetrics.totalMs,
          metricStopwatch.elapsedMicroseconds / 1000,
          attributes: {AiTelemetryKeys.operationStatus: 'success'},
        );
        recordMetric(AiTelemetryMetrics.stepCount, steps.length);
        recordMetric(AiTelemetryMetrics.usageKnown, usage == null ? 0 : 1);
        recordMetric(AiTelemetryMetrics.retryCount, retryCount);
        recordMetric(AiTelemetryMetrics.success, 1);
      }),
    ),
    onError: (Object e, StackTrace st) {
      final cancelled = abortSignal?.isCancelled == true;
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
        ..recordException(e, stackTrace: st)
        ..end(error: e);
    },
  );

  final canonicalStream = terminalAwareBroadcastStream(
    source: fullController.stream,
    isTerminal: () => isTerminal,
    terminalError: () => terminalError,
    terminalStackTrace: () => terminalStackTrace,
    replayOnError: () => terminalFullStreamErrorEvent == null
        ? const <StreamTextEvent>[]
        : <StreamTextEvent>[terminalFullStreamErrorEvent!],
  );
  final providerStream = terminalAwareBroadcastStream(
    source: rawController.stream,
    isTerminal: () => isTerminal,
    terminalError: () => terminalError,
    terminalStackTrace: () => terminalStackTrace,
  );

  return StreamTextResult<TOutput>(
    stream: canonicalStream,
    providerStream: providerStream,
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
    reasoningFiles: reasoningFilesCompleter.future,
    sources: sourcesCompleter.future,
    documentSources: documentSourcesCompleter.future,
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
    finalStep: finalStepCompleter.future,
  );
}

LanguageModelV4ResponseMetadata? _streamFilteredResponseMetadata(
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

LanguageModelV4StreamPart _filterStreamPart(
  LanguageModelV4StreamPart part,
  BodyInclusionPolicy policy,
) => switch (part) {
  StreamPartResponseMetadata(:final metadata) => StreamPartResponseMetadata(
    metadata: _streamFilteredResponseMetadata(metadata, policy)!,
  ),
  StreamPartError(:final error) => StreamPartError(
    error: filterBodyBearingError(error, policy),
  ),
  _ => part,
};

bool _hasMeaningfulTelemetryPayload(LanguageModelV4StreamPart part) =>
    switch (part) {
      StreamPartTextDelta(:final delta) => delta.isNotEmpty,
      StreamPartReasoningDelta(:final delta) => delta.isNotEmpty,
      StreamPartToolInputDelta(:final delta) => delta.isNotEmpty,
      StreamPartToolCall(:final toolCall) => toolCall.toolName.isNotEmpty,
      StreamPartToolResult(:final toolResult) => toolResult.toolName.isNotEmpty,
      StreamPartToolApprovalRequest(:final approvalRequest) =>
        approvalRequest.toolCall.toolName.isNotEmpty,
      StreamPartSource(:final source) =>
        source.id.isNotEmpty || source.url.isNotEmpty,
      StreamPartFile(:final file) => file.mediaType.isNotEmpty,
      _ => false,
    };

Future<bool> _moveNextWithStreamTimeout(
  StreamIterator<StreamOutcome<LanguageModelV4StreamPart>> iterator, {
  CancellationToken? abortSignal,
  Duration? timeout,
  Duration? stepTimeout,
  Stopwatch? stepStopwatch,
  Duration? totalTimeout,
  required Stopwatch overallStopwatch,
}) {
  final moveNext = raceWithCancellation(iterator.moveNext(), abortSignal);
  final effectiveTimeout = minTimeout(
    remainingTimeout(timeout: totalTimeout, elapsed: overallStopwatch.elapsed),
    minTimeout(
      timeout,
      stepStopwatch == null
          ? stepTimeout
          : remainingTimeout(
              timeout: stepTimeout,
              elapsed: stepStopwatch.elapsed,
            ),
    ),
  );
  if (effectiveTimeout == null) return moveNext;
  return moveNext.timeout(
    effectiveTimeout,
    onTimeout: () {
      if (abortSignal case final signal?) {
        scheduleMicrotask(signal.cancel);
      }
      throw TimeoutException('Stream chunk timed out.', effectiveTimeout);
    },
  );
}

void _throwIfStreamDeadline(
  CancellationToken signal, {
  required Duration? stepTimeout,
  required Stopwatch stepStopwatch,
}) {
  if (stepTimeout != null && stepStopwatch.elapsed >= stepTimeout) {
    signal.cancel();
    throw TimeoutException('Model step timed out.', stepTimeout);
  }
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
