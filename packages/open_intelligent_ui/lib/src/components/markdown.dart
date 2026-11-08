import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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

/// Inline Markdown as spans. Links open through [OpenUiServices.openUrl];
/// a link that is not http(s) renders as its label.
List<InlineSpan> inlineSpans(
  String text,
  BuildContext context, {
  TextStyle? style,
}) {
  final theme = OpenUiTheme.of(context);
  final services = OpenUiScope.servicesOf(context);
  final base = style ?? DefaultTextStyle.of(context).style;

  List<InlineSpan> walk(String source, TextStyle current) {
    final out = <InlineSpan>[];
    var rest = source;
    while (rest.isNotEmpty) {
      final m = _inline.firstMatch(rest);
      if (m == null) {
        out.add(TextSpan(text: rest, style: current));
        break;
      }
      if (m.start > 0) {
        out.add(TextSpan(text: rest.substring(0, m.start), style: current));
      }
      final token = m[0]!;
      if (m[1] != null) {
        out.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: current.copyWith(
              fontFamily: theme.monoFontFamily,
              fontSize: (current.fontSize ?? 14) * 0.88,
              backgroundColor: theme.surface,
            ),
          ),
        );
      } else if (m[2] != null) {
        out.addAll(
          walk(
            token.substring(2, token.length - 2),
            current.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      } else if (m[3] != null) {
        out.addAll(
          walk(
            token.substring(2, token.length - 2),
            current.copyWith(decoration: TextDecoration.lineThrough),
          ),
        );
      } else if (m[4] != null) {
        out.addAll(
          walk(
            token.substring(1, token.length - 1),
            current.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else {
        final close = token.indexOf('](');
        final label = token.substring(1, close);
        final href = webUri(token.substring(close + 2, token.length - 1));
        if (href == null) {
          out.addAll(walk(label, current));
        } else {
          final linkStyle = current.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: theme.borderStrong,
          );
          // ponytail: recognizers are not disposed; they hold no platform resources
          final tap = TapGestureRecognizer()
            ..onTap = () => services.openUrl(href);
          // Leaves carry the recognizer: a tap resolves to the leaf span only.
          out.addAll([
            for (final s in walk(label, linkStyle).cast<TextSpan>())
              TextSpan(
                text: s.text,
                style: s.style,
                recognizer: tap,
                mouseCursor: SystemMouseCursors.click,
              ),
          ]);
        }
      }
      rest = rest.substring(m.end);
    }
    return out;
  }

  return walk(text, base);
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

List<String> _cells(String line) => line
    .trim()
    .replaceAll(RegExp(r'^\||\|$'), '')
    .split('|')
    .map((c) => c.trim())
    .toList();

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
      out.add(_ListBlock(ordered, ordered ? int.parse(item[2]!) : 1, items));
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

/// Markdown prose as a column of blocks, styled as the reference's
/// `.iui-markdown` (16/1.65, 12px between blocks, more air above headings).
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
      if (index > 0) {
        final previous = blocks[index - 1];
        final gap = switch (block) {
          _Heading() => 26.0,
          _ListBlock() when previous is _Paragraph && !previous.quote => 6.0,
          _ when previous is _Heading => 8.0,
          _Rule() => 20.0,
          _ when previous is _Rule => 20.0,
          _ => 12.0,
        };
        children.add(SizedBox(height: gap));
      }
      children.add(_block(context, block, base, theme));
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
    Widget rich(String s, [TextStyle? style]) => Text.rich(
      TextSpan(children: inlineSpans(s, context, style: style ?? base)),
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
          fontWeight: FontWeight.w600,
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (j, item) in items.indexed) ...[
              if (j > 0) const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      ordered ? '${start + j}.' : '•',
                      style: base.copyWith(
                        color: theme.muted,
                        fontWeight: ordered ? FontWeight.w500 : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(child: rich(item)),
                ],
              ),
            ],
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
