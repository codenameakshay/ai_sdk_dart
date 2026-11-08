import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../view.dart';
import 'markdown.dart';

final _numeric = RegExp(
  r'^[-+−]?[$€£¥₹]?\s?\d[\d,]*(\.\d+)?\s?(%|[kKmMbB]|bn)?$',
);
final _blank = RegExp(r'^(n/a|—|–|-)$', caseSensitive: false);
final _tabular = [const FontFeature.tabularFigures()];

Widget buildTable(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final columns = node.props.list('columns').map(_label).toList();
  final rows = node.props.list('rows').whereType<List<Object?>>().toList();
  final numeric = [
    for (var c = 0; c < columns.length; c++) _isNumeric(rows, c),
  ];
  final body = TextStyle(fontSize: 14, height: 1.5, color: theme.ink);
  final head = body.copyWith(fontSize: 13, fontWeight: FontWeight.w500);

  final headerRow = TableRow(
    decoration: BoxDecoration(color: theme.surface),
    children: [
      for (var c = 0; c < columns.length; c++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: _align(
            Text(
              columns[c],
              softWrap: false,
              style: numeric[c] ? head.copyWith(fontFeatures: _tabular) : head,
            ),
            numeric[c],
          ),
        ),
    ],
  );
  final bodyRows = [
    for (final row in rows)
      TableRow(
        children: [
          for (var c = 0; c < columns.length; c++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: _cell(
                context,
                node,
                c < row.length ? row[c] : null,
                numeric[c] ? body.copyWith(fontFeatures: _tabular) : body,
                numeric[c],
              ),
            ),
        ],
      ),
  ];

  return Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      border: Border.all(color: theme.border),
      borderRadius: BorderRadius.circular(14),
    ),
    child: LayoutBuilder(
      builder: (_, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              border: TableBorder(
                horizontalInside: BorderSide(color: theme.border),
              ),
              children: [headerRow, ...bodyRows],
            ),
          ),
        ),
      ),
    ),
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

Widget _align(Widget child, bool right) => Align(
  alignment: right
      ? AlignmentDirectional.centerEnd
      : AlignmentDirectional.centerStart,
  child: child,
);

Widget _cell(
  BuildContext context,
  OpenUiNode node,
  Object? value,
  TextStyle style,
  bool right,
) {
  final content = switch (value) {
    OpenUiElement element => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: node.render(element),
    ),
    final num number => Text(_formatNumber(number), style: style),
    _ => Text.rich(
      TextSpan(
        children: inlineSpans(
          value == null ? '' : jsString(value),
          context,
          style: style,
        ),
      ),
    ),
  };
  return _align(content, right);
}

/// en-US with at most two decimals, as `toLocaleString` prints it.
String _formatNumber(num value) {
  if (!value.isFinite) return jsString(value);
  final parts = value.abs().toStringAsFixed(2).split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+$)'),
    (_) => ',',
  );
  final fraction = parts[1].replaceFirst(RegExp(r'0+$'), '');
  return '${value.isNegative ? '-' : ''}$whole'
      '${fraction.isEmpty ? '' : '.$fraction'}';
}
