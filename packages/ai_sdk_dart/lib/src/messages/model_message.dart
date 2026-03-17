import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Message role for [ModelMessage].
enum ModelMessageRole { system, user, assistant, tool }

/// User-facing message for [generateText] and [streamText].
///
/// Use [content] for simple text or [parts] for multimodal content
/// (images, tool calls, etc.).
class ModelMessage {
  const ModelMessage({required this.role, required String this.content})
    : parts = null;

  const ModelMessage.parts({
    required this.role,
    required List<LanguageModelV3ContentPart> this.parts,
  }) : content = null;

  final ModelMessageRole role;
  final String? content;
  final List<LanguageModelV3ContentPart>? parts;
}

/// Tool approval request emitted when a tool requires user approval.
class ToolApprovalRequestContent {
  const ToolApprovalRequestContent({
    required this.approvalId,
    required this.toolCallId,
    required this.toolName,
    required this.input,
  });

  final String approvalId;
  final String toolCallId;
  final String toolName;
  final Object input;
}

/// User's approval or denial response for a tool call.
class ToolApprovalResponseContent {
  const ToolApprovalResponseContent({
    required this.approvalId,
    required this.approved,
    this.reason,
  });

  final String approvalId;
  final bool approved;
  final String? reason;
}
