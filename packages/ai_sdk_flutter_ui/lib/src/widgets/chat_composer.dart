import 'package:flutter/material.dart';

/// A message-input row: a text field plus a send button, with optional attach
/// and stop affordances.
///
/// - Calls [onSend] with the trimmed text when the user submits (and clears the
///   field if no external [controller] is supplied).
/// - The send button is disabled while [isLoading] is true.
/// - When [isLoading] and [onStop] are both set, the send button is replaced by
///   a stop button.
/// - An optional [onAttach] callback adds a leading attach button. The package
///   intentionally does NOT depend on `image_picker`/`file_selector`; wire your
///   own picker inside this callback.
///
/// Stateless and theme-driven. Provide a [controller] to keep ownership of the
/// text, or let the widget manage its own internally.
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
    widget.onSend(text);
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
              IconButton(
                key: const ValueKey('chat-composer-attach'),
                tooltip: 'Attach',
                onPressed: widget.enabled ? widget.onAttach : null,
                icon: const Icon(Icons.attach_file_rounded),
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
            if (showStop)
              IconButton.filled(
                key: const ValueKey('chat-composer-stop'),
                onPressed: widget.onStop,
                icon: const Icon(Icons.stop_rounded),
              )
            else
              IconButton.filled(
                key: const ValueKey('chat-composer-send'),
                onPressed: (widget.enabled && !widget.isLoading) ? _send : null,
                icon: const Icon(Icons.send_rounded),
              ),
          ],
        ),
      ),
    );
  }
}
