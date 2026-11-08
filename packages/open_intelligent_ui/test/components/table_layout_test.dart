import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/src/components/table.dart';

import '../support/pump.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(IuiTable),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

void main() {
  testWidgets('numeric cells round decimal ties and expand large numbers', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Table(["Amount"], [[1.005], [1e21]])])',
    );
    expect(find.text('1.01'), findsOneWidget);
    expect(find.text('1,000,000,000,000,000,000,000'), findsOneWidget);
  });

  testWidgets('columns share spare width in proportion to their content', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([Table(["A", "BB"], [["x", "y"]])])');
    expect(tester.getTopLeft(find.text('BB')).dx, closeTo(371.2, 0.5));
  });

  testWidgets('long text wraps on a phone instead of scrolling', (
    tester,
  ) async {
    _phone(tester);
    final note = List.filled(30, 'word').join(' ');
    await pumpProgram(
      tester,
      'root = Col([Table(["Name", "Note"], [["Ana", "$note"]])])',
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(IuiTable),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == note,
        ),
      ),
    );
    expect(paragraph.size.height, greaterThan(21));
    expect(_scroll(tester).maxScrollExtent, 0);
  });

  testWidgets('components that size from constraints render in cells', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Table(["Svg", "Chart", "Grid"], [[s, c, g]])])\n'
      's = Svg([Circle(10, 10, 5)], "0 0 100 100")\n'
      'c = Chart("bar", [{name: "x", v: 3}])\n'
      'g = Grid([Text("a"), Text("b")], 2, 120)',
    );
    expect(tester.takeException(), isNull);
    final svg = find.descendant(
      of: find.byType(IuiTable),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(svg.first).width, greaterThan(0));
  });

  testWidgets('a table wider than the screen scrolls', (tester) async {
    _phone(tester);
    final word = 'x' * 20;
    await pumpProgram(
      tester,
      'root = Col([Table(["a", "b", "c", "d", "e", "f"], '
      '[["$word", "$word", "$word", "$word", "$word", "$word"]])])',
    );
    expect(_scroll(tester).maxScrollExtent, greaterThan(0));
  });

  testWidgets('cells take the phone padding', (tester) async {
    _phone(tester);
    await pumpProgram(tester, 'root = Col([Table(["A"], [["x"]])])');
    final frame = tester.getTopLeft(find.byType(IuiTable)).dx;
    expect(tester.getTopLeft(find.text('A')).dx, frame + 1 + 12);
  });

  testWidgets('hovering a body row highlights it until the pointer leaves', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([Table(["A"], [["first"], ["second"]])])',
    );
    final table = tester.renderObject<RenderIuiTable>(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TableLayout'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('first')));
    await tester.pump();
    expect(table.hoveredRow, 0);
    await mouse.moveTo(const Offset(5, 590));
    await tester.pump();
    expect(table.hoveredRow, isNull);
  });

  testWidgets('a header with no rows keeps its bottom line', (tester) async {
    await pumpProgram(tester, 'root = Col([Table(["A"], [])])');
    final table = tester.renderObject<RenderIuiTable>(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TableLayout'),
    );
    final header = tester.getSize(find.text('A')).height + 22;
    expect(table.size.height, header + 1);
  });

  testWidgets('a table repaints with the new theme and relayouts on resize', (
    tester,
  ) async {
    Widget app(Brightness b, int columns) => MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(
        body: IuiTable(
          head: [for (var c = 0; c < columns; c++) Text('H$c')],
          rows: [
            [for (var c = 0; c < columns; c++) IuiCell(Text('c$c'))],
          ],
        ),
      ),
    );
    await tester.pumpWidget(app(Brightness.light, 2));
    final table = tester.renderObject<RenderIuiTable>(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TableLayout'),
    );
    final twoColumns = tester.getTopLeft(find.text('H1')).dx;
    await tester.pumpWidget(app(Brightness.dark, 3));
    await tester.pumpAndSettle();
    expect(
      tester.renderObject<RenderIuiTable>(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_TableLayout',
        ),
      ),
      same(table),
    );
    expect(tester.getTopLeft(find.text('H1')).dx, lessThan(twoColumns));
    _phone(tester);
    await tester.pumpWidget(app(Brightness.dark, 3));
    expect(tester.getTopLeft(find.text('H0')).dx, 1 + 12);
  });

  testWidgets('a table with no columns is empty', (tester) async {
    await pumpProgram(tester, 'root = Col([Table([], [])])');
    final table = tester.renderObject<RenderIuiTable>(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_TableLayout'),
    );
    expect(table.size.height, 0);
  });

  testWidgets('a Text cell breaks its long word, like overflow-wrap: anywhere', (
    tester,
  ) async {
    _phone(tester);
    final note = List.filled(60, 'word').join(' ');
    await pumpProgram(
      tester,
      'root = Col([Table(["Item", "Notes"], [[Text("Supercalifragilistic"), "$note"]])])',
    );
    // Column 1: its 77px header, plus its share (289 of 4483.5) of the
    // 198.75px the column minimums leave in the 366px table.
    expect(
      tester.getTopLeft(find.text('Notes')).dx -
          tester.getTopLeft(find.text('Item')).dx,
      closeTo(77 + 198.75 * 289 / 4483.5, 1e-9),
    );
    expect(
      tester.getSize(find.text('Supercalifragilistic')).height,
      greaterThan(2 * 14 * 1.5),
    );
  });

  testWidgets('a table reads as a table of rows, column headers and cells', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpProgram(
      tester,
      'root = Col([Table(["Name", "Age"], [["Ana", 31]])])',
    );
    final head = tester.getSemantics(find.text('Name'));
    expect(head.role, SemanticsRole.columnHeader);
    expect(head.parent!.role, SemanticsRole.row);
    expect(head.parent!.parent!.role, SemanticsRole.table);
    final cell = tester.getSemantics(find.text('Ana'));
    expect(cell.role, SemanticsRole.cell);
    expect(cell.parent!.indexInParent, 1);
    handle.dispose();
  });
}
