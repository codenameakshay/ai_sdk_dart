import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme.dart';
import '../view.dart';
import 'markdown.dart';

final _numeric = RegExp(
  r'^[-+−]?[$€£¥₹]?\s?\d[\d,]*(\.\d+)?\s?(%|[kKmMbB]|bn)?$',
);
final _blank = RegExp(r'^(n/a|—|–|-)$', caseSensitive: false);
const _fixedComponents = {'Badge', 'Button', 'IconButton', 'Icon', 'Link'};

/// `.iui-table th`: 13px, weight 560, ink.
TextStyle iuiTableHeadStyle(OpenUiTheme t) => TextStyle(
  fontSize: t.typography.size(13),
  height: 1.5,
  fontWeight: t.typography.medium,
  color: t.ink,
  fontFamily: t.fontFamily,
);

/// `.iui-table td`: 14px, line height 1.5, ink.
TextStyle iuiTableBodyStyle(OpenUiTheme t) => TextStyle(
  fontSize: t.typography.size(14),
  height: 1.5,
  color: t.ink,
  fontFamily: t.fontFamily,
);

/// One body cell; [component] names the element it renders, if any.
final class IuiCell {
  const IuiCell(this.child, {this.component});
  final Widget child;
  final String? component;
}

/// A `.iui-table` frame laid out like an HTML table with `width: 100%`.
class IuiTable extends StatefulWidget {
  const IuiTable({
    super.key,
    required this.head,
    required this.rows,
    this.numeric = const [],
  });

  final List<Widget> head;

  /// Rows shorter than [head] get empty cells; longer rows are cut.
  final List<List<IuiCell>> rows;

  /// Per column: right-aligned, tabular figures, no wrapping.
  final List<bool> numeric;

  @override
  State<IuiTable> createState() => _IuiTableState();
}

class _IuiTableState extends State<IuiTable> {
  final _layoutKey = GlobalKey();
  int? _hovered;

  void _hover(Offset position) {
    final box = _layoutKey.currentContext?.findRenderObject();
    final row = box is RenderIuiTable ? box.rowAt(position) : null;
    if (row != _hovered) setState(() => _hovered = row);
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final s = theme.styleOf('Table');
    final tableTheme = s.foreground == null
        ? theme
        : theme.withInk(s.foreground!);
    final phone = MediaQuery.sizeOf(context).width <= 640;
    final h = phone ? 12.0 : 16.0;
    final bodyV = phone ? 11.0 : 13.0;
    final styledPadding = s.padding?.resolve(Directionality.of(context));
    final horizontalPadding = styledPadding?.horizontal ?? 2 * h;
    final columns = widget.head.length;
    bool numeric(int c) => c < widget.numeric.length && widget.numeric[c];
    Widget align(Widget child, int c) => Align(
      alignment: numeric(c)
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: child,
    );

    final cells = <Widget>[
      for (var c = 0; c < columns; c++)
        _CellData(
          row: 0,
          col: c,
          kind: _Kind.header,
          child: Semantics(
            container: true,
            role: SemanticsRole.columnHeader,
            child: Padding(
              padding:
                  styledPadding ??
                  EdgeInsets.symmetric(horizontal: h, vertical: 11),
              child: DefaultTextStyle.merge(
                style: iuiTableHeadStyle(tableTheme).copyWith(
                  fontFeatures: numeric(c)
                      ? tableTheme.typography.tabular
                      : null,
                ),
                softWrap: false,
                child: align(widget.head[c], c),
              ),
            ),
          ),
        ),
      for (var r = 0; r < widget.rows.length; r++)
        for (var c = 0; c < columns; c++)
          _bodyCell(
            r,
            c,
            c < widget.rows[r].length ? widget.rows[r][c] : null,
            tableTheme,
            styledPadding ??
                EdgeInsets.symmetric(horizontal: h, vertical: bodyV),
            numeric(c),
            align,
          ),
    ];

    Widget table = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: s.border ?? theme.border),
        borderRadius: BorderRadius.circular(s.radius ?? theme.radii.xl),
      ),
      child: LayoutBuilder(
        builder: (_, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: MouseRegion(
            onHover: (e) => _hover(e.localPosition),
            onExit: (_) => setState(() => _hovered = null),
            child: _TableLayout(
              key: _layoutKey,
              columns: columns,
              availableWidth: constraints.maxWidth,
              horizontalPadding: horizontalPadding,
              hoveredRow: _hovered,
              header: s.background ?? theme.surface,
              hover: theme.surface.withValues(alpha: theme.surface.a * 0.7),
              line: theme.border,
              children: cells,
            ),
          ),
        ),
      ),
    );
    if (s.foreground case final foreground?) {
      table = Theme(
        data: Theme.of(context).copyWith(
          extensions: [...Theme.of(context).extensions.values, tableTheme],
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: table,
        ),
      );
    }
    return table;
  }

  Widget _bodyCell(
    int r,
    int c,
    IuiCell? cell,
    OpenUiTheme theme,
    EdgeInsets padding,
    bool numeric,
    Widget Function(Widget, int) align,
  ) {
    final kind = cell?.component != null
        ? _Kind.component
        : numeric
        ? _Kind.numeric
        : _Kind.text;
    return _CellData(
      row: r + 1,
      col: c,
      kind: kind,
      component: cell?.component,
      child: Semantics(
        container: true,
        role: SemanticsRole.cell,
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(
            style: iuiTableBodyStyle(
              theme,
            ).copyWith(fontFeatures: numeric ? theme.typography.tabular : null),
            softWrap: !numeric,
            child: align(cell?.child ?? const SizedBox.shrink(), c),
          ),
        ),
      ),
    );
  }
}

