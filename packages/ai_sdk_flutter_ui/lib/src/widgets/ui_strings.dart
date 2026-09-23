import 'package:flutter/widgets.dart';

/// Built-in labels used by the prebuilt chat widgets.
///
/// Apps can provide translated labels by placing an
/// [AiSdkUiStringsScope] above their chat widgets. A widget-level label (for
/// example, [ChatComposer.hintText] or [ToolApprovalCard.approveLabel]) always
/// takes precedence over this scope.
class AiSdkUiStrings {
  const AiSdkUiStrings({
    this.messageHint = 'Message…',
    this.attachFile = 'Attach file',
    this.sendMessage = 'Send message',
    this.stopResponse = 'Stop response',
    this.retry = 'Retry',
    this.dismiss = 'Dismiss',
    this.assistantTyping = 'Assistant is typing',
    this.assistantResponding = 'Assistant is responding…',
    this.approveToolCall = 'Approve the tool call to continue.',
    this.toolApprovalTitle = 'Approve tool call?',
    this.approve = 'Approve',
    this.deny = 'Deny',
    this.approvalReasonHint = 'Reason (optional)',
    this.userMessage = 'User message',
    this.assistantMessage = 'Assistant message',
    this.systemMessage = 'System message',
    this.toolMessage = 'Tool message',
    this.sources = 'Sources',
    this.scrollToLatest = 'Scroll to latest message',
    this.remoteImageBlocked = 'Remote image blocked',
    this.attachedImage = 'Attached image',
    this.imageFailedToLoad = 'Image failed to load',
    this.attachment = 'Attachment',
    this.openAttachment = 'Open attachment',
    this.reasoningAttachment = 'Reasoning attachment',
  });

  final String messageHint;
  final String attachFile;
  final String sendMessage;
  final String stopResponse;
  final String retry;
  final String dismiss;
  final String assistantTyping;
  final String assistantResponding;
  final String approveToolCall;
  final String toolApprovalTitle;
  final String approve;
  final String deny;
  final String approvalReasonHint;
  final String userMessage;
  final String assistantMessage;
  final String systemMessage;
  final String toolMessage;
  final String sources;
  final String scrollToLatest;
  final String remoteImageBlocked;
  final String attachedImage;
  final String imageFailedToLoad;
  final String attachment;
  final String openAttachment;
  final String reasoningAttachment;
}

/// Inherited localization scope for the built-in Flutter UI labels.
class AiSdkUiStringsScope extends InheritedWidget {
  const AiSdkUiStringsScope({
    super.key,
    required this.strings,
    required super.child,
  });

  final AiSdkUiStrings strings;

  static AiSdkUiStrings of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AiSdkUiStringsScope>();
    return scope?.strings ?? const AiSdkUiStrings();
  }

  @override
  bool updateShouldNotify(AiSdkUiStringsScope oldWidget) =>
      strings != oldWidget.strings;
}
