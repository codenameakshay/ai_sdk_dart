import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import '../support/pump.dart';

void _phoneWidth(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder get _shimmer => find.byKey(const ValueKey('iui-shimmer'));

void main() {
  testWidgets('a slider has one division per step when the steps are whole', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Slider(0, 0, 10, 2, "Budget")');
    expect(tester.widget<Slider>(find.byType(Slider)).divisions, 5);
  });

  testWidgets('a slider whose range is not a whole number of steps has none', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Slider(0, 0, 10, 3, "Budget")');
    expect(tester.widget<Slider>(find.byType(Slider)).divisions, isNull);
  });

  testWidgets('a slider announces the value an increase would reach', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpProgram(tester, 'root = Slider(0, 0, 10, 2, "Budget")');
    // The node that carries the value is the slider's own node on older
    // Flutter releases and its child on newer ones.
    final increased = <String>[];
    void visit(SemanticsNode node) {
      if (node.increasedValue.isNotEmpty) increased.add(node.increasedValue);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(tester.getSemantics(find.byType(Slider)));
    semantics.dispose();
    expect(increased, ['2']);
  });

  testWidgets(
    'a block segmented control gives each segment its natural width plus an equal share',
    (tester) async {
      await pumpProgram(
        tester,
        'root = SegmentedControl("none", ["A", "Longer"], true)',
      );
      double widthOf(String label) => tester
          .getSize(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (w) => w is Stack && w.alignment == Alignment.center,
                  ),
                )
                .first,
          )
          .width;
      double textWidth(String label) => tester.getSize(find.text(label)).width;
      expect(
        widthOf('Longer') - widthOf('A'),
        closeTo(textWidth('Longer') - textWidth('A'), 0.01),
      );
    },
  );

  testWidgets(
    'a segmented control with many options scrolls on one line at phone width',
    (tester) async {
      _phoneWidth(tester);
      final options = [for (var i = 1; i <= 12; i++) '"Option $i"'].join(', ');
      await pumpProgram(
        tester,
        'root = SegmentedControl("Option 1", [$options])',
      );

      final scroll = find.ancestor(
        of: find.text('Option 12'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(scroll, findsOneWidget);
      expect(
        find.descendant(of: scroll, matching: find.byType(Row)),
        findsOneWidget,
      );
      final top = tester.getTopLeft(find.text('Option 1')).dy;
      for (var i = 2; i <= 12; i++) {
        expect(tester.getTopLeft(find.text('Option $i')).dy, top);
      }
    },
  );

  testWidgets('radio cards in one row are as tall as the tallest card', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = RadioGroup("a", [{value: "a", label: "Basic"}, {value: "b", label: "Pro", description: "Paid for teams that need room to grow"}], null, "cards")',
    );
    double heightOf(String label) => tester
        .getSize(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        )
        .height;
    expect(heightOf('Basic'), heightOf('Pro'));
  });

  testWidgets('a timer does not announce every tick as a live region', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([Timer(\$left, "Tea")])\n\$left = 3');
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      ),
      findsNothing,
    );
  });

  testWidgets('a photo that is still loading shows a shimmer', (tester) async {
    await pumpProgram(
      tester,
      'root = SearchImage("a red bicycle")',
      services: OpenUiServices(
        searchImages: (_) => Completer<List<Uri>>().future,
        mapTiles: null,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(_shimmer, findsOneWidget);
  });

  testWidgets(
    'a photo with no search results shows the empty icon, not a shimmer',
    (tester) async {
      await pumpProgram(
        tester,
        'root = SearchImage("a red bicycle")',
        services: OpenUiServices(searchImages: (_) async => [], mapTiles: null),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(_shimmer, findsNothing);
      final icon = tester.widget<Glyph>(
        find.byWidgetPredicate((w) => w is Glyph && w.name == 'image'),
      );
      expect(icon.size, 26);
    },
  );
}
