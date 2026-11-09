import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';

import '../localizations.dart';
import '../theme.dart';
import '../view.dart';
import 'block_slot.dart';
import 'controls.dart' show Press;
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
    gap: node.theme.spaceOf(node.props.number('gap')) ?? 12,
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
    for (final w in node.render(v, slot: '${out.length}')) {
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
                  key: item.widget.key == null
                      ? null
                      : ValueKey<Object?>(('carousel-item', item.widget.key)),
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
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _changed();
            return false;
          },
          child: track,
        ),
        if (position != null && position.pixels >= 4)
          PositionedDirectional(
            start: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrow(
                name: 'chevron-left',
                label: OpenUiLocalizations.of(context).previous,
                onTap: () => _page(-1),
              ),
            ),
          ),
        if (position != null && position.pixels < position.maxScrollExtent - 4)
          PositionedDirectional(
            end: 8,
            top: 0,
            bottom: 0,
            child: Center(
              child: _CarouselArrow(
                name: 'chevron-right',
                label: OpenUiLocalizations.of(context).next,
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

/// `backdrop-filter: blur(12px) saturate(1.4)`.
final _frost = ImageFilter.compose(
  outer: const ColorFilter.matrix([
    1.3148, -0.286, -0.0288, 0, 0, //
    -0.0852, 1.114, -0.0288, 0, 0, //
    -0.0852, -0.286, 1.3712, 0, 0, //
    0, 0, 0, 1, 0,
  ]),
  inner: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
);

final class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({
    required this.name,
    required this.label,
    required this.onTap,
  });

  final String name;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final size = theme.styleOf('Carousel.arrow').size ?? 34;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: Press(
        radius: size / 2,
        onTap: (_) => onTap(),
        builder: (hovered, pressed) => DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: theme.floatShadow,
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: _frost,
              child: AnimatedContainer(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hovered ? theme.surface : theme.glass,
                  border: Border.all(color: theme.glassRing),
                ),
                child: Glyph(name, size: 18, color: theme.ink, strokeWidth: 2),
              ),
            ),
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
  final parts = trigger is List
      ? trigger.expand((p) => p is List ? p : [p]).toList()
      : [trigger];
  final row = Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      for (final part in parts)
        for (final widget in node.render(
          part,
          slot: 'trigger${parts.indexOf(part)}',
        ))
          _keepsWidth(part) ? widget : Flexible(child: widget),
    ],
  );
  return _Popover(
    trigger: switch (trigger) {
      String() || num() => _inlineText(context, trigger),
      // `.iui-row > * { min-width: 0 }` can squeeze the trigger below its
      // `flex: none` parts; they overflow it, as in CSS.
      // ponytail: a squeezed trigger with text parts still reports overflow.
      _ when parts.every(_keepsWidth) => OverflowBox(
        maxWidth: double.infinity,
        alignment: AlignmentDirectional.centerStart,
        fit: OverflowBoxFit.deferToChild,
        child: row,
      ),
      _ => row,
    },
    content: switch (content) {
      String() || num() => _inlineText(context, content),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: node.render(content, slot: 'content'),
      ),
    },
  );
}

/// Trigger parts with CSS `flex: none`: they keep their width and the text
/// beside them takes what is left.
bool _keepsWidth(Object? part) =>
    part is OpenUiElement &&
    const {'Icon', 'Badge', 'Button', 'IconButton'}.contains(part.typeName);

Widget _inlineText(BuildContext context, Object? value) => InlineText(
  (context, links) => inlineSpans(jsString(value), context, links: links),
);

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
  final _scrolls = <ScrollPosition>[];
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
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final position = (element.state as ScrollableState).position;
        _scrolls.add(position);
        position.addListener(_hide);
      }
      return true;
    });
    setState(_controller.show);
  }

  void _hide() {
    if (!_controller.isShowing) return;
    _stopListening();
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

  void _stopListening() {
    for (final position in _scrolls) {
      position.removeListener(_hide);
    }
    _scrolls.clear();
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return OverlayPortal(
      controller: _controller,
      overlayChildBuilder: (context) => Stack(
        children: [
          // Measured global anchor: a physical left, not a text-direction offset.
          Positioned(
            left: _left,
            top: _top,
            bottom: _bottom,
            child: TapRegion(
              groupId: this,
              onTapOutside: (_) => _hide(),
              child: Semantics(
                container: true,
                role: SemanticsRole.dialog,
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
                      borderRadius: BorderRadius.circular(theme.radii.lg),
                      boxShadow: theme.shadow,
                    ),
                    child: DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: theme.fontFamily,
                        fontSize: theme.fontSizeOf('Popover', 14),
                        fontWeight: theme.typography.normal,
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
            child: Press(
              radius: 4,
              onTap: (_) => _toggle(),
              builder: (hovered, pressed) => DefaultTextStyle.merge(
                style: TextStyle(color: hovered ? theme.muted : null),
                child: widget.trigger,
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
  final radius = Radius.circular(
    theme.styleOf('Quote').radius ?? theme.radii.lg,
  );
  return ClipRRect(
    borderRadius: BorderRadiusDirectional.only(
      topEnd: radius,
      bottomEnd: radius,
    ),
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
                  InlineText(
                    (context, links) => inlineSpans(
                      text,
                      context,
                      style: TextStyle(
                        fontSize: theme.fontSizeOf('Quote', 16),
                        height: 1.6,
                        color: theme.ink,
                      ),
                      links: links,
                    ),
                  ),
                  if (cite != null && cite.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: InlineText(
                        (context, links) => inlineSpans(
                          cite,
                          context,
                          style: TextStyle(
                            fontSize: theme.fontSizeOf('Quote.cite', 13),
                            color: theme.muted,
                          ),
                          links: links,
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
