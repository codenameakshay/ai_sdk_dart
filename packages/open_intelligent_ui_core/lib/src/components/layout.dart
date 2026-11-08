import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../view.dart';
import 'block_slot.dart';
import 'flex_row.dart';
import 'media.dart' show MediaRowSlot;

Widget buildCol(BuildContext context, OpenUiNode node) {
  final gap = node.theme.spaceOf(node.props['gap']);
  final items = _slot(
    _items(node, node.props['children']),
    parent: _flowParent(context, node, flow: gap == null),
    flow: gap == null,
  );
  return _column(
    context,
    items,
    gap: gap,
    cross: _cross(node.props.string('align'), CrossAxisAlignment.stretch),
    align: node.props.string('align'),
  );
}

Widget buildRow(BuildContext context, OpenUiNode node) {
  final gap = node.theme.spaceOf(node.props['gap']) ?? 8;
  final align = node.props.string('align');
  final justify = node.props.string('justify');
  final items = _slot(
    _items(node, node.props['children']),
    parent: SlotParent.other,
    flow: false,
  );
  return _cardHead(
    context,
    node,
    _row(
      items,
      theme: node.theme,
      gap: gap,
      align: align,
      justify: justify,
      wrap: node.props.boolean('wrap') ?? false,
    ),
  );
}

Widget buildBox(BuildContext context, OpenUiNode node) {
  final row = node.props.string('direction') == 'row';
  final gap = node.theme.spaceOf(node.props['gap']);
  final align = node.props.string('align');
  final justify = node.props.string('justify');
  final wrap = node.props.boolean('wrap') ?? false;
  final items = _items(node, node.props['children']);
  final Widget content;
  if (row) {
    content = _row(
      _slot(items, parent: SlotParent.other, flow: false),
      theme: node.theme,
      gap: gap ?? 8,
      align: align,
      justify: justify,
      wrap: wrap,
    );
  } else {
    content = _column(
      context,
      _slot(
        items,
        parent: _flowParent(context, node, flow: gap == null),
        flow: gap == null,
      ),
      gap: gap,
      cross: _cross(align, CrossAxisAlignment.stretch),
      main: _main(justify),
      align: align,
    );
  }

  final theme = node.theme;
  final background = node.props['background'];
  final clip = node.props.has('radius');
  final radius = theme.radiusOf(node.props['radius']) ?? 0;
  final padded = Padding(
    padding: EdgeInsets.all(theme.spaceOf(node.props['padding']) ?? 0),
    child: row ? _cardHead(context, node, content) : content,
  );
  final fixedHeight = OpenUiTheme.length(node.props['height']).px != null;
  final contained = fixedHeight
      ? LayoutBuilder(
          builder: (context, constraints) => OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: constraints.maxHeight,
            maxHeight: double.infinity,
            child: padded,
          ),
        )
      : padded;
  final clipped = clip
      ? ClipRRect(borderRadius: BorderRadius.circular(radius), child: contained)
      : contained;
  Widget box = Container(
    decoration: BoxDecoration(
      color: theme.bg(background),
      gradient: theme.bgGradient(background),
      borderRadius: BorderRadius.circular(radius),
      border: (node.props.boolean('border') ?? false)
          ? Border.all(color: theme.border)
          : null,
    ),
    child: clipped,
  );

  // In a media row the photo slot sets the width (CSS `!important`).
  box = _sized(context, box, node, width: !MediaRowSlot.of(context));

  final ink = theme.inkOn(background);
  if (ink == null) return box;
  return DefaultTextStyle.merge(
    style: TextStyle(color: ink),
    child: Theme(data: _themed(context, theme.withInk(ink)), child: box),
  );
}

/// A Box's width and height. A percent height only applies inside a bounded
/// height, as in CSS; content taller than a fixed height overflows, unclipped,
/// without breaking the layout.
Widget _sized(
  BuildContext context,
  Widget box,
  OpenUiNode node, {
  bool width = true,
}) {
  final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
  final viewport = MediaQuery.sizeOf(context);
  final w = width
      ? OpenUiTheme.length(
          node.props['width'],
          fontSize: fontSize,
          viewport: viewport,
        )
      : (px: null, fraction: null);
  final height = OpenUiTheme.length(
    node.props['height'],
    fontSize: fontSize,
    viewport: viewport,
  );
  var out = box;
  if (w.px != null || height.px != null) {
    out = SizedBox(width: w.px, height: height.px, child: out);
    // A stretched column would widen it; CSS keeps an explicit width.
    if (w.px != null) {
      out = Align(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: 1,
        child: out,
      );
    }
  }
  if (w.fraction != null || height.fraction != null) {
    final inner = out;
    out = LayoutBuilder(
      builder: (context, constraints) => FractionallySizedBox(
        widthFactor: constraints.hasBoundedWidth ? w.fraction : null,
        heightFactor: constraints.hasBoundedHeight ? height.fraction : null,
        child: inner,
      ),
    );
  }
  return out;
}

