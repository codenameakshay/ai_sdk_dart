import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../generate_text.dart';

typedef StreamTextOnChunk = void Function(StreamTextChunk chunk);
typedef StreamTextOnError = void Function(Object error);
typedef StreamTextOnFinish<TOutput> =
    void Function(StreamTextFinishEvent<TOutput> event);
typedef StreamTextOnEnd<TOutput> = StreamTextOnFinish<TOutput>;
typedef StreamTextOnStepEnd = GenerateTextOnStepFinish;
typedef StreamTextOnAbort = void Function();
typedef StreamTextOnInputStart =
    void Function(StreamTextToolInputStartEvent event);
typedef StreamTextOnInputDelta =
    void Function(StreamTextToolInputDeltaEvent event);
typedef StreamTextOnInputAvailable =
    void Function(StreamTextToolInputEndEvent event);
typedef StreamTextTransform = Stream<String> Function(String delta);

StreamTextTransform smoothStream({int chunkSize = 12, int delayInMs = 0}) {
  if (chunkSize <= 0) {
    return (delta) => Stream.value(delta);
  }
  return (delta) async* {
    if (delta.isEmpty) return;
    var first = true;
    for (var i = 0; i < delta.length; i += chunkSize) {
      if (!first && delayInMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayInMs));
      }
      final end = (i + chunkSize) > delta.length ? delta.length : i + chunkSize;
      yield delta.substring(i, end);
      first = false;
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

  final LanguageModelV4ToolCallPart toolCall;
}

class StreamTextToolResultChunk extends StreamTextChunk {
  const StreamTextToolResultChunk({
    required this.toolResult,
    required this.preliminary,
  });

  final LanguageModelV4ToolResultPart toolResult;
  final bool preliminary;
}

class StreamTextRawChunk extends StreamTextChunk {
  const StreamTextRawChunk({required this.rawValue});

  final Object? rawValue;
}

class StreamTextSourceChunk extends StreamTextChunk {
  const StreamTextSourceChunk({required this.source});

  final LanguageModelV4SourcePart source;
}

class StreamTextDocumentSourceChunk extends StreamTextChunk {
  const StreamTextDocumentSourceChunk({required this.source});

  final LanguageModelV4DocumentSourcePart source;
}

class StreamTextFileChunk extends StreamTextChunk {
  const StreamTextFileChunk({required this.file});

  final LanguageModelV4FilePart file;
}

class StreamTextReasoningFileChunk extends StreamTextChunk {
  const StreamTextReasoningFileChunk({required this.file});

  final LanguageModelV4ReasoningFilePart file;
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

  final LanguageModelV4Usage usage;
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
  const StreamTextReasoningStartEvent({
    required this.id,
    this.providerMetadata,
  });

  final String id;
  final ProviderMetadata? providerMetadata;
}

class StreamTextReasoningDeltaEvent extends StreamTextEvent {
  const StreamTextReasoningDeltaEvent({
    required this.id,
    required this.delta,
    this.providerMetadata,
  });

  final String id;
  final String delta;
  final ProviderMetadata? providerMetadata;
}

class StreamTextReasoningEndEvent extends StreamTextEvent {
  const StreamTextReasoningEndEvent({
    required this.id,
    this.providerMetadata,
    this.signature,
  });

  final String id;
  final ProviderMetadata? providerMetadata;
  final String? signature;
}

class StreamTextSourceEvent extends StreamTextEvent {
  const StreamTextSourceEvent({required this.source});

  final LanguageModelV4SourcePart source;
}

class StreamTextDocumentSourceEvent extends StreamTextEvent {
  const StreamTextDocumentSourceEvent({required this.source});

  final LanguageModelV4DocumentSourcePart source;
}

class StreamTextFileEvent extends StreamTextEvent {
  const StreamTextFileEvent({required this.file});

  final LanguageModelV4FilePart file;
}

class StreamTextReasoningFileEvent extends StreamTextEvent {
  const StreamTextReasoningFileEvent({required this.file});

  final LanguageModelV4ReasoningFilePart file;
}

class StreamTextOpaqueEvent extends StreamTextEvent {
  const StreamTextOpaqueEvent({required this.opaque});

