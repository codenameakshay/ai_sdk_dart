import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../errors/ai_errors.dart';
import '../messages/model_message.dart';
import '../output/output.dart';
import '../stop_conditions/stop_conditions.dart';
import '../tools/tool.dart';
import 'generate_text.dart';

typedef StreamTextOnChunk = void Function(StreamTextChunk chunk);
typedef StreamTextOnError = void Function(Object error);
typedef StreamTextOnFinish<TOutput> =
    void Function(StreamTextFinishEvent<TOutput> event);
typedef StreamTextOnInputStart =
    void Function(StreamTextToolInputStartEvent event);
typedef StreamTextOnInputDelta =
    void Function(StreamTextToolInputDeltaEvent event);
typedef StreamTextOnInputAvailable =
    void Function(StreamTextToolInputEndEvent event);
typedef StreamTextTransform = Iterable<String> Function(String delta);

StreamTextTransform smoothStream({int chunkSize = 12}) {
  if (chunkSize <= 0) {
    return (delta) sync* {
      yield delta;
    };
  }
  return (delta) sync* {
    if (delta.isEmpty) {
      return;
    }
    for (var i = 0; i < delta.length; i += chunkSize) {
      final end = (i + chunkSize) > delta.length ? delta.length : i + chunkSize;
      yield delta.substring(i, end);
    }
  };
}

sealed class StreamTextChunk {
  const StreamTextChunk();
}

class StreamTextTextChunk extends StreamTextChunk {
  const StreamTextTextChunk({required this.id, required this.text});

  final String id;
  final String text;
}

class StreamTextReasoningChunk extends StreamTextChunk {
  const StreamTextReasoningChunk({required this.delta});

  final String delta;
}

class StreamTextToolCallChunk extends StreamTextChunk {
  const StreamTextToolCallChunk({required this.toolCall});

  final LanguageModelV3ToolCallPart toolCall;
}

class StreamTextToolResultChunk extends StreamTextChunk {
  const StreamTextToolResultChunk({
    required this.toolResult,
    required this.preliminary,
  });

  final LanguageModelV3ToolResultPart toolResult;
  final bool preliminary;
}

class StreamTextRawChunk extends StreamTextChunk {
  const StreamTextRawChunk({required this.part});

  final LanguageModelV3StreamPart part;
}

class StreamTextSourceChunk extends StreamTextChunk {
  const StreamTextSourceChunk({required this.source});

  final LanguageModelV3SourcePart source;
}

class StreamTextFileChunk extends StreamTextChunk {
  const StreamTextFileChunk({required this.file});

  final LanguageModelV3FilePart file;
}

class StreamTextToolInputStartChunk extends StreamTextChunk {
  const StreamTextToolInputStartChunk({
    required this.toolCallId,
    required this.toolName,
  });

  final String toolCallId;
  final String toolName;
}

class StreamTextToolInputDeltaChunk extends StreamTextChunk {
  const StreamTextToolInputDeltaChunk({
    required this.toolCallId,
    required this.toolName,
    required this.delta,
    required this.inputBuffer,
  });

  final String toolCallId;
  final String toolName;
  final String delta;
  final String inputBuffer;
}

class StreamTextUsageChunk extends StreamTextChunk {
  const StreamTextUsageChunk({required this.usage});
  final LanguageModelV3Usage usage;
}

sealed class StreamTextEvent {
  const StreamTextEvent();
}

class StreamTextStartEvent extends StreamTextEvent {
  const StreamTextStartEvent();
}

class StreamTextStartStepEvent extends StreamTextEvent {
  const StreamTextStartStepEvent({required this.stepNumber});

  final int stepNumber;
}

class StreamTextTextStartEvent extends StreamTextEvent {
  const StreamTextTextStartEvent({required this.id});

  final String id;
}

class StreamTextTextDeltaEvent extends StreamTextEvent {
  const StreamTextTextDeltaEvent({required this.id, required this.delta});

  final String id;
  final String delta;
}

class StreamTextTextEndEvent extends StreamTextEvent {
  const StreamTextTextEndEvent({required this.id});

  final String id;
}

class StreamTextReasoningStartEvent extends StreamTextEvent {
  const StreamTextReasoningStartEvent({required this.id});

