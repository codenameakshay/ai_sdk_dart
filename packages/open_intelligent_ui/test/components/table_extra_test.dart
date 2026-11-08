import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:open_intelligent_ui/src/components/table.dart';

import '../support/pump.dart';

double _left(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dx;

void main() {
  group('Table', () {
    testWidgets('renders headers and text, number and component cells', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([t])\n'
        't = Table(["Player", "Difficulty"], [["Drones", Badge("Hard", "danger")], ["Pilots", null]])',
      );
      expect(find.text('Player'), findsOneWidget);
      expect(find.text('Difficulty'), findsOneWidget);
      expect(find.text('Drones'), findsOneWidget);
      expect(find.text('Hard'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Hard'), matching: find.byType(IuiTable)),
        findsOneWidget,
      );
    });

    testWidgets('a numeric column aligns right, a text column left', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([t])\n'
        't = Table(["Name", "Count", "Mixed"], [["Alpha", 5, 70], ["Beta", 1000, "abc"], ["Gamma", "n/a", 2], ["Delta", null, 3], ["Eps", "", 4]])',
      );
      expect(find.text('1,000'), findsOneWidget);
      expect(_left(tester, '5'), greaterThan(_left(tester, '1,000')));
      expect(_left(tester, 'Alpha'), closeTo(_left(tester, 'Beta'), 0.5));
      expect(_left(tester, '70'), closeTo(_left(tester, 'abc'), 0.5));
    });

    testWidgets('formats numbers as en-US and keeps negative values', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([t])\n'
        't = Table(["Value"], [[1234.5], [-42], [1234567]])',
      );
      expect(find.text('1,234.5'), findsOneWidget);
      expect(find.text('-42'), findsOneWidget);
      expect(find.text('1,234,567'), findsOneWidget);
    });

    testWidgets('a text cell renders inline Markdown', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([t])\n'
        't = Table(["Note"], [["**Bold** point"]])',
      );
      expect(find.textContaining('Bold point'), findsOneWidget);
    });

    testWidgets('a short row leaves its missing cells empty', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([t])\n'
        't = Table(["A", "B"], [["x"]])',
      );
      expect(find.text('x'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('a table with no rows shows only its header', (tester) async {
      await pumpProgram(tester, 'root = Col([t])\nt = Table(["A", null], [])');
      expect(find.text('A'), findsOneWidget);
      expect(find.byType(IuiTable), findsOneWidget);
    });

    testWidgets('a wide table scrolls horizontally inside a narrow screen', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([t])\n'
        't = Table(["Long header one", "Long header two", "Long header three", "Long header four", "Long header five"], [["aaaaaaaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbbbbbbbbbbb", "ccccccccccccccccccccc", "dddddddddddddddddddd", "eeeeeeeeeeeeeeeeeeeee"]])',
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );
    });
  });

  group('Carousel', () {
    testWidgets('items render at the default 240px width with a 12px gap', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([c])\nc = Carousel([Text("One"), Text("Two")])',
      );
      expect(tester.getSize(_sizedBoxAround(tester, 'One')).width, 240);
      expect(_left(tester, 'Two') - _left(tester, 'One'), 252);
    });

    testWidgets('itemWidth and gap set the item width and spacing', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([c])\nc = Carousel([Text("A"), Text("B")], 300, 5)',
      );
      expect(tester.getSize(_sizedBoxAround(tester, 'A')).width, 300);
      expect(_left(tester, 'B') - _left(tester, 'A'), 320);
    });

    testWidgets('itemWidth clamps to 80 and 640', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([a, b])\na = Carousel([Text("Tiny")], 20)\nb = Carousel([Text("Huge")], 2000)',
      );
      expect(tester.getSize(_sizedBoxAround(tester, 'Tiny')).width, 80);
      expect(tester.getSize(_sizedBoxAround(tester, 'Huge')).width, 640);
    });

    testWidgets('a string child renders as text', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([c])\nc = Carousel(["plain", 7], 200)',
      );
      expect(find.text('plain'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('a drag past half an item snaps to the next item', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([c])\nc = Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])',
      );
      await tester.drag(find.text('One'), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(_horizontalPixels(tester), closeTo(252, 0.5));
    });

    testWidgets('a short drag snaps back to the first item', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([c])\nc = Carousel([Text("One"), Text("Two"), Text("Three"), Text("Four"), Text("Five")])',
      );
      await tester.drag(find.text('One'), const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(_horizontalPixels(tester), closeTo(0, 0.5));
    });
  });

  group('Popover', () {
    testWidgets(
      'a text trigger opens its content on tap and closes on an outside tap',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([p])\np = Popover("Info", "Details here")',
        );
        expect(find.text('Details here'), findsNothing);
        await tester.tap(find.text('Info'));
        await tester.pumpAndSettle();
        expect(find.text('Details here'), findsOneWidget);
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(find.text('Details here'), findsNothing);
      },
    );

    testWidgets('a tap on the open panel keeps it open', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([p])\np = Popover("Info", "Stays open")',
      );
      await tester.tap(find.text('Info'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stays open'));
      await tester.pumpAndSettle();
      expect(find.text('Stays open'), findsOneWidget);
    });

    testWidgets('number and element slots render', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([p])\np = Popover(5, [Title("Heading"), Text("Body")])',
      );
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();
      expect(find.text('Heading'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('a numeric content slot renders as text', (tester) async {
      await pumpProgram(tester, 'root = Col([p])\np = Popover("Count", 42)');
      await tester.tap(find.text('Count'));
      await tester.pumpAndSettle();
      expect(find.text('42'), findsOneWidget);
    });
  });

  group('Quote', () {
    testWidgets('renders the text and cite with a side rule', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([q])\nq = Quote("Plan **twice**", "Field notes")',
      );
      expect(find.textContaining('Plan twice'), findsOneWidget);
      expect(find.text('Field notes'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.color == const Color(0xFF030303),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no cite line without a cite', (tester) async {
      await pumpProgram(tester, 'root = Col([q])\nq = Quote("Alone")');
      expect(find.text('Alone'), findsOneWidget);
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('an empty cite is omitted', (tester) async {
      await pumpProgram(tester, 'root = Col([q])\nq = Quote("Alone", "")');
      expect(find.text('Alone'), findsOneWidget);
      expect(find.byType(RichText), findsOneWidget);
    });

    testWidgets('dark mode uses the dark ink for the side rule', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([q])\nq = Quote("Night", "Dark source")',
        brightness: Brightness.dark,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.color == const Color(0xFFFAFAFA),
        ),
        findsOneWidget,
      );
      expect(find.text('Dark source'), findsOneWidget);
    });
  });
}

Finder _sizedBoxAround(WidgetTester tester, String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(SizedBox)).first;

double _horizontalPixels(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.byWidgetPredicate(
        (w) => w is Scrollable && w.axis == Axis.horizontal,
      ),
    )
    .position
    .pixels;