enum _Kind { header, text, numeric, component }

final class _CellParentData extends ContainerBoxParentData<RenderBox> {
  int row = 0;
  int col = 0;
  _Kind kind = _Kind.text;
  String? component;
}

class _CellData extends ParentDataWidget<_CellParentData> {
  const _CellData({
    required this.row,
    required this.col,
    required this.kind,
    this.component,
    required super.child,
  });

  final int row;
  final int col;
  final _Kind kind;
  final String? component;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _CellParentData;
    if (data.row == row &&
        data.col == col &&
        data.kind == kind &&
        data.component == component) {
      return;
    }
    data
      ..row = row
      ..col = col
      ..kind = kind
      ..component = component;
    renderObject.parent?.markNeedsLayout();
  }

  // coverage:ignore-start
  @override
  Type get debugTypicalAncestorWidgetClass => _TableLayout;
  // coverage:ignore-end
}

class _TableLayout extends MultiChildRenderObjectWidget {
  const _TableLayout({
    super.key,
    required this.columns,
    required this.availableWidth,
    required this.horizontalPadding,
    required this.hoveredRow,
    required this.header,
    required this.hover,
    required this.line,
    required super.children,
  });

  final int columns;
  final double availableWidth;
  final double horizontalPadding;
  final int? hoveredRow;
  final Color header;
  final Color hover;
  final Color line;

  @override
  RenderIuiTable createRenderObject(BuildContext context) => RenderIuiTable(
    columns: columns,
    availableWidth: availableWidth,
    horizontalPadding: horizontalPadding,
    hoveredRow: hoveredRow,
    header: header,
    hover: hover,
    line: line,
  );

  @override
  void updateRenderObject(BuildContext context, RenderIuiTable renderObject) {
    renderObject
      ..columns = columns
      ..availableWidth = availableWidth
      ..horizontalPadding = horizontalPadding
      ..hoveredRow = hoveredRow
      ..header = header
      ..hover = hover
      ..line = line;
  }
}

/// Lays out table cells with the CSS automatic table layout algorithm.
class RenderIuiTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CellParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CellParentData> {
  RenderIuiTable({
    required int columns,
    required double availableWidth,
    required double horizontalPadding,
    required int? hoveredRow,
    required Color header,
    required Color hover,
    required Color line,
  }) : _columns = columns,
       _availableWidth = availableWidth,
       _horizontalPadding = horizontalPadding,
       _hoveredRow = hoveredRow,
       _header = header,
       _hover = hover,
       _line = line;

  int _columns;
  set columns(int v) {
    if (v == _columns) return;
    _columns = v;
    markNeedsLayout();
  }

  double _availableWidth;
  set availableWidth(double v) {
    if (v == _availableWidth) return;
    _availableWidth = v;
    markNeedsLayout();
  }

  double _horizontalPadding;
  set horizontalPadding(double v) {
    if (v == _horizontalPadding) return;
    _horizontalPadding = v;
    markNeedsLayout();
  }

  int? _hoveredRow;

  /// The hovered body row, counted from 0, or null.
  int? get hoveredRow => _hoveredRow;
  set hoveredRow(int? v) {
    if (v == _hoveredRow) return;
    _hoveredRow = v;
    markNeedsPaint();
  }

  Color _header;
  set header(Color v) {
    if (v == _header) return;
    _header = v;
    markNeedsPaint();
  }

