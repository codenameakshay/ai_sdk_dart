import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;

import '../theme.dart';
import '../view.dart';
import 'block_slot.dart';
import 'controls.dart' show Press;
import 'glyph.dart';
import 'markdown.dart';

final _stepMarker = RegExp(r'^[0-9A-Za-z]{1,2}$');

const _headingLevels = <String, int>{
  '3xl': 1,
  '2xl': 2,
  'xl': 2,
  'lg': 2,
  'md': 3,
  'sm': 4,
};

FontWeight? _weightNamed(OpenUiTypography typography, String? name) =>
    switch (name) {
      'normal' => typography.normal,
      'medium' => typography.medium,
      'semibold' => typography.semibold,
      _ => null,
    };

({double fontSize, double height, double letterSpacing}) _titleMetrics(
  OpenUiTheme theme,
  String? size, {
  required bool compact,
}) {
  final title = theme.typography.title[size] ?? theme.typography.title['md']!;
  return (
    fontSize: theme.typography.size(
      compact ? title.compactFontSize : title.fontSize,
    ),
    height: title.height,
    letterSpacing: title.letterSpacing,
  );
}

TextStyle _textStyle(
  OpenUiTheme theme, {
  Color? color,
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
  OpenUiNode node,
  Object? value,
  TextStyle style,
  InlineLinks links,
  List<String> ids,
) {
  if (value is String) {
    return inlineSpans(
      _preLine(value, dropSpace: true),
      context,
      style: style,
      links: links,
    );
  }
  if (value is! List) return const [];
  final spans = <InlineSpan>[];
  var dropSpace = true;
  var k = 0;
  for (final (index, part)
      in value.expand((p) => p is List ? p : [p]).indexed) {
    if (part is OpenUiElement) {
      // Ids are kept per text: the spans callback reruns on hover, and a
      // second childId call would rename the element to '~2'.
      if (k == ids.length) {
        ids.add(node.childId(part, index, slot: 'parts'));
      }
      final id = ids[k++];
      dropSpace = false;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: OpenUiElementView(
              key: ValueKey('openui:$id'),
              element: part,
              id: id,
            ),
          ),
        ),
      );
    } else if (part != null) {
      final text = _preLine(jsString(part), dropSpace: dropSpace);
      if (text.isNotEmpty) {
        dropSpace = text.endsWith('\n') || text.endsWith(' ');
      }
      spans.addAll(inlineSpans(text, context, style: style, links: links));
    }
  }
  return spans;
}

/// CSS `white-space: pre-line`: runs of spaces collapse to one, newlines stay,
/// and spaces at the start or end of a line disappear.
String _preLine(String text, {required bool dropSpace}) {
  final collapsed = text
      .replaceAll(RegExp(r'[ \t\f\r]+'), ' ')
      .replaceAll(RegExp(r' ?\n ?'), '\n');
  return dropSpace ? collapsed.replaceFirst(RegExp('^ '), '') : collapsed;
}

Widget _richText(
  BuildContext context,
  OpenUiNode node,
  Object? value,
  TextStyle style, {
  int? maxLines,
}) {
  final ids = <String>[];
  return InlineText(
    (context, links) => _textSpans(context, node, value, style, links, ids),
    style: style,
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
  );
}

int? _lineLimit(Props props) {
  final lines = props.number('maxLines')?.round();
  return lines != null && lines > 0 ? lines : null;
}

/// The direct child of a card, or the first item of its head row.
bool _isCardTitle(BuildContext context, BlockSlot? slot) =>
    (slot?.parent == SlotParent.card && slot?.index == 0) ||
    CardHeadScope.of(context);

/// Directly in a card, or in a flow column inside a grid or carousel item.
bool _isCardSized(BlockSlot? slot) =>
    slot?.parent == SlotParent.card || slot?.parent == SlotParent.cardSizedFlow;

/// A Text or Caption right under a card's title, which makes it a subtitle.
bool _isSubtitle(BuildContext context, BlockSlot? slot) {
  final previous = slot?.previous;
  if (previous == null || previous.typeName != 'Title') return false;
  final size = previous.props.string('size');
  if (size != null && size != 'sm' && size != 'md') return false;
  return (slot?.parent == SlotParent.card && slot?.index == 1) ||
      CardHeadScope.of(context);
}

