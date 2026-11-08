import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import '../view.dart';
import 'glyph.dart';
import 'markdown.dart';

const _tabular = [FontFeature.tabularFigures()];
final _stepMarker = RegExp(r'^[0-9A-Za-z]{1,2}$');

const _textSizes = <String, ({double size, double height})>{
  'xs': (size: 12, height: 1.6),
  'sm': (size: 14, height: 1.55),
  'md': (size: 16, height: 1.6),
  'lg': (size: 18, height: 1.55),
};

const _weights = <String, FontWeight>{
  'normal': FontWeight.w400,
  'medium': FontWeight.w500,
  'semibold': FontWeight.w600,
};

({double fontSize, double height, double letterSpacing}) _titleMetrics(
  String? size,
) => switch (size) {
  'sm' => (fontSize: 15, height: 1.5, letterSpacing: 0),
  'lg' => (fontSize: 21, height: 1.3, letterSpacing: -0.55),
  'xl' => (fontSize: 25, height: 1.2, letterSpacing: -0.8),
  '2xl' => (fontSize: 32, height: 1.15, letterSpacing: -1),
  '3xl' => (fontSize: 40, height: 1.1, letterSpacing: -1.4),
  _ => (fontSize: 17, height: 1.4, letterSpacing: -0.2),
};

TextStyle _textStyle(
  OpenUiTheme theme, {
  required Color color,
  double? size,
  double? height,
  FontWeight? weight,
  FontStyle? fontStyle,
  TextDecoration? decoration,
  List<FontFeature>? fontFeatures,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: theme.fontFamily,
  fontSize: size,
  height: height,
  fontWeight: weight,
  fontStyle: fontStyle,
  decoration: decoration,
  color: color,
  fontFeatures: fontFeatures,
  letterSpacing: letterSpacing,
);

/// Text, or a run of strings and inline components. A list is flattened one
/// level, like the reference's `.flat()`.
List<InlineSpan> _textSpans(
  BuildContext context,
  Object? value,
  TextStyle style,
) {
  if (value is String) return inlineSpans(value, context, style: style);
  if (value is! List) return const [];
  final spans = <InlineSpan>[];
  for (final part in value.expand((p) => p is List ? p : [p])) {
    if (part is OpenUiElement) {
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: OpenUiElementView(element: part),
          ),
        ),
      );
    } else {
      spans.addAll(
        part == null
            ? const []
            : inlineSpans(jsString(part), context, style: style),
      );
    }
  }
  return spans;
}

Widget _richText(
  BuildContext context,
  Object? value,
  TextStyle style, {
  int? maxLines,
}) => Text.rich(
  TextSpan(children: _textSpans(context, value, style)),
  style: style,
  maxLines: maxLines,
  overflow: maxLines == null ? null : TextOverflow.ellipsis,
);

int? _lineLimit(Props props) {
  final lines = props.number('maxLines')?.round();
  return lines != null && lines > 0 ? lines : null;
}

Widget buildTitle(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final metrics = _titleMetrics(node.props.string('size'));
  final style = _textStyle(
    theme,
    color: theme.fg(node.props['color']) ?? theme.ink,
    size: metrics.fontSize,
    height: metrics.height,
    letterSpacing: metrics.letterSpacing,
    weight: FontWeight.w600,
    fontFeatures: _tabular,
  );
  return Semantics(
    header: true,
    child: _richText(context, node.props.string('text') ?? '', style),
  );
}

Widget buildText(BuildContext context, OpenUiNode node) {
  final props = node.props;
  final theme = node.theme;
  final size = _textSizes[props.string('size')];
  final style = _textStyle(
    theme,
    color: theme.fg(props['color']) ?? theme.ink,
    size: size?.size,
    height: size?.height ?? 1.6,
    weight: _weights[props.string('weight')],
    fontStyle: props.boolean('italic') == true ? FontStyle.italic : null,
    decoration: props.boolean('lineThrough') == true
        ? TextDecoration.lineThrough
        : null,
    fontFeatures: props.boolean('tabularNums') == true ? _tabular : null,
  );
  return _richText(context, props['text'], style, maxLines: _lineLimit(props));
}

