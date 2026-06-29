import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import 'message_media.dart';
import 'reasoning_view.dart';
import 'source_citations.dart';
import 'tool_approval_card.dart';
import 'tool_call_card.dart';

/// Signature for rendering a text segment of an assistant message. Use it to
/// plug in a markdown renderer of your choice — the package stays dependency
/// free and renders plain selectable text by default.
typedef AssistantTextBuilder =
    Widget Function(BuildContext context, String text);

/// Signature for the approve/deny callbacks of an inline tool-approval request.
typedef ToolApprovalCallback =
    void Function(
      LanguageModelV3ToolApprovalRequestPart request,
      String? reason,
    );

/// Renders a full assistant turn by walking a [ModelMessage]'s content parts
/// and dispatching each to the right widget:
///
/// - text → [textBuilder] (markdown slot) or selectable text
/// - reasoning → [ReasoningView]
/// - tool call → [ToolCallCard] (paired with a matching [toolResults] entry)
/// - tool-approval request → [ToolApprovalCard] (when approval callbacks are set)
/// - image → [MessageImage]
/// - file → [MessageAttachment]
/// - source → collected into a single trailing [SourceCitations]
///
/// When the message has no `parts` (plain text path), its `content` is rendered
/// as a single text segment. Pure presentation: it themes via
/// `Theme.of(context)` and reads only its inputs.
class AssistantMessageView extends StatelessWidget {
  const AssistantMessageView({
    super.key,
    required this.message,
    this.textBuilder,
    this.toolResults = const [],
    this.onSourceTap,
    this.onFileTap,
    this.onToolApprove,
    this.onToolDeny,
    this.spacing = 8,
  });

  /// The assistant message to render.
  final ModelMessage message;

  /// Optional renderer for text segments (e.g. a markdown widget). Defaults to
  /// selectable text.
  final AssistantTextBuilder? textBuilder;

  /// Tool results to pair with tool-call parts by `toolCallId`.
  final List<LanguageModelV3ToolResultPart> toolResults;

  /// Called when a source citation chip is tapped.
  final void Function(LanguageModelV3SourcePart source)? onSourceTap;

  /// Called when a file attachment is tapped.
  final void Function(LanguageModelV3FilePart file)? onFileTap;

  /// Called when an inline tool-approval request is approved. When both this
  /// and [onToolDeny] are null, approval requests render as plain tool cards.
  final ToolApprovalCallback? onToolApprove;

  /// Called when an inline tool-approval request is denied.
  final ToolApprovalCallback? onToolDeny;

  /// Vertical gap between rendered segments.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    final parts = message.parts;
    if (parts == null) {
      final text = message.content ?? '';
      if (text.isNotEmpty) children.add(_text(context, text));
    } else {
      final sources = <LanguageModelV3SourcePart>[];
      for (final part in parts) {
        switch (part) {
          case LanguageModelV3TextPart(:final text):
            if (text.isNotEmpty) children.add(_text(context, text));
          case LanguageModelV3ReasoningPart(:final text):
            children.add(ReasoningView(text: text));
          case LanguageModelV3ToolCallPart():
            children.add(ToolCallCard(call: part, result: _resultFor(part)));
          case LanguageModelV3ToolApprovalRequestPart():
            children.add(_approval(part));
          case LanguageModelV3ImagePart():
            children.add(MessageImage(image: part));
          case LanguageModelV3FilePart():
            children.add(
              MessageAttachment(
                file: part,
                onTap: onFileTap == null ? null : () => onFileTap!(part),
              ),
            );
          case LanguageModelV3SourcePart():
            sources.add(part);
          case LanguageModelV3RedactedReasoningPart():
          case LanguageModelV3ToolResultPart():
          case LanguageModelV3ToolApprovalResponse():
            break; // not rendered inline
        }
      }
      if (sources.isNotEmpty) {
        children.add(SourceCitations(sources: sources, onTap: onSourceTap));
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          children[i],
        ],
      ],
    );
  }

  Widget _text(BuildContext context, String text) {
    final builder = textBuilder;
    if (builder != null) return builder(context, text);
    return SelectableText(text, style: const TextStyle(height: 1.4));
  }

  Widget _approval(LanguageModelV3ToolApprovalRequestPart part) {
    if (onToolApprove == null && onToolDeny == null) {
      return ToolCallCard(call: part.toolCall);
    }
    return ToolApprovalCard(
      request: part,
      onApprove: (reason) => onToolApprove?.call(part, reason),
      onDeny: (reason) => onToolDeny?.call(part, reason),
    );
  }

  LanguageModelV3ToolResultPart? _resultFor(LanguageModelV3ToolCallPart call) {
    for (final result in toolResults) {
      if (result.toolCallId == call.toolCallId) return result;
    }
    return null;
  }
}
