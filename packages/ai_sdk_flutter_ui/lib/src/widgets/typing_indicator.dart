import 'package:flutter/material.dart';

import '../theme/ai_motion.dart';

/// An animated three-dot "assistant is typing" indicator.
///
/// Use it as a standalone affordance while waiting for the first token (e.g.
/// when [ChatController.status] is submitted but no text has streamed yet).
/// The dots breathe on a staggered wave; under reduced motion they hold steady.
/// Themed via `Theme.of(context)`; holds no business logic.
///
/// ```dart
/// if (controller.status == ChatStatus.submitted) const TypingIndicator()
/// ```
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({
    super.key,
    this.label,
    this.dotColor,
    this.dotSize = 8,
  });

  /// Optional text shown next to the dots (e.g. "Assistant is typing").
  final String? label;

  /// Color of the dots; defaults to the theme's `onSurfaceVariant`.
  final Color? dotColor;

  /// Diameter of each dot in logical pixels.
  final double dotSize;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AiMotion.typingPeriod,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!AiMotion.reduced(context)) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.dotColor ?? scheme.onSurfaceVariant;
    final label = widget.label;

    return Row(
      key: const ValueKey('typing-indicator'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
            child: _Dot(
              key: ValueKey('typing-dot-$i'),
              controller: _controller,
              index: i,
              color: color,
              size: widget.dotSize,
            ),
          ),
        if (label != null) ...[
          const SizedBox(width: 9),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    super.key,
    required this.controller,
    required this.index,
    required this.color,
    required this.size,
  });

  final AnimationController controller;
  final int index;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (AiMotion.reduced(context)) {
      return Opacity(opacity: 0.55, child: dot);
    }

    // Each dot peaks at a staggered point in the cycle, producing a wave that
    // both fades and gently rises — calmer than a hard opacity flicker.
    final start = index * 0.18;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = (controller.value - start) % 1.0;
        // Triangle wave 0 -> 1 -> 0, smoothed via the gentle curve.
        final raw = t < 0.5 ? t * 2 : (1 - t) * 2;
        final wave = AiMotion.gentle.transform(raw.clamp(0.0, 1.0));
        return Opacity(
          opacity: 0.3 + 0.7 * wave,
          child: Transform.translate(offset: Offset(0, -1.5 * wave), child: child),
        );
      },
      child: dot,
    );
  }
}
