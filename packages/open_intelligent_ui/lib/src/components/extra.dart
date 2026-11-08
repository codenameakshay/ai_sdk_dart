import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../view.dart';
import 'block_slot.dart';
import 'flex_row.dart';
import 'glyph.dart';
import 'markdown.dart';

typedef _Slot = ({OpenUiElement? element, Widget widget});

Widget buildCarousel(BuildContext context, OpenUiNode node) {
  final platform = defaultTargetPlatform;
  return _Carousel(
    itemWidth: (node.props.number('itemWidth') ?? 240)
        .clamp(80, 640)
        .toDouble(),
    gap: OpenUiTheme.space(node.props.number('gap')) ?? 12,
    items: _slots(node, node.props['children']),
    arrows:
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux,
  );
}

List<_Slot> _slots(OpenUiNode node, Object? value) {
  final out = <_Slot>[];
  void visit(Object? v) {
    if (v is List) {
      for (final x in v) {
        visit(x);
      }
      return;
    }
    final element = v is OpenUiElement ? v : null;
    for (final w in node.render(v)) {
      out.add((element: element, widget: w));
    }
  }

  visit(value);
  return out;
}

final class _Carousel extends StatefulWidget {
  const _Carousel({
    required this.itemWidth,
    required this.gap,
    required this.items,
    required this.arrows,
  });

  final double itemWidth;
  final double gap;
  final List<_Slot> items;
  final bool arrows;

  @override
  State<_Carousel> createState() => _CarouselState();
}

final class _CarouselState extends State<_Carousel> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.arrows) {
      _controller.addListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _page(int direction) {
    final position = _controller.position;
    final target =
        position.pixels + direction * 0.85 * position.viewportDimension;
    _controller.animateTo(
      target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final physics = ScrollConfiguration.of(context).getScrollPhysics(context);
    final track = LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = math.min(
          widget.itemWidth,
          0.85 * constraints.maxWidth,
        );
        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: _SnapPhysics(itemWidth + widget.gap, parent: physics),
          child: FlexRow(
            gap: widget.gap,
            align: FlexAlign.stretch,
            children: [
              for (final (i, item) in widget.items.indexed)
                FlexRowItem(
                  shrink: false,
                  child: SizedBox(
                    width: itemWidth,
                    child: BlockSlot(
                      element: item.element,
                      parent: SlotParent.carouselItem,
                      index: i,
                      previous: i == 0 ? null : widget.items[i - 1].element,
                      flow: false,
                      child: LayoutBuilder(
                        builder: (context, slot) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _fillsItem(item.element) && slot.hasBoundedHeight
                                ? Expanded(child: item.widget)
                                : item.widget,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (!widget.arrows) return track;
    final position = _controller.hasClients ? _controller.position : null;
    return Stack(
      children: [
        track,
        if (position != null && position.pixels >= 4)
          Positioned(
            left: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrow(
                name: 'chevron-left',
                label: 'Previous',
                onTap: () => _page(-1),
              ),
            ),
          ),
        if (position != null && position.pixels < position.maxScrollExtent - 4)
          Positioned(
            right: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrow(
                name: 'chevron-right',
                label: 'Next',
                onTap: () => _page(1),
              ),
            ),
          ),
      ],
    );
  }
}

bool _fillsItem(OpenUiElement? element) => switch (element?.typeName) {
  'Card' || 'Pressable' => true,
  _ => false,
};

final class _CarouselArrow extends StatefulWidget {
  const _CarouselArrow({
    required this.name,
    required this.label,
    required this.onTap,
  });

  final String name;
  final String label;
  final VoidCallback onTap;

  @override
  State<_CarouselArrow> createState() => _CarouselArrowState();
}

final class _CarouselArrowState extends State<_CarouselArrow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovering ? theme.surface : theme.glass,
              border: Border.all(color: theme.glassRing),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Glyph(widget.name, size: 18, color: theme.ink),
          ),
        ),
      ),
    );
  }
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

Widget buildPopover(BuildContext context, OpenUiNode node) {
  final trigger = node.props['trigger'];
  final content = node.props['content'];
  return _Popover(
    trigger: switch (trigger) {
      String() || num() => _inlineText(context, trigger),
      _ => Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: node.render(trigger),
      ),
    },
    content: switch (content) {
      String() || num() => _inlineText(context, content),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: node.render(content),
      ),
    },
  );
}

Widget _inlineText(BuildContext context, Object? value) =>
    Text.rich(TextSpan(children: inlineSpans(jsString(value), context)));

final class _Popover extends StatefulWidget {
  const _Popover({required this.trigger, required this.content});

  final Widget trigger;
  final Widget content;

  @override
  State<_Popover> createState() => _PopoverState();
}

final class _PopoverState extends State<_Popover> {
  final _controller = OverlayPortalController();
  final _triggerKey = GlobalKey();
  ScrollPosition? _scroll;
  bool _hovering = false;
  double _left = 0;
  double? _top;
  double? _bottom;

  void _toggle() {
    if (_controller.isShowing) {
      _hide();
    } else {
      _show();
    }
  }

  void _show() {
    _place();
    _scroll = Scrollable.maybeOf(context)?.position;
    _scroll?.addListener(_hide);
    setState(_controller.show);
  }

  void _hide() {
    if (!_controller.isShowing) return;
    _scroll?.removeListener(_hide);
    _scroll = null;
    setState(_controller.hide);
  }

  /// Opens above the trigger when there is no room below it.
  void _place() {
    final trigger =
        _triggerKey.currentContext!.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final rect =
        trigger.localToGlobal(Offset.zero, ancestor: overlay) & trigger.size;
    final up = rect.bottom + 220 > overlay.size.height && rect.top > 240;
    _left = math.min(math.max(12.0, rect.left), overlay.size.width - 292);
    _top = up ? null : rect.bottom + 8;
    _bottom = up ? overlay.size.height - (rect.top - 8) : null;
  }

  @override
  void dispose() {
    _scroll?.removeListener(_hide);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => Stack(
        children: [
          Positioned(
            left: _left,
            top: _top,
            bottom: _bottom,
            child: TapRegion(
              groupId: this,
              onTapOutside: (_) => _hide(),
              child: Semantics(
                scopesRoute: true,
                explicitChildNodes: true,
                child: Focus(
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (event.logicalKey != LogicalKeyboardKey.escape) {
                      return KeyEventResult.ignored;
                    }
                    _hide();
                    return KeyEventResult.handled;
                  },
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
                      style: TextStyle(
                        fontFamily: theme.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: theme.ink,
                      ),
                      child: widget.content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      child: TapRegion(
        groupId: this,
        onTapOutside: (_) => _hide(),
        child: KeyedSubtree(
          key: _triggerKey,
          child: Semantics(
            button: true,
            expanded: _controller.isShowing,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovering = true),
              onExit: (_) => setState(() => _hovering = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: _hovering ? theme.muted : null),
                  child: widget.trigger,
                ),
              ),
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