  Color _hover;
  set hover(Color v) {
    if (v == _hover) return;
    _hover = v;
    markNeedsPaint();
  }

  Color _line;
  set line(Color v) {
    if (v == _line) return;
    _line = v;
    markNeedsPaint();
  }

  /// Top of each row, with one extra entry for the bottom edge.
  List<double> _rowTops = const [0];

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CellParentData) {
      child.parentData = _CellParentData();
    }
  }

  /// The body row at [position], counted from 0; null over the header or outside.
  int? rowAt(Offset position) {
    for (var r = 1; r < _rowTops.length - 1; r++) {
      if (position.dy >= _rowTops[r] && position.dy < _rowTops[r + 1]) {
        return r - 1;
      }
    }
    return null;
  }

  final Map<int, SemanticsNode> _semanticRows = {};

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..role = SemanticsRole.table
      ..isSemanticBoundary = true
      ..explicitChildNodes = true;
  }

  @override
  void clearSemantics() {
    super.clearSemantics();
    _semanticRows.clear();
  }

  /// Rows are not render objects, so their nodes are made here: each cell's
  /// node goes into the row whose band holds its top edge. Row nodes keep the
  /// table's coordinates, so the cells' own transforms stay right.
  @override
  void assembleSemanticsNode(
    SemanticsNode node,
    SemanticsConfiguration config,
    Iterable<SemanticsNode> children,
  ) {
    final rowCount = _rowTops.length - 1;
    final cells = List.generate(rowCount, (_) => <SemanticsNode>[]);
    for (final child in children) {
      final shift = child.transform == null
          ? Offset.zero
          : MatrixUtils.getAsTranslation(child.transform!) ?? Offset.zero;
      final top = child.rect.top + shift.dy;
      var row = rowCount - 1;
      while (row > 0 && _rowTops[row] > top + 0.5) {
        row--;
      }
      if (row >= 0) cells[row].add(child);
    }
    node.updateWith(
      config: config,
      childrenInInversePaintOrder: [
        for (var r = 0; r < rowCount; r++)
          if (cells[r].isNotEmpty)
            (_semanticRows[r] ??= SemanticsNode())
              ..updateWith(
                config: SemanticsConfiguration()
                  ..role = SemanticsRole.row
                  ..indexInParent = r,
                childrenInInversePaintOrder: cells[r],
              )
              ..rect = Rect.fromLTRB(
                0,
                _rowTops[r],
                size.width,
                _rowTops[r + 1],
              ),
      ],
    );
  }

  /// A cell's CSS min-content width, from Flutter's intrinsic widths. A
  /// LayoutBuilder cannot report one: release builds count it as 0, and the
  /// flag makes debug builds do the same instead of throwing.
  double _minContent(RenderBox child) {
    var checking = false;
    assert(() {
      checking = RenderObject.debugCheckingIntrinsics;
      RenderObject.debugCheckingIntrinsics = true;
      return true;
    }());
    try {
      return child.getMinIntrinsicWidth(double.infinity);
    } finally {
      assert(() {
        RenderObject.debugCheckingIntrinsics = checking;
        return true;
      }());
    }
  }

  ({double min, double max}) _measure(RenderBox child, _CellParentData data) {
    switch (data.kind) {
      case _Kind.header || _Kind.numeric:
        final w = child.getMaxIntrinsicWidth(double.infinity);
        return (min: w, max: w);
      case _Kind.text:
        return (
          min: _minContent(child),
          max: child.getMaxIntrinsicWidth(double.infinity),
        );
      case _Kind.component:
        child.layout(
          BoxConstraints(maxWidth: math.max(0, _availableWidth)),
          parentUsesSize: true,
        );
        final probe = child.size.width;
        // `.iui-text`, `.iui-title` and `.iui-markdown` wrap anywhere, so their
        // CSS min-content is about one glyph; Flutter's only breaks at words.
        return _fixedComponents.contains(data.component)
            ? (min: probe, max: probe)
            : (min: _horizontalPadding, max: probe);
    }
  }

  List<double> _widths() {
    final mins = List.filled(_columns, 0.0);
    final maxes = List.filled(_columns, 0.0);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _CellParentData;
      if (data.col >= _columns) continue;
      final m = _measure(child, data);
      mins[data.col] = math.max(mins[data.col], m.min);
      maxes[data.col] = math.max(maxes[data.col], math.max(m.min, m.max));
    }
    final w = _availableWidth;
    final sumMin = mins.fold(0.0, (a, b) => a + b);
    final sumMax = maxes.fold(0.0, (a, b) => a + b);
    if (sumMax <= w) {
      final extra = w - sumMax;
      return [
        for (final m in maxes)
          m + (sumMax == 0 ? extra / _columns : extra * m / sumMax),
      ];
    }
    if (sumMin <= w) {
      final spread = sumMax - sumMin;
      return [
        for (var c = 0; c < _columns; c++)
          mins[c] +
              (spread == 0 ? 0 : (w - sumMin) * (maxes[c] - mins[c]) / spread),
      ];
    }
    return mins;
  }

  @override
  void performLayout() {
    if (_columns == 0) {
      _rowTops = const [0];
      size = constraints.constrain(Size.zero);
      return;
    }
    final widths = _widths();
    final lefts = [0.0];
    for (final w in widths) {
      lefts.add(lefts.last + w);
    }
    var rows = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      rows = math.max(rows, (child.parentData! as _CellParentData).row + 1);
    }
    final heights = List.filled(rows, 0.0);
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _CellParentData;
      if (data.col >= _columns) continue;
      child.layout(
        BoxConstraints.tightFor(width: widths[data.col]),
        parentUsesSize: true,
      );
      heights[data.row] = math.max(heights[data.row], child.size.height);
    }
    final tops = [0.0];
    for (var r = 0; r < rows; r++) {
      final line = r < rows - 1 || r == 0 ? 1.0 : 0.0;
      tops.add(tops.last + heights[r] + line);
    }
    _rowTops = tops;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _CellParentData;
      if (data.col >= _columns) continue;
      data.offset = Offset(
        lefts[data.col],
        tops[data.row] + (heights[data.row] - child.size.height) / 2,
      );
    }
    size = constraints.constrain(Size(lefts.last, tops.last));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final width = size.width;
    if (_rowTops.length > 1) {
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, width, _rowTops[1] - 1),
        Paint()..color = _header,
      );
    }
    final hovered = _hoveredRow;
    if (hovered != null && hovered + 2 < _rowTops.length) {
      final top = _rowTops[hovered + 1];
      canvas.drawRect(
        Rect.fromLTWH(
          offset.dx,
          offset.dy + top,
          width,
          _rowTops[hovered + 2] - top,
        ),
        Paint()..color = _hover,
      );
    }
    defaultPaint(context, offset);
    final paint = Paint()..color = _line;
    for (var r = 1; r < _rowTops.length; r++) {
      final isLast = r == _rowTops.length - 1;
      if (isLast && r > 1) break;
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy + _rowTops[r] - 1, width, 1),
        paint,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

