import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// How a [FlexRow] child takes free space: `grow` 0 keeps its own width
/// (it may still shrink); a Spacer grows from a zero basis.
class FlexRowItem extends ParentDataWidget<_FlexRowData> {
  const FlexRowItem({
    super.key,
    this.grow = 0,
    this.spacer = false,
    this.shrink = true,
    this.fixed,
    this.zeroBasis = false,
    required super.child,
  });
  final double grow;
  final bool spacer;

  /// CSS `flex-shrink`: false keeps the natural width when the row is short.
  final bool shrink;

  /// A width from the row's width that neither grows nor shrinks
  /// (`flex: none`), like the media-row photo.
  final double Function(double available)? fixed;

  /// Starts from a zero basis, so [grow] alone sets the width (`flex: N 1 0%`).
  final bool zeroBasis;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _FlexRowData;
    if (data.grow != grow ||
        data.spacer != spacer ||
        data.fixed != fixed ||
        data.shrink != shrink ||
        data.zeroBasis != zeroBasis) {
      data
        ..grow = grow
        ..spacer = spacer
        ..shrink = shrink
        ..zeroBasis = zeroBasis
        ..fixed = fixed;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => FlexRow;
}

enum FlexJustify { start, center, end, between }

enum FlexAlign { start, center, end, stretch }

/// A CSS flex row (`display: flex; min-width: 0` children): children keep
/// their natural width, free space goes to growers (or to [justify]), and when
/// the children do not fit every one shrinks in proportion to its width, as
/// `flex-shrink: 1` does. Flutter's Row cannot express both at once.
class FlexRow extends MultiChildRenderObjectWidget {
  const FlexRow({
    super.key,
    this.gap = 0,
    this.justify = FlexJustify.start,
    this.align = FlexAlign.center,
    super.children,
  });
  final double gap;
  final FlexJustify justify;
  final FlexAlign align;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderFlexRow(gap: gap, justify: justify, align: align);

  @override
  void updateRenderObject(BuildContext context, RenderFlexRow renderObject) =>
      renderObject
        ..gap = gap
        ..justify = justify
        ..align = align;
}

class _FlexRowData extends ContainerBoxParentData<RenderBox> {
  double grow = 0;
  bool spacer = false;
  bool shrink = true;
  bool zeroBasis = false;
  double Function(double available)? fixed;
}

class RenderFlexRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FlexRowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FlexRowData> {
  RenderFlexRow({
    required double gap,
    required FlexJustify justify,
    required FlexAlign align,
  }) : _gap = gap,
       _justify = justify,
       _align = align;

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  FlexJustify _justify;
  set justify(FlexJustify v) {
    if (v == _justify) return;
    _justify = v;
    markNeedsLayout();
  }

  FlexAlign _align;
  set align(FlexAlign v) {
    if (v == _align) return;
    _align = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FlexRowData) child.parentData = _FlexRowData();
  }

  List<RenderBox> get _children {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  _FlexRowData _data(RenderBox c) => c.parentData! as _FlexRowData;

  /// The width each child gets, from natural widths measured at [available].
  List<double> _widths(
    List<RenderBox> children,
    double available,
    List<double> natural,
  ) {
    final gaps = _gap * math.max(0, children.length - 1);
    final total = natural.fold(0.0, (a, b) => a + b) + gaps;
    if (!available.isFinite) return natural;
    if (total <= available) {
      double grows(RenderBox c) =>
          _data(c).fixed != null ? 0 : (_data(c).spacer ? 1 : _data(c).grow);
      final growth = children.fold(0.0, (a, c) => a + grows(c));
      if (growth == 0) return natural;
      final free = available - total;
      return [
        for (final (i, c) in children.indexed)
          natural[i] + free * grows(c) / growth,
      ];
    }
    final shrinkable = [
      for (final (i, c) in children.indexed)
        if (_data(c).fixed == null && _data(c).shrink) natural[i],
    ].fold(0.0, (a, b) => a + b);
    final overflow = total - available;
    return [
      for (final (i, c) in children.indexed)
        _data(c).fixed != null || !_data(c).shrink || shrinkable == 0
            ? natural[i]
            : math.max(0.0, natural[i] - overflow * natural[i] / shrinkable),
    ];
  }

  List<double> _natural(
    List<RenderBox> children,
    double available, {
    required bool dry,
  }) => [
    for (final c in children)
      _data(c).spacer || _data(c).zeroBasis
          ? 0
          : _data(c).fixed != null && available.isFinite
          ? _data(c).fixed!(available)
          : dry
          ? c.getDryLayout(BoxConstraints(maxWidth: available)).width
          : (c..layout(
                  BoxConstraints(maxWidth: available),
                  parentUsesSize: true,
                ))
                .size
                .width,
  ];

  @override
  void performLayout() {
    final children = _children;
    final available = constraints.maxWidth;
    final widths = _widths(
      children,
      available,
      _natural(children, available, dry: false),
    );
    var height = 0.0;
    for (final (i, c) in children.indexed) {
      c.layout(
        BoxConstraints(minWidth: widths[i], maxWidth: widths[i]),
        parentUsesSize: true,
      );
      height = math.max(height, c.size.height);
    }
    height = constraints.constrainHeight(height);
    if (_align == FlexAlign.stretch) {
      for (final (i, c) in children.indexed) {
        c.layout(
          BoxConstraints.tightFor(width: widths[i], height: height),
          parentUsesSize: true,
        );
      }
    }
    final used =
        widths.fold(0.0, (a, b) => a + b) +
        _gap * math.max(0, children.length - 1);
    final width = available.isFinite ? available : used;
    final free = math.max(0.0, width - used);
    var x = switch (_justify) {
      FlexJustify.center => free / 2,
      FlexJustify.end => free,
      _ => 0.0,
    };
    final between = _justify == FlexJustify.between && children.length > 1
        ? free / (children.length - 1)
        : 0.0;
    for (final c in children) {
      final y = switch (_align) {
        FlexAlign.start || FlexAlign.stretch => 0.0,
        FlexAlign.end => height - c.size.height,
        FlexAlign.center => (height - c.size.height) / 2,
      };
      _data(c).offset = Offset(x, y);
      x += c.size.width + _gap + between;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _children.fold(0.0, (a, c) => a + c.getMaxIntrinsicWidth(height)) +
      _gap * math.max(0, childCount - 1);

  @override
  double computeMinIntrinsicHeight(double width) => _children.fold(
    0.0,
    (a, c) => math.max(a, c.getMinIntrinsicHeight(double.infinity)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _children.fold(
    0.0,
    (a, c) => math.max(a, c.getMaxIntrinsicHeight(double.infinity)),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final children = _children;
    final widths = _widths(
      children,
      constraints.maxWidth,
      _natural(children, constraints.maxWidth, dry: true),
    );
    var height = 0.0;
    for (final (i, c) in children.indexed) {
      height = math.max(
        height,
        c.getDryLayout(BoxConstraints.tightFor(width: widths[i])).height,
      );
    }
    final used =
        widths.fold(0.0, (a, b) => a + b) +
        _gap * math.max(0, children.length - 1);
    return constraints.constrain(
      Size(constraints.maxWidth.isFinite ? constraints.maxWidth : used, height),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
