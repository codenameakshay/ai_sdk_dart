import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/services.dart'
    show PointerEnterEventListener, PointerExitEventListener;

import '../services.dart';
import '../theme.dart';
import '../view.dart';
import 'table.dart';

// A port of the reference's small Markdown renderer. It never interprets HTML.
// Inline: **bold**, *italic*, ~~strike~~, `code`, [text](https://...).
// Blocks: paragraphs, # headings, - and 1. lists, > quotes, ``` code, ---, | tables |.

final _inline = RegExp(
  r'(`[^`\n]+`)|(\*\*[^*\n]+?\*\*|__[^_\n]+?__)|(~~[^~\n]+?~~)|(\*[^*\s][^*\n]*?\*|_[^_\s][^_\n]*?_)|(\[[^\]\n]+\]\([^)\s]+\))',
);

/// The link recognizers and the hovered link of one [InlineText].
final class InlineLinks {
  InlineLinks._(this._changed);
  final VoidCallback _changed;
  final _recognizers = <_LinkRecognizer>[];
  var _used = 0;
  int? _hovered;

  TapGestureRecognizer _next(VoidCallback onTap) {
    if (_used == _recognizers.length) _recognizers.add(_LinkRecognizer());
    return _recognizers[_used++]..onTap = onTap;
  }

  void _hover(int? link) {
    if (_hovered == link) return;
    _hovered = link;
    _changed();
  }
}

final class _LinkRecognizer extends TapGestureRecognizer {
  bool _disposed = false;

