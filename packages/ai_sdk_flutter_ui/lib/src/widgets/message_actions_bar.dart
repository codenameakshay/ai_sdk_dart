import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ai_motion.dart';

/// A compact row of per-message actions: copy, regenerate, and 👍/👎 feedback.
///
/// Each action renders only when its input is supplied, so you opt into exactly
/// the affordances you want. Copy uses the core `Clipboard` service (no extra
/// dependency); the rest are plain callbacks you wire to your controller. Every
/// button answers a press with a subtle scale and a light haptic.
///
/// ```dart
/// MessageActionsBar(
///   copyText: message.content,
///   onRegenerate: controller.regenerate,
/// )
/// ```
class MessageActionsBar extends StatelessWidget {
  const MessageActionsBar({
    super.key,
    this.copyText,
    this.onCopied,
    this.onRegenerate,
    this.onThumbUp,
    this.onThumbDown,
    this.iconSize = 18,
  });

  /// When non-null and non-empty, a copy button is shown that writes this text
  /// to the clipboard.
  final String? copyText;

  /// Called after [copyText] is written to the clipboard (e.g. to show a
  /// "Copied" snackbar).
  final VoidCallback? onCopied;

  /// When provided, a regenerate button is shown.
  final VoidCallback? onRegenerate;

  /// When provided, a thumbs-up button is shown.
  final VoidCallback? onThumbUp;

  /// When provided, a thumbs-down button is shown.
  final VoidCallback? onThumbDown;

  /// Size of the action icons.
  final double iconSize;

  Future<void> _copy() async {
    AiHaptics.light();
    await Clipboard.setData(ClipboardData(text: copyText!));
    onCopied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurfaceVariant;
    final copyText = this.copyText;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (copyText != null && copyText.isNotEmpty)
          _ActionButton(
            buttonKey: const ValueKey('message-copy'),
            tooltip: 'Copy',
            icon: Icons.copy_rounded,
            color: color,
            iconSize: iconSize,
            onPressed: _copy,
          ),
        if (onRegenerate != null)
          _ActionButton(
            buttonKey: const ValueKey('message-regenerate'),
            tooltip: 'Regenerate',
            icon: Icons.refresh_rounded,
            color: color,
            iconSize: iconSize,
            onPressed: () {
              AiHaptics.selection();
              onRegenerate!();
            },
          ),
        if (onThumbUp != null)
          _ActionButton(
            buttonKey: const ValueKey('message-thumb-up'),
            tooltip: 'Good response',
            icon: Icons.thumb_up_outlined,
            color: color,
            iconSize: iconSize,
            onPressed: () {
              AiHaptics.selection();
              onThumbUp!();
            },
          ),
        if (onThumbDown != null)
          _ActionButton(
            buttonKey: const ValueKey('message-thumb-down'),
            tooltip: 'Bad response',
            icon: Icons.thumb_down_outlined,
            color: color,
            iconSize: iconSize,
            onPressed: () {
              AiHaptics.selection();
              onThumbDown!();
            },
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.iconSize,
    required this.onPressed,
  });

  final Key buttonKey;
  final String tooltip;
  final IconData icon;
  final Color color;
  final double iconSize;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: IconButton(
        key: buttonKey,
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: iconSize,
        visualDensity: VisualDensity.compact,
        color: color,
        icon: Icon(icon),
      ),
    );
  }
}
