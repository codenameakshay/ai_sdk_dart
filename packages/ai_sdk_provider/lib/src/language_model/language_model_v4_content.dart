import 'dart:typed_data';

import 'language_model_v3_data_content.dart';

/// A part of a language model message content.
///
/// Messages can have multi-modal content — text, images, files,
/// tool calls, and tool results.
sealed class LanguageModelV3ContentPart {
  const LanguageModelV3ContentPart();
}

// ─── User / System content parts ─────────────────────────────────────────────

/// A plain text content part.
class LanguageModelV3TextPart extends LanguageModelV3ContentPart {
  const LanguageModelV3TextPart({required this.text, this.providerOptions});

  final String text;
  final Map<String, dynamic>? providerOptions;
}

/// An image content part.
class LanguageModelV3ImagePart extends LanguageModelV3ContentPart {
  const LanguageModelV3ImagePart({
    required this.image,
    this.mediaType,
    this.providerOptions,
  });

  /// The image data — bytes, base64 string, or URL.
  final LanguageModelV3DataContent image;

  /// Optional IANA media type (e.g., 'image/png').
  final String? mediaType;

  final Map<String, dynamic>? providerOptions;
}

/// A file content part.
class LanguageModelV3FilePart extends LanguageModelV3ContentPart {
  const LanguageModelV3FilePart({
    required this.data,
    required this.mediaType,
    this.filename,
    this.providerOptions,
  });

  final LanguageModelV3DataContent data;

  /// IANA media type (e.g., 'application/pdf').
  final String mediaType;

  final String? filename;
  final Map<String, dynamic>? providerOptions;
}

// ─── Assistant content parts ──────────────────────────────────────────────────

/// A reasoning / chain-of-thought part from the assistant.
class LanguageModelV3ReasoningPart extends LanguageModelV3ContentPart {
  const LanguageModelV3ReasoningPart({
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
class LanguageModelV3RedactedReasoningPart extends LanguageModelV3ContentPart {
  const LanguageModelV3RedactedReasoningPart({
    required this.data,
    this.providerOptions,
  });

  final Uint8List data;
  final Map<String, dynamic>? providerOptions;
}

/// A tool call initiated by the assistant.
class LanguageModelV3ToolCallPart extends LanguageModelV3ContentPart {
  const LanguageModelV3ToolCallPart({
    required this.toolCallId,
    required this.toolName,
    required this.input,
    this.providerOptions,
  });

  final String toolCallId;
  final String toolName;

  /// The validated input object (already parsed from JSON).
  final Object input;

  final Map<String, dynamic>? providerOptions;
}

/// A tool execution approval request (needsApproval tools).
class LanguageModelV3ToolApprovalRequestPart
    extends LanguageModelV3ContentPart {
  const LanguageModelV3ToolApprovalRequestPart({
    required this.approvalId,
    required this.toolCall,
  });

  final String approvalId;
  final LanguageModelV3ToolCallPart toolCall;
}

// ─── Tool result content parts ────────────────────────────────────────────────

/// The result of a tool execution.
sealed class LanguageModelV3ToolResultOutput {
  const LanguageModelV3ToolResultOutput();
}

/// A text tool result.
class ToolResultOutputText extends LanguageModelV3ToolResultOutput {
  const ToolResultOutputText(this.text);
  final String text;
}

/// A multi-part content tool result (for rich media outputs).
class ToolResultOutputContent extends LanguageModelV3ToolResultOutput {
  const ToolResultOutputContent(this.parts);
  final List<LanguageModelV3ContentPart> parts;
}

/// A tool result message part.
class LanguageModelV3ToolResultPart extends LanguageModelV3ContentPart {
  const LanguageModelV3ToolResultPart({
    required this.toolCallId,
    required this.toolName,
    required this.output,
    this.isError = false,
    this.providerOptions,
  });

  final String toolCallId;
  final String toolName;
  final LanguageModelV3ToolResultOutput output;
  final bool isError;
  final Map<String, dynamic>? providerOptions;
}

/// A source reference (returned by web-search / RAG models).
class LanguageModelV3SourcePart extends LanguageModelV3ContentPart {
  const LanguageModelV3SourcePart({
    required this.id,
    required this.url,
    this.title,
    this.providerMetadata,
  });

  final String id;
  final String url;
  final String? title;
  final Map<String, dynamic>? providerMetadata;
}

/// A tool approval response (user approved or denied a tool call).
class LanguageModelV3ToolApprovalResponse extends LanguageModelV3ContentPart {
  const LanguageModelV3ToolApprovalResponse({
    required this.approvalId,
    required this.approved,
    this.reason,
  });

  final String approvalId;
  final bool approved;
  final String? reason;
}