  /// For tests: the recognizer was released with its text.
  bool get isDisposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A paragraph of inline Markdown that owns its links' tap recognizers;
/// [spans] passes the [InlineLinks] it is given on to [inlineSpans].
class InlineText extends StatefulWidget {
  const InlineText(
    this.spans, {
    super.key,
    this.textAlign,
    this.style,
    this.maxLines,
    this.overflow,
  });
  final List<InlineSpan> Function(BuildContext context, InlineLinks links)
  spans;
  final TextAlign? textAlign;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<InlineText> createState() => _InlineTextState();
}

class _InlineTextState extends State<InlineText> {
  late final InlineLinks _links = InlineLinks._(() {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    for (final r in _links._recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _links._used = 0;
    final spans = widget.spans(context, _links);
    while (_links._recognizers.length > _links._used) {
      _links._recognizers.removeLast().dispose();
    }
    return Text.rich(
      TextSpan(children: spans),
      textAlign: widget.textAlign,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

final class _Link {
  const _Link(this.open, this.recognizer, this.onEnter, this.onExit);
  final VoidCallback open;
  final TapGestureRecognizer recognizer;
  final PointerEnterEventListener onEnter;
  final PointerExitEventListener onExit;
}

/// Inline Markdown as spans. Links open through [OpenUiServices.openUrl];
/// a link that is not http(s) renders as its label. [links] comes from an
/// [InlineText], which disposes the link recognizers.
List<InlineSpan> inlineSpans(
  String text,
  BuildContext context, {
  required InlineLinks links,
  TextStyle? style,
}) {
  final theme = OpenUiTheme.of(context);
  final services = OpenUiScope.servicesOf(context);
  final base = style ?? DefaultTextStyle.of(context).style;
  var linkCount = 0;

  List<InlineSpan> walk(String source, TextStyle current, _Link? link) {
    final out = <InlineSpan>[];
    void plain(String s) => out.add(
      link == null
          ? TextSpan(text: s, style: current)
          : TextSpan(
              text: s,
              style: current,
              recognizer: link.recognizer,
              mouseCursor: SystemMouseCursors.click,
              onEnter: link.onEnter,
              onExit: link.onExit,
            ),
    );
    var rest = source;
    while (rest.isNotEmpty) {
      final m = _inline.firstMatch(rest);
      if (m == null) {
        plain(rest);
        break;
      }
      if (m.start > 0) plain(rest.substring(0, m.start));
      final token = m[0]!;
      if (m[1] != null) {
        out.add(
          _code(token.substring(1, token.length - 1), current, theme, link),
        );
      } else if (m[2] != null) {
        out.addAll(
          walk(
            token.substring(2, token.length - 2),
            current.copyWith(fontWeight: OpenUiTheme.weightSemibold),
            link,
          ),
        );
      } else if (m[3] != null) {
        out.addAll(
          walk(
            token.substring(2, token.length - 2),
            current.copyWith(decoration: TextDecoration.lineThrough),
            link,
          ),
        );
      } else if (m[4] != null) {
        out.addAll(
          walk(
            token.substring(1, token.length - 1),
            current.copyWith(fontStyle: FontStyle.italic),
            link,
          ),
        );
      } else {
        final close = token.indexOf('](');
        final label = token.substring(1, close);
        final href = webUri(token.substring(close + 2, token.length - 1));
        if (href == null) {
          out.addAll(walk(label, current, link));
        } else {
          final index = linkCount++;
          void open() => services.openUrl(href);
          final hovered = links._hovered == index;
          out.addAll(
            walk(
              label,
              current.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: hovered
                    ? current.color ?? theme.ink
                    : theme.borderStrong,
              ),
              _Link(
                open,
                links._next(open),
                (_) => links._hover(index),
                (_) => links._hover(null),
              ),
            ),
          );
        }
      }
      rest = rest.substring(m.end);
    }
    return out;
  }

  return walk(text, base, null);
}

/// `.iui-code`: 1px 5px padding, 5px radius, surface fill, mono at 0.88em.
/// The box sits on the text baseline; its height is the font's own, as a
/// CSS inline background ignores line-height.
InlineSpan _code(
  String text,
  TextStyle current,
  OpenUiTheme theme,
  _Link? link,
) {
  Widget box = DecoratedBox(
    decoration: BoxDecoration(
      color: theme.surface,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Text(
        text,
        style: TextStyle(
          inherit: false,
          color: current.color,
          fontWeight: current.fontWeight,
          fontStyle: current.fontStyle,
          decoration: current.decoration,
          decorationColor: current.decorationColor,
          fontFamily: theme.monoFontFamily,
          fontSize: (current.fontSize ?? 14) * 0.88,
        ),
      ),
    ),
  );
  if (link != null) {
    box = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: link.onEnter,
      onExit: link.onExit,
      child: GestureDetector(onTap: link.open, child: box),
    );
  }
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: box,
  );
}

sealed class _Block {
  const _Block();
}

final class _Paragraph extends _Block {
  const _Paragraph(this.text, {this.quote = false});
  final String text;
  final bool quote;
}

final class _Heading extends _Block {
  const _Heading(this.level, this.text);
  final int level;
  final String text;
}

final class _ListBlock extends _Block {
  const _ListBlock(this.ordered, this.start, this.items);
  final bool ordered;
  final int start;
  final List<String> items;
}

final class _CodeBlock extends _Block {
  const _CodeBlock(this.text);
  final String text;
}

final class _Rule extends _Block {
  const _Rule();
}

final class _TableBlock extends _Block {
  const _TableBlock(this.head, this.rows);
  final List<String> head;
  final List<List<String>> rows;
}

final _listItem = RegExp(r'^\s{0,3}([-*+]|(\d+)[.)])\s+(.*)$');
final _fence = RegExp(r'^\s*```');
final _heading = RegExp(r'^(#{1,4})\s+(.*)$');
final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
final _tableRule = RegExp(r'^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$');
final _quote = RegExp(r'^\s*>');
final _paragraphStop = RegExp(r'^(#{1,4})\s|^\s*```|^\s*>');

/// `.iui-markdown ul, ol { padding-left: 1.4em }` at 16px.
const _listIndent = 22.4;

// The disc is Chrome's outside disc for Inter at 16px (list_marker.cc: a
// (ascent·2/3+1)/2 = 5px dot, 18px left of the item, 9px under the text top),
// on a 26.4px line with 3.2px half-leading.

List<String> _cells(String line) => line
    .trim()
    .replaceAll(RegExp(r'^\||\|$'), '')
    .split('|')
    .map((c) => c.trim())
    .toList();

/// Chrome's largest list ordinal (a 32-bit int).
const _maxOrdinal = 0x7FFFFFFF;

/// `<ol start={Number(n)}>` as Chrome reads it: a start past 2147483647 is
/// not a valid integer, so the list counts from 1.
int _start(String digits) {
  final n = int.tryParse(digits);
  return n != null && n <= _maxOrdinal ? n : 1;
}

List<_Block> _blocks(String source) {
  final lines = source.replaceAll(RegExp(r'\r\n?'), '\n').split('\n');
  final out = <_Block>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      i++;
      continue;
    }
    if (_fence.hasMatch(line)) {
      final body = <String>[];
      for (i++; i < lines.length && !_fence.hasMatch(lines[i]); i++) {
        body.add(lines[i]);
      }
      out.add(_CodeBlock(body.join('\n')));
      i++;
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      out.add(_Heading(heading[1]!.length, heading[2]!));
      i++;
      continue;
    }
    if (_rule.hasMatch(line)) {
      out.add(const _Rule());
      i++;
      continue;
    }
    if (line.contains('|') &&
        i + 1 < lines.length &&
        _tableRule.hasMatch(lines[i + 1])) {
      final head = _cells(line);
      final rows = <List<String>>[];
      for (
        i += 2;
        i < lines.length &&
            lines[i].contains('|') &&
            lines[i].trim().isNotEmpty;
        i++
      ) {
        rows.add(_cells(lines[i]));
      }
      out.add(_TableBlock(head, rows));
      continue;
    }
    if (_quote.hasMatch(line)) {
      final body = <String>[];
      for (; i < lines.length && _quote.hasMatch(lines[i]); i++) {
        body.add(lines[i].replaceFirst(RegExp(r'^\s*>\s?'), ''));
      }
      out.add(_Paragraph(body.join(' '), quote: true));
      continue;
    }
    final item = _listItem.firstMatch(line);
    if (item != null) {
      final ordered = item[2] != null;
      final items = <String>[];
      for (; i < lines.length; i++) {
        final next = _listItem.firstMatch(lines[i]);
        if (next != null && (next[2] != null) == ordered) {
          items.add(next[3]!);
        } else if (lines[i].trim().isNotEmpty &&
            RegExp(r'^\s{2,}').hasMatch(lines[i]) &&
            items.isNotEmpty) {
          items[items.length - 1] += ' ${lines[i].trim()}';
        } else {
          break;
        }
      }
      out.add(_ListBlock(ordered, ordered ? _start(item[2]!) : 1, items));
      continue;
    }
    final body = <String>[];
    for (
      ;
      i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !_listItem.hasMatch(lines[i]) &&
          !_paragraphStop.hasMatch(lines[i]);
      i++
    ) {
      body.add(lines[i].trim());
    }
    out.add(_Paragraph(body.join(' ')));
  }
  return out;
}

/// The space between two blocks: the rule's 20px margin below it plus the
/// next block's margin above (flex items, so margins add).
double _gap(_Block previous, _Block block) {
  final below = previous is _Rule ? 20.0 : 0.0;
  final above = switch (block) {
    _ when previous is _Heading => 8.0,
    _Heading() => 26.0,
    _Rule() => 20.0,
    _ListBlock() when previous is _Paragraph && !previous.quote => 6.0,
    _ => 12.0,
  };
  return below + above;
}

/// Markdown prose as a column of blocks, spaced and styled as the reference's `.iui-markdown`.
class MarkdownBlocks extends StatelessWidget {
  const MarkdownBlocks(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final base = DefaultTextStyle.of(context).style.copyWith(
      fontSize: 16,
      height: 1.65,
      color: theme.ink,
      fontFamily: theme.fontFamily,
    );
    final blocks = _blocks(text);
    final children = <Widget>[];
    for (final (index, block) in blocks.indexed) {
      if (index == 0 && block is _Rule) {
        children.add(const SizedBox(height: 20));
      }
      if (index > 0) {
        children.add(SizedBox(height: _gap(blocks[index - 1], block)));
      }
      children.add(_block(context, block, base, theme));
    }
    if (blocks.isNotEmpty && blocks.last is _Rule) {
      children.add(const SizedBox(height: 20));
    }
    return DefaultTextStyle(
      style: base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _block(
    BuildContext context,
    _Block block,
    TextStyle base,
    OpenUiTheme theme,
  ) {
    Widget rich(String s, [TextStyle? style]) => InlineText(
      (context, links) =>
          inlineSpans(s, context, style: style ?? base, links: links),
    );
    switch (block) {
      case _Paragraph(:final text, quote: false):
        return rich(text);
      case _Paragraph(:final text, quote: true):
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.surface,
            border: Border(
              left: BorderSide(color: theme.borderStrong, width: 3),
            ),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(12),
            ),
          ),
          child: rich(text),
        );
      case _Heading(:final level, :final text):
        final style = base.copyWith(
          fontWeight: OpenUiTheme.weightSemibold,
          fontSize: switch (level) {
            1 => 22,
            2 => 19,
            _ => 16,
          },
          letterSpacing: switch (level) {
            1 => -0.5,
            2 => -0.3,
            _ => 0,
          },
          height: switch (level) {
            1 => 1.3,
            2 => 1.35,
            _ => 1.4,
          },
        );
        return Semantics(
          header: true,
          headingLevel: level + 1,
          child: rich(text, style),
        );
      case _CodeBlock(:final text):
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(OpenUiTheme.radiusMd),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              text,
              style: base.copyWith(
                fontFamily: theme.monoFontFamily,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
        );
      case _Rule():
        return Divider(height: 1, thickness: 1, color: theme.border);
      case _ListBlock(:final ordered, :final start, :final items):
        final marker = base.copyWith(
          color: theme.muted,
          fontWeight: ordered ? OpenUiTheme.weightMedium : null,
          fontFeatures: ordered ? const [FontFeature.tabularFigures()] : null,
        );
        // An outside marker ends at the item's edge, its trailing space included.
        final painter = TextPainter(
          text: TextSpan(text: ' ', style: marker),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final space = math.min(painter.width, _listIndent);
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 6,
          children: [
            for (final (j, item) in items.indexed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _listIndent,
                    child: ordered
                        ? Padding(
                            padding: EdgeInsets.only(right: space),
                            child: OverflowBox(
                              maxWidth: double.infinity,
                              alignment: Alignment.topRight,
                              fit: OverflowBoxFit.deferToChild,
                              child: Text(
                                '${math.min(start + j, _maxOrdinal)}.',
                                style: marker,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          )
                        : Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 5.4,
                                top: 12.2,
                              ),
                              child: SizedBox.square(
                                dimension: 5,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: theme.muted,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(child: rich(item)),
                ],
              ),
          ],
        );
      case _TableBlock(:final head, :final rows):
        return markdownTable(context, head, rows, rich);
    }
  }
}

/// A Markdown table, styled like the `Table` component.
Widget markdownTable(
  BuildContext context,
  List<String> head,
  List<List<String>> rows,
  Widget Function(String text, [TextStyle? style]) cell,
) {
  final theme = OpenUiTheme.of(context);
  return IuiTable(
    head: [for (final h in head) cell(h, iuiTableHeadStyle(theme))],
    rows: [
      for (final r in rows)
        [for (final c in r) IuiCell(cell(c, iuiTableBodyStyle(theme)))],
    ],
  );
}

/// `Markdown(text)`.
Widget buildMarkdown(BuildContext context, OpenUiNode node) =>
    MarkdownBlocks(node.props.string('text') ?? '');