Widget buildGrid(BuildContext context, OpenUiNode node) {
  final columns = math.max(
    1,
    math.min(12, (node.props.number('columns') ?? 2).round()),
  );
  final gap = node.theme.spaceOf(node.props['gap']) ?? 12;
  final minWidth = node.props.number('minChildWidth') ?? 0;
  final items = _slot(
    _items(node, node.props['children']),
    parent: SlotParent.grid,
    flow: false,
  );
  if (minWidth == 0) return _gridRows(items, columns, gap);
  final minPx = math.max(0, minWidth).toDouble();
  return LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth;
      final fit = available.isFinite && minPx + gap > 0
          ? ((available + gap) / (minPx + gap)).floor()
          : columns;
      return _gridRows(items, math.max(1, math.min(columns, fit)), gap);
    },
  );
}

Widget buildCard(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final nested = context.findAncestorWidgetOfExactType<_CardScope>() != null;
  final compact = nested || MediaQuery.sizeOf(context).width <= 640;
  final soft = node.props.string('variant') == 'soft';
  final s = theme.styleOf('Card', soft ? 'soft' : 'outline');
  final gap = theme.spaceOf(node.props['gap']);
  final body = _column(
    context,
    _slot(
      _items(node, node.props['children']),
      parent: SlotParent.card,
      flow: gap == null,
    ),
    gap: gap,
    cross: CrossAxisAlignment.stretch,
    flowBase: 12,
  );
  final modelPadding = theme.spaceOf(node.props['padding']);
  Widget content = _CardScope(
    child: DefaultTextStyle.merge(
      style: TextStyle(fontSize: theme.typography.size(14), height: 1.55),
      child: CardHeadScope(active: false, child: body),
    ),
  );
  if (s.foreground case final foreground?) {
    content = Theme(
      data: _themed(context, theme.withInk(foreground)),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: foreground),
        child: content,
      ),
    );
  }
  return Container(
    padding: modelPadding != null
        ? EdgeInsets.all(modelPadding)
        : s.padding ?? EdgeInsets.all(compact ? 16 : 20),
    decoration: BoxDecoration(
      color: s.background ?? (soft ? theme.surface : theme.canvas),
      borderRadius: BorderRadius.circular(
        s.radius ?? (nested ? theme.radii.lg : theme.radii.xl),
      ),
      border: Border.all(
        color: s.border ?? (soft ? Colors.transparent : theme.border),
      ),
    ),
    child: content,
  );
}

Widget buildDivider(BuildContext context, OpenUiNode node) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Container(height: 1, color: node.theme.border),
);

Widget buildSpacer(BuildContext context, OpenUiNode node) =>
    const SizedBox.shrink();

Widget buildForm(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final items = _slot(
    _items(node, node.props['children']),
    parent: SlotParent.other,
    flow: false,
  );
  return node.form(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: theme.spacing.fieldGap,
      children: [
        for (final (i, item) in items.indexed)
          i == items.length - 1 && _isAction(item)
              ? Padding(
                  key: item.siblingKey,
                  padding: EdgeInsets.only(
                    top: theme.spacing.actionGap - theme.spacing.fieldGap,
                  ),
                  child: item.widget,
                )
              : item.widget,
      ],
    ),
  );
}

final class _FlowScope extends InheritedWidget {
  const _FlowScope({required super.child});

  @override
  bool updateShouldNotify(_FlowScope old) => false;
}

final class _CardScope extends InheritedWidget {
  const _CardScope({required super.child});

  @override
  bool updateShouldNotify(_CardScope old) => false;
}

final class _Item {
  const _Item(this.widget, this.element);
  final Widget widget;
  final OpenUiElement? element;

  Key? get siblingKey {
    final key = widget.key;
    return key == null ? null : ValueKey<Object>(key);
  }

  String? get type => element?.typeName;
}