  final String id;
}

class StreamTextReasoningDeltaEvent extends StreamTextEvent {
  const StreamTextReasoningDeltaEvent({required this.id, required this.delta});

  final String id;
  final String delta;
}

class StreamTextReasoningEndEvent extends StreamTextEvent {
  const StreamTextReasoningEndEvent({required this.id});

  final String id;
}

class StreamTextSourceEvent extends StreamTextEvent {
  const StreamTextSourceEvent({required this.source});

  final LanguageModelV3SourcePart source;
}

class StreamTextFileEvent extends StreamTextEvent {
  const StreamTextFileEvent({required this.file});

  final LanguageModelV3FilePart file;
}

class StreamTextToolInputStartEvent extends StreamTextEvent {
  const StreamTextToolInputStartEvent({
    required this.toolCallId,
    required this.toolName,
  });

  final String toolCallId;
  final String toolName;
}

class StreamTextToolInputDeltaEvent extends StreamTextEvent {
  const StreamTextToolInputDeltaEvent({
    required this.toolCallId,
    required this.toolName,
    required this.delta,
    required this.inputBuffer,
  });

  final String toolCallId;
  final String toolName;
  final String delta;
  final String inputBuffer;
}

class StreamTextToolInputEndEvent extends StreamTextEvent {
  const StreamTextToolInputEndEvent({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    required this.inputBuffer,
  });

  final String toolCallId;
  final String toolName;
  final Object input;
  final String inputBuffer;
}

class StreamTextToolResultEvent extends StreamTextEvent {
  const StreamTextToolResultEvent({
    required this.toolResult,
    required this.preliminary,
  });

  final LanguageModelV3ToolResultPart toolResult;
  final bool preliminary;
}

class StreamTextToolErrorEvent extends StreamTextEvent {
  const StreamTextToolErrorEvent({
    required this.toolCallId,
    required this.toolName,
    required this.error,
  });

  final String toolCallId;
  final String toolName;
  final Object error;
}

class StreamTextRawEvent extends StreamTextEvent {
  const StreamTextRawEvent({required this.part});

  final LanguageModelV3StreamPart part;
}

class StreamTextErrorEvent extends StreamTextEvent {
  const StreamTextErrorEvent({required this.error});

  final Object error;
}

class StreamTextFinishStepEvent extends StreamTextEvent {
  const StreamTextFinishStepEvent({required this.step});

  final GenerateTextStepFinishEvent step;
}

/// Emitted when mid-stream usage data arrives from the provider.
class StreamTextUsageEvent extends StreamTextEvent {
  const StreamTextUsageEvent({required this.usage});
  final LanguageModelV3Usage usage;
}

class StreamTextFinishEvent<TOutput> extends StreamTextEvent {
  const StreamTextFinishEvent({
    required this.text,
    required this.output,
    required this.finishReason,
    required this.steps,
    required this.reasoning,
    required this.reasoningText,
    required this.sources,
    required this.files,
    required this.responseMessages,
    required this.request,
    required this.response,
    this.rawFinishReason,
    this.usage,
    this.totalUsage,
    this.warnings = const [],
    this.providerMetadata,
  });

  final String text;
  final TOutput output;
  final LanguageModelV3FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV3Usage? usage;
  final LanguageModelV3Usage? totalUsage;
  final ProviderMetadata? providerMetadata;
  final List<GenerateTextStep> steps;
  final List<LanguageModelV3ReasoningPart> reasoning;
  final String reasoningText;
  final List<LanguageModelV3SourcePart> sources;
  final List<LanguageModelV3FilePart> files;
  final List<LanguageModelV3Message> responseMessages;
  final GenerateTextRequest request;
  final GenerateTextResponse response;
  final List<String> warnings;
}

/// Result wrapper for `streamText`.
class StreamTextResult<TOutput> {
  const StreamTextResult({
    required this.stream,
    required this.fullStream,
    required this.textStream,
    required this.partialOutputStream,
    required this.elementStream,
    required this.text,
    required this.output,
    required this.content,
    required this.reasoning,
    required this.reasoningText,
    required this.files,
    required this.sources,
    required this.toolCalls,
    required this.toolResults,
    required this.finishReason,
    required this.rawFinishReason,
    required this.usage,
    required this.totalUsage,
    required this.warnings,
    required this.steps,
    required this.request,
    required this.response,
    required this.providerMetadata,
    required this.finish,
  });

