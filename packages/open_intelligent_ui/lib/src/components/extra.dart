import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../view.dart';
import 'markdown.dart';

Widget buildCarousel(BuildContext context, OpenUiNode node) {
  final width = (node.props.number('itemWidth') ?? 240)
      .clamp(80, 640)
      .toDouble();
  final gap = OpenUiTheme.space(node.props.number('gap')) ?? 12;
  final items = node.children();
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    physics: _SnapPhysics(
      width + gap,
      parent: ScrollConfiguration.of(context).getScrollPhysics(context),
    ),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == items.length - 1 ? 0 : gap),
              child: SizedBox(width: width, child: items[i]),
            ),
        ],
      ),
    ),
  );
}

/// Settles on the nearest multiple of [step] (the item pitch), in the
/// direction of a fling.
final class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics(this.step, {super.parent});

  final double step;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) =>
      _SnapPhysics(step, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final tolerance = toleranceFor(position);
    final current = position.pixels;
    final index = current / step;
    final snapped = velocity > tolerance.velocity
        ? index.ceilToDouble()
        : velocity < -tolerance.velocity
        ? index.floorToDouble()
        : index.roundToDouble();
    final target = (snapped * step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - current).abs() < tolerance.distance &&
        velocity.abs() < tolerance.velocity) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      current,
      target,
      velocity,
      tolerance: tolerance,
    );
  }
}

Widget buildPopover(BuildContext context, OpenUiNode node) => _Popover(
  trigger: _slot(context, node, node.props['trigger']),
  content: _slot(context, node, node.props['content']),
);

Widget _slot(BuildContext context, OpenUiNode node, Object? value) =>
    switch (value) {
      String() || num() => Text.rich(
        TextSpan(children: inlineSpans(jsString(value), context)),
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: node.render(value),
      ),
    };

final class _Popover extends StatefulWidget {
  const _Popover({required this.trigger, required this.content});

  final Widget trigger;
  final Widget content;

  @override
  State<_Popover> createState() => _PopoverState();
}

final class _PopoverState extends State<_Popover> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _toggle() => setState(_controller.toggle);

  void _hide() => setState(_controller.hide);

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hide,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: math.min(
                    280,
                    MediaQuery.sizeOf(context).width - 24,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: theme.canvas,
                  border: Border.all(color: theme.border),
                  borderRadius: BorderRadius.circular(OpenUiTheme.radiusLg),
                  boxShadow: theme.shadow,
                ),
                child: DefaultTextStyle(
                  style: TextStyle(fontSize: 14, height: 1.5, color: theme.ink),
                  child: widget.content,
                ),
              ),
            ),
          ),
        ],
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: Semantics(
          button: true,
          expanded: _controller.isShowing,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: widget.trigger,
            ),
          ),
        ),
      ),
    );
  }
}

Widget buildQuote(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final text = node.props.string('text') ?? '';
  final cite = node.props.string('cite');
  return ClipRRect(
    borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: theme.ink),
          Expanded(
            child: Container(
              color: theme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: inlineSpans(
                        text,
                        context,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: theme.ink,
                        ),
                      ),
                    ),
                  ),
                  if (cite != null && cite.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text.rich(
                        TextSpan(
                          children: inlineSpans(
                            cite,
                            context,
                            style: TextStyle(fontSize: 13, color: theme.muted),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
