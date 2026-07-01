import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// A single chat message rendered as a bubble, styled by its [role].
///
/// In the default transcript ([ChatMessageList]) this renders the **user**
/// turn — a soft, right-aligned bubble in the host `primary` color. Assistant
/// turns render flush (bubbleless) for readability. Used standalone, it still
/// styles every role:
///
/// - [ModelMessageRole.user] → right-aligned, `primary` / `onPrimary`.
/// - [ModelMessageRole.assistant] / [ModelMessageRole.system] → left-aligned,
///   `surfaceContainerHigh` / `onSurface`.
/// - [ModelMessageRole.tool] → left-aligned, `surfaceContainerHighest` /
///   `onSurfaceVariant`.
///
/// The text is selectable. Themed entirely via `Theme.of(context)`, so it picks
/// up your app's `ColorScheme` automatically.
class ChatMessageBubble extends StatelessWidget {
  /// Creates a bubble for a single [message].
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
  });

  /// Creates a bubble from raw [text] and a [role] without a [ModelMessage].
  ///
  /// Convenient for rendering an optimistic streaming bubble, whose content
  /// only exists as a `String` buffer until the turn completes.
  ChatMessageBubble.text({
    super.key,
    required String text,
    ModelMessageRole role = ModelMessageRole.assistant,
    this.isStreaming = false,
  }) : message = ModelMessage(role: role, content: text);

  /// The message to render.
  final ModelMessage message;

  /// When true, a breathing cursor is shown after the text.
  final bool isStreaming;

  bool get _isUser => message.role == ModelMessageRole.user;
  bool get _isTool => message.role == ModelMessageRole.tool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final Color background;
    final Color foreground;
    if (_isUser) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else if (_isTool) {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
    } else {
      background = scheme.surfaceContainerHigh;
      foreground = scheme.onSurface;
    }

    final text = message.content ?? '';

    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(_isUser ? 16 : 4),
            bottomRight: Radius.circular(_isUser ? 4 : 16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: SelectableText(
                text.isEmpty ? '…' : text,
                style: TextStyle(color: foreground, height: 1.4),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 2),
              StreamingCursor(
                key: const ValueKey('streaming-cursor'),
                color: foreground,
                height: 14,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
