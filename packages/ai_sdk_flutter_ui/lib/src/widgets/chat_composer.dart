import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// A message-input row: a text field plus a send button, with optional attach
/// and stop affordances.
///
/// - Calls [onSend] with the trimmed text when the user submits (and clears the
///   field if no external [controller] is supplied).
/// - The send button is disabled while [isLoading] is true.
/// - When [isLoading] and [onStop] are both set, the send button **morphs**
///   into a stop button (cross-fade + scale), so it reads as one control
///   changing state.
/// - An optional [onAttach] callback adds a leading attach button. The package
///   intentionally does NOT depend on `image_picker`/`file_selector`; wire your
///   own picker inside this callback.
///
/// Buttons answer a press with a subtle scale and a light haptic. Theme-driven;
/// honors reduced motion. Provide a [controller] to keep ownership of the text,
/// or let the widget manage its own internally.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.onSend,
    this.controller,
    this.isLoading = false,
    this.onStop,
    this.onAttach,
    this.hintText = 'Message…',
    this.enabled = true,
  });

  /// Called with the trimmed, non-empty text when the user sends.
  final ValueChanged<String> onSend;

  /// Optional external text controller. When null, an internal one is used and
  /// cleared automatically after each send.
  final TextEditingController? controller;

  /// Disables the send button (e.g. while a response streams in).
  final bool isLoading;

  /// When provided together with [isLoading], shows a stop button in place of
  /// the send button.
  final VoidCallback? onStop;

  /// Optional attachment callback. When non-null, an attach button is shown.
  final VoidCallback? onAttach;

  /// Placeholder text for the input field.
  final String hintText;

  /// Whether the whole composer is interactive.
  final bool enabled;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (!widget.enabled || widget.isLoading) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_ownsController) _controller.clear();
    AiHaptics.light();
    widget.onSend(text);
  }

  void _stop() {
    AiHaptics.light();
    widget.onStop?.call();
  }

  void _attach() {
    AiHaptics.selection();
    widget.onAttach?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showStop = widget.isLoading && widget.onStop != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            if (widget.onAttach != null)
              PressableScale(
                child: IconButton(
                  key: const ValueKey('chat-composer-attach'),
                  tooltip: 'Attach',
                  onPressed: widget.enabled ? _attach : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
            Expanded(
              child: TextField(
                key: const ValueKey('chat-composer-field'),
                controller: _controller,
                enabled: widget.enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: AiMotion.duration(context, AiMotion.quick),
              switchInCurve: AiMotion.standard,
              switchOutCurve: AiMotion.standard,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: showStop
                  ? PressableScale(
                      key: const ValueKey('composer-trailing-stop'),
                      child: IconButton.filled(
                        key: const ValueKey('chat-composer-stop'),
                        onPressed: _stop,
                        icon: const Icon(Icons.stop_rounded),
                      ),
                    )
                  : PressableScale(
                      key: const ValueKey('composer-trailing-send'),
                      child: IconButton.filled(
                        key: const ValueKey('chat-composer-send'),
                        onPressed: (widget.enabled && !widget.isLoading)
                            ? _send
                            : null,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