List<_Item> _items(OpenUiNode node, Object? value) {
  final out = <_Item>[];
  void visit(Object? v) {
    if (v is List) {
      for (final x in v) {
        visit(x);
      }
      return;
    }
    if (v is OpenUiElement) {
      final id = node.childId(v, out.length, slot: 'children');
      out.add(
        _Item(
          OpenUiElementView(key: ValueKey('openui:$id'), element: v, id: id),
          v,
        ),
      );
      return;
    }
    for (final w in node.render(v)) {
      out.add(_Item(w, null));
    }
  }

  visit(value);
  return out;
}

/// Wraps each item in its [BlockSlot], so CSS sibling rules see Spacers too.
List<_Item> _slot(
  List<_Item> items, {
  required SlotParent parent,
  required bool flow,
}) {
  final out = <_Item>[];
  var index = 0;
  OpenUiElement? previous;
  for (final item in items) {
    out.add(
      _Item(
        BlockSlot(
          key: item.siblingKey,
          element: item.element,
          parent: parent,
          index: index,
          previous: previous,
          flow: flow,
          child: item.widget,
        ),
        item.element,
      ),
    );
    index++;
    previous = item.element;
  }
  return out;
}

/// A flow column inside a grid or carousel item is card-sized, as in CSS
/// `.iui-grid > .iui-flow`; its children inherit that.
SlotParent _flowParent(
  BuildContext context,
  OpenUiNode node, {
  required bool flow,
}) {
  if (!flow) return SlotParent.other;
  final parent = BlockSlot.of(context, node.element)?.parent;
  return parent == SlotParent.grid || parent == SlotParent.carouselItem
      ? SlotParent.cardSizedFlow
      : SlotParent.other;
}

/// A Row, or a row Box, in a card's first slot heads the card.
Widget _cardHead(BuildContext context, OpenUiNode node, Widget content) {
  final slot = BlockSlot.of(context, node.element);
  final head = slot?.parent == SlotParent.card && slot?.index == 0;
  return head ? CardHeadScope(active: true, child: content) : content;
}

bool _isBadgeRow(OpenUiElement? element) =>
    element?.typeName == 'Row' &&
    element!.props.elements('children').any((c) => c.typeName == 'Badge');

bool _isAction(_Item item) {
  final element = item.element;
  if (element == null) return false;
  if (element.typeName == 'Button') return true;
  return element.typeName == 'Row' &&
      element.props.elements('children').any((c) => c.typeName == 'Button');
}

double _flowGap(_Item prev, _Item next, double base) {
  final before = prev.type;
  final after = next.type;
  if (before == 'Title') {
    return after == 'Text' || after == 'Caption' || _isBadgeRow(next.element)
        ? 8
        : 12;
  }
  if (before == 'Caption' && after == 'Title') return 4;
  if (before == 'Text' && after == 'Text') return 12;
  return base;
}

/// Blocks with CSS `align-self: flex-start`, which a column's align does not move.
const _startAligned = {'Badge', 'Button', 'SegmentedControl'};

Widget _column(
  BuildContext context,
  List<_Item> items, {
  required double? gap,
  required CrossAxisAlignment cross,
  MainAxisAlignment main = MainAxisAlignment.start,
  String? align,
  double? flowBase,
}) {
  final flow = gap == null;
  final base =
      flowBase ??
      (context.findAncestorWidgetOfExactType<_FlowScope>() != null
          ? 12.0
          : 24.0);
  Widget place(_Item item) =>
      cross != CrossAxisAlignment.stretch && _startAligned.contains(item.type)
      ? Align(
          key: item.siblingKey,
          alignment: AlignmentDirectional.centerStart,
          child: item.widget,
        )
      : item.widget;
  final column = Column(
    crossAxisAlignment: cross,
    mainAxisAlignment: main,
    spacing: gap ?? 0,
    children: flow
        ? [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) SizedBox(height: _flowGap(items[i - 1], item, base)),
              place(item),
            ],
          ]
        : [for (final item in items) place(item)],
  );
  final textAlign = switch (align) {
    'center' => TextAlign.center,
    'end' => TextAlign.end,
    _ => null,
  };
  final aligned = textAlign == null
      ? column
      : DefaultTextStyle.merge(textAlign: textAlign, child: column);
  return flow ? _FlowScope(child: aligned) : aligned;
}

bool _isMedia(_Item item) {
  final e = item.element;
  if (e == null) return false;
  if (e.typeName == 'SearchImage' || e.typeName == 'Image') return true;
  final children = e.typeName == 'Box'
      ? e.props.elements('children')
      : const <OpenUiElement>[];
  return children.length == 1 &&
      (children.single.typeName == 'SearchImage' ||
          children.single.typeName == 'Image');
}

