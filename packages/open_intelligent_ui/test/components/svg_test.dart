import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/svg.dart';

import '../gallery_fixture.dart';
import '../support/pump.dart';

final _light = OpenUiTheme.light;

Finder get _scene => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is SvgScenePainter,
);

RenderBox _box(WidgetTester tester, [int index = 0]) =>
    tester.renderObject<RenderBox>(_scene.at(index));

Size _size(WidgetTester tester, [int index = 0]) =>
    tester.getSize(_scene.at(index));

Future<void> _svg(
  WidgetTester tester,
  String shapes, {
  String box = '0 0 100 100',
  String extra = '',
}) => pumpProgram(tester, 'root = Col([Svg([$shapes], "$box"$extra)])');

/// The text color the Svg inherits from the surrounding DefaultTextStyle.
Color _ink(WidgetTester tester) =>
    DefaultTextStyle.of(tester.element(_scene.first)).style.color ?? _light.ink;

Offset _apply(Matrix4 m, Offset p) => MatrixUtils.transformPoint(m, p);

Matcher _near(Offset o) =>
    predicate<Offset>((p) => (p - o).distance < 1e-6, 'is near $o');

void main() {
  group('parseTransform', () {
    test('translate with one or two arguments', () {
      expect(
        _apply(parseTransform('translate(10)')!, Offset.zero),
        _near(const Offset(10, 0)),
      );
      expect(
        _apply(parseTransform('translate(10, 20)')!, Offset.zero),
        _near(const Offset(10, 20)),
      );
      expect(
        _apply(parseTransform('translate(10 -5)')!, const Offset(1, 1)),
        _near(const Offset(11, -4)),
      );
    });

    test('rotate about the origin and about a center', () {
      expect(
        _apply(parseTransform('rotate(90)')!, const Offset(1, 0)),
        _near(const Offset(0, 1)),
      );
      expect(
        _apply(parseTransform('rotate(180 50 50)')!, const Offset(60, 50)),
        _near(const Offset(40, 50)),
      );
      expect(
        _apply(parseTransform('rotate(90 10 10)')!, const Offset(10, 10)),
        _near(const Offset(10, 10)),
        reason: 'the center stays put',
      );
    });

    test('scale with one or two arguments', () {
      expect(
        _apply(parseTransform('scale(2)')!, const Offset(3, 4)),
        _near(const Offset(6, 8)),
      );
      expect(
        _apply(parseTransform('scale(2, 3)')!, const Offset(3, 4)),
        _near(const Offset(6, 12)),
      );
    });

    test('skewX and skewY shear by the angle', () {
      expect(
        _apply(parseTransform('skewX(45)')!, const Offset(0, 10)),
        _near(const Offset(10, 10)),
      );
      expect(
        _apply(parseTransform('skewY(45)')!, const Offset(10, 0)),
        _near(const Offset(10, 10)),
      );
    });

    test('matrix(a b c d e f) maps x = ax + cy + e and y = bx + dy + f', () {
      final m = parseTransform('matrix(1 2 3 4 5 6)')!;
      expect(_apply(m, const Offset(1, 1)), _near(const Offset(9, 12)));
    });

    test('a list applies left to right, like SVG', () {
      final m = parseTransform('translate(10, 0) scale(2)')!;
      expect(_apply(m, const Offset(1, 1)), _near(const Offset(12, 2)));
      final n = parseTransform('scale(2) translate(10, 0)')!;
      expect(_apply(n, const Offset(1, 1)), _near(const Offset(22, 2)));
    });

    test('bad argument counts are rejected', () {
      for (final bad in [
        'translate()',
        'translate(1, 2, 3)',
        'rotate(1, 2)',
        'rotate(1 2 3 4)',
        'scale(1 2 3)',
        'skewX(1 2)',
        'skewY()',
        'matrix(1 2 3 4 5)',
        'matrix(1 2 3 4 5 6 7)',
      ]) {
        expect(parseTransform(bad), isNull, reason: bad);
      }
    });

    test('garbage, unknown functions and non-finite numbers are rejected', () {
      for (final bad in [
        '',
        'nonsense',
        'rotate(a)',
        'translate(1, x)',
        'spin(10)',
        'rotate(10) junk',
        'junk rotate(10)',
        'translate(1e999)',
        'rotate((1))',
        'url(#x)',
      ]) {
        expect(parseTransform(bad), isNull, reason: bad);
      }
      expect(parseTransform(5), isNull);
      expect(parseTransform(null), isNull);
      expect(
        parseTransform('translate(${'1' * 600})'),
        isNull,
        reason: 'too long',
      );
    });
  });

  group('Svg sizing', () {
    // A Col stretches the box to the column width, so the width asserted here is
    // the one the height is derived from: height == width * viewBox ratio.
    testWidgets(
      'scales to the available width, capped at 1.5x the viewBox width (min 280)',
      (tester) async {
        await _svg(tester, 'Circle(10, 10, 5)', box: '0 0 320 160');
        expect(_size(tester).height, 240, reason: '480 wide');
      },
    );

    testWidgets('a small viewBox still gets 280 wide', (tester) async {
      await _svg(tester, 'Circle(10, 10, 5)', box: '0 0 100 50');
      expect(_size(tester).height, 140, reason: '280 wide');
    });

    testWidgets('a wide viewBox fills the available width', (tester) async {
      await _svg(tester, 'Circle(10, 10, 5)', box: '0 0 2000 1000');
      expect(_size(tester).height, 384, reason: '768 wide');
    });

    testWidgets('width as px or percent, and height as px', (tester) async {
      await _svg(
        tester,
        'Circle(10, 10, 5)',
        box: '0 0 100 50',
        extra: ', 200',
      );
      expect(_size(tester).height, 100);
      await _svg(
        tester,
        'Circle(10, 10, 5)',
        box: '0 0 100 50',
        extra: ', "50%"',
      );
      expect(_size(tester).height, 192);
      await _svg(
        tester,
        'Circle(10, 10, 5)',
        box: '0 0 100 50',
        extra: ', 200, 40',
      );
      expect(_size(tester).height, 40);
    });

    testWidgets('an explicit width is not capped by the viewBox', (
      tester,
    ) async {
      await _svg(
        tester,
        'Circle(10, 10, 5)',
        box: '0 0 100 100',
        extra: ', 600',
      );
      expect(_size(tester).height, 600);
    });

    testWidgets('a bad viewBox falls back to 0 0 100 100', (tester) async {
      await _svg(tester, 'Circle(10, 10, 5)', box: 'not a box');
      expect(_size(tester).height, 280);
      final painter =
          tester.widget<CustomPaint>(_scene).painter as SvgScenePainter;
      expect(painter.viewBox, const Rect.fromLTWH(0, 0, 100, 100));
    });

    testWidgets('a viewBox with commas and a negative origin is read', (
      tester,
    ) async {
      await _svg(tester, 'Circle(0, 0, 5)', box: '-50,-50,100,100');
      final painter =
          tester.widget<CustomPaint>(_scene).painter as SvgScenePainter;
      expect(painter.viewBox, const Rect.fromLTWH(-50, -50, 100, 100));
    });

    testWidgets('a zero-size viewBox draws nothing and does not crash', (
      tester,
    ) async {
      await _svg(tester, 'Circle(10, 10, 5)', box: '0 0 0 0');
      expect(_size(tester).height, 768, reason: 'square at the column width');
      expect(_box(tester), isNot(paints..path()));
    });

    testWidgets('an Svg in a Carousel lays out', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Carousel([Svg([Circle(10, 10, 5)], "0 0 100 100")], 300)])',
      );
      expect(tester.takeException(), isNull);
      expect(_scene, findsOneWidget);
    });

    testWidgets('an explicit width and the cap are honored', (tester) async {
      await _svg(
        tester,
        'Circle(10, 10, 5)',
        box: '0 0 100 50',
        extra: ', 200',
      );
      expect(_size(tester), const Size(200, 100));
      await _svg(tester, 'Circle(10, 10, 5)', box: '0 0 320 160');
      expect(_size(tester), const Size(480, 240));
    });

    testWidgets('is announced as an image', (tester) async {
      final handle = tester.ensureSemantics();
      await _svg(tester, 'Circle(10, 10, 5)');
      expect(
        tester.getSemantics(
          find.ancestor(of: _scene, matching: find.byType(Semantics)).first,
        ),
        isSemantics(isImage: true),
      );
      handle.dispose();
    });
  });

  group('shapes outside an Svg', () {
    testWidgets('render nothing', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Text("only"), Circle(1, 1, 1), Ellipse(1, 1, 1, 1), Rect(0, 0, 1, 1), Line(0, 0, 1, 1), '
        'Path("M 0 0 L 1 1"), Polyline("0,0 1,1"), Polygon("0,0 1,1 2,0"), G([Circle(1, 1, 1)]), SvgText("hi", 0, 0)])',
      );
      expect(find.text('hi'), findsNothing);
      expect(_scene, findsNothing);
      for (final name in [
        'Circle',
        'Ellipse',
        'Rect',
        'Line',
        'Path',
        'Polyline',
        'Polygon',
        'G',
        'SvgText',
      ]) {
        final views = find.byWidgetPredicate(
          (w) => w is OpenUiElementView && w.element.typeName == name,
        );
        if (views.evaluate().isNotEmpty) {
          expect(tester.getSize(views.first).height, 0, reason: name);
        }
      }
    });
  });

  group('shapes inside an Svg paint', () {
    testWidgets('a circle with a token fill', (tester) async {
      await _svg(tester, 'Circle(50, 50, 20, "danger")');
      expect(
        _box(tester),
        paints..path(color: _light.status['danger'], style: PaintingStyle.fill),
      );
    });

    testWidgets(
      'filled shapes default to the text color; a stroke alone leaves them unfilled',
      (tester) async {
        await _svg(
          tester,
          'Rect(10, 10, 30, 20), Rect(50, 10, 30, 20, null, "success", 3)',
        );
        expect(
          _box(tester),
          paints
            ..path(color: _ink(tester), style: PaintingStyle.fill)
            ..path(
              color: _light.status['success'],
              style: PaintingStyle.stroke,
              strokeWidth: 3,
            ),
        );
      },
    );

    testWidgets('fill and stroke together draw both', (tester) async {
      await _svg(tester, 'Ellipse(50, 50, 30, 10, "info", "danger", 4)');
      expect(
        _box(tester),
        paints
          ..path(color: _light.status['info'], style: PaintingStyle.fill)
          ..path(
            color: _light.status['danger'],
            style: PaintingStyle.stroke,
            strokeWidth: 4,
          ),
      );
    });

    testWidgets(
      'a line strokes in the text color, 2 wide, and a zero stroke draws nothing',
      (tester) async {
        await _svg(tester, 'Line(10, 10, 90, 90)');
        expect(
          _box(tester),
          paints..path(
            color: _ink(tester),
            style: PaintingStyle.stroke,
            strokeWidth: 2,
          ),
        );
        await _svg(tester, 'Line(10, 10, 90, 90, "info", 0)');
        expect(_box(tester), isNot(paints..path()));
      },
    );

    testWidgets('opacity draws the shape in a layer', (tester) async {
      await _svg(tester, 'Circle(50, 50, 20, "#ff0000", null, null, 0.5)');
      expect(
        _box(tester),
        paints
          ..something((m, a) => m == #saveLayer)
          ..path(color: const Color(0xFFFF0000)),
      );
    });

    testWidgets('a group draws its children in its opacity layer', (
      tester,
    ) async {
      await _svg(
        tester,
        'G([Circle(50, 50, 20, "#ff0000", null, null, 0.5)], null, 0.5)',
      );
      expect(
        _box(tester),
        paints
          ..something((m, a) => m == #saveLayer)
          ..path(color: const Color(0xFFFF0000)),
      );
    });

    testWidgets('a polygon fills, and a polyline strokes without a fill', (
      tester,
    ) async {
      await _svg(
        tester,
        'Polygon("10,10 90,10 50,90", "warning"), Polyline("10,90 50,50 90,90", "danger", 3)',
      );
      expect(
        _box(tester),
        paints
          ..path(color: _light.status['warning'], style: PaintingStyle.fill)
          ..path(
            color: _light.status['danger'],
            style: PaintingStyle.stroke,
            strokeWidth: 3,
          ),
      );
    });

    testWidgets('a path with a stroke and no fill is only stroked', (
      tester,
    ) async {
      await _svg(tester, 'Path("M 10 10 L 90 10 L 50 90 Z", null, "faint", 2)');
      expect(
        _box(tester),
        paints..path(
          color: _light.muted,
          style: PaintingStyle.stroke,
          strokeWidth: 2,
        ),
      );
    });

    testWidgets('a path with a fill is filled', (tester) async {
      await _svg(tester, 'Path("M 10 10 L 90 10 L 50 90 Z", "chart2")');
      expect(
        _box(tester),
        paints..path(color: _light.chart[1], style: PaintingStyle.fill),
      );
    });

    testWidgets('a bad path, bad points and a bad path command are skipped', (
      tester,
    ) async {
      await _svg(
        tester,
        'Path("M 0 0 <script>"), Path("M 0 0 L"), Polygon("a,b c,d"), Polyline("1,2 x"), Circle(50, 50, 10)',
      );
      expect(_box(tester), paints..path(color: _ink(tester)));
      final painter =
          tester.widget<CustomPaint>(_scene).painter as SvgScenePainter;
      expect(painter.scene, hasLength(1));
    });

    testWidgets(
      'a rect with rx draws a rounded outline and a negative size is treated as 0',
      (tester) async {
        await _svg(
          tester,
          'Rect(10, 10, 80, 40, "info", null, null, null, 8), Rect(0, 0, -5, -5), Circle(5, 5, -3)',
        );
        expect(_box(tester), paints..path(color: _light.status['info']));
      },
    );

    testWidgets('a group with a transform moves its children', (tester) async {
      await _svg(tester, 'G([Circle(0, 0, 5)], "translate(50 50)")');
      expect(
        _box(tester),
        paints
          ..transform()
          ..path(),
      );
    });

    testWidgets(
      'a group with a bad transform draws its children untransformed',
      (tester) async {
        await _svg(tester, 'G([Circle(50, 50, 5)], "rotate(oops)")');
        final recorded = _box(tester);
        expect(recorded, paints..path());
        expect(recorded, isNot(paints..transform()));
      },
    );

    testWidgets('text draws at its position with the anchor, size and weight', (
      tester,
    ) async {
      await _svg(
        tester,
        'SvgText("Hello", 50, 50, 14, "danger", "middle", "semibold"), SvgText("Plain", 10, 80), SvgText("End", 90, 20, 10, null, "end", "medium")',
      );
      final painter =
          tester.widget<CustomPaint>(_scene).painter as SvgScenePainter;
      expect(painter.scene, hasLength(3));
      expect(
        _box(tester),
        paints
          ..paragraph()
          ..paragraph()
          ..paragraph(),
      );
    });

    testWidgets('the painter repaints when the scene changes', (tester) async {
      await _svg(tester, 'Circle(50, 50, 5)');
      final painter =
          tester.widget<CustomPaint>(_scene).painter as SvgScenePainter;
      expect(painter.shouldRepaint(painter), isTrue);
    });
  });

  group('SvgScenePainter on a recording canvas', () {
    testWidgets('fits the viewBox into the box, centered (xMidYMid meet)', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Svg([Rect(0, 0, 100, 50, "danger")], "0 0 100 50", 200, 200)])',
      );
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter =
          tester.widget<CustomPaint>(_scene).painter as SvgScenePainter;
      painter.paint(canvas, const Size(200, 200));
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(200, 200));
      final bytes = (await tester.runAsync(() => image!.toByteData()))!;
      int pixel(int x, int y) {
        final i = (y * 200 + x) * 4;
        return (bytes.getUint8(i + 3) << 24) |
            (bytes.getUint8(i) << 16) |
            (bytes.getUint8(i + 1) << 8) |
            bytes.getUint8(i + 2);
      }

      final red = _light.status['danger']!.toARGB32();
      expect(pixel(100, 100), red, reason: 'the middle of the rect');
      expect(pixel(100, 30), 0, reason: 'letterbox above the drawing');
      expect(pixel(100, 170), 0, reason: 'letterbox below the drawing');
      expect(pixel(2, 100), red, reason: 'the rect reaches the left edge');
    });
  });

  group('gallery programs', () {
    testWidgets(
      'svg: the crank turns with its slider and the legend shapes draw',
      (tester) async {
        final p = await pumpProgram(tester, galleryProgram('svg'));
        expect(find.text('Turn the crank'), findsOneWidget);
        expect(_scene, findsNWidgets(2));
        expect(p.session.issues, isEmpty);

        final crank =
            tester.widget<CustomPaint>(_scene.at(0)).painter as SvgScenePainter;
        expect(crank.viewBox, const Rect.fromLTWH(0, 0, 320, 160));
        expect(crank.scene, hasLength(4));
        expect(
          _box(tester, 0),
          paints
            ..path()
            ..path()
            ..path()
            ..path()
            ..paragraph(),
        );

        final legend =
            tester.widget<CustomPaint>(_scene.at(1)).painter as SvgScenePainter;
        expect(legend.scene, hasLength(5));
        expect(
          _box(tester, 1),
          paints
            ..something((m, a) => m == #saveLayer)
            ..path(color: _light.status['info']!)
            ..path(color: _light.status['success'])
            ..path(color: _light.status['warning'])
            ..path(
              color: _light.status['danger'],
              style: PaintingStyle.stroke,
              strokeWidth: 3,
            )
            ..paragraph(),
        );

        expect(p.session.state[r'$angle'], 40);
        await tester.drag(find.byType(Slider), const Offset(120, 0));
        await tester.pump();
        expect(p.session.state[r'$angle'], isNot(40));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('example-steps: each step draws, Next swaps the big drawing', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final p = await pumpProgram(tester, galleryProgram('example-steps'));
      expect(p.session.issues, isEmpty);
      expect(find.text('Lay out the parts'), findsWidgets);
      expect(find.text('Step 1 of 4'), findsOneWidget);
      // One large drawing plus the four thumbnails in the strip.
      expect(_scene, findsNWidgets(5));
      final first =
          tester.widget<CustomPaint>(_scene.first).painter as SvgScenePainter;
      expect(first.scene, hasLength(12));
      expect(
        _box(tester, 0),
        paints
          ..path()
          ..path()
          ..path()
          ..path()
          ..path()
          ..path()
          ..path()
          ..path()
          ..path()
          ..path()
          ..paragraph(),
      );

      await tester.tap(find.text('Next step'));
      await tester.pump();
      expect(find.text('Step 2 of 4'), findsOneWidget);
      final second =
          tester.widget<CustomPaint>(_scene.first).painter as SvgScenePainter;
      expect(second.scene, hasLength(10));
      expect(
        _box(tester, 0),
        paints
          ..path()
          ..paragraph(),
      );
    });

    testWidgets('example-steps in dark mode uses the dark tokens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await pumpProgram(
        tester,
        galleryProgram('example-steps'),
        brightness: Brightness.dark,
      );
      expect(
        _box(tester, 0),
        paints
          ..path(color: OpenUiTheme.dark.surface)
          ..path(color: OpenUiTheme.dark.ink, style: PaintingStyle.stroke),
      );
    });
  });
}