  final LanguageModelV4OpaquePart opaque;
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

  final LanguageModelV4ToolResultPart toolResult;
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
  const StreamTextRawEvent({required this.rawValue});

  final Object? rawValue;
}

class StreamTextErrorEvent extends StreamTextEvent {
  const StreamTextErrorEvent({required this.error});

  final Object error;
}

class StreamTextFinishStepEvent extends StreamTextEvent {
  const StreamTextFinishStepEvent({required this.step});

  final GenerateTextStepFinishEvent step;
}

class StreamTextUsageEvent extends StreamTextEvent {
  const StreamTextUsageEvent({required this.usage});

  final LanguageModelV4Usage usage;
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
    required this.documentSources,
    required this.files,
    required this.reasoningFiles,
    required this.responseMessages,
    required this.request,
    required this.response,
    required this.finalStep,
    this.rawFinishReason,
    this.usage,
    this.totalUsage,
    this.warnings = const [],
    this.providerMetadata,
  });

  final String text;
  final TOutput output;
  final LanguageModelV4FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV4Usage? usage;
  final LanguageModelV4Usage? totalUsage;
  final ProviderMetadata? providerMetadata;
  final List<GenerateTextStep> steps;
  final List<LanguageModelV4ReasoningPart> reasoning;
  final String reasoningText;
  final List<LanguageModelV4SourcePart> sources;
  final List<LanguageModelV4DocumentSourcePart> documentSources;
  final List<LanguageModelV4FilePart> files;
  final List<LanguageModelV4ReasoningFilePart> reasoningFiles;
  final List<LanguageModelV4Message> responseMessages;
  final GenerateTextRequest request;
  final GenerateTextResponse response;
  final GenerateTextStep finalStep;
  final List<LanguageModelV4Warning> warnings;
}

class StreamTextResult<TOutput> {
  const StreamTextResult({
    required this.stream,
    required this.providerStream,
    required this.textStream,
    required this.partialOutputStream,
    required this.elementStream,
    required this.text,
    required this.output,
    required this.content,
    required this.reasoning,
    required this.reasoningText,
    required this.files,
    required this.reasoningFiles,
    required this.sources,
    required this.documentSources,
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
    required this.finalStep,
  });

  /// Exhaustive high-level lifecycle events for this generation.
  final Stream<StreamTextEvent> stream;

  /// Provider-native stream parts, exposed for adapters and diagnostics.
  final Stream<LanguageModelV4StreamPart> providerStream;

  /// Deprecated migration alias for [stream].
  ///
  /// This getter intentionally returns the canonical stream instance. It is
  /// kept as a source migration aid and does not create a second broadcast
  /// subscription or event producer.
  @Deprecated('Use stream instead.')
  Stream<StreamTextEvent> get fullStream => stream;
  final Stream<String> textStream;
  final Stream<Object?> partialOutputStream;
  final Stream<Object?> elementStream;
  final Future<String> text;
  final Future<TOutput> output;
  final Future<List<LanguageModelV4ContentPart>> content;
  final Future<List<LanguageModelV4ReasoningPart>> reasoning;
  final Future<String> reasoningText;
  final Future<List<LanguageModelV4FilePart>> files;
  final Future<List<LanguageModelV4ReasoningFilePart>> reasoningFiles;
  final Future<List<LanguageModelV4SourcePart>> sources;
  final Future<List<LanguageModelV4DocumentSourcePart>> documentSources;
  final Future<List<LanguageModelV4ToolCallPart>> toolCalls;
  final Future<List<LanguageModelV4ToolResultPart>> toolResults;
  final Future<LanguageModelV4FinishReason?> finishReason;
  final Future<String?> rawFinishReason;
  final Future<LanguageModelV4Usage?> usage;
  final Future<LanguageModelV4Usage?> totalUsage;
  final Future<List<LanguageModelV4Warning>> warnings;
  final Future<List<GenerateTextStep>> steps;
  final Future<GenerateTextRequest> request;
  final Future<GenerateTextResponse> response;
  final Future<ProviderMetadata?> providerMetadata;
  final Future<StreamPartFinish?> finish;
  final Future<GenerateTextStep> finalStep;
}