  /// Raw provider stream.
  final Stream<LanguageModelV3StreamPart> stream;

  /// Full stream with normalized event taxonomy.
  final Stream<StreamTextEvent> fullStream;

  /// Convenience stream with text deltas only.
  final Stream<String> textStream;

  /// Parsed partial output snapshots for structured outputs.
  final Stream<Object?> partialOutputStream;

  /// Parsed completed elements for `Output.array(...)`.
  final Stream<Object?> elementStream;

  /// Full generated text after stream completion.
  final Future<String> text;

  /// Parsed output after stream completion.
  final Future<TOutput> output;

  final Future<List<LanguageModelV3ContentPart>> content;
  final Future<List<LanguageModelV3ReasoningPart>> reasoning;
  final Future<String> reasoningText;
  final Future<List<LanguageModelV3FilePart>> files;
  final Future<List<LanguageModelV3SourcePart>> sources;
  final Future<List<LanguageModelV3ToolCallPart>> toolCalls;
  final Future<List<LanguageModelV3ToolResultPart>> toolResults;
  final Future<LanguageModelV3FinishReason?> finishReason;
  final Future<String?> rawFinishReason;
  final Future<LanguageModelV3Usage?> usage;
  final Future<LanguageModelV3Usage?> totalUsage;
  final Future<List<String>> warnings;
  final Future<List<GenerateTextStep>> steps;
  final Future<GenerateTextRequest> request;
  final Future<GenerateTextResponse> response;
  final Future<ProviderMetadata?> providerMetadata;

  /// Finish metadata when available.
  final Future<StreamPartFinish?> finish;
}

