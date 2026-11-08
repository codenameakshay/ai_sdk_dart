import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import '../support/pump.dart';

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Rect _rect(WidgetTester tester, String text) => tester.getRect(find.text(text));

void _phoneWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _cardBodies() => find.byWidgetPredicate(
  (w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration! as BoxDecoration).borderRadius ==
          BorderRadius.circular(14),
);

void main() {
  testWidgets('a card title is 14 medium and the body under it is a muted 15', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Card([Title("Head"), Text("body")])');
    final head = _style(tester, 'Head');
    expect(head.fontSize, 14);
    expect(head.height, closeTo(20 / 14, 1e-9));
    expect(head.fontWeight, FontWeight.w500);
    final body = _style(tester, 'body');
    expect(body.fontSize, 15);
    expect(body.height, closeTo(22 / 15, 1e-9));
    expect(body.color, OpenUiTheme.light.muted);
    expect(
      _rect(tester, 'body').top - _rect(tester, 'Head').bottom,
      closeTo(8, 0.5),
    );
  });

  testWidgets('a card with a gap adds the 2px subtitle offset to that gap', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Card([Title("Head"), Text("body")], null, null, 2)',
    );
    expect(
      _rect(tester, 'body').top - _rect(tester, 'Head').bottom,
      closeTo(10, 0.5),
    );
  });

  testWidgets('a caption under a card title is a muted 13 subtitle', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Card([Title("Head"), Caption("sub")])');
    final sub = _style(tester, 'sub');
    expect(sub.fontSize, 13);
    expect(sub.height, closeTo(18 / 13, 1e-9));
    expect(sub.color, OpenUiTheme.light.muted);
  });

  testWidgets(
    'a title and caption inside a card head row style as the card title',
    (tester) async {
      await pumpProgram(
        tester,
        'root = Card([Row([Col([Title("Name"), Caption("Role")]), Badge("New")])])',
      );
      expect(_style(tester, 'Name').fontSize, 14);
      final role = _style(tester, 'Role');
      expect(role.fontSize, 13);
      expect(role.color, OpenUiTheme.light.muted);
    },
  );

  testWidgets('a title after the first card item keeps the 17 default size', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Card([Text("first"), Title("Later")])');
    expect(_style(tester, 'Later').fontSize, 17);
    final first = _style(tester, 'first');
    expect(first.fontSize, 15);
    expect(first.color, OpenUiTheme.light.ink);
  });

  testWidgets('a 2xl title in a card is 18 semibold with tighter tracking', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Card([Title("Big", "2xl")])');
    final big = _style(tester, 'Big');
    expect(big.fontSize, 18);
    expect(big.height, closeTo(24 / 18, 1e-9));
    expect(big.letterSpacing, closeTo(-0.3, 1e-9));
  });

  testWidgets('a grid cell column makes its xl title 18 and its text 15', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Grid([Col([Title("Cell", "xl"), Text("cell body")])])',
    );
    expect(_style(tester, 'Cell').fontSize, 18);
    expect(_style(tester, 'cell body').fontSize, 15);
  });

  testWidgets(
    'a grid cell column with a gap keeps the plain title and text sizes',
    (tester) async {
      await pumpProgram(
        tester,
        'root = Grid([Col([Title("Cell", "xl"), Text("cell body")], 4)])',
      );
      expect(_style(tester, 'Cell').fontSize, 25);
      expect(_style(tester, 'cell body').fontSize, isNot(15));
    },
  );

  testWidgets('text in a row inside a card keeps the card font size of 14', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Card([Row([Text("deep")])])');
    expect(_style(tester, 'deep').fontSize, 14);
  });

  testWidgets('grid cards in one row share the height of the taller card', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'a = Card([Text("x")])\n'
      'b = Card([Text("y"), Text("z"), Text("w")])\n'
      'root = Grid([a, b])',
    );
    expect(_cardBodies(), findsNWidgets(2));
    expect(
      tester.getSize(_cardBodies().at(0)).height,
      tester.getSize(_cardBodies().at(1)).height,
    );
  });

  testWidgets('a title reports its heading level to semantics', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpProgram(
      tester,
      'root = Col([Title("H1", "3xl"), Title("H4", "sm")])',
    );
    expect(tester.getSemantics(find.text('H1')).headingLevel, 1);
    expect(tester.getSemantics(find.text('H4')).headingLevel, 4);
    handle.dispose();
  });

  testWidgets('a row keeps a fixed-width box at its width when text is long', (
    tester,
  ) async {
    _phoneWidth(tester);
    await pumpProgram(
      tester,
      'root = Row([Box([Text("long long long long long long long long long long long long long long")]), '
      'Box([Text("x")], null, null, null, null, null, null, 80)])',
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('x'), matching: find.byType(Container))
                .first,
          )
          .width,
      80,
    );
  });

  testWidgets('two flex boxes in a row split the free space equally', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Row([Box([Text("aaaaaaaaaaaa")], null, null, null, null, null, null, null, null, 1), '
      'Box([Text("b")], null, null, null, null, null, null, null, null, 1)])',
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('aaaaaaaaaaaa'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .width,
      380,
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('b'), matching: find.byType(Container))
                .first,
          )
          .width,
      380,
    );
  });

  testWidgets('a flex box takes its share in proportion to its flex', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Row([Box([Text("aaaaaaaaaaaa")], null, null, null, null, null, null, null, null, 1.5), '
      'Box([Text("b")], null, null, null, null, null, null, null, null, 1)])',
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(
                  of: find.text('aaaaaaaaaaaa'),
                  matching: find.byType(Container),
                )
                .first,
          )
          .width,
      456,
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('b'), matching: find.byType(Container))
                .first,
          )
          .width,
      304,
    );
  });

  testWidgets('a box width in em resolves against the card font size', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Card([Box([Text("e")], null, null, null, null, null, null, "10em")])',
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('e'), matching: find.byType(Container))
                .first,
          )
          .width,
      140,
    );
  });

  testWidgets('a box width in vw resolves against the viewport', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Card([Box([Text("v")], null, null, null, null, null, null, "50vw")])',
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('v'), matching: find.byType(Container))
                .first,
          )
          .width,
      400,
    );
  });

  testWidgets('a box with a fr width takes the full card width', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Card([Box([Text("f")], null, null, null, null, null, null, "1fr")])',
    );
    expect(
      tester
          .getSize(
            find
                .ancestor(of: find.text('f'), matching: find.byType(Container))
                .first,
          )
          .width,
      726,
    );
  });
}
