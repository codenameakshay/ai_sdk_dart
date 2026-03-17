import '../shared/provider_metadata.dart';
import 'language_model_v3_finish_reason.dart';
import 'language_model_v3_content.dart';
import 'language_model_v3_usage.dart';

/// A part emitted during streaming generation.
sealed class LanguageModelV3StreamPart {
  const LanguageModelV3StreamPart();
}

class StreamPartTextStart extends LanguageModelV3StreamPart {
  const StreamPartTextStart({required this.id});
  final String id;
}

class StreamPartTextDelta extends LanguageModelV3StreamPart {
  const StreamPartTextDelta({required this.id, required this.delta});
  final String id;
  final String delta;
}

class StreamPartTextEnd extends LanguageModelV3StreamPart {
  const StreamPartTextEnd({required this.id});
  final String id;
}

class StreamPartReasoningDelta extends LanguageModelV3StreamPart {
  const StreamPartReasoningDelta({required this.delta});
  final String delta;
}

class StreamPartSource extends LanguageModelV3StreamPart {
  const StreamPartSource({required this.source});

  final LanguageModelV3SourcePart source;
}

class StreamPartFile extends LanguageModelV3StreamPart {
  const StreamPartFile({required this.file});

  final LanguageModelV3FilePart file;
}

class StreamPartToolCallStart extends LanguageModelV3StreamPart {
  const StreamPartToolCallStart({
    required this.toolCallId,
    required this.toolName,
  });

  final String toolCallId;
  final String toolName;
}

class StreamPartToolCallDelta extends LanguageModelV3StreamPart {
  const StreamPartToolCallDelta({
    required this.toolCallId,
    required this.toolName,
    required this.argsTextDelta,
  });

  final String toolCallId;
  final String toolName;
  final String argsTextDelta;
}

class StreamPartToolCallEnd extends LanguageModelV3StreamPart {
  const StreamPartToolCallEnd({
    required this.toolCallId,
    required this.toolName,
    required this.input,
  });

  final String toolCallId;
  final String toolName;
  final Object input;
}

class StreamPartError extends LanguageModelV3StreamPart {
  const StreamPartError({required this.error});
  final Object error;
}

class StreamPartFinish extends LanguageModelV3StreamPart {
  const StreamPartFinish({
    required this.finishReason,
    this.rawFinishReason,
    this.usage,
    this.providerMetadata,
  });

  final LanguageModelV3FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV3Usage? usage;
  final ProviderMetadata? providerMetadata;
}
