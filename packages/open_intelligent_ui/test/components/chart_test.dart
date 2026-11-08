import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/chart.dart'
    show chartFormat, niceStep;

import '../gallery_fixture.dart';
import '../support/pump.dart';

final _light = OpenUiTheme.light;

/// 2.2 as the engine's 32-bit float.
const _w22 = 2.200000047683716;

Finder get _plot => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_PlotPainter',
);

Finder get _pie => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_PiePainter',
);

/// What the painter at [finder] draws, as recorded calls named [name].
List<Invocation> _calls(
  WidgetTester tester,
  Symbol name, {
  Finder? finder,
  int index = 0,
}) {
  final box = tester.renderObject<RenderCustomPaint>(
    (finder ?? _plot).at(index),
  );
  final canvas = TestRecordingCanvas();
  box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return [
    for (final call in canvas.invocations)
      if (call.invocation.memberName == name) call.invocation,
  ];
}

Offset _global(WidgetTester tester, Offset local, {Finder? finder}) => tester
    .renderObject<RenderBox>((finder ?? _plot).first)
    .localToGlobal(local);

List<RRect> _bars(WidgetTester tester) => [
  for (final c in _calls(tester, #drawRRect))
    c.positionalArguments.first as RRect,
];

List<Offset> _dots(WidgetTester tester) => [
  for (final c in _calls(tester, #drawCircle))
    c.positionalArguments.first as Offset,
];

List<int> _pathColors(WidgetTester tester, {Finder? finder}) => [
  for (final c in _calls(tester, #drawPath, finder: finder))
    (c.positionalArguments[1] as Paint).color.toARGB32(),
];

String _chartLabel(WidgetTester tester) => tester
    .widgetList<Semantics>(find.byType(Semantics))
    .map((s) => s.properties.label)
    .firstWhere((l) => l != null && l.contains(' chart of '))!;

Future<String> _label(WidgetTester tester, String chart) async {
  await pumpProgram(tester, 'root = Col([$chart])');
  return _chartLabel(tester);
}

double _plotHeight(WidgetTester tester) => tester.getSize(_plot).height;

const _rows3 =
    '[{m: "Jan", a: 10, b: 20}, {m: "Feb", a: 30, b: 5}, {m: "Mar", a: 20, b: 40}]';

void main() {
  group('chartFormat', () {
    test(
      'number: grouped with up to two decimals, compact above a million',
      () {
        final f = chartFormat('number', null);
        expect(f(1234.5), '1,234.5');
        expect(f(0), '0');
        expect(f(0.126), '0.13');
        expect(f(-42), '-42');
        expect(f(999999), '999,999');
        expect(f(1234567), '1.23M');
        expect(f(2500000), '2.5M');
        expect(f(1240000000), '1.24B');
      },
    );

    test('number, compact for axis ticks: one decimal from a thousand', () {
      final f = chartFormat(null, null);
      expect(f(999.5, compact: true), '999.5');
      expect(f(1234, compact: true), '1.2K');
      expect(f(2000000, compact: true), '2M');
      expect(f(-1500, compact: true), '-1.5K');
    });

    test('currency: dollars by default, any three-letter code', () {
      final usd = chartFormat('currency', null);
      expect(usd(1234.5), r'$1,234.5');
      expect(usd(7), r'$7');
      expect(usd(1240000000), r'$1.24B');
      expect(usd(2000000000, compact: true), r'$2B');
      expect(usd(1500, compact: true), r'$1.5K');
      expect(usd(950, compact: true), r'$950');
      final eur = chartFormat('currency', 'EUR');
      expect(eur(840), '€840');
      expect(chartFormat('currency', 'eur')(840), '€840');
      expect(
        chartFormat('currency', 'euro')(840),
        r'$840',
        reason: 'not a code, so USD',
      );
      expect(chartFormat('currency', '12')(840), r'$840');
    });

    test(
      'percent: the value with a sign, rounded to two decimals (one for ticks)',
      () {
        final f = chartFormat('percent', null);
        expect(f(45), '45%');
        expect(f(45.678), '45.68%');
        expect(f(45.678, compact: true), '45.7%');
        expect(f(0), '0%');
      },
    );
  });

  group('niceStep', () {
    test('rounds a span up to 1, 2, 2.5, 5 or 10 times a power of ten', () {
      expect(niceStep(0), 1);
      expect(niceStep(-4), 1);
      expect(niceStep(1), 1);
      expect(niceStep(1.5), 2);
      expect(niceStep(2.2), 2.5);
      expect(niceStep(3), 5);
      expect(niceStep(7), 10);
      expect(niceStep(120), 200);
      expect(niceStep(1234), 2000);
      expect(niceStep(0.03), 0.05);
      expect(niceStep(0.2), 0.2);
    });
  });

  group('ChartSpec defaults', () {
    testWidgets(
      'x is the first string key and the series are the other number keys',
      (tester) async {
        final label = await _label(
          tester,
          'Chart("bar", [{n: 1, name: "x", v: 3, w: 4, note: "z"}])',
        );
        expect(label, 'bar chart of n, v, w by name');
      },
    );

    testWidgets('a scatter takes its first number key as x', (tester) async {
      final label = await _label(
        tester,
        'Chart("scatter", [{label: "p", a: 1, b: 2, c: 3}])',
      );
      expect(label, 'scatter chart of b, c by a');
    });

    testWidgets('with no string key x is the first key', (tester) async {
      expect(
        await _label(tester, 'Chart("line", [{a: 1, b: 2}, {a: 2, b: 3}])'),
        'line chart of b by a',
      );
    });

    testWidgets('an unknown x is replaced by the default', (tester) async {
      expect(
        await _label(tester, 'Chart("bar", [{m: "Jan", v: 1}], "nope")'),
        'bar chart of v by m',
      );
    });

    testWidgets(
      'a requested x and series are kept, and non-string series are ignored',
      (tester) async {
        expect(
          await _label(
            tester,
            'Chart("line", [{p: "a", q: "b", u: 1, v: 2, w: 3}], "q", ["w", 5, null, "u"])',
          ),
          'line chart of w, u by q',
        );
      },
    );

    testWidgets('at most eight series are used', (tester) async {
      final label = await _label(
        tester,
        'Chart("bar", [{m: "x", a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10}])',
      );
      expect(label, 'bar chart of a, b, c, d, e, f, g, h by m');
    });

    testWidgets('rows that are not objects are dropped', (tester) async {
      expect(
        await _label(tester, 'Chart("bar", [1, "x", {m: "Jan", v: 1}])'),
        'bar chart of v by m',
      );
    });

    testWidgets('no usable rows leaves an empty 240px space', (tester) async {
      await pumpProgram(tester, 'root = Col([Chart("bar", [])])');
      expect(_plot, findsNothing);
      expect(_pie, findsNothing);
      final box = tester.widget<SizedBox>(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 240 && w.child == null,
        ),
      );
      expect(box.height, 240);
      await pumpProgram(tester, 'root = Col([Chart("bar", [1, 2])])');
      expect(_plot, findsNothing);
    });

    testWidgets('height is 240 by default and clamps to 140..480', (
      tester,
    ) async {
      Future<double> heightOf(String height) async {
        await pumpProgram(
          tester,
          'root = Col([Chart("bar", [{m: "a", v: 1}], null, null, null, null, null, $height)])',
        );
        return _plotHeight(tester);
      }

      await pumpProgram(tester, 'root = Col([Chart("bar", [{m: "a", v: 1}])])');
      expect(_plotHeight(tester), 240);
      expect(await heightOf('300'), 300);
      expect(await heightOf('50'), 140);
      expect(await heightOf('9999'), 480);
      expect(await heightOf('null'), 240);
    });
  });

  group('bar charts', () {
    testWidgets(
      'draw one rounded bar per row and series in the series colors',
      (tester) async {
        await pumpProgram(tester, 'root = Col([Chart("bar", $_rows3)])');
        final bars = _bars(tester);
        expect(bars, hasLength(6));
        expect(
          _plot,
          paints
            ..rrect(color: _light.chart[0])
            ..rrect(color: _light.chart[1]),
        );
      },
    );

    testWidgets('bar heights follow the values, from a common baseline', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a"])])',
      );
      final bars = _bars(tester);
      expect(bars, hasLength(3));
      final heights = [for (final b in bars) b.height];
      expect(heights[1] / heights[0], closeTo(3, 0.05), reason: '30 vs 10');
      expect(heights[2] / heights[0], closeTo(2, 0.05), reason: '20 vs 10');
      expect(
        {for (final b in bars) b.bottom.round()},
        hasLength(1),
        reason: 'same baseline',
      );
      expect(bars[0].left, lessThan(bars[1].left));
    });

    testWidgets('negative values hang below the zero line', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", [{m: "up", v: 10}, {m: "down", v: -10}], "m", ["v"])])',
      );
      final bars = _bars(tester);
      expect(bars[1].top, closeTo(bars[0].bottom, 1));
      expect(bars[1].height, closeTo(bars[0].height, 1));
    });

    testWidgets('stacked bars sit on top of each other', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a", "b"], null, null, true)])',
      );
      final bars = _bars(tester);
      expect(bars, hasLength(6));
      expect(bars[1].bottom, closeTo(bars[0].top, 0.5), reason: 'b rests on a');
      expect(bars[0].left, closeTo(bars[1].left, 0.5));
      expect(
        bars[1].height,
        closeTo(bars[0].height * 2, 1),
        reason: '20 on top of 10',
      );
    });

    testWidgets(
      'side by side bars share a baseline and sit next to each other',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([Chart("bar", $_rows3, "m", ["a", "b"])])',
        );
        final bars = _bars(tester);
        expect(bars[0].bottom, closeTo(bars[1].bottom, 0.5));
        expect(bars[1].left, greaterThan(bars[0].left));
      },
    );

    testWidgets('text values are read as numbers and junk as zero', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", [{m: "a", v: "12"}, {m: "b", v: "oops"}, {m: "c", v: 4}], "m", ["v"])])',
      );
      final heights = [for (final b in _bars(tester)) b.height];
      expect(heights[0], greaterThan(heights[2]));
      expect(
        heights[1],
        lessThan(2),
        reason: 'zero height (at most the 1px minimum)',
      );
    });

    testWidgets(
      'a tap shows the tooltip with the row and its formatted value',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([Chart("bar", $_rows3, "m", ["a"], "currency")])',
        );
        expect(find.text('Feb'), findsNothing);
        await tester.tapAt(_global(tester, _bars(tester)[1].center));
        await tester.pump();
        expect(find.text('Feb'), findsOneWidget);
        expect(find.text(r'$30'), findsOneWidget);
        expect(find.text('Jan'), findsNothing);
      },
    );

    testWidgets(
      'a tooltip lists every series by name, and moving to another bar replaces it',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([Chart("bar", $_rows3, "m", ["a", "b"])])',
        );
        await tester.tapAt(_global(tester, _bars(tester)[0].center));
        await tester.pump();
        expect(find.text('Jan'), findsOneWidget);
        expect(find.text('a'), findsNWidgets(2), reason: 'legend and tooltip');
        expect(find.text('10'), findsOneWidget);
        expect(find.text('20'), findsOneWidget);
        await tester.tapAt(_global(tester, _bars(tester)[4].center));
        await tester.pump();
        expect(find.text('Jan'), findsNothing);
        expect(find.text('Mar'), findsOneWidget);
        expect(find.text('40'), findsOneWidget);
      },
    );

    testWidgets('hovering with a mouse shows it and leaving hides it', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a"])])',
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(_global(tester, _bars(tester)[2].center));
      await tester.pump();
      expect(find.text('Mar'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(find.text('Mar'), findsNothing);
    });

    testWidgets('dragging along the chart follows the pointer', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a"])])',
      );
      final from = _global(tester, _bars(tester)[0].center);
      final gesture = await tester.startGesture(from);
      await gesture.moveBy(const Offset(25, 0));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(find.text('Jan'), findsOneWidget);
      await gesture.moveTo(_global(tester, _bars(tester)[2].center));
      await tester.pump();
      expect(find.text('Mar'), findsOneWidget);
      await gesture.up();
    });

    testWidgets('a tap outside every band shows nothing', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a"])])',
      );
      await tester.tapAt(_global(tester, const Offset(5, 100)));
      await tester.pump();
      for (final m in ['Jan', 'Feb', 'Mar']) {
        expect(find.text(m), findsNothing);
      }
    });

    testWidgets('the legend appears only with two or more series', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a"])])',
      );
      expect(find.text('a'), findsNothing);
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a", "b"])])',
      );
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('dark mode paints with the dark chart colors', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", $_rows3, "m", ["a", "b"])])',
        brightness: Brightness.dark,
      );
      expect(
        _plot,
        paints
          ..rrect(color: OpenUiTheme.dark.chart[0])
          ..rrect(color: OpenUiTheme.dark.chart[1]),
      );
    });

    testWidgets('long labels on many rows are thinned out', (tester) async {
      final rows = [
        for (var i = 0; i < 24; i++) '{m: "Long label number $i", v: $i}',
      ].join(', ');
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", [$rows], "m", ["v"])])',
      );
      final shown = _calls(tester, #drawParagraph).length;
      await pumpProgram(
        tester,
        'root = Col([Chart("bar", [{m: "a", v: 1}, {m: "b", v: 2}], "m", ["v"])])',
      );
      final few = _calls(tester, #drawParagraph).length;
      expect(
        shown,
        lessThan(24 + 6),
        reason: 'not every one of the 24 labels fits',
      );
      expect(few, greaterThanOrEqualTo(2));
    });
  });

  group('line and area charts', () {
    testWidgets('a line is one stroked path per series with a dot per point', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("line", $_rows3, "m", ["a", "b"])])',
      );
      expect(
        _plot,
        paints
          ..path(
            color: _light.chart[0],
            style: PaintingStyle.stroke,
            strokeWidth: _w22,
          )
          ..path(
            color: _light.chart[1],
            style: PaintingStyle.stroke,
            strokeWidth: _w22,
          ),
      );
      expect(
        _dots(tester),
        hasLength(12),
        reason: '3 points x 2 series, each a fill and a ring',
      );
    });

    testWidgets('an area chart also fills under the line with a gradient', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("area", $_rows3, "m", ["a"])])',
      );
      final calls = _calls(tester, #drawPath);
      expect(calls, hasLength(2));
      expect((calls[0].positionalArguments[1] as Paint).shader, isNotNull);
      expect(
        (calls[1].positionalArguments[1] as Paint).style,
        PaintingStyle.stroke,
      );
    });

    testWidgets('a single point draws no area', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("area", [{m: "a", v: 1}], "m", ["v"])])',
      );
      expect(_calls(tester, #drawPath), hasLength(1));
    });

    testWidgets('stacked areas stack, and stacked is ignored for lines', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("area", $_rows3, "m", ["a", "b"], null, null, true)])',
      );
      expect(_calls(tester, #drawPath), hasLength(4));
      await pumpProgram(
        tester,
        'root = Col([Chart("line", $_rows3, "m", ["a", "b"], null, null, true)])',
      );
      final ys = [for (final d in _dots(tester).take(3)) d.dy];
      await pumpProgram(
        tester,
        'root = Col([Chart("line", $_rows3, "m", ["a", "b"])])',
      );
      expect([for (final d in _dots(tester).take(3)) d.dy], ys);
    });

    testWidgets('with more than 16 points only the hovered dots show', (
      tester,
    ) async {
      final rows = [
        for (var i = 0; i < 20; i++) '{m: "$i", v: ${i * 2}}',
      ].join(', ');
      await pumpProgram(
        tester,
        'root = Col([Chart("line", [$rows], "m", ["v"])])',
      );
      expect(_dots(tester), isEmpty);
      final box = tester.renderObject<RenderBox>(_plot);
      await tester.tapAt(box.localToGlobal(Offset(box.size.width * 0.5, 100)));
      await tester.pump();
      expect(_dots(tester), hasLength(2));
    });

    testWidgets(
      'hovering shows the guide line and the tooltip with its formatted value',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([Chart("line", $_rows3, "m", ["a"], "percent")])',
        );
        final lines = _calls(tester, #drawLine).length;
        final dot = _dots(tester)[2];
        await tester.tapAt(_global(tester, dot));
        await tester.pump();
        expect(find.text('Feb'), findsOneWidget);
        expect(find.text('30%'), findsOneWidget);
        expect(
          _calls(tester, #drawLine).length,
          greaterThan(lines),
          reason: 'vertical guide',
        );
        expect(_dots(tester), hasLength(6));
      },
    );
  });

  group('scatter charts', () {
    const data =
        '[{name: "Ann", h: 150, w: 50}, {name: "Bo", h: 170, w: 70}, {name: "Cy", h: 190, w: 90}]';

    testWidgets('draw a dot per point and series, with a canvas-colored ring', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Chart("scatter", $data)])');
      expect(_dots(tester), hasLength(6));
      expect(
        _plot,
        paints..circle(color: _light.chart[0].withValues(alpha: 0.78)),
      );
    });

    testWidgets('dot positions rise with y and move right with x', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Chart("scatter", $data)])');
      final dots = _dots(tester).where((d) => true).toList();
      final points = [dots[0], dots[2], dots[4]];
      expect(points[1].dx, greaterThan(points[0].dx));
      expect(points[2].dx, greaterThan(points[1].dx));
      expect(points[1].dy, lessThan(points[0].dy));
      expect(points[2].dy, lessThan(points[1].dy));
    });

    testWidgets(
      'a tap near a point shows the row name, its x and its formatted value',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([Chart("scatter", $data, "h", ["w"], "currency")])',
        );
        await tester.tapAt(_global(tester, _dots(tester)[2]));
        await tester.pump();
        expect(find.text('Bo'), findsOneWidget);
        expect(find.text('170'), findsOneWidget);
        expect(find.text(r'$70'), findsOneWidget);
        expect(find.text('h'), findsOneWidget);
        expect(find.text('w'), findsOneWidget);
      },
    );

    testWidgets('a tap far from every point shows nothing', (tester) async {
      await pumpProgram(tester, 'root = Col([Chart("scatter", $data)])');
      await tester.tapAt(_global(tester, const Offset(2, 2)));
      await tester.pump();
      expect(find.text('Ann'), findsNothing);
      expect(find.text('Bo'), findsNothing);
    });

    testWidgets('a row without a name titles the tooltip with the series', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("scatter", [{x: 1, y: 2}, {x: 3, y: 5}])])',
      );
      await tester.tapAt(_global(tester, _dots(tester)[0]));
      await tester.pump();
      expect(find.text('y'), findsNWidgets(2), reason: 'title and value line');
    });

    testWidgets('large x values and several series draw with a legend', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("scatter", [{n: "a", x: 20000, p: 1, q: 3}, {n: "b", x: 90000, p: 2, q: 1}], "x", ["p", "q"])])',
      );
      expect(_dots(tester), hasLength(8));
      expect(find.text('p'), findsOneWidget);
      expect(find.text('q'), findsOneWidget);
    });

    testWidgets('hovering a scatter dot makes it larger', (tester) async {
      await pumpProgram(tester, 'root = Col([Chart("scatter", $data)])');
      final before = _calls(
        tester,
        #drawCircle,
      ).map((c) => c.positionalArguments[1] as double).toSet();
      await tester.tapAt(_global(tester, _dots(tester)[0]));
      await tester.pump();
      final after = _calls(
        tester,
        #drawCircle,
      ).map((c) => c.positionalArguments[1] as double).toSet();
      expect(before, {5.0});
      expect(after, containsAll([5.0, 6.5]));
    });

    testWidgets('a constant series still gets an axis', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("scatter", [{x: 1, y: 5}, {x: 1, y: 5}])])',
      );
      expect(_dots(tester), hasLength(4));
      await pumpProgram(
        tester,
        'root = Col([Chart("scatter", [{x: 0, y: 0}])])',
      );
      expect(_dots(tester), hasLength(2));
    });
  });

  group('pie and donut charts', () {
    const pieProgram =
        'root = Col([Chart("pie", [{mode: "Walking", share: 52}, {mode: "Transit", share: 31}, {mode: "Cycling", share: 17}], "mode", ["share"], "percent")])';

    testWidgets('a legend lists each slice with its share of the total', (
      tester,
    ) async {
      await pumpProgram(tester, pieProgram);
      for (final t in ['Walking', 'Transit', 'Cycling', '52%', '31%', '17%']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(_plot, findsNothing);
    });

    testWidgets(
      'slices are painted in the chart colors and outlined in the canvas color',
      (tester) async {
        await pumpProgram(tester, pieProgram);
        expect(_pathColors(tester, finder: _pie), [
          _light.chart[0].toARGB32(),
          _light.canvas.toARGB32(),
          _light.chart[1].toARGB32(),
          _light.canvas.toARGB32(),
          _light.chart[2].toARGB32(),
          _light.canvas.toARGB32(),
        ]);
      },
    );

    testWidgets('a donut leaves a hole and rounds shares to one decimal', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("donut", [{item: "Lodging", amount: 840}, {item: "Food", amount: 420}, {item: "Transport", amount: 260}, {item: "Museums", amount: 90}], "item", ["amount"], "currency", "EUR")])',
      );
      for (final t in ['52.2%', '26.1%', '16.1%', '5.6%']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(_pathColors(tester, finder: _pie), [
        for (var i = 0; i < 4; i++) ...[
          _light.chart[i].toARGB32(),
          _light.canvas.toARGB32(),
        ],
      ]);
    });

    testWidgets('a single slice is a full circle, ring or disc', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("pie", [{k: "All", v: 5}], "k", ["v"])])',
      );
      expect(find.text('100%'), findsOneWidget);
      expect(
        _calls(tester, #drawPath, finder: _pie),
        hasLength(1),
        reason: 'no outline for a full circle',
      );
      await pumpProgram(
        tester,
        'root = Col([Chart("donut", [{k: "All", v: 5}], "k", ["v"])])',
      );
      expect(find.text('100%'), findsOneWidget);
      expect(_calls(tester, #drawPath, finder: _pie), hasLength(1));
    });

    testWidgets('zeros, negatives and junk count as nothing', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("pie", [{k: "a", v: 0}, {k: "b", v: -3}, {k: "c", v: "x"}], "k", ["v"])])',
      );
      expect(find.text('0%'), findsNWidgets(3));
      await pumpProgram(
        tester,
        'root = Col([Chart("pie", [{k: "a", v: 1}, {k: "b"}], "k", ["v"])])',
      );
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });

    testWidgets('a pie without a number column shows 0% for every row', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Chart("pie", [{k: "a"}, {k: "b"}], "k", [])])',
      );
      expect(find.text('0%'), findsNWidgets(2));
    });

    testWidgets('on a wide screen the pie sits left of its legend', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpProgram(tester, pieProgram);
      final pie = tester.getTopLeft(_pie);
      final legend = tester.getTopLeft(find.text('Walking'));
      expect(legend.dx, greaterThan(pie.dx + 100));
      expect(tester.getSize(_pie), const Size(200, 200));
    });

    testWidgets('on a narrow screen the legend sits under the pie', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(300, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpProgram(tester, pieProgram);
      expect(
        tester.getTopLeft(find.text('Walking')).dy,
        greaterThan(tester.getBottomLeft(_pie).dy),
      );
      expect(tester.getSize(_pie).width, closeTo((300 - 32) * 0.62, 1));
    });
  });

  group('gallery chart program', () {
    testWidgets(
      'renders the stacked bar chart, its legend, a pie and a donut',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final p = await pumpProgram(tester, galleryProgram('chart'));
        expect(p.session.issues, isEmpty);
        expect(find.text('Drone services revenue'), findsOneWidget);
        expect(find.text('Photography'), findsOneWidget);
        expect(find.text('Inspection'), findsOneWidget);
        expect(find.text('Walking'), findsOneWidget);
        expect(find.text('Lodging'), findsOneWidget);
        expect(_bars(tester), hasLength(8));
        expect(_pie, findsNWidgets(2));
      },
    );

    testWidgets(
      'a tap on a bar shows the currency values, and the control switches type',
      (tester) async {
        tester.view.physicalSize = const Size(1170, 2532);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final p = await pumpProgram(tester, galleryProgram('chart'));
        await tester.tapAt(_global(tester, _bars(tester)[4].center));
        await tester.pump();
        expect(find.text('2030'), findsOneWidget);
        expect(find.text(r'$1.24B'), findsOneWidget);
        expect(find.text(r'$1.31B'), findsOneWidget);

        await tester.tap(find.text('line'));
        await tester.pump();
        expect(p.session.state[r'$type'], 'line');
        expect(_calls(tester, #drawRRect), isEmpty);
        expect(
          _plot,
          paints..path(
            color: _light.chart[0],
            style: PaintingStyle.stroke,
            strokeWidth: _w22,
          ),
        );

        await tester.tap(find.text('area'));
        await tester.pump();
        expect(
          _calls(tester, #drawPath),
          hasLength(4),
          reason: 'two fills and two lines, stacked',
        );
      },
    );

    testWidgets('dark mode renders too', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpProgram(
        tester,
        galleryProgram('chart'),
        brightness: Brightness.dark,
      );
      expect(_plot, paints..rrect(color: OpenUiTheme.dark.chart[0]));
    });
  });
}
