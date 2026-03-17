import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// User-facing model message role.
enum ModelMessageRole { system, user, assistant, tool }

/// User-facing model message used by `generateText` and `streamText`.
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

/// A tool approval request in a message (emitted when a tool needs approval).
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

/// A tool approval response in a message (user approved or denied).
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
