import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// Renders text that grows as it streams in, with a soft breathing cursor shown
/// while [isStreaming] is true.
///
/// Pair it with any controller that exposes a growing `String` — e.g.
/// `CompletionController.completion` or `ChatController.streamingContent` —
/// inside a `ListenableBuilder`.
///
/// ```dart
/// ListenableBuilder(
///   listenable: completion,
///   builder: (context, _) => StreamingTextView(
///     text: completion.completion,
///     isStreaming: completion.isStreaming,
///   ),
/// )
/// ```
///
/// The cursor honors reduced-motion (it holds steady instead of pulsing).
class StreamingTextView extends StatelessWidget {
  const StreamingTextView({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.style,
    this.textAlign = TextAlign.start,
    this.selectable = true,
  });

  /// The (growing) text to display.
  final String text;

  /// Whether to show the breathing typing cursor.
  final bool isStreaming;

  /// Text style; falls back to the ambient `DefaultTextStyle`/`bodyMedium`.
  final TextStyle? style;

  /// Horizontal alignment of the text.
  final TextAlign textAlign;

  /// Whether the text can be selected. Disabled automatically while streaming
  /// (selection during rapid updates is jarring).
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? Theme.of(context).textTheme.bodyMedium;

    if (!isStreaming) {
      return selectable
          ? SelectableText(text, style: effectiveStyle, textAlign: textAlign)
          : Text(text, style: effectiveStyle, textAlign: textAlign);
    }

    // While streaming, render the text plus an inline breathing caret. The
    // caret rides the last line so the message reads as "still arriving".
    return Text.rich(
      TextSpan(
        style: effectiveStyle,
        children: [
          TextSpan(text: text),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: StreamingCursor(key: ValueKey('streaming-cursor')),
          ),
        ],
      ),
      textAlign: textAlign,
    );
  }
}
