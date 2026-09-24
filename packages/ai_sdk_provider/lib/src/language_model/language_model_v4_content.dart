import 'dart:typed_data';

import 'language_model_v4_data_content.dart';
import '../shared/json_value.dart';

/// A part of a language model message content.
///
/// Messages can have multi-modal content — text, images, files,
/// tool calls, and tool results.
sealed class LanguageModelV4ContentPart {
  const LanguageModelV4ContentPart();
}

// ─── User / System content parts ─────────────────────────────────────────────

/// A plain text content part.
class LanguageModelV4TextPart extends LanguageModelV4ContentPart {
  const LanguageModelV4TextPart({required this.text, this.providerOptions});

  final String text;
  final Map<String, dynamic>? providerOptions;
}

/// Opaque provider content that the portable contract does not interpret.
///
/// Providers use this part to retain unknown response items for history
/// replay without pretending they are user-visible text.
class LanguageModelV4OpaquePart extends LanguageModelV4ContentPart {
  const LanguageModelV4OpaquePart({required this.provider, required this.raw});

  final String provider;
  final Object raw;
}

/// An image content part.
class LanguageModelV4ImagePart extends LanguageModelV4ContentPart {
  const LanguageModelV4ImagePart({
    required this.image,
    this.mediaType,
    this.providerOptions,
  });

  /// The image data — bytes, base64 string, or URL.
  final LanguageModelV4DataContent image;

  /// Optional IANA media type (e.g., 'image/png').
  final String? mediaType;

  final Map<String, dynamic>? providerOptions;
}

/// A file content part.
class LanguageModelV4FilePart extends LanguageModelV4ContentPart {
  const LanguageModelV4FilePart({
    required this.data,
    required this.mediaType,
    this.filename,
    this.providerOptions,
  });

  final LanguageModelV4DataContent data;

  /// IANA media type (e.g., 'application/pdf').
  final String mediaType;

  final String? filename;
  final Map<String, dynamic>? providerOptions;
}

/// A file produced as part of the model's reasoning trace.
class LanguageModelV4ReasoningFilePart extends LanguageModelV4ContentPart {
  const LanguageModelV4ReasoningFilePart({
    required this.data,
    required this.mediaType,
    this.filename,
    this.providerOptions,
  });

  final LanguageModelV4DataContent data;
  final String mediaType;
  final String? filename;
  final Map<String, dynamic>? providerOptions;
}

// ─── Assistant content parts ──────────────────────────────────────────────────

/// A reasoning / chain-of-thought part from the assistant.
class LanguageModelV4ReasoningPart extends LanguageModelV4ContentPart {
  const LanguageModelV4ReasoningPart({
    required this.text,
    this.signature,
    this.providerOptions,
  });

  final String text;

  /// Optional signature for verified reasoning (Anthropic extended thinking).
  final String? signature;
  final Map<String, dynamic>? providerOptions;
}

/// A redacted reasoning part (provider hides the content).
class LanguageModelV4RedactedReasoningPart extends LanguageModelV4ContentPart {
  const LanguageModelV4RedactedReasoningPart({
    required this.data,
    this.providerOptions,
  });

  final Uint8List data;
  final Map<String, dynamic>? providerOptions;
}

/// A tool call initiated by the assistant.
class LanguageModelV4ToolCallPart extends LanguageModelV4ContentPart {
  const LanguageModelV4ToolCallPart({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    this.providerOptions,
    this.providerExecuted = false,
  });

  final String toolCallId;
  final String toolName;

  /// The validated input object (already parsed from JSON).
  final Object input;

  final Map<String, dynamic>? providerOptions;

  /// Whether the provider already ran this call and the core must not invoke
  /// a same-named local tool.
  final bool providerExecuted;
}

/// A tool execution approval request (needsApproval tools).
class LanguageModelV4ToolApprovalRequestPart
    extends LanguageModelV4ContentPart {
  const LanguageModelV4ToolApprovalRequestPart({
    required this.approvalId,
    required this.toolCall,
    this.policyRevision,
    this.argumentsFingerprint,
  });

  final String approvalId;
  final LanguageModelV4ToolCallPart toolCall;
  final String? policyRevision;
  final String? argumentsFingerprint;
}