Widget buildTable(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final style = theme.styleOf('Table');
  final tableTheme = style.foreground == null
      ? theme
      : theme.withInk(style.foreground!);
  final columns = node.props.list('columns').map(_label).toList();
  final rows = node.props.list('rows').whereType<List<Object?>>().toList();
  final numeric = [
    for (var c = 0; c < columns.length; c++) _isNumeric(rows, c),
  ];
  final body = iuiTableBodyStyle(tableTheme);
  return IuiTable(
    head: [
      for (final c in columns) Text(c, style: iuiTableHeadStyle(tableTheme)),
    ],
    numeric: numeric,
    rows: [
      for (final row in rows)
        [
          for (var c = 0; c < columns.length; c++)
            _cell(context, node, c < row.length ? row[c] : null, body),
        ],
    ],
  );
}

String _label(Object? value) => value == null ? '' : jsString(value);

bool _isNumeric(List<List<Object?>> rows, int c) {
  final cells =
      [
        for (final row in rows)
          if (c < row.length) row[c],
      ].where(
        (v) =>
            v != null && v != '' && !(v is String && _blank.hasMatch(v.trim())),
      );
  return cells.isNotEmpty &&
      cells.every(
        (v) => v is num || (v is String && _numeric.hasMatch(v.trim())),
      );
}

IuiCell _cell(
  BuildContext context,
  OpenUiNode node,
  Object? value,
  TextStyle style,
) => switch (value) {
  OpenUiElement element => IuiCell(
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: node.render(element),
    ),
    component: element.typeName,
  ),
  final num number => IuiCell(Text(_formatNumber(number))),
  _ => IuiCell(
    InlineText(
      (context, links) => inlineSpans(
        value == null ? '' : jsString(value),
        context,
        style: style,
        links: links,
      ),
    ),
  ),
};

/// en-US with at most two decimals, as `toLocaleString` prints it.
String _formatNumber(num value) {
  if (!value.isFinite) return jsString(value);
  return intelligentUi.functions.firstWhere((f) => f.name == 'Format').fn({
        'value': value,
      })!
      as String;
}