/// A CSS flex row, wrapping when [wrap]: children keep their width and
/// shrink when they do not fit; a Spacer or a flex Box takes the free space. A photo (or a Box with
/// only a photo) makes a media row: top-aligned, 16px gap, the photo a third
/// of the row between 120 and 200px.
Widget _row(
  List<_Item> items, {
  required OpenUiTheme theme,
  required double gap,
  String? align,
  String? justify,
  bool wrap = false,
}) {
  final media = items.any(_isMedia);
  return FlexRow(
    gap: media ? theme.spacing.groupLarge : gap,
    justify: switch (justify) {
      'center' => FlexJustify.center,
      'end' => FlexJustify.end,
      'between' => FlexJustify.between,
      _ => FlexJustify.start,
    },
    align: media
        ? FlexAlign.start
        : switch (align) {
            'start' => FlexAlign.start,
            'end' => FlexAlign.end,
            'stretch' => FlexAlign.stretch,
            _ => FlexAlign.center,
          },
    wrap: wrap,
    children: [
      for (final item in items)
        if (item.type == 'Spacer')
          FlexRowItem(
            key: item.siblingKey,
            spacer: true,
            child: const SizedBox.shrink(),
          )
        else if (_isMedia(item))
          FlexRowItem(
            key: item.siblingKey,
            fixed: (w) => (w * 0.33).clamp(120, 200),
            child: MediaRowSlot(child: item.widget),
          )
        else if (_flexOf(item) case final flex?)
          FlexRowItem(
            key: item.siblingKey,
            grow: flex,
            zeroBasis: true,
            child: item.widget,
          )
        else
          FlexRowItem(
            key: item.siblingKey,
            shrink: !_hasNumericWidth(item) && !_rowFixed.contains(item.type),
            alignSelf: _alignSelf(item),
            child: item.widget,
          ),
    ],
  );
}

/// A Box's `flex: N 1 0%` share. A flex of 0 or less is no flex; CSS gives
/// it width 0 instead (parity note).
double? _flexOf(_Item item) {
  final flex = item.type == 'Box' ? item.element!.props.number('flex') : null;
  return flex != null && flex > 0 ? flex.toDouble() : null;
}

/// A Box with a px width keeps it (`flex: 0 0 auto`).
bool _hasNumericWidth(_Item item) =>
    item.type == 'Box' && item.element!.props['width'] is num;

/// Row children with CSS `flex: none`: they keep their width.
const _rowFixed = {'Button', 'IconButton', 'Badge', 'Icon'};

/// `align-self` a row's align does not change: `.iui-row > .iui-button` and
/// `.iui-row > .iui-badge` are centred, `.iui-segmented` sits at the start.
FlexAlign? _alignSelf(_Item item) => switch (item.type) {
  'Button' || 'Badge' => FlexAlign.center,
  'SegmentedControl' => FlexAlign.start,
  _ => null,
};

Widget _gridRows(List<_Item> items, int columns, double gap) => FlexRow(
  gap: gap,
  align: FlexAlign.stretch,
  wrap: true,
  childrenPerLine: columns,
  children: [
    for (final item in items)
      FlexRowItem(
        key: item.siblingKey,
        fixed: (w) => math.max(0, w - gap * (columns - 1)) / columns,
        child: _cell(item),
      ),
  ],
);

/// Photos keep their own height at the top of a stretched grid cell.
Widget _cell(_Item item) => item.type == 'Image' || item.type == 'SearchImage'
    ? Align(
        key: item.siblingKey,
        alignment: Alignment.topCenter,
        child: item.widget,
      )
    : item.widget;

ThemeData _themed(BuildContext context, OpenUiTheme tokens) {
  final base = Theme.of(context);
  return base.copyWith(extensions: [...base.extensions.values, tokens]);
}

CrossAxisAlignment _cross(String? align, CrossAxisAlignment fallback) =>
    switch (align) {
      'start' => CrossAxisAlignment.start,
      'center' => CrossAxisAlignment.center,
      'end' => CrossAxisAlignment.end,
      'stretch' => CrossAxisAlignment.stretch,
      _ => fallback,
    };

MainAxisAlignment _main(String? justify) => switch (justify) {
  'center' => MainAxisAlignment.center,
  'end' => MainAxisAlignment.end,
  'between' => MainAxisAlignment.spaceBetween,
  _ => MainAxisAlignment.start,
};
