import 'package:flutter/material.dart';

/// Renders text that grows as it streams in, with a subtle blinking cursor
/// shown while [isStreaming] is true.
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
class StreamingTextView extends StatefulWidget {
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

  /// Whether to show the blinking typing cursor.
  final bool isStreaming;

  /// Text style; falls back to the ambient `DefaultTextStyle`/`bodyMedium`.
  final TextStyle? style;

  /// Horizontal alignment of the text.
  final TextAlign textAlign;

  /// Whether the text can be selected. Disabled automatically while streaming
  /// (selection during rapid updates is jarring).
  final bool selectable;

  @override
  State<StreamingTextView> createState() => _StreamingTextViewState();
}

class _StreamingTextViewState extends State<StreamingTextView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isStreaming) _blink.repeat();
  }

  @override
  void didUpdateWidget(covariant StreamingTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isStreaming && !_blink.isAnimating) {
      _blink.repeat();
    } else if (!widget.isStreaming && _blink.isAnimating) {
      _blink.stop();
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        widget.style ?? Theme.of(context).textTheme.bodyMedium;

    final textWidget = widget.selectable && !widget.isStreaming
        ? SelectableText(
            widget.text,
            style: effectiveStyle,
            textAlign: widget.textAlign,
          )
        : Text(widget.text, style: effectiveStyle, textAlign: widget.textAlign);

    if (!widget.isStreaming) return textWidget;

    return RichText(
      textAlign: widget.textAlign,
      text: TextSpan(
        style: effectiveStyle,
        children: [
          TextSpan(text: widget.text),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: FadeTransition(
              opacity: _blink.drive(
                Animatable<double>.fromCallback((t) => (t < 0.5) ? 1.0 : 0.0),
              ),
              child: _Cursor(color: effectiveStyle?.color),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cursor extends StatelessWidget {
  const _Cursor({this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('streaming-cursor'),
      width: 2,
      height: 16,
      margin: const EdgeInsets.only(left: 2),
      color: color ?? scheme.primary,
    );
  }
}
