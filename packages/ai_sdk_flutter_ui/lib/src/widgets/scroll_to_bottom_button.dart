import 'package:flutter/material.dart';

/// A small floating button that appears when a scroll view is scrolled away
/// from its bottom edge, and jumps back to the bottom when tapped.
///
/// Drop it into a `Stack` over your [ChatMessageList] (or any [ListView]) and
/// give it the same [ScrollController]. It hides itself while the list is
/// within [threshold] pixels of the bottom, so it never covers the latest
/// message when the user is already there.
///
/// ```dart
/// Stack(children: [
///   ListView(controller: scrollController, ...),
///   Positioned(
///     right: 12, bottom: 12,
///     child: ScrollToBottomButton(controller: scrollController),
///   ),
/// ])
/// ```
class ScrollToBottomButton extends StatefulWidget {
  const ScrollToBottomButton({
    super.key,
    required this.controller,
    this.threshold = 120,
    this.icon = Icons.keyboard_arrow_down_rounded,
    this.duration = const Duration(milliseconds: 250),
    this.curve = Curves.easeOut,
  });

  /// The scroll controller of the list this button controls.
  final ScrollController controller;

  /// How far (in pixels) the list must be from the bottom before the button
  /// appears.
  final double threshold;

  /// Icon shown on the button.
  final IconData icon;

  /// Animation duration used when scrolling to the bottom.
  final Duration duration;

  /// Animation curve used when scrolling to the bottom.
  final Curve curve;

  @override
  State<ScrollToBottomButton> createState() => _ScrollToBottomButtonState();
}

class _ScrollToBottomButtonState extends State<ScrollToBottomButton> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
    // The list hasn't laid out yet on the first build, so re-evaluate once the
    // scroll position has real dimensions.
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
  }

  @override
  void didUpdateWidget(covariant ScrollToBottomButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_update);
      widget.controller.addListener(_update);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    final next = _shouldShow();
    if (next != _visible && mounted) {
      setState(() => _visible = next);
    }
  }

  bool _shouldShow() {
    final controller = widget.controller;
    if (!controller.hasClients) return false;
    final position = controller.position;
    if (!position.hasContentDimensions) return false;
    return position.maxScrollExtent - position.pixels > widget.threshold;
  }

  void _scrollToBottom() {
    final controller = widget.controller;
    if (!controller.hasClients) return;
    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: widget.duration,
      curve: widget.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return FloatingActionButton.small(
      key: const ValueKey('scroll-to-bottom'),
      onPressed: _scrollToBottom,
      tooltip: 'Scroll to latest',
      child: Icon(widget.icon),
    );
  }
}