Widget _subtitleGap(Widget text, bool subtitle, BlockSlot? slot) =>
    subtitle && slot?.flow == false
    ? Padding(padding: const EdgeInsets.only(top: 2), child: text)
    : text;

Widget buildTitle(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final name = node.props.string('size');
  final slot = BlockSlot.of(context, node.element);
  final base = _titleMetrics(
    theme,
    name,
    compact: MediaQuery.sizeOf(context).width <= 640,
  );
  final cardTitle =
      (name == null || name == 'sm' || name == 'md') &&
      _isCardTitle(context, slot);
  final cardSized =
      (name == 'lg' || name == 'xl' || name == '2xl' || name == '3xl') &&
      _isCardSized(slot);
  final (fontSize, height, letterSpacing, weight) = cardTitle
      ? (
          theme.fontSizeOf('Title.card', 14),
          20 / 14,
          base.letterSpacing,
          theme.typography.medium,
        )
      : cardSized
      ? (
          theme.fontSizeOf('Title.cardLarge', 18),
          24 / 18,
          -0.3,
          theme.typography.semibold,
        )
      : (
          base.fontSize,
          base.height,
          base.letterSpacing,
          theme.typography.semibold,
        );
  final style = _textStyle(
    theme,
    color: theme.fg(node.props['color']) ?? theme.ink,
    size: fontSize,
    height: height,
    letterSpacing: letterSpacing,
    weight: weight,
    fontFeatures: theme.typography.tabular,
  );
  return Semantics(
    header: true,
    headingLevel: _headingLevels[name ?? 'md'] ?? 3,
    child: _richText(context, node, node.props.string('text') ?? '', style),
  );
}

Widget buildText(BuildContext context, OpenUiNode node) {
  final props = node.props;
  final theme = node.theme;
  final slot = BlockSlot.of(context, node.element);
  final sizeName = props.string('size');
  final size = theme.typography.text[sizeName];
  final cardSized =
      _isCardSized(slot) &&
      sizeName != 'xs' &&
      sizeName != 'sm' &&
      sizeName != 'lg';
  final subtitle = _isSubtitle(context, slot);
  final metrics = cardSized
      ? (fontSize: theme.fontSizeOf('Text.card', 15), height: 22 / 15)
      : subtitle
      ? (fontSize: theme.fontSizeOf('Text.subtitle', 13), height: 18 / 13)
      : (
          fontSize: size == null ? null : theme.typography.size(size.fontSize),
          height: size?.height ?? 1.6,
        );
  final struck = props.boolean('lineThrough') == true;
  final style = _textStyle(
    theme,
    color:
        theme.fg(props['color']) ??
        (subtitle || (struck && PressableScope.of(context))
            ? theme.muted
            : null),
    size: metrics.fontSize,
    height: metrics.height,
    weight: _weightNamed(theme.typography, props.string('weight')),
    fontStyle: props.boolean('italic') == true ? FontStyle.italic : null,
    decoration: struck ? TextDecoration.lineThrough : null,
    fontFeatures: props.boolean('tabularNums') == true
        ? theme.typography.tabular
        : theme.typography.allText,
  );
  return _subtitleGap(
    _richText(context, node, props['text'], style, maxLines: _lineLimit(props)),
    subtitle,
    slot,
  );
}

Widget buildCaption(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final slot = BlockSlot.of(context, node.element);
  final subtitle = _isSubtitle(context, slot);
  return _subtitleGap(
    _richText(
      context,
      node,
      node.props.string('text') ?? '',
      _textStyle(
        theme,
        color: theme.fg(node.props['color']) ?? theme.muted,
        size: subtitle
            ? theme.fontSizeOf('Caption.subtitle', 13)
            : theme.fontSizeOf('Caption', 12),
        height: subtitle ? 18 / 13 : 1.6,
      ),
    ),
    subtitle,
    slot,
  );
}

Widget buildLabel(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  return Text(
    node.props.string('text') ?? '',
    style: _textStyle(
      theme,
      color: theme.ink,
      size: theme.fontSizeOf('Label', 14),
      height: 1.4,
      weight: theme.typography.medium,
    ),
  );
}