Widget buildCaption(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  return _richText(
    context,
    node.props.string('text') ?? '',
    _textStyle(
      theme,
      color: theme.fg(node.props['color']) ?? theme.muted,
      size: 12,
      height: 1.6,
    ),
  );
}

Widget buildLabel(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  return Text(
    node.props.string('text') ?? '',
    style: _textStyle(
      theme,
      color: theme.ink,
      size: 14,
      height: 1.4,
      weight: FontWeight.w500,
    ),
  );
}

Widget buildBadge(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final tone = node.props.string('color');
  final (background, foreground) = tone == 'info'
      ? (theme.statusSoft['info'], theme.status['info'])
      : (theme.badgeSoft[tone], theme.badge[tone]);
  final color = foreground ?? theme.ink;
  final icon = node.props.string('icon');
  return Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? theme.badgeNeutralSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lucideCodepoint(icon) != null) ...[
            Glyph(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              node.props.string('text') ?? '',
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: _textStyle(
                theme,
                color: color,
                size: 13,
                height: 18 / 13,
                weight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget buildLink(BuildContext context, OpenUiNode node) {
  final text = node.props.string('text') ?? '';
  final uri = webUri(node.props['url']);
  if (uri == null) return Text(text);
  return _Link(
    label: text.isEmpty ? uri.host : text,
    style: DefaultTextStyle.of(context).style,
    restingDecoration: node.theme.borderStrong,
    onTap: () => node.services.openUrl(uri),
  );
}

final class _Link extends StatefulWidget {
  const _Link({
    required this.label,
    required this.style,
    required this.restingDecoration,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final Color restingDecoration;
  final VoidCallback onTap;

  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.style;
    final style = base.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: _hovered ? base.color : widget.restingDecoration,
    );
    return Semantics(
      link: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: widget.label),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Glyph(
                      'arrow-up-right',
                      size: (base.fontSize ?? 14) * 0.85,
                      color: base.color,
                    ),
                  ),
                ),
              ],
            ),
            style: style,
          ),
        ),
      ),
    );
  }
}

/// Items of a List, flattened one level.
List<Object?> _listItems(Object? raw) => [
  if (raw is List)
    for (final v in raw)
      if (v is List) ...v else v,
];

bool _isListItem(Object? item) =>
    item is OpenUiElement && item.typeName == 'ListItem';

String? _itemMarker(Object? item) {
  if (item is! OpenUiElement) return null;
  final marker = item.props.string('marker');
  return marker == null || marker.isEmpty ? null : marker;
}

bool _isRich(OpenUiElement item) =>
    (item.props.string('description') ?? '').isNotEmpty ||
    item.props['children'] != null;

Widget _numberCircle(OpenUiTheme theme, int number) => Container(
  width: 24,
  height: 24,
  alignment: Alignment.center,
  decoration: BoxDecoration(color: theme.ink, shape: BoxShape.circle),
  child: Text(
    '$number',
    style: _textStyle(
      theme,
      color: theme.onInk,
      size: 13,
      height: 1,
      fontFeatures: _tabular,
    ),
  ),
);

Widget _dot(OpenUiTheme theme) => Container(
  width: 5,
  height: 5,
  decoration: BoxDecoration(color: theme.faint, shape: BoxShape.circle),
);

Widget _ring(OpenUiTheme theme) => Container(
  width: 9,
  height: 9,
  decoration: BoxDecoration(
    color: theme.canvas,
    shape: BoxShape.circle,
    border: Border.all(color: theme.ink, width: 2),
  ),
);

Widget _customMarker(OpenUiTheme theme, String marker) {
  if (_stepMarker.hasMatch(marker)) {
    return Container(
      height: 20,
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.ink,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        marker,
        softWrap: false,
        style: _textStyle(
          theme,
          color: theme.onInk,
          size: 12,
          height: 1,
          weight: FontWeight.w500,
          fontFeatures: _tabular,
        ),
      ),
    );
  }
  return Text(
    marker,
    softWrap: false,
    style: _textStyle(
      theme,
      color: theme.muted,
      size: 13,
      fontFeatures: _tabular,
    ),
  );
}

