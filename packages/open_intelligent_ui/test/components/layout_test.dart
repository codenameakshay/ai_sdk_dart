import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import '../support/pump.dart';

// The default test view is 800 wide: the scroll body is 768 wide, from x 16 to 784.
const _left = 16.0;
const _right = 784.0;
const _phoneRight = 384.0;

Rect _rect(WidgetTester tester, String text) => tester.getRect(find.text(text));

double _gap(WidgetTester tester, String above, String below) =>
    _rect(tester, below).top - _rect(tester, above).bottom;

Finder _decorated(bool Function(BoxDecoration d) test) =>
    find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          test(w.decoration! as BoxDecoration),
    );

Finder _colored(Color color) => _decorated((d) => d.color == color);

Finder _dividerLine(Color color) =>
    find.byWidgetPredicate((w) => w is Container && w.color == color);

void _phoneWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Color? _inkOf(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style?.color;

void main() {
  group('Col', () {
    testWidgets('without gap, blocks flow like an article', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([t, x, c, y])\n'
        't = Title("Head")\n'
        'x = Text("body")\n'
        'c = Caption("cap")\n'
        'y = Text("after")',
      );
      expect(_gap(tester, 'Head', 'body'), closeTo(8, 0.5));
      expect(_gap(tester, 'body', 'cap'), closeTo(24, 0.5));
    });

    testWidgets('flow spacing: caption before title is 4px', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([c, t])\nc = Caption("cap")\nt = Title("Head")',
      );
      expect(_gap(tester, 'cap', 'Head'), closeTo(4, 0.5));
    });

    testWidgets(
      'flow spacing: title before a box is 12px, box before box is 24px',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([t, inner, z])\n'
          't = Title("Head")\n'
          'inner = Box([Text("p")])\n'
          'z = Box([Text("q")])',
        );
        expect(_gap(tester, 'Head', 'p'), closeTo(12, 0.5));
        expect(_gap(tester, 'p', 'q'), closeTo(24, 0.5));
      },
    );

    testWidgets(
      'a flow column nested in a flow column spaces its blocks by 12px',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([inner, z])\n'
          'inner = Col([b1, b2])\n'
          'b1 = Box([Text("p")])\n'
          'b2 = Box([Text("q")])\n'
          'z = Box([Text("r")])',
        );
        expect(_gap(tester, 'p', 'q'), closeTo(12, 0.5));
        expect(_gap(tester, 'q', 'r'), closeTo(24, 0.5));
      },
    );

    testWidgets('title before a badge row is 8px', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([t, r])\nt = Title("Head")\nr = Row([Badge("New")])',
      );
      expect(_gap(tester, 'Head', 'New'), greaterThan(7));
      expect(_gap(tester, 'Head', 'New'), lessThan(14));
    });

    testWidgets('with gap, children are gap * 4 px apart', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([a, b], 2)\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(8, 0.5));
    });

    testWidgets('a Spacer in a column renders nothing', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([a, Spacer(), b], 2)\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(8, 0.5));
    });

    testWidgets('a divider between children keeps its 4px margins', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([a, Divider(), b], 0)\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(9, 0.5));
    });

    testWidgets('a box stretches across a Col by default', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([b])\nb = Box([Text("hi")], null, null, null, "surface")',
      );
      expect(
        tester.getRect(_colored(OpenUiTheme.light.surface)).width,
        closeTo(_right - _left, 0.5),
      );
    });

    for (final (align, check) in [
      ('start', (Rect t, Rect w) => expect(t.left, closeTo(w.left, 0.5))),
      (
        'center',
        (Rect t, Rect w) => expect(t.center.dx, closeTo(w.center.dx, 0.5)),
      ),
      ('end', (Rect t, Rect w) => expect(t.right, closeTo(w.right, 0.5))),
    ]) {
      testWidgets('align $align places children in the column', (tester) async {
        await pumpProgram(
          tester,
          'root = Col([t, wide], null, "$align")\n'
          't = Text("hi")\n'
          'wide = Text("a much longer line of text")',
        );
        check(_rect(tester, 'hi'), _rect(tester, 'a much longer line of text'));
      });
    }

    testWidgets('align center and end set the text alignment', (tester) async {
      await pumpProgram(tester, 'root = Col([a], null, "end")\na = Text("hi")');
      expect(
        DefaultTextStyle.of(tester.element(find.text('hi'))).textAlign,
        TextAlign.end,
      );
    });

    testWidgets('align center sets centered text', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([a], null, "center")\na = Text("hi")',
      );
      expect(
        DefaultTextStyle.of(tester.element(find.text('hi'))).textAlign,
        TextAlign.center,
      );
    });
  });

  group('Row', () {
    testWidgets('children sit side by side with an 8px default gap', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([a, b])\na = Text("a")\nb = Text("b")',
      );
      expect(
        _rect(tester, 'b').left - _rect(tester, 'a').right,
        closeTo(8, 0.5),
      );
    });

    testWidgets('gap is in 4px steps', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([a, b], 1)\na = Text("a")\nb = Text("b")',
      );
      expect(
        _rect(tester, 'b').left - _rect(tester, 'a').right,
        closeTo(4, 0.5),
      );
    });

    testWidgets('children are vertically centered by default', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([a, Box([b], null, null, null, null, null, null, null, 60)])\n'
        'a = Text("a")\n'
        'b = Text("b")',
      );
      final boxTop = _rect(tester, 'b').top;
      expect(_rect(tester, 'a').center.dy, closeTo(boxTop + 30, 1));
    });

    for (final (align, check) in [
      (
        'start',
        (Rect a, Rect b, Rect box) => expect(a.top, closeTo(box.top, 1)),
      ),
      (
        'end',
        (Rect a, Rect b, Rect box) => expect(a.bottom, closeTo(box.bottom, 1)),
      ),
      (
        'center',
        (Rect a, Rect b, Rect box) =>
            expect(a.center.dy, closeTo(box.center.dy, 1)),
      ),
    ]) {
      testWidgets('align $align positions children on the cross axis', (
        tester,
      ) async {
        await pumpProgram(
          tester,
          'root = Row([a, big], null, "$align")\n'
          'a = Text("a")\n'
          'big = Box([Text("b")], null, null, null, null, null, null, null, 60)',
        );
        final a = _rect(tester, 'a');
        final b = _rect(tester, 'b');
        final box = Rect.fromLTWH(b.left, b.top, b.width, 60);
        check(a, b, box);
      });
    }

    testWidgets('align stretch lays out without error', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([a, b], null, "stretch")\na = Text("a")\nb = Text("b")',
      );
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('justify start packs children at the left edge', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([a], null, null, "start")\na = Text("a")',
      );
      expect(_rect(tester, 'a').left, closeTo(_left, 0.5));
    });

    testWidgets('justify center centers the row', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([a], null, null, "center")\na = Text("a")',
      );
      expect(_rect(tester, 'a').center.dx, closeTo(400, 0.5));
    });

    testWidgets('justify end packs children at the right edge', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([a], null, null, "end")\na = Text("a")',
      );
      expect(_rect(tester, 'a').right, closeTo(_right, 0.5));
    });

    testWidgets('justify between spreads children to both edges', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([a, b], null, null, "between")\na = Text("a")\nb = Text("b")',
      );
      expect(_rect(tester, 'a').left, closeTo(_left, 0.5));
      expect(_rect(tester, 'b').right, closeTo(_right, 0.5));
    });

    testWidgets('a Spacer fills the free space', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([a, Spacer(), b])\na = Text("a")\nb = Text("b")',
      );
      expect(_rect(tester, 'a').left, closeTo(_left, 0.5));
      expect(_rect(tester, 'b').right, closeTo(_right, 0.5));
    });

    testWidgets('wrap moves overflowing children to a new line', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([x, y], null, null, null, true)\n'
        'x = Box([Text("x")], null, null, null, null, null, null, 500)\n'
        'y = Box([Text("y")], null, null, null, null, null, null, 500)',
      );
      expect(_rect(tester, 'y').top, greaterThan(_rect(tester, 'x').top));
      expect(_rect(tester, 'y').left, closeTo(_rect(tester, 'x').left, 0.5));
    });

    for (final (justify, check) in [
      ('start', (Rect a, Rect b) => expect(a.left, closeTo(_left, 0.5))),
      (
        'center',
        (Rect a, Rect b) => expect((a.left + b.right) / 2, closeTo(400, 0.5)),
      ),
      ('end', (Rect a, Rect b) => expect(b.right, closeTo(_right, 0.5))),
      (
        'between',
        (Rect a, Rect b) {
          expect(a.left, closeTo(_left, 0.5));
          expect(b.right, closeTo(_right, 0.5));
        },
      ),
    ]) {
      testWidgets('wrap with justify $justify', (tester) async {
        await pumpProgram(
          tester,
          'root = Row([a, b], null, null, "$justify", true)\na = Text("a")\nb = Text("b")',
        );
        check(_rect(tester, 'a'), _rect(tester, 'b'));
      });
    }

    for (final (align, check) in [
      ('start', (Rect a, Rect b) => expect(a.top, closeTo(b.top, 1))),
      (
        'center',
        (Rect a, Rect b) => expect(a.center.dy, closeTo(b.center.dy, 1)),
      ),
      ('end', (Rect a, Rect b) => expect(a.bottom, closeTo(b.bottom, 1))),
    ]) {
      testWidgets('wrap with align $align', (tester) async {
        await pumpProgram(
          tester,
          'root = Row([a, big], null, "$align", null, true)\n'
          'a = Text("a")\n'
          'big = Title("Big", "xl")',
        );
        check(_rect(tester, 'a'), _rect(tester, 'Big'));
      });
    }

    testWidgets('wrap without align centers children', (tester) async {
      await pumpProgram(
        tester,
        'root = Row([a, big], null, null, null, true)\n'
        'a = Text("a")\n'
        'big = Title("Big", "xl")',
      );
      expect(
        _rect(tester, 'a').center.dy,
        closeTo(_rect(tester, 'Big').center.dy, 1),
      );
    });

    testWidgets('a long text child shrinks instead of overflowing a phone', (
      tester,
    ) async {
      _phoneWidth(tester);
      final long = 'word ' * 60;
      await pumpProgram(
        tester,
        'root = Row([a, b])\na = Text("$long")\nb = Text("end")',
      );
      expect(tester.takeException(), isNull);
      expect(_rect(tester, 'end').right, lessThanOrEqualTo(_phoneRight));
    });

    testWidgets('a flex box takes the free space beside a fixed child', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Row([grow, b])\n'
        'grow = Box([Text("g")], null, null, null, "surface", null, null, null, null, 1)\n'
        'b = Text("b")',
      );
      final box = tester.getRect(_colored(OpenUiTheme.light.surface));
      expect(box.right, closeTo(_rect(tester, 'b').left - 8, 0.5));
    });
  });

  group('Box', () {
    testWidgets('row direction has an 8px default gap', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a, b], "row")\na = Text("a")\nb = Text("b")',
      );
      expect(
        _rect(tester, 'b').left - _rect(tester, 'a').right,
        closeTo(8, 0.5),
      );
    });

    testWidgets('row direction with gap uses 4px steps', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a, b], "row", 1)\na = Text("a")\nb = Text("b")',
      );
      expect(
        _rect(tester, 'b').left - _rect(tester, 'a').right,
        closeTo(4, 0.5),
      );
    });

    testWidgets('a column without gap flows like Col', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a, b])\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(12, 0.5));
    });

    testWidgets('a column with gap is gap * 4 apart', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a, b], "col", 2)\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(8, 0.5));
    });

    testWidgets('padding is in 4px steps', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([box], null, "start")\n'
        'box = Box([t], null, null, 2, "surface")\n'
        't = Text("pad")',
      );
      expect(_rect(tester, 'pad').left, closeTo(_left + 8, 0.5));
    });

    testWidgets('a surface background paints the box', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "surface")\nt = Text("in")',
      );
      expect(_colored(OpenUiTheme.light.surface), findsOneWidget);
      expect(_inkOf(tester, 'in'), isNot(const Color(0xFFFFFFFF)));
    });

    testWidgets('a status background uses its soft tint', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "success")\nt = Text("ok")',
      );
      expect(
        _colored(OpenUiTheme.light.statusSoft['success']!),
        findsOneWidget,
      );
    });

    testWidgets('a raw dark background gets light text', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "#101010")\nt = Text("on")',
      );
      expect(_inkOf(tester, 'on'), const Color(0xFFFFFFFF));
    });

    testWidgets('a raw light background gets dark text', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "#ffffff")\nt = Text("on")',
      );
      expect(_inkOf(tester, 'on'), const Color(0xFF0D0D0D));
    });

    testWidgets('a named radius rounds and clips the content', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "surface", "md")\nt = Text("r")',
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is ClipRRect && w.borderRadius == BorderRadius.circular(10),
        ),
        findsOneWidget,
      );
      expect(
        _decorated((d) => d.borderRadius == BorderRadius.circular(10)),
        findsOneWidget,
      );
    });

    testWidgets('a numeric radius is in px and full is a pill', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([a, b], null, "start")\n'
        'a = Box([Text("p")], null, null, null, "surface", 4)\n'
        'b = Box([Text("f")], null, null, null, "surface", "full")',
      );
      expect(
        _decorated((d) => d.borderRadius == BorderRadius.circular(4)),
        findsOneWidget,
      );
      expect(
        _decorated((d) => d.borderRadius == BorderRadius.circular(999)),
        findsOneWidget,
      );
    });

    testWidgets('no radius means no clipping', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "surface")\nt = Text("n")',
      );
      expect(find.byType(ClipRRect), findsNothing);
    });

    testWidgets('border draws a 1px line in the border color', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, null, null, true)\nt = Text("b")',
      );
      expect(
        _decorated(
          (d) => d.border == Border.all(color: OpenUiTheme.light.border),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a px width fixes the box width', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([box], null, "start")\n'
        'box = Box([t], null, null, null, "surface", null, null, 100)\n'
        't = Text("w")',
      );
      expect(
        tester.getSize(_colored(OpenUiTheme.light.surface)).width,
        closeTo(100, 0.5),
      );
    });

    testWidgets('a px height fixes the box height', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "surface", null, null, null, 40)\nt = Text("h")',
      );
      expect(
        tester.getSize(_colored(OpenUiTheme.light.surface)).height,
        closeTo(40, 0.5),
      );
    });

    testWidgets('a percent width is a fraction of the parent', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "surface", null, null, "50%")\nt = Text("p")',
      );
      expect(
        tester.getSize(_colored(OpenUiTheme.light.surface)).width,
        closeTo((_right - _left) / 2, 0.5),
      );
    });

    testWidgets('a width that is not a length is ignored', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([t], null, null, null, "surface", null, null, "wide")\nt = Text("x")',
      );
      expect(
        tester.getSize(_colored(OpenUiTheme.light.surface)).width,
        closeTo(_right - _left, 0.5),
      );
    });

    testWidgets('column justify between spreads children top to bottom', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Box([a, b], "col", null, null, "surface", null, null, null, 200, null, null, "between")\n'
        'a = Text("a")\n'
        'b = Text("b")',
      );
      final box = tester.getRect(_colored(OpenUiTheme.light.surface));
      expect(_rect(tester, 'a').top, closeTo(box.top, 0.5));
      expect(_rect(tester, 'b').bottom, closeTo(box.bottom, 0.5));
    });

    testWidgets('column justify end packs children at the bottom', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Box([a], "col", null, null, "surface", null, null, null, 200, null, null, "end")\na = Text("a")',
      );
      final box = tester.getRect(_colored(OpenUiTheme.light.surface));
      expect(_rect(tester, 'a').bottom, closeTo(box.bottom, 0.5));
    });

    testWidgets('column justify center centers children vertically', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Box([a], "col", null, null, "surface", null, null, null, 200, null, null, "center")\na = Text("a")',
      );
      final box = tester.getRect(_colored(OpenUiTheme.light.surface));
      expect(_rect(tester, 'a').center.dy, closeTo(box.center.dy, 0.5));
    });

    testWidgets('column align center centers children', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a], "col", null, null, "surface", null, null, null, null, null, "center")\na = Text("a")',
      );
      final box = tester.getRect(_colored(OpenUiTheme.light.surface));
      expect(_rect(tester, 'a').center.dx, closeTo(box.center.dx, 0.5));
    });

    testWidgets('column align end packs children at the right', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a], "col", null, null, "surface", null, null, null, null, null, "end")\na = Text("a")',
      );
      final box = tester.getRect(_colored(OpenUiTheme.light.surface));
      expect(_rect(tester, 'a').right, closeTo(box.right, 0.5));
    });

    testWidgets('row wrap moves children to a new line with an 8px gap', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([w], null, "start")\n'
        'w = Box([x, y], "row", null, null, null, null, null, 300, null, null, null, null, true)\n'
        'x = Box([Text("x")], null, null, null, null, null, null, 200)\n'
        'y = Box([Text("y")], null, null, null, null, null, null, 200)',
      );
      expect(_gap(tester, 'x', 'y'), closeTo(8, 0.5));
    });

    testWidgets('column wrap keeps children in one run with no gap by default', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Box([a, b], "col", null, null, null, null, null, null, null, null, null, null, true)\n'
        'a = Text("a")\n'
        'b = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(0, 0.5));
    });

    testWidgets('column wrap honors gap', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a, b], "col", 1, null, null, null, null, null, null, null, null, null, true)\n'
        'a = Text("a")\n'
        'b = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(4, 0.5));
    });

    testWidgets('a flex row wrap box lays out its children', (tester) async {
      await pumpProgram(
        tester,
        'root = Box([a, b], "row", null, null, null, null, null, null, null, null, null, null, true)\n'
        'a = Text("a")\n'
        'b = Text("b")',
      );
      expect(_rect(tester, 'b').top, closeTo(_rect(tester, 'a').top, 1));
    });
  });

  group('Grid', () {
    testWidgets('defaults to two equal columns with a 12px gap', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b, c, d])\na = Text("a")\nb = Text("b")\nc = Text("c")\nd = Text("d")',
      );
      expect(_rect(tester, 'b').left, greaterThan(_rect(tester, 'a').left));
      expect(_rect(tester, 'c').left, closeTo(_rect(tester, 'a').left, 0.5));
      expect(_rect(tester, 'c').top, greaterThan(_rect(tester, 'a').top));
      expect(
        _rect(tester, 'b').left - _rect(tester, 'a').left,
        closeTo((_right - _left - 12) / 2 + 12, 0.5),
      );
    });

    testWidgets('gap is in 4px steps', (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b], 2, null, 1)\na = Text("a")\nb = Text("b")',
      );
      expect(
        _rect(tester, 'b').left - _rect(tester, 'a').left,
        closeTo((_right - _left - 4) / 2 + 4, 0.5),
      );
    });

    testWidgets('columns sets the count', (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b, c], 3)\na = Text("a")\nb = Text("b")\nc = Text("c")',
      );
      expect(_rect(tester, 'c').top, closeTo(_rect(tester, 'a').top, 0.5));
    });

    testWidgets('columns rounds to a whole number', (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b, c], 2.6)\na = Text("a")\nb = Text("b")\nc = Text("c")',
      );
      expect(_rect(tester, 'c').top, closeTo(_rect(tester, 'a').top, 0.5));
    });

    testWidgets('columns clamps below 1 to 1', (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b], 0)\na = Text("a")\nb = Text("b")',
      );
      expect(_rect(tester, 'b').top, greaterThan(_rect(tester, 'a').top));
    });

    testWidgets('columns clamps above 12 to 12', (tester) async {
      final items = [for (var i = 1; i <= 13; i++) 'c$i'];
      final defs = [for (final i in items) '$i = Text("$i")'].join('\n');
      await pumpProgram(
        tester,
        'root = Grid([${items.join(', ')}], 40)\n$defs',
      );
      expect(_rect(tester, 'c12').top, closeTo(_rect(tester, 'c1').top, 0.5));
      expect(_rect(tester, 'c13').top, greaterThan(_rect(tester, 'c1').top));
    });

    testWidgets('rows align to the top', (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([big, small])\nbig = Title("Big", "xl")\nsmall = Text("small")',
      );
      expect(
        _rect(tester, 'small').top,
        closeTo(_rect(tester, 'Big').top, 0.5),
      );
    });

    testWidgets('minChildWidth drops columns when they cannot fit', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b], 2, 400)\na = Text("a")\nb = Text("b")',
      );
      expect(_rect(tester, 'b').top, greaterThan(_rect(tester, 'a').top));
    });

    testWidgets('minChildWidth keeps the columns that fit', (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b, c, d], 4, 150)\na = Text("a")\nb = Text("b")\nc = Text("c")\nd = Text("d")',
      );
      expect(_rect(tester, 'c').top, closeTo(_rect(tester, 'a').top, 0.5));
    });

    testWidgets('minChildWidth on a narrow phone falls back to one column', (
      tester,
    ) async {
      _phoneWidth(tester);
      await pumpProgram(
        tester,
        'root = Grid([a, b], 4, 180)\na = Text("a")\nb = Text("b")',
      );
      expect(_rect(tester, 'b').top, greaterThan(_rect(tester, 'a').top));
    });

    testWidgets('minChildWidth never exceeds columns', (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b, c], 2, 100)\na = Text("a")\nb = Text("b")\nc = Text("c")',
      );
      expect(_rect(tester, 'c').top, greaterThan(_rect(tester, 'a').top));
      expect(_rect(tester, 'c').left, closeTo(_rect(tester, 'a').left, 0.5));
    });

    testWidgets('minChildWidth of zero uses the fixed column count', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Grid([a, b, c], 3, 0)\na = Text("a")\nb = Text("b")\nc = Text("c")',
      );
      expect(_rect(tester, 'c').top, closeTo(_rect(tester, 'a').top, 0.5));
    });
  });

  group('Card', () {
    testWidgets('has 20px padding, 14px radius and a canvas panel', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Card([t])\nt = Text("c")');
      expect(_rect(tester, 'c').left, closeTo(_left + 21, 0.5));
      expect(
        _decorated(
          (d) =>
              d.borderRadius == BorderRadius.circular(14) &&
              d.color == OpenUiTheme.light.canvas,
        ),
        findsOneWidget,
      );
      expect(
        _decorated(
          (d) => d.border == Border.all(color: OpenUiTheme.light.border),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pads 16px on a phone', (tester) async {
      _phoneWidth(tester);
      await pumpProgram(tester, 'root = Card([t])\nt = Text("c")');
      expect(_rect(tester, 'c').left, closeTo(_left + 17, 0.5));
    });

    testWidgets('a nested card is 16px padded with a 12px radius', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Card([inner])\ninner = Card([t])\nt = Text("n")',
      );
      expect(_rect(tester, 'n').left, closeTo(_left + 1 + 20 + 1 + 16, 0.5));
      expect(
        _decorated((d) => d.borderRadius == BorderRadius.circular(12)),
        findsOneWidget,
      );
    });

    testWidgets('a soft card fills with the surface and has no border', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Card([t], "soft")\nt = Text("s")');
      expect(_colored(OpenUiTheme.light.surface), findsOneWidget);
      expect(
        _decorated((d) => d.border?.top.color == const Color(0x00000000)),
        findsOneWidget,
      );
    });

    testWidgets('padding is in 4px steps', (tester) async {
      await pumpProgram(tester, 'root = Card([t], null, 3)\nt = Text("p")');
      expect(_rect(tester, 'p').left, closeTo(_left + 13, 0.5));
    });

    testWidgets('gap sets the spacing between children', (tester) async {
      await pumpProgram(
        tester,
        'root = Card([a, b], null, null, 2)\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(8, 0.5));
    });

    testWidgets('without gap, children flow like Col', (tester) async {
      await pumpProgram(
        tester,
        'root = Card([t, x])\nt = Title("Head")\nx = Text("body")',
      );
      expect(_gap(tester, 'Head', 'body'), closeTo(8, 0.5));
    });
  });

  group('Divider and Spacer', () {
    testWidgets('a divider is a 1px line in the border color', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([a, Divider(), b], 0)\na = Text("a")\nb = Text("b")',
      );
      final line = tester.getSize(_dividerLine(OpenUiTheme.light.border));
      expect(line.height, closeTo(1, 0.5));
    });

    testWidgets('a Spacer in a row fills the free space', (tester) async {
      await pumpProgram(tester, 'root = Row([Spacer(), a])\na = Text("a")');
      expect(_rect(tester, 'a').right, closeTo(_right, 0.5));
    });

    testWidgets('a Spacer inside a box row fills its free space', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Box([Spacer(), a], "row", null, null, null, null, null, 300)\na = Text("a")',
      );
      expect(_rect(tester, 'a').right, lessThan(_right));
    });
  });

  group('Form', () {
    testWidgets('children are 24px apart', (tester) async {
      await pumpProgram(
        tester,
        'root = Form([a, b])\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(24, 0.5));
    });

    testWidgets('a Spacer is left out of the form', (tester) async {
      await pumpProgram(
        tester,
        'root = Form([a, Spacer(), b])\na = Text("a")\nb = Text("b")',
      );
      expect(_gap(tester, 'a', 'b'), closeTo(24, 0.5));
    });

    testWidgets('a trailing button sits 40px below the field above it', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Form([a, Button("Go")])\na = Text("a")',
      );
      expect(_gap(tester, 'a', 'Go'), greaterThanOrEqualTo(40));
    });

    testWidgets('a trailing row of buttons gets the same action gap', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Form([a, Row([Button("Go")])])\na = Text("a")',
      );
      expect(_gap(tester, 'a', 'Go'), greaterThanOrEqualTo(40));
    });
  });

  group('rebuilds', () {
    testWidgets('a rebuilt nested card and flow column keep their spacing', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Card([inner])\ninner = Card([a, b])\na = Text("a")\nb = Text("b")',
      );
      pumped.session.update(
        'root = Card([inner])\ninner = Card([a, b])\na = Text("a")\nb = Text("c")',
        streaming: false,
      );
      await tester.pump();
      expect(_rect(tester, 'c').left, closeTo(_left + 1 + 20 + 1 + 16, 0.5));
      expect(_gap(tester, 'a', 'c'), closeTo(12, 0.5));
    });

    testWidgets('a rebuilt flow column keeps its article spacing', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = Col([a, b])\na = Text("a")\nb = Text("b")',
      );
      pumped.session.update(
        'root = Col([a, b])\na = Text("a")\nb = Text("c")',
        streaming: false,
      );
      await tester.pump();
      expect(_gap(tester, 'a', 'c'), closeTo(12, 0.5));
    });
  });

  group('wrapping row beside a Spacer', () {
    testWidgets(
      'a wrapping row inside a Row with a Spacer lays out without error',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([r])\n'
          'r = Row([inner, Spacer(), b])\n'
          'inner = Row([x, y], null, null, null, true)\n'
          'x = Text("x")\n'
          'y = Text("y")\n'
          'b = Text("b")',
        );
        expect(tester.takeException(), isNull);
        expect(_rect(tester, 'b').right, closeTo(_right, 0.5));
      },
    );
  });

  group('Spacer alone', () {
    testWidgets('a root Spacer has no size', (tester) async {
      await pumpProgram(tester, 'root = Spacer()');
      expect(tester.getSize(find.byType(OpenUiElementView)), Size.zero);
    });
  });

  group('dark mode', () {
    testWidgets('cards, dividers and borders use the dark tokens', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Card([a, Divider()])\na = Text("dark")',
        brightness: Brightness.dark,
      );
      expect(
        _decorated((d) => d.color == OpenUiTheme.dark.canvas),
        findsOneWidget,
      );
      expect(_dividerLine(OpenUiTheme.dark.border), findsOneWidget);
    });
  });
}