// ─── Tool result content parts ────────────────────────────────────────────────

/// The result of a tool execution.
sealed class LanguageModelV4ToolResultOutput {
  const LanguageModelV4ToolResultOutput();
}

/// A text tool result.
class ToolResultOutputText extends LanguageModelV4ToolResultOutput {
  const ToolResultOutputText(this.text);
  final String text;
}

/// A multi-part content tool result (for rich media outputs).
class ToolResultOutputContent extends LanguageModelV4ToolResultOutput {
  const ToolResultOutputContent(this.parts);
  final List<LanguageModelV4ContentPart> parts;
}

/// A structured JSON tool result.
class ToolResultOutputJson extends LanguageModelV4ToolResultOutput {
  const ToolResultOutputJson(this.value);

  final JsonValue value;
}

/// A structured JSON tool error result.
class ToolResultOutputErrorJson extends LanguageModelV4ToolResultOutput {
  const ToolResultOutputErrorJson(this.value);

  final JsonValue value;
}

/// A text tool error result.
class ToolResultOutputErrorText extends LanguageModelV4ToolResultOutput {
  const ToolResultOutputErrorText(this.text);

  final String text;
}

/// A tool result produced when execution was denied by policy.
class ToolResultOutputExecutionDenied extends LanguageModelV4ToolResultOutput {
  const ToolResultOutputExecutionDenied([
    this.reason = 'Tool call execution denied.',
    this.approvalId,
  ]);

  final String reason;
  final String? approvalId;
}

/// A tool result message part.
class LanguageModelV4ToolResultPart extends LanguageModelV4ContentPart {
  const LanguageModelV4ToolResultPart({
    required this.toolCallId,
    required this.toolName,
    required this.output,
    bool isError = false,
    this.preliminary = false,
    this.isDynamic = false,
    this.providerOptions,
  }) : isError =
           isError ||
           output is ToolResultOutputErrorJson ||
           output is ToolResultOutputErrorText ||
           output is ToolResultOutputExecutionDenied;

  final String toolCallId;
  final String toolName;
  final LanguageModelV4ToolResultOutput output;
  final bool isError;
  final bool preliminary;
  final Map<String, dynamic>? providerOptions;

  /// Dart spelling of the upstream `dynamic` discriminator.
  final bool isDynamic;
}

/// A source reference (returned by web-search / RAG models).
class LanguageModelV4SourcePart extends LanguageModelV4ContentPart {
  const LanguageModelV4SourcePart({
    required this.id,
    required this.url,
    this.title,
    this.providerMetadata,
  });

  final String id;
  final String url;
  final String? title;
  final Map<String, dynamic>? providerMetadata;

  /// The upstream v4 source discriminator. URL sources are the legacy
  /// constructor shape; document sources use [LanguageModelV4DocumentSourcePart].
  String get sourceType => 'url';
}

/// A document citation that has no URL and carries its media identity.
class LanguageModelV4DocumentSourcePart extends LanguageModelV4ContentPart {
  const LanguageModelV4DocumentSourcePart({
    required this.id,
    required this.mediaType,
    required this.title,
    this.filename,
    this.providerMetadata,
  });

  final String id;
  final String mediaType;
  final String title;
  final String? filename;
  final Map<String, dynamic>? providerMetadata;

  String get sourceType => 'document';
}

/// A tool approval response (user approved or denied a tool call).
class LanguageModelV4ToolApprovalResponse extends LanguageModelV4ContentPart {
  const LanguageModelV4ToolApprovalResponse({
    required this.approvalId,
    required this.approved,
    this.reason,
    this.toolCallId,
    this.toolName,
    this.argumentsFingerprint,
    this.policyRevision,
  });

  final String approvalId;
  final bool approved;
  final String? reason;
  final String? toolCallId;
  final String? toolName;
  final String? argumentsFingerprint;
  final String? policyRevision;
}
