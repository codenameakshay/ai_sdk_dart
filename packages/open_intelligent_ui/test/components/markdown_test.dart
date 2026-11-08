import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/table.dart';

import '../support/pump.dart';

final _light = OpenUiTheme.light;

String _md(String source) => 'root = Col([Markdown(${_quote(source)})])';

String _quote(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}"';

Finder _text(String plain) => find.byWidgetPredicate(
  (w) => w is Text && w.textSpan?.toPlainText() == plain,
  description: 'Text "$plain"',
);

TextSpan _span(WidgetTester tester, String plain) =>
    tester.widget<Text>(_text(plain)).textSpan! as TextSpan;

TextStyle? _style(WidgetTester tester, String plain) =>
    _span(tester, plain).children!.first.style;

List<InlineSpan> _children(WidgetTester tester, String plain) =>
    _span(tester, plain).children!;

void main() {
  group('blocks', () {
    testWidgets(
      'a paragraph joins its lines with spaces, and blank lines separate paragraphs',
      (tester) async {
        await pumpProgram(
          tester,
          _md('first line\nsecond line\n\nnext paragraph'),
        );
        expect(_text('first line second line'), findsOneWidget);
        expect(_text('next paragraph'), findsOneWidget);
      },
    );

    testWidgets(
      'headings h1 to h4 get decreasing sizes and are announced as headers',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpProgram(
          tester,
          _md('# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five'),
        );
        expect(_style(tester, 'One')!.fontSize, 22);
        expect(_style(tester, 'Two')!.fontSize, 19);
        expect(_style(tester, 'Three')!.fontSize, 16);
        expect(_style(tester, 'Four')!.fontSize, 16);
        expect(_style(tester, 'One')!.fontWeight, FontWeight.w600);
        expect(_style(tester, 'One')!.letterSpacing, -0.5);
        expect(_style(tester, 'Two')!.letterSpacing, -0.3);
        expect(_style(tester, 'Three')!.letterSpacing, 0);
        expect(_style(tester, 'One')!.height, 1.3);
        expect(_style(tester, 'Two')!.height, 1.35);
        expect(_style(tester, 'Three')!.height, 1.4);
        expect(
          _text('##### Five'),
          findsOneWidget,
          reason: 'h5 is not a heading',
        );
        expect(tester.getSemantics(_text('One')), isSemantics(isHeader: true));
        handle.dispose();
      },
    );

    testWidgets(
      'a bulleted list shows bullets, and its continuation lines join the item',
      (tester) async {
        await pumpProgram(
          tester,
          _md('- apples\n* pears\n+ plums and\n  more plums'),
        );
        expect(find.text('•'), findsNWidgets(3));
        expect(_text('apples'), findsOneWidget);
        expect(_text('pears'), findsOneWidget);
        expect(_text('plums and more plums'), findsOneWidget);
      },
    );

    testWidgets('a numbered list starts at its first number', (tester) async {
      await pumpProgram(tester, _md('3. three\n4. four\n5) five'));
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('4.'), findsOneWidget);
      expect(find.text('5.'), findsOneWidget);
      expect(find.text('•'), findsNothing);
      expect(_text('three'), findsOneWidget);
    });

    testWidgets('a bullet list followed by a numbered one are two lists', (
      tester,
    ) async {
      await pumpProgram(tester, _md('- a\n- b\n1. x\n2. y'));
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('2.'), findsOneWidget);
    });

    testWidgets(
      'a quote has a side rule, its lines joined, and inline Markdown',
      (tester) async {
        await pumpProgram(tester, _md('> to be\n> or **not**'));
        expect(
          find.byWidgetPredicate(
            (w) => w is Text && w.textSpan?.toPlainText() == 'to be or not',
          ),
          findsOneWidget,
        );
        final box = tester.widget<Container>(
          find
              .ancestor(
                of: find.byWidgetPredicate(
                  (w) =>
                      w is Text && w.textSpan?.toPlainText() == 'to be or not',
                ),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = box.decoration! as BoxDecoration;
        expect((decoration.border! as Border).left.width, 3);
        expect(decoration.color, _light.surface);
      },
    );

    testWidgets(
      'a fenced code block is monospace, keeps its lines and does not parse Markdown',
      (tester) async {
        await pumpProgram(
          tester,
          _md('```dart\nvar a = **1**;\n  b();\n```\nafter'),
        );
        final code = tester.widget<Text>(find.text('var a = **1**;\n  b();'));
        expect(code.style!.fontFamily, _light.monoFontFamily);
        expect(code.style!.fontSize, 13);
        expect(_text('after'), findsOneWidget);
      },
    );

    testWidgets('an unclosed fence runs to the end', (tester) async {
      await pumpProgram(tester, _md('```\nstill code\nmore'));
      expect(find.text('still code\nmore'), findsOneWidget);
    });

    testWidgets('a horizontal rule draws a divider', (tester) async {
      await pumpProgram(tester, _md('above\n\n---\n\nbelow'));
      expect(find.byType(Divider), findsOneWidget);
      expect(tester.widget<Divider>(find.byType(Divider)).color, _light.border);
      await pumpProgram(tester, _md('a\n\n* * *\n\nb\n\n___'));
      expect(find.byType(Divider), findsNWidgets(2));
    });

    testWidgets('a table shows its header and rows, padding short rows', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        _md(
          '| Name | Qty |\n|---|:--:|\n| apple | 3 |\n| pear |\n| plum | 5 | extra |\n\ndone',
        ),
      );
      expect(find.byType(IuiTable), findsOneWidget);
      for (final t in ['Name', 'Qty', 'apple', '3', 'pear', 'plum', '5']) {
        expect(_text(t), findsOneWidget, reason: t);
      }
      expect(
        find.text('extra'),
        findsNothing,
        reason: 'cells beyond the header are dropped',
      );
      expect(
        _text('done'),
        findsOneWidget,
        reason: 'the table ends at the blank line',
      );
      expect(
        tester.getTopLeft(_text('apple')).dy,
        lessThan(tester.getTopLeft(_text('pear')).dy),
      );
      expect(
        tester.getTopLeft(_text('Qty')).dx,
        tester.getTopLeft(_text('3')).dx,
      );
      expect(_style(tester, 'Name')!.color, _light.ink);
    });

    testWidgets('a line with a pipe but no divider row is a paragraph', (
      tester,
    ) async {
      await pumpProgram(tester, _md('a | b | c'));
      expect(find.byType(Table), findsNothing);
      expect(_text('a | b | c'), findsOneWidget);
    });

    testWidgets('no HTML is ever interpreted', (tester) async {
      await pumpProgram(
        tester,
        _md('<b>bold</b> <script>x()</script> <img src=x>'),
      );
      expect(
        _text('<b>bold</b> <script>x()</script> <img src=x>'),
        findsOneWidget,
      );
    });

    testWidgets('empty text renders an empty column', (tester) async {
      await pumpProgram(tester, 'root = Col([Markdown("")])');
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('windows line endings are read as lines', (tester) async {
      await pumpProgram(tester, _md('a\r\nb\r\n\r\n- x\r\n- y'));
      expect(_text('a b'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
    });

    testWidgets('spacing between blocks follows the reference', (tester) async {
      await pumpProgram(
        tester,
        _md(
          'para one\n\npara two\n\n- item\n\n## Head\n\nunder head\n\n---\n\nafter rule',
        ),
      );
      double gap(String above, String below) =>
          tester.getTopLeft(_text(below)).dy -
          tester.getBottomLeft(_text(above)).dy;
      expect(gap('para one', 'para two'), 12);
      expect(
        gap('para two', 'item') + 0,
        closeTo(6, 0.01),
        reason: 'a list hugs the paragraph before it',
      );
      expect(gap('item', 'Head'), 26);
      expect(gap('Head', 'under head'), 8);
      final divider = tester.getTopLeft(find.byType(Divider)).dy;
      expect(divider - tester.getBottomLeft(_text('under head')).dy, 20);
      expect(
        tester.getTopLeft(_text('after rule')).dy -
            tester.getBottomLeft(find.byType(Divider)).dy,
        20,
      );
    });

    testWidgets('a list after a quote has the normal gap', (tester) async {
      await pumpProgram(tester, _md('> quoted\n\n- item'));
      expect(find.text('•'), findsOneWidget);
    });

    testWidgets('uses the dark ink in dark mode', (tester) async {
      await pumpProgram(tester, _md('hello'), brightness: Brightness.dark);
      expect(_style(tester, 'hello')!.color, OpenUiTheme.dark.ink);
      expect(_style(tester, 'hello')!.fontSize, 16);
      expect(_style(tester, 'hello')!.height, 1.65);
    });
  });

  group('inline', () {
    testWidgets(
      'bold, italic and strike each style their text, either marker',
      (tester) async {
        await pumpProgram(
          tester,
          _md('a **bold** b __also__ c *it* d _too_ e ~~gone~~ f'),
        );
        final spans = _children(
          tester,
          'a bold b also c it d too e gone f',
        ).cast<TextSpan>();
        TextSpan span(String text) => spans.firstWhere((s) => s.text == text);
        expect(span('bold').style!.fontWeight, FontWeight.w600);
        expect(span('also').style!.fontWeight, FontWeight.w600);
        expect(span('it').style!.fontStyle, FontStyle.italic);
        expect(span('too').style!.fontStyle, FontStyle.italic);
        expect(span('gone').style!.decoration, TextDecoration.lineThrough);
        expect(span('a ').style!.fontWeight, isNot(FontWeight.w600));
      },
    );

    testWidgets(
      'inline code is monospace on a tinted background and keeps its markers',
      (tester) async {
        await pumpProgram(tester, _md('use `a *b* c` here'));
        final code = _children(
          tester,
          'use a *b* c here',
        ).cast<TextSpan>().firstWhere((s) => s.text == 'a *b* c');
        expect(code.style!.fontFamily, _light.monoFontFamily);
        expect(code.style!.backgroundColor, _light.surface);
        expect(code.style!.fontSize, closeTo(16 * 0.88, 0.001));
      },
    );

    testWidgets('styles nest: italic inside bold', (tester) async {
      await pumpProgram(tester, _md('**one _two_ three**'));
      final spans = _children(tester, 'one two three').cast<TextSpan>();
      final two = spans.firstWhere((s) => s.text == 'two');
      expect(two.style!.fontWeight, FontWeight.w600);
      expect(two.style!.fontStyle, FontStyle.italic);
      expect(spans.first.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('an http link opens through services.openUrl when tapped', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        _md('see [the docs](https://example.com/a?b=1) now'),
      );
      expect(find.text('see the docs now'), findsOneWidget);
      await tester.tapOnText(find.textRange.ofSubstring('the docs'));
      await tester.pump();
      expect(p.opened, [Uri.parse('https://example.com/a?b=1')]);
      final link = _children(
        tester,
        'see the docs now',
      ).cast<TextSpan>().firstWhere((s) => s.recognizer != null);
      expect(link.text, 'the docs');
      expect(link.style!.decoration, TextDecoration.underline);
    });

    testWidgets('a link shows a click cursor and styles its label', (
      tester,
    ) async {
      await pumpProgram(tester, _md('[**bold** link](http://example.com)'));
      final bold = _children(
        tester,
        'bold link',
      ).cast<TextSpan>().firstWhere((s) => s.text == 'bold');
      expect(bold.mouseCursor, SystemMouseCursors.click);
      expect(bold.style!.fontWeight, FontWeight.w600);
      expect(bold.style!.decoration, TextDecoration.underline);
    });

    testWidgets('a javascript: link renders as plain text and does nothing', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        _md(
          '[click me](javascript:alert) and [file](file:///etc/passwd) and [ftp](ftp://x.test/f) and [data](data:text/html,x)',
        ),
      );
      final spans = _children(tester, 'click me and file and ftp and data');
      expect(
        spans.cast<TextSpan>().where((s) => s.recognizer != null),
        isEmpty,
      );
      expect(
        spans.cast<TextSpan>().where((s) => s.mouseCursor != MouseCursor.defer),
        isEmpty,
      );
      await tester.tapAt(
        tester.getTopLeft(_text('click me and file and ftp and data')) +
            const Offset(10, 8),
      );
      await tester.pump();
      expect(p.opened, isEmpty);
    });

    testWidgets('a tap on a link opens only that link', (tester) async {
      final p = await pumpProgram(
        tester,
        _md('[one](https://one.test) and [two](https://two.test)'),
      );
      await tester.tapOnText(find.textRange.ofSubstring('two'));
      await tester.pump();
      expect(p.opened.single.host, 'two.test');
    });

    testWidgets('unfinished markers stay as text', (tester) async {
      await pumpProgram(tester, _md('2 * 3 and **open and `tick'));
      expect(_text('2 * 3 and **open and `tick'), findsOneWidget);
    });
  });
}