Widget buildList(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final props = node.props;
  final marker = props.string('marker') ?? 'bullet';
  final numbered = marker == 'number';
  final none = marker == 'none';
  final timeline = props.boolean('timeline') ?? false;
  final entries = [
    for (final (index, item) in _listItems(props['items']).indexed)
      if (item is String || item is num || _isListItem(item)) (index, item),
  ];
  final customs = [for (final (_, item) in entries) _itemMarker(item)];
  final wide = customs.any((m) => m != null && m.length > 2);
  final chips = customs.any((m) => m != null && _stepMarker.hasMatch(m));
  final hasColumn = !none || customs.any((m) => m != null);
  final bullet = !numbered && !none;
  final (columnWidth, gap) = wide
      ? (76.0, timeline ? 24.0 : 16.0)
      : bullet && !timeline && !chips
      ? (14.0, 8.0)
      : (24.0, 12.0);
  final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;

  final rows = <Widget>[];
  for (final (k, (index, item)) in entries.indexed) {
    final last = k == entries.length - 1;
    final custom = customs[k];
    final textMarker = custom != null && !_stepMarker.hasMatch(custom);
    final rich = item is OpenUiElement && _isRich(item);
    final body = item is OpenUiElement
        ? _ListRowScope(
            rich: rich,
            child: OpenUiElementView(element: item),
          )
        : _richText(context, jsString(item), const TextStyle());

    Widget? mark;
    if (custom != null) {
      mark = _customMarker(theme, custom);
    } else if (!none) {
      mark = ExcludeSemantics(
        child: numbered
            ? _numberCircle(theme, index + 1)
            : timeline
            ? _ring(theme)
            : _dot(theme),
      );
    }
    final markerBox = mark == null
        ? null
        : SizedBox(
            height: fontSize * 1.55,
            child: Align(
              alignment: (custom == null ? numbered : textMarker)
                  ? Alignment.centerLeft
                  : Alignment.center,
              child: mark,
            ),
          );

    final connects = timeline && !last && (!none || wide);
    final row = Padding(
      padding: EdgeInsets.only(
        bottom: timeline ? (last ? 0.0 : 18.0) : (rich ? 4.0 : 0.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasColumn) ...[
            SizedBox(width: columnWidth, child: markerBox),
            SizedBox(width: gap),
          ],
          Expanded(child: body),
        ],
      ),
    );
    rows.add(
      Stack(
        children: [
          if (connects)
            Positioned(
              left: wide ? 83 : 11.5,
              top: 1.7 * fontSize,
              bottom: 0.15 * fontSize,
              width: 1,
              child: ColoredBox(color: theme.borderStrong),
            ),
          row,
          if (timeline && wide && textMarker)
            Positioned(left: 80, top: 0.55 * fontSize, child: _ring(theme)),
        ],
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (k, row) in rows.indexed) ...[
        if (k > 0 && !timeline) const SizedBox(height: 10),
        row,
      ],
    ],
  );
}

Widget buildListItem(BuildContext context, OpenUiNode node) {
  final props = node.props;
  final theme = node.theme;
  final inRich =
      context.dependOnInheritedWidgetOfExactType<_ListRowScope>()?.rich ??
      false;
  final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 14;
  final description = props.string('description') ?? '';
  final children = node.children();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _richText(
        context,
        props.string('title') ?? '',
        TextStyle(fontWeight: inRich ? FontWeight.w500 : null),
      ),
      if (description.isNotEmpty) ...[
        const SizedBox(height: 2),
        _richText(
          context,
          description,
          _textStyle(
            theme,
            color: theme.muted,
            size: fontSize * 0.93,
            height: 1.55,
          ),
        ),
      ],
      if (children.isNotEmpty) ...[const SizedBox(height: 8), ...children],
    ],
  );
}

/// Tells a ListItem inside a List whether its row is rich (has a description
/// or children), which is when its title is medium weight.
final class _ListRowScope extends InheritedWidget {
  const _ListRowScope({required this.rich, required super.child});

  final bool rich;

  @override
  bool updateShouldNotify(_ListRowScope old) => rich != old.rich;
}
