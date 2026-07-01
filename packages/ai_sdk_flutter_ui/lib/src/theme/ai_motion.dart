import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Motion and haptic vocabulary shared by the AI SDK Flutter UI widgets.
///
/// The intent is Apple-grade restraint: continuity over popping, gentle
/// ease-out curves (never bounce or elastic), every interaction answers a
/// press, and a first-class reduced-motion path. Everything here is built from
/// core Flutter primitives — no animation dependency — to honor the package's
/// dependency-light contract.
abstract final class AiMotion {
  /// Tap-down / release feedback.
  static const Duration press = Duration(milliseconds: 120);

  /// Small state changes (icon swap, hover, fade-through).
  static const Duration quick = Duration(milliseconds: 200);

  /// Disclosure, larger reveals, list entrance.
  static const Duration base = Duration(milliseconds: 240);

  /// Default entrance for newly-arrived content.
  static const Duration entrance = Duration(milliseconds: 220);

  /// Auto-scroll and scroll-to-bottom.
  static const Duration scroll = Duration(milliseconds: 280);

  /// Streaming caret blink period.
  static const Duration cursorPeriod = Duration(milliseconds: 900);

  /// Typing-indicator wave period.
  static const Duration typingPeriod = Duration(milliseconds: 1200);

  /// Confident deceleration for most transitions.
  static const Curve standard = Curves.easeOutCubic;

  /// Slightly snappier deceleration for larger reveals.
  static const Curve emphasized = Curves.easeOutQuart;

  /// Ease-out-expo — decisive, used for scale-ins. No overshoot.
  static const Curve gentle = Cubic(0.16, 1, 0.3, 1);

  /// Whether the platform requests reduced motion. Also true when there is no
  /// ambient [MediaQuery] (e.g. a bare test harness), which keeps widgets calm
  /// by default rather than animating into a vacuum.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// [d], collapsed to [Duration.zero] when reduced motion is on.
  static Duration duration(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}

/// Subtle, platform-appropriate haptics. No-ops on platforms without haptic
/// hardware (desktop, web), so callers never need to guard.
abstract final class AiHaptics {
  /// A light tap — for send, stop, copy-success, scroll-to-bottom.
  static void light() {
    if (_enabled) HapticFeedback.lightImpact();
  }

  /// A selection tick — for approve / deny and discrete toggles.
  static void selection() {
    if (_enabled) HapticFeedback.selectionClick();
  }

  static bool get _enabled {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
        return true;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return false;
    }
  }
}

/// Wraps [child] so it scales down slightly while pressed, then springs back on
/// release. Uses a [Listener], so it never steals the gesture from the child's
/// own button/ink handling — drop it around any interactive control.
///
/// Collapses to a plain [child] under reduced motion.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.96,
  });

  final Widget child;

  /// Scale at full press. 1.0 disables the effect.
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Create the controller eagerly rather than lazily in build(): under reduced
    // motion build() returns the child and never touches it, and a lazy
    // `late final` would otherwise be constructed for the first time inside
    // dispose() — creating a Ticker against a defunct element and throwing
    // "Looking up a deactivated widget's ancestor is unsafe."
    _controller = AnimationController(vsync: this, duration: AiMotion.press);
  }

  void _press() => _controller.forward();
  void _release() => _controller.reverse();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AiMotion.reduced(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: 1 - (1 - widget.pressedScale) * _controller.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Fades and lifts [child] into place once, when it first mounts. Use it for
/// content that genuinely arrives (a new message, a tool tile), not for static
/// rows that merely scroll into view.
///
/// Under reduced motion the child appears instantly.
class AiEntrance extends StatefulWidget {
  const AiEntrance({
    super.key,
    required this.child,
    this.dy = 6,
    this.duration = AiMotion.entrance,
    this.curve = AiMotion.standard,
  });

  final Widget child;

  /// Vertical travel of the lift, in logical pixels.
  final double dy;
  final Duration duration;
  final Curve curve;

  @override
  State<AiEntrance> createState() => _AiEntranceState();
}

class _AiEntranceState extends State<AiEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AiMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final t = _t.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.dy * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A streaming caret that breathes on a smooth eased cycle (not a hard blink).
/// Holds steady under reduced motion. Pass a [ValueKey] so it can be found by
/// hosting widgets.
class StreamingCursor extends StatefulWidget {
  const StreamingCursor({
    super.key,
    this.color,
    this.width = 2,
    this.height = 15,
  });

  final Color? color;
  final double width;
  final double height;

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AiMotion.cursorPeriod,
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
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final bar = Container(
      width: widget.width,
      height: widget.height,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(widget.width),
      ),
    );
    if (AiMotion.reduced(context)) return bar;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Smooth cosine ease between 1.0 and 0.2 — softer than an on/off blink.
        final wave = 0.5 + 0.5 * math.cos(_controller.value * 2 * math.pi);
        return Opacity(opacity: 0.2 + 0.8 * wave, child: child);
      },
      child: bar,
    );
  }
}
