import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// A human-in-the-loop prompt for a tool call that requires approval.
///
/// Renders the requested tool's name and pretty-printed input, plus Approve and
/// Deny buttons. Feed it a [LanguageModelV3ToolApprovalRequestPart] from
/// `ChatController.pendingApprovalRequests` (or `result.steps`) and wire the
/// callbacks to `ChatController.addToolApprovalResponse(...)`:
///
/// ```dart
/// for (final request in controller.pendingApprovalRequests)
///   ToolApprovalCard(
///     request: request,
///     onApprove: (reason) => controller.addToolApprovalResponse(
///       approvalId: request.approvalId, approved: true, reason: reason),
///     onDeny: (reason) => controller.addToolApprovalResponse(
///       approvalId: request.approvalId, approved: false, reason: reason),
///   )
/// ```
///
/// The buttons answer a press with a subtle scale and a selection haptic. Set
/// [showReasonField] to collect an optional free-text reason that is passed to
/// the callbacks; otherwise they receive `null`.
class ToolApprovalCard extends StatefulWidget {
  const ToolApprovalCard({
    super.key,
    required this.request,
    required this.onApprove,
    required this.onDeny,
    this.showReasonField = false,
    this.title = 'Approve tool call?',
    this.approveLabel = 'Approve',
    this.denyLabel = 'Deny',
  });

  /// The approval request to render.
  final LanguageModelV3ToolApprovalRequestPart request;

  /// Called with the (optional) reason when the user approves.
  final ValueChanged<String?> onApprove;

  /// Called with the (optional) reason when the user denies.
  final ValueChanged<String?> onDeny;

  /// Whether to show a free-text reason field above the buttons.
  final bool showReasonField;

  /// Header label.
  final String title;

  /// Label for the approve button.
  final String approveLabel;

  /// Label for the deny button.
  final String denyLabel;

  @override
  State<ToolApprovalCard> createState() => _ToolApprovalCardState();
}

class _ToolApprovalCardState extends State<ToolApprovalCard> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String? get _reasonText {
    if (!widget.showReasonField) return null;
    final text = _reason.text.trim();
    return text.isEmpty ? null : text;
  }

  void _approve() {
    AiHaptics.selection();
    widget.onApprove(_reasonText);
  }

  void _deny() {
    AiHaptics.selection();
    widget.onDeny(_reasonText);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final call = widget.request.toolCall;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: scheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              call.toolName,
              style: textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            _CodeBlock(text: _prettyJson(call.input)),
            if (widget.showReasonField) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('tool-approval-reason'),
                controller: _reason,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Reason (optional)',
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PressableScale(
                  child: TextButton(
                    key: const ValueKey('tool-approval-deny'),
                    onPressed: _deny,
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    child: Text(widget.denyLabel),
                  ),
                ),
                const SizedBox(width: 8),
                PressableScale(
                  child: FilledButton(
                    key: const ValueKey('tool-approval-approve'),
                    onPressed: _approve,
                    child: Text(widget.approveLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _prettyJson(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}