/// Provider-agnostic streaming text generation.
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
  List<LanguageModelV3ToolApprovalResponse> toolApprovalResponses = const [],
  Object? abortSignal,
  Object? experimentalContext,
  int? maxOutputTokens,
  double? temperature,
  double? topP,
  StreamTextOnChunk? onChunk,
  StreamTextOnError? onError,
  StreamTextOnFinish<TOutput>? onFinish,
  GenerateTextOnStepFinish? onStepFinish,
  GenerateTextPrepareStep? prepareStep,
  StreamTextOnInputStart? onInputStart,
  StreamTextOnInputDelta? onInputDelta,
  StreamTextOnInputAvailable? onInputAvailable,
  StreamTextTransform? experimentalTransform,
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

  unawaited(
    Future<void>(() async {
      final steps = <GenerateTextStep>[];
      final overallTextBuffer = StringBuffer();
      var emittedArrayElements = 0;
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

      try {
        fullController.add(const StreamTextStartEvent());
        final totalSteps = tools.isEmpty ? 1 : (maxSteps < 1 ? 1 : maxSteps);
        for (var stepNumber = 0; stepNumber < totalSteps; stepNumber++) {
          fullController.add(StreamTextStartStepEvent(stepNumber: stepNumber));

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
          final stepProviderOptions =
              prepareResult?.providerOptions ?? providerOptions;
          final activeTools = _selectActiveTools(
            tools,
            prepareResult?.activeTools,
          );
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

          final response = await stepModel.doStream(
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
          if (response.rawResponse is Map) {
            rawEnvelope = (response.rawResponse as Map)
                .cast<Object?, Object?>();
            refreshEnvelopeFromRaw();
          }

          final stepTextById = <String, StringBuffer>{};
          final stepToolCalls = <LanguageModelV3ToolCallPart>[];
          final stepToolResults = <LanguageModelV3ToolResultPart>[];
          final stepApprovalRequests =
              <LanguageModelV3ToolApprovalRequestPart>[];
          final stepContent = <LanguageModelV3ContentPart>[];
          final toolInputBuffers = <String, StringBuffer>{};
          var inReasoning = false;
          var reasoningClosed = false;
          const reasoningId = 'reasoning-0';
          final reasoningBuffer = StringBuffer();
          StreamPartFinish? stepFinishPart;

          await for (final part in response.stream) {
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
                final transformedDeltas =
                    experimentalTransform?.call(delta) ?? [delta];
                for (final transformedDelta in transformedDeltas) {
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

                  if (outputSpec is! TextOutput) {
                    final partial = _tryParsePartialOutput(
                      outputSpec,
                      overallTextBuffer.toString(),
                    );
                    if (partial != null) {
                      partialController.add(partial);
                    }
                    final nextCount = _emitArrayElementsIfAny(
                      output: outputSpec,
                      text: overallTextBuffer.toString(),
                      alreadyEmittedCount: emittedArrayElements,
                      onElement: elementController.add,
                    );
                    emittedArrayElements = nextCount;
                  }
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
                fullController.add(StreamTextErrorEvent(error: error));
                onError?.call(error);
              case StreamPartFinish():
                if (part.usage != null) {
                  fullController.add(StreamTextUsageEvent(usage: part.usage!));
                  onChunk?.call(StreamTextUsageChunk(usage: part.usage!));
                }
                stepFinishPart = part;
                lastFinishPart = part;
            }
          }

          if (inReasoning && !reasoningClosed) {
            stepContent.add(
              LanguageModelV3ReasoningPart(text: reasoningBuffer.toString()),
            );
            fullController.add(
              const StreamTextReasoningEndEvent(id: reasoningId),
            );
          }

          _validateToolChoiceInStreamingStep(
            stepToolCalls: stepToolCalls,
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
              final execution = await _executeToolCall(
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
                      _stringifyToolOutput(preliminary),
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

          _safeInvoke(() => onStepFinish?.call(stepFinish));
          fullController.add(StreamTextFinishStepEvent(step: stepFinish));

          final shouldStop =
              stepToolResults.isEmpty ||
              stepApprovalRequests.isNotEmpty ||
              stopConditions.any(
                (condition) => condition(
                  StepSnapshot(
                    stepCount: stepNumber + 1,
                    toolCallNames: stepToolCalls
                        .map((call) => call.toolName)
                        .toList(),
                  ),
                ),
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
        final finalOutput = _parseOutputWithNoObjectError(
          output: outputSpec,
          text: finalText,
          usage: lastFinishPart?.usage,
          response: lastResponseMetadata,
        );
        final totalUsage = _sumUsage(steps.map((step) => step.usage));
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
              (part) => part is LanguageModelV3ReasoningPart
                  ? part.text
                  : '[REDACTED]',
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

        fullController.add(finishEvent);
        _safeInvoke(() => onFinish?.call(finishEvent));

        if (!textCompleter.isCompleted) {
          textCompleter.complete(finalText);
        }
        if (!outputCompleter.isCompleted) {
          outputCompleter.complete(finalOutput);
        }
        if (!finishCompleter.isCompleted) {
          finishCompleter.complete(lastFinishPart);
        }
        if (!contentCompleter.isCompleted) {
          contentCompleter.complete(List.unmodifiable(lastContent));
        }
        if (!reasoningCompleter.isCompleted) {
          reasoningCompleter.complete(List.unmodifiable(reasoning));
        }
        if (!reasoningTextCompleter.isCompleted) {
          reasoningTextCompleter.complete(resolvedReasoningText);
        }
        if (!filesCompleter.isCompleted) {
          filesCompleter.complete(List.unmodifiable(files));
        }
        if (!sourcesCompleter.isCompleted) {
          sourcesCompleter.complete(List.unmodifiable(sources));
        }
        if (!toolCallsCompleter.isCompleted) {
          toolCallsCompleter.complete(
            List.unmodifiable(
              lastContent.whereType<LanguageModelV3ToolCallPart>().toList(),
            ),
          );
        }
        if (!toolResultsCompleter.isCompleted) {
          toolResultsCompleter.complete(
            List.unmodifiable(
              lastContent.whereType<LanguageModelV3ToolResultPart>().toList(),
            ),
          );
        }
        if (!finishReasonCompleter.isCompleted) {
          finishReasonCompleter.complete(resolvedFinish.finishReason);
        }
        if (!rawFinishReasonCompleter.isCompleted) {
          rawFinishReasonCompleter.complete(resolvedFinish.rawFinishReason);
        }
        if (!usageCompleter.isCompleted) {
          usageCompleter.complete(resolvedFinish.usage);
        }
        if (!totalUsageCompleter.isCompleted) {
          totalUsageCompleter.complete(totalUsage);
        }
        if (!warningsCompleter.isCompleted) {
          warningsCompleter.complete(List.unmodifiable(lastWarnings));
        }
        if (!stepsCompleter.isCompleted) {
          stepsCompleter.complete(List.unmodifiable(steps));
        }
        if (!requestCompleter.isCompleted) {
          requestCompleter.complete(requestInfo);
        }
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(responseInfo);
        }
        if (!providerMetadataCompleter.isCompleted) {
          providerMetadataCompleter.complete(resolvedFinish.providerMetadata);
        }
      } catch (error, stackTrace) {
        refreshEnvelopeFromRaw();
        if (!textCompleter.isCompleted) {
          textCompleter.complete(overallTextBuffer.toString());
        }
        if (!outputCompleter.isCompleted) {
          outputCompleter.completeError(error, stackTrace);
        }
        if (!finishCompleter.isCompleted) {
          finishCompleter.complete(lastFinishPart);
        }
        final reasoning = lastContent
            .whereType<LanguageModelV3ReasoningPart>()
            .toList();
        final files = lastContent.whereType<LanguageModelV3FilePart>().toList();
        final sources = lastContent
            .whereType<LanguageModelV3SourcePart>()
            .toList();
        final fallbackRequest = GenerateTextRequest(
          system: systemInstruction,
          messages: List.unmodifiable(normalizedMessages),
          body: lastRequestBody,
        );
        final fallbackResponse = GenerateTextResponse(
          messages: List.unmodifiable(
            normalizedMessages
                .where(
                  (message) =>
                      message.role == LanguageModelV3Role.assistant ||
                      message.role == LanguageModelV3Role.tool,
                )
                .toList(),
          ),
          body: lastResponseBody,
          metadata: lastResponseMetadata,
        );

        if (!contentCompleter.isCompleted) {
          contentCompleter.complete(List.unmodifiable(lastContent));
        }
        if (!reasoningCompleter.isCompleted) {
          reasoningCompleter.complete(List.unmodifiable(reasoning));
        }
        if (!reasoningTextCompleter.isCompleted) {
          reasoningTextCompleter.complete(
            lastContent
                .where(
                  (part) =>
                      part is LanguageModelV3ReasoningPart ||
                      part is LanguageModelV3RedactedReasoningPart,
                )
                .map(
                  (part) => part is LanguageModelV3ReasoningPart
                      ? part.text
                      : '[REDACTED]',
                )
                .join(),
          );
        }
        if (!filesCompleter.isCompleted) {
          filesCompleter.complete(List.unmodifiable(files));
        }
        if (!sourcesCompleter.isCompleted) {
          sourcesCompleter.complete(List.unmodifiable(sources));
        }
        if (!toolCallsCompleter.isCompleted) {
          toolCallsCompleter.complete(
            List.unmodifiable(
              lastContent.whereType<LanguageModelV3ToolCallPart>().toList(),
            ),
          );
        }
        if (!toolResultsCompleter.isCompleted) {
          toolResultsCompleter.complete(
            List.unmodifiable(
              lastContent.whereType<LanguageModelV3ToolResultPart>().toList(),
            ),
          );
        }
        if (!finishReasonCompleter.isCompleted) {
          finishReasonCompleter.complete(lastFinishPart?.finishReason);
        }
        if (!rawFinishReasonCompleter.isCompleted) {
          rawFinishReasonCompleter.complete(lastFinishPart?.rawFinishReason);
        }
        if (!usageCompleter.isCompleted) {
          usageCompleter.complete(lastFinishPart?.usage);
        }
        if (!totalUsageCompleter.isCompleted) {
          totalUsageCompleter.complete(
            _sumUsage(steps.map((step) => step.usage)),
          );
        }
        if (!warningsCompleter.isCompleted) {
          warningsCompleter.complete(List.unmodifiable(lastWarnings));
        }
        if (!stepsCompleter.isCompleted) {
          stepsCompleter.complete(List.unmodifiable(steps));
        }
        if (!requestCompleter.isCompleted) {
          requestCompleter.complete(fallbackRequest);
        }
        if (!responseCompleter.isCompleted) {
          responseCompleter.complete(fallbackResponse);
        }
        if (!providerMetadataCompleter.isCompleted) {
          providerMetadataCompleter.complete(lastFinishPart?.providerMetadata);
        }
        onError?.call(error);
        fullController.add(StreamTextErrorEvent(error: error));
      } finally {
        await rawController.close();
        await textController.close();
        await fullController.close();
        await partialController.close();
        await elementController.close();
      }
    }),
  );

  return StreamTextResult<TOutput>(
    stream: rawController.stream,
    fullStream: fullController.stream,
    textStream: textController.stream,
    partialOutputStream: partialController.stream,
    elementStream: elementController.stream,
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

class _ToolSelection {
  const _ToolSelection({required this.exposedTools, required this.toolChoice});

  final ToolSet exposedTools;
  final LanguageModelV3ToolChoice? toolChoice;
}

class _ToolExecutionResult {
  const _ToolExecutionResult({
    this.toolResult,
    this.approvalRequest,
    this.toolError,
  });

  final LanguageModelV3ToolResultPart? toolResult;
  final LanguageModelV3ToolApprovalRequestPart? approvalRequest;
  final Object? toolError;
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

void _validateToolChoiceInStreamingStep({
  required List<LanguageModelV3ToolCallPart> stepToolCalls,
  required ToolSet tools,
  required LanguageModelV3ToolChoice? toolChoice,
  required int stepNumber,
}) {
  if (toolChoice is ToolChoiceNone && stepToolCalls.isNotEmpty) {
    throw AiApiCallError(
      'Step $stepNumber produced tool calls while toolChoice is none.',
    );
  }
  if (toolChoice is ToolChoiceRequired && stepToolCalls.isEmpty) {
    throw AiApiCallError(
      'Step $stepNumber produced no tool calls while toolChoice is required.',
    );
  }
  if (toolChoice is ToolChoiceSpecific) {
    for (final call in stepToolCalls) {
      if (call.toolName != toolChoice.toolName) {
        throw AiApiCallError(
          'Step $stepNumber called "${call.toolName}" but toolChoice '
          'requires "${toolChoice.toolName}".',
        );
      }
    }
  }
  for (final call in stepToolCalls) {
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
  required void Function(Object? value) onPreliminaryResult,
  Object? abortSignal,
  Object? experimentalContext,
  GenerateTextExperimentalOnToolCallStart? onToolCallStart,
  GenerateTextExperimentalOnToolCallFinish? onToolCallFinish,
}) async {
  final tool = tools[call.toolName];
  if (tool == null) {
    final error = 'Tool not found.';
    return _ToolExecutionResult(
      toolResult: LanguageModelV3ToolResultPart(
        toolCallId: call.toolCallId,
        toolName: call.toolName,
        isError: true,
        output: ToolResultOutputText(error),
      ),
      toolError: error,
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
        toolError: approvalResponse.reason ?? 'Tool execution denied.',
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
      const error = 'Tool has no executor.';
      return _ToolExecutionResult(
        toolResult: LanguageModelV3ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          isError: true,
          output: ToolResultOutputText(error),
        ),
        toolError: error,
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
      final finalOutput = await _resolveFinalToolOutput(
        output,
        onPreliminaryResult: onPreliminaryResult,
      );
      stopwatch.stop();
      _safeInvoke(
        () => onToolCallFinish?.call(
          GenerateTextExperimentalToolCallFinishEvent(
            toolCall: call,
            durationMs: stopwatch.elapsedMilliseconds,
            success: true,
            output: finalOutput,
          ),
        ),
      );
      return _ToolExecutionResult(
        toolResult: LanguageModelV3ToolResultPart(
          toolCallId: call.toolCallId,
          toolName: call.toolName,
          output: ToolResultOutputText(_stringifyToolOutput(finalOutput)),
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
      toolError: error,
    );
  }
}

Future<Object?> _resolveFinalToolOutput(
  Object? output, {
  required void Function(Object? value) onPreliminaryResult,
}) async {
  if (output is Stream) {
    Object? previous;
    var seenAny = false;
    await for (final item in output) {
      if (seenAny) {
        onPreliminaryResult(previous);
      }
      previous = item;
      seenAny = true;
    }
    if (!seenAny) {
      return null;
    }
    return previous;
  }
  return output;
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

int _emitArrayElementsIfAny({
  required Output<dynamic> output,
  required String text,
  required int alreadyEmittedCount,
  required void Function(Object? element) onElement,
}) {
  if (output is! ArrayOutput) {
    return alreadyEmittedCount;
  }
  final parsedElements = _parsePartialArrayElements(text);
  var emittedCount = alreadyEmittedCount;

  for (
    var index = alreadyEmittedCount;
    index < parsedElements.length;
    index++
  ) {
    final item = parsedElements[index];
    try {
      if (item is Map<String, dynamic>) {
        onElement(output.element.fromJson(item));
        emittedCount++;
      } else if (item is Map) {
        onElement(output.element.fromJson(item.cast<String, dynamic>()));
        emittedCount++;
      }
    } catch (_) {}
  }
  return emittedCount;
}

TOutput? _tryParsePartialOutput<TOutput>(Output<TOutput> output, String text) {
  if (output is ArrayOutput) {
    final arrayOutput = output as ArrayOutput<dynamic>;
    final parsedElements = _parsePartialArrayElements(text);
    final values = <dynamic>[];
    for (final item in parsedElements) {
      try {
        if (item is Map<String, dynamic>) {
          values.add(arrayOutput.element.fromJson(item));
        } else if (item is Map) {
          values.add(
            arrayOutput.element.fromJson(item.cast<String, dynamic>()),
          );
        }
      } catch (_) {}
    }
    return values as TOutput;
  }
  try {
    return _parseOutput(output, text);
  } catch (_) {
    return null;
  }
}

List<Object?> _parsePartialArrayElements(String text) {
  final fullJson = _safeParseJson(text.trim());
  if (fullJson is List) {
    return fullJson.cast<Object?>();
  }

  final candidate = _extractJsonCandidate(text);
  if (candidate == null) {
    return const [];
  }
  final start = candidate.indexOf('[');
  if (start < 0) {
    return const [];
  }
  final body = candidate.substring(start + 1);
  final elements = <Object?>[];
  var inString = false;
  var escaped = false;
  var depth = 0;
  var tokenStart = 0;

  void flushToken(int endExclusive) {
    final token = body.substring(tokenStart, endExclusive).trim();
    if (token.isEmpty) {
      tokenStart = endExclusive + 1;
      return;
    }
    try {
      elements.add(jsonDecode(token));
    } catch (_) {}
    tokenStart = endExclusive + 1;
  }

  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char == '{' || char == '[') {
      depth++;
      continue;
    }
    if (char == '}' || char == ']') {
      if (depth > 0) {
        depth--;
      } else if (char == ']') {
        flushToken(i);
        break;
      }
      continue;
    }
    if (char == ',' && depth == 0) {
      flushToken(i);
    }
  }

  return elements;
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
  required LanguageModelV3Usage? usage,
  required LanguageModelV3ResponseMetadata? response,
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
      response: response,
      usage: usage,
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
        } catch (_) {}
      }
    }

    final candidate = _extractJsonCandidate(text);
    if (candidate != null) {
      try {
        return jsonDecode(candidate);
      } catch (_) {
        return null;
      }
    }

    return null;
  }
}

String? _extractJsonCandidate(String text) {
  final startObject = text.indexOf('{');
  final startArray = text.indexOf('[');
  final starts = [
    if (startObject >= 0) startObject,
    if (startArray >= 0) startArray,
  ];
  if (starts.isEmpty) {
    return null;
  }
  final start = starts.reduce((a, b) => a < b ? a : b);
  final open = text[start];
  final close = open == '{' ? '}' : ']';

  var inString = false;
  var escaped = false;
  var depth = 0;
  for (var i = start; i < text.length; i++) {
    final char = text[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == r'\') {
      escaped = true;
      continue;
    }
    if (char == '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char == open) {
      depth++;
      continue;
    }
    if (char == close) {
      depth--;
      if (depth == 0) {
        return text.substring(start, i + 1);
      }
    }
  }
  return null;
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
