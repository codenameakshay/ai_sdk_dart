import '../shared/provider_metadata.dart';
import 'language_model_v4_generate_result.dart';
import 'language_model_v4_finish_reason.dart';
import 'language_model_v4_content.dart';
import 'language_model_v4_usage.dart';
import 'language_model_v4_warning.dart';

/// A part emitted during streaming generation.
sealed class LanguageModelV4StreamPart {
  const LanguageModelV4StreamPart();
}

class StreamPartTextStart extends LanguageModelV4StreamPart {
  const StreamPartTextStart({required this.id, this.providerMetadata});
  final String id;
  final ProviderMetadata? providerMetadata;
}

class StreamPartTextDelta extends LanguageModelV4StreamPart {
  const StreamPartTextDelta({
    required this.id,
    required this.delta,
    this.providerMetadata,
  });
  final String id;
  final String delta;
  final ProviderMetadata? providerMetadata;
}

class StreamPartTextEnd extends LanguageModelV4StreamPart {
  const StreamPartTextEnd({required this.id, this.providerMetadata});
  final String id;
  final ProviderMetadata? providerMetadata;
}

class StreamPartReasoningStart extends LanguageModelV4StreamPart {
  const StreamPartReasoningStart({
    // coverage:ignore-line
    required this.id,
    this.providerMetadata,
  });
  final String id;
  final ProviderMetadata? providerMetadata;
}

class StreamPartReasoningDelta extends LanguageModelV4StreamPart {
  const StreamPartReasoningDelta({
    required this.id,
    required this.delta,
    this.providerMetadata,
  });
  final String id;
  final String delta;
  final ProviderMetadata? providerMetadata;
}

class StreamPartReasoningEnd extends LanguageModelV4StreamPart {
  const StreamPartReasoningEnd({
    // coverage:ignore-line
    required this.id,
    this.providerMetadata,
  });
  final String id;
  final ProviderMetadata? providerMetadata;
}

class StreamPartSource extends LanguageModelV4StreamPart {
  const StreamPartSource({required this.source});

  final LanguageModelV4SourcePart source;
}

class StreamPartFile extends LanguageModelV4StreamPart {
  const StreamPartFile({required this.file});

  final LanguageModelV4FilePart file;
}

class StreamPartToolInputStart extends LanguageModelV4StreamPart {
  const StreamPartToolInputStart({
    required this.id,
    required this.toolName,
    this.providerMetadata,
  });

  final String id;
  final String toolName;
  final ProviderMetadata? providerMetadata;
}

class StreamPartToolInputDelta extends LanguageModelV4StreamPart {
  const StreamPartToolInputDelta({
    required this.id,
    required this.delta,
    this.providerMetadata,
  });

  final String id;
  final String delta;
  final ProviderMetadata? providerMetadata;
}

class StreamPartToolInputEnd extends LanguageModelV4StreamPart {
  const StreamPartToolInputEnd({required this.id, this.providerMetadata});

  final String id;
  final ProviderMetadata? providerMetadata;
}

class StreamPartToolCall extends LanguageModelV4StreamPart {
  const StreamPartToolCall({required this.toolCall});

  final LanguageModelV4ToolCallPart toolCall;
}

class StreamPartToolResult extends LanguageModelV4StreamPart {
  const StreamPartToolResult({
    // coverage:ignore-line
    required this.toolResult,
    this.preliminary = false,
  });

  final LanguageModelV4ToolResultPart toolResult;
  final bool preliminary;
}

class StreamPartToolApprovalRequest extends LanguageModelV4StreamPart {
  const StreamPartToolApprovalRequest({
    required this.approvalRequest,
  }); // coverage:ignore-line

  final LanguageModelV4ToolApprovalRequestPart approvalRequest;
}

class StreamPartStreamStart extends LanguageModelV4StreamPart {
  const StreamPartStreamStart({
    this.warnings = const [],
  }); // coverage:ignore-line

  final List<LanguageModelV4Warning> warnings;
}

class StreamPartResponseMetadata extends LanguageModelV4StreamPart {
  const StreamPartResponseMetadata({
    required this.metadata,
  }); // coverage:ignore-line

  final LanguageModelV4ResponseMetadata metadata;
}

class StreamPartRaw extends LanguageModelV4StreamPart {
  const StreamPartRaw({required this.rawValue}); // coverage:ignore-line

  final Object? rawValue;
}

class StreamPartError extends LanguageModelV4StreamPart {
  const StreamPartError({required this.error});
  final Object error;
}

class StreamPartFinish extends LanguageModelV4StreamPart {
  const StreamPartFinish({
    required this.finishReason,
    this.rawFinishReason,
    LanguageModelV4Usage? usage,
    this.providerMetadata,
  }) : usage = usage ?? const LanguageModelV4Usage();

  final LanguageModelV4FinishReason finishReason;
  final String? rawFinishReason;
  final LanguageModelV4Usage usage;
  final ProviderMetadata? providerMetadata;
}
