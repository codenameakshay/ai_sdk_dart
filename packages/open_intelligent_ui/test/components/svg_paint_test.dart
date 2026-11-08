import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/svg.dart';

import '../support/pump.dart';

final _light = OpenUiTheme.light;

Finder get _scene => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is SvgScenePainter,
);

RenderBox _box(WidgetTester tester) =>
    tester.renderObject<RenderBox>(_scene.first);

Future<void> _svg(WidgetTester tester, String shapes) =>
    pumpProgram(tester, 'root = Col([Svg([$shapes], "0 0 100 100")])');

Color _ink(WidgetTester tester) =>
    DefaultTextStyle.of(tester.element(_scene.first)).style.color ?? _light.ink;

void main() {
  group('Svg paint', () {
    testWidgets('SvgText with currentColor paints its text', (tester) async {
      await _svg(tester, 'SvgText("Hi", 10, 10, null, "currentColor")');
      expect(_box(tester), paints..paragraph());
    });

    testWidgets('SvgText with an oklch fill paints without an exception', (
      tester,
    ) async {
      await _svg(tester, 'SvgText("Hi", 10, 10, null, "oklch(0.7 0.15 30)")');
      expect(tester.takeException(), isNull);
      expect(_box(tester), paints..paragraph());
    });

    testWidgets('SvgText with an unknown fill paints in the text color', (
      tester,
    ) async {
      await _svg(tester, 'SvgText("Hi", 10, 10, null, "nonsense")');
      expect(tester.takeException(), isNull);
      expect(_box(tester), paints..paragraph());
    });

    testWidgets('a path with currentColor fill is filled in the text color', (
      tester,
    ) async {
      await _svg(tester, 'Path("M 10 10 L 90 10 L 50 90 Z", "currentColor")');
      expect(
        _box(tester),
        paints..path(color: _ink(tester), style: PaintingStyle.fill),
      );
    });

    testWidgets('the scene is not clipped to its box', (tester) async {
      await _svg(tester, 'Circle(50, 50, 500)');
      expect(_box(tester), isNot(paints..clipRect()));
    });

    testWidgets('a shape with opacity draws at full alpha inside a layer', (
      tester,
    ) async {
      await _svg(tester, 'Circle(50, 50, 20, "red", null, null, 0.5)');
      expect(
        _box(tester),
        paints
          ..something((m, a) => m == #saveLayer)
          ..path(color: const Color(0xFFFF0000)),
      );
    });

    testWidgets('a group with opacity draws its children inside a layer', (
      tester,
    ) async {
      await _svg(tester, 'G([Circle(50, 50, 20, "red")], null, 0.5)');
      expect(
        _box(tester),
        paints
          ..something((m, a) => m == #saveLayer)
          ..path(color: const Color(0xFFFF0000)),
      );
    });

    testWidgets('a shape with fill and stroke shares one opacity layer', (
      tester,
    ) async {
      await _svg(tester, 'Circle(50, 50, 20, "red", "blue", 4, 0.5)');
      expect(
        _box(tester),
        paints
          ..something((m, a) => m == #saveLayer)
          ..path(color: const Color(0xFFFF0000), style: PaintingStyle.fill)
          ..path(
            color: const Color(0xFF0000FF),
            style: PaintingStyle.stroke,
            strokeWidth: 4,
          ),
      );
      expect(
        _box(tester),
        isNot(
          paints
            ..something((m, a) => m == #saveLayer)
            ..something((m, a) => m == #saveLayer),
        ),
      );
    });

    testWidgets('an Svg is capped at the available width at phone width', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpProgram(
        tester,
        'root = Col([Svg([Circle(50, 50, 10)], "0 0 100 100", 600)])',
      );
      expect(tester.getSize(_scene).width, 368);
    });
  });
}
