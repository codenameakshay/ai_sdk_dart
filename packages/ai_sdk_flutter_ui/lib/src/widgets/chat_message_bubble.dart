import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:flutter/material.dart';

/// A single chat message rendered as a bubble, styled by its [role].
///
/// - [ModelMessageRole.user] bubbles align right with the primary color.
/// - [ModelMessageRole.assistant] / [ModelMessageRole.system] bubbles align
///   left with a neutral surface color.
/// - [ModelMessageRole.tool] bubbles use the tertiary/surface-variant color and
///   align left.
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
  /// Convenient for rendering the optimistic streaming bubble, whose content
  /// only exists as a `String` buffer until the turn completes.
  ChatMessageBubble.text({
    super.key,
    required String text,
    ModelMessageRole role = ModelMessageRole.assistant,
    this.isStreaming = false,
  }) : message = ModelMessage(role: role, content: text);

  /// The message to render.
  final ModelMessage message;

  /// When true, a small typing indicator is shown alongside the text.
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
        margin: const EdgeInsets.symmetric(vertical: 4),
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
              const SizedBox(width: 6),
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
