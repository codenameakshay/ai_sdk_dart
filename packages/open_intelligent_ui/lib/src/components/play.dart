import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';
import '../view.dart';
import 'controls.dart' show Press;
import 'markdown.dart';

/// `Flashcard(front, back, hint?)`: flips between its faces when tapped.
Widget buildFlashcard(BuildContext context, OpenUiNode node) {
  Widget face(Object? value, {required bool back}) {
    if (value is String) {
      final style = back
          ? const TextStyle(
              fontSize: 16,
              height: 1.3,
              fontWeight: OpenUiTheme.weightMedium,
            )
          : const TextStyle(
              fontSize: 21,
              height: 1.3,
              fontWeight: OpenUiTheme.weightSemibold,
              letterSpacing: -0.4,
            );
      return InlineText(
        (context, links) => inlineSpans(
          value,
          context,
          style: style.copyWith(color: node.theme.ink),
          links: links,
        ),
        textAlign: TextAlign.center,
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: node.render(value));
  }

  final hint = node.props.string('hint');
  return Flashcard(
    front: face(node.props['front'], back: false),
    back: face(node.props['back'], back: true),
    hint: hint == null || hint.isEmpty ? 'Tap to flip' : hint,
  );
}

class Flashcard extends StatefulWidget {
  const Flashcard({
    super.key,
    required this.front,
    required this.back,
    required this.hint,
  });
  final Widget front;
  final Widget back;
  final String hint;

  @override
  State<Flashcard> createState() => _FlashcardState();
}

class _FlashcardState extends State<Flashcard> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      container: true,
      button: true,
      toggled: _flipped,
      child: Press(
        radius: OpenUiTheme.radiusXl,
        onTap: (_) => setState(() => _flipped = !_flipped),
        builder: (hovered, pressed) {
          Widget side(Widget child, {required bool back}) => Container(
            constraints: const BoxConstraints(minHeight: 168),
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: back ? theme.surface : theme.canvas,
              border: Border.all(
                color: hovered ? theme.borderStrong : theme.border,
              ),
              borderRadius: BorderRadius.circular(OpenUiTheme.radiusXl),
            ),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                child,
                if (!back)
                  Positioned(
                    bottom: -20,
                    child: Text(
                      widget.hint,
                      style: TextStyle(fontSize: 11, color: theme.faint),
                    ),
                  ),
              ],
            ),
          );

          return _turning(side, reduce);
        },
      ),
    );
  }

  Widget _turning(
    Widget Function(Widget, {required bool back}) side,
    bool reduce,
  ) => TweenAnimationBuilder<double>(
    tween: Tween(end: _flipped ? 1 : 0),
    duration: reduce ? Duration.zero : const Duration(milliseconds: 450),
    curve: const Cubic(.3, .7, .3, 1),
    builder: (context, t, _) {
      final showBack = t >= 0.5;
      final angle = t * math.pi;
      Widget face(Widget child, {required bool back}) => _Ghost(
        hidden: showBack != back,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 1 / 900)
            ..rotateY(back ? angle - math.pi : angle),
          child: side(child, back: back),
        ),
      );
      return _Faces(
        children: [
          face(widget.front, back: false),
          face(widget.back, back: true),
        ],
      );
    },
  );
}

class _Faces extends MultiChildRenderObjectWidget {
  const _Faces({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFaces();
}

class _RenderFaces extends RenderStack {
  _RenderFaces() : super(alignment: Alignment.topLeft);

  @override
  void performLayout() {
    super.performLayout();
    for (var child = firstChild; child != null; child = childAfter(child)) {
      child.layout(BoxConstraints.tight(size), parentUsesSize: true);
    }
  }
}

/// Hidden faces still set the card's height without receiving input or semantics.
class _Ghost extends SingleChildRenderObjectWidget {
  const _Ghost({required this.hidden, required super.child});
  final bool hidden;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGhost(hidden);

  @override
  void updateRenderObject(BuildContext context, _RenderGhost renderObject) {
    renderObject.hidden = hidden;
  }

  @override
  SingleChildRenderObjectElement createElement() => _GhostElement(this);
}

class _GhostElement extends SingleChildRenderObjectElement {
  _GhostElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    if (!(widget as _Ghost).hidden) super.debugVisitOnstageChildren(visitor);
  }
}

class _RenderGhost extends RenderProxyBox {
  _RenderGhost(this._hidden);
  bool _hidden;

  set hidden(bool value) {
    if (_hidden == value) return;
    _hidden = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hidden) super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !_hidden && super.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!_hidden) super.visitChildrenForSemantics(visitor);
  }
}

/// `Celebration(when)`: confetti when `when` turns true after the program
/// stops streaming.
Widget buildCelebration(BuildContext context, OpenUiNode node) =>
    Celebration(when: node.props['when'] == true, streaming: node.isStreaming);

class Celebration extends StatefulWidget {
  const Celebration({super.key, required this.when, required this.streaming});
  final bool when;
  final bool streaming;

  @override
  State<Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst;
  bool? _was;
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _check();
  }

  @override
  void didUpdateWidget(Celebration old) {
    super.didUpdateWidget(old);
    _check();
  }

  void _check() {
    if (widget.streaming) return;
    if (_was == false && widget.when) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fire());
    }
    _was = widget.when;
  }

  void _fire() {
    if (!mounted || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final colors = OpenUiTheme.of(context).chart;
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: CustomPaint(
          painter: _ConfettiPainter(_burst, colors),
          size: Size.infinite,
        ),
      ),
    );
    overlay.insert(_entry!);
    _burst.forward(from: 0).whenComplete(() {
      _entry?.remove();
      _entry = null;
    });
  }

  @override
  void dispose() {
    _entry?.remove();
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.progress, this.colors) : super(repaint: progress);
  final Animation<double> progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = progress.value * 2200;
    for (var i = 0; i < 70; i++) {
      final delay = (i % 10) * 40;
      final duration = 1200 + ((i * 53) % 900);
      final t = ((elapsed - delay) / duration).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final eased = Curves.easeOutCubic.transform(t);
      final x =
          size.width * ((i * 37) % 100) / 100 +
          (((i * 71) % 200) - 100) * eased;
      final y = -12 + (size.height * 1.05 + 12) * eased;
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 1 - 0.3 * t);
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(((i * 97) % 720) * math.pi / 180 * eased)
        ..drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-4, -6, 8, 12),
            const Radius.circular(2),
          ),
          paint,
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