Widget buildBadge(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final tone = node.props.string('color');
  final (background, foreground) = tone == 'info'
      ? (theme.statusSoft['info'], theme.status['info'])
      : (theme.badgeSoft[tone], theme.badge[tone]);
  final s = theme.styleOf('Badge', tone);
  final color = s.foreground ?? foreground ?? theme.ink;
  final icon = node.props.string('icon');
  return Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding:
          s.padding ??
          EdgeInsetsDirectional.fromSTEB(
            Glyph.has(context, icon) ? 8 : 10,
            3,
            10,
            3,
          ),
      decoration: BoxDecoration(
        color: s.background ?? background ?? theme.badgeNeutralSoft,
        borderRadius: BorderRadius.circular(s.radius ?? theme.radii.full),
        border: s.border == null ? null : Border.all(color: s.border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Glyph.has(context, icon)) ...[
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
                size: theme.fontSizeOf('Badge', 13),
                height: 18 / 13,
                weight: theme.typography.medium,
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
  final base = DefaultTextStyle.of(context).style;
  final resting = node.theme.borderStrong;
  return Semantics(
    link: true,
    child: Press(
      radius: 0,
      onTap: (_) => node.services.openUrl(uri),
      builder: (hovered, pressed) => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text.isEmpty ? uri.host : text),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 2),
                child: Glyph(
                  'arrow-up-right',
                  size: (base.fontSize ?? 14) * 0.85,
                  color: base.color,
                  strokeWidth: 2,
                ),
              ),
            ),
          ],
        ),
        style: base.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: hovered ? base.color : resting,
        ),
      ),
    ),
  );
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
      size: theme.fontSizeOf('List.number', 13),
      height: 1,
      fontFeatures: theme.typography.tabular,
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
          size: theme.fontSizeOf('List.step', 12),
          height: 1,
          weight: theme.typography.medium,
          fontFeatures: theme.typography.tabular,
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
      size: theme.fontSizeOf('List.marker', 13),
      fontFeatures: theme.typography.tabular,
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
  final compact = MediaQuery.sizeOf(context).width <= 640;
  final (columnWidth, gap) = wide
      ? (compact ? 64.0 : 76.0, compact ? 20.0 : (timeline ? 24.0 : 16.0))
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
    final id = item is OpenUiElement
        ? node.childId(item, k, slot: 'items')
        : '';
    final body = item is OpenUiElement
        ? _ListRowScope(
            rich: rich,
            child: OpenUiElementView(
              key: ValueKey('openui:$id'),
              element: item,
              id: id,
            ),
          )
        : _richText(context, node, jsString(item), const TextStyle());

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
        : numbered && !textMarker
        ? SizedBox.square(
            dimension: 24,
            child: custom == null
                ? mark
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.ink,
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: mark),
                  ),
          )
        : SizedBox(
            height: fontSize * 1.55,
            child: Align(
              alignment: textMarker
                  ? AlignmentDirectional.centerStart
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
      Semantics(
        key: item is OpenUiElement ? ValueKey(('list-item', id)) : null,
        container: true,
        role: SemanticsRole.listItem,
        child: Stack(
          children: [
            if (connects)
              PositionedDirectional(
                start: wide ? (compact ? 73 : 83) : 11.5,
                top: 1.7 * fontSize,
                bottom: 0.15 * fontSize,
                width: 1,
                child: ColoredBox(color: theme.borderStrong),
              ),
            row,
            if (timeline && wide && textMarker)
              PositionedDirectional(
                start: compact ? 70 : 80,
                top: 0.55 * fontSize,
                child: _ring(theme),
              ),
          ],
        ),
      ),
    );
  }

  return Semantics(
    container: true,
    role: SemanticsRole.list,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (k, row) in rows.indexed) ...[
          if (k > 0 && !timeline) const SizedBox(height: 10),
          row,
        ],
      ],
    ),
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
        node,
        props.string('title') ?? '',
        TextStyle(fontWeight: inRich ? theme.typography.medium : null),
      ),
      if (description.isNotEmpty) ...[
        const SizedBox(height: 2),
        _richText(
          context,
          node,
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
