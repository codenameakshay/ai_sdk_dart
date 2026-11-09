// ignore_for_file: implementation_imports
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/src/css_color.dart';

import 'support/pump.dart';

void expectColor(Color? actual, int argb, {double tolerance = 1.5}) {
  expect(actual, isNotNull);
  final c = actual!;
  expect(c.a, closeTo(((argb >> 24) & 0xFF) / 255, tolerance / 255));
  expect(c.r, closeTo(((argb >> 16) & 0xFF) / 255, tolerance / 255));
  expect(c.g, closeTo(((argb >> 8) & 0xFF) / 255, tolerance / 255));
  expect(c.b, closeTo((argb & 0xFF) / 255, tolerance / 255));
}

/// Paints [css] as a [width] by [height] box background and reads pixels.
Future<List<int> Function(int x, int y)> _paintGradient(
  WidgetTester tester,
  String css, {
  double width = 100,
  double height = 50,
}) async {
  const key = Key('gradient');
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: parseCssGradient(css)),
          ),
        ),
      ),
    ),
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
  ))!;
  return (x, y) => [
    for (var k = 0; k < 4; k++) bytes.getUint8((y * image.width + x) * 4 + k),
  ];
}

Matcher _pixel(int r, int g, int b, [int a = 255]) => predicate<List<int>>(
  (p) =>
      (p[0] - r).abs() <= 4 &&
      (p[1] - g).abs() <= 4 &&
      (p[2] - b).abs() <= 4 &&
      (p[3] - a).abs() <= 4,
  'rgba($r, $g, $b, $a)',
);

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('oklch and oklab parse to the sRGB colour they describe', () {
    expectColor(parseCssColor('oklch(0.7 0.15 30)'), 0xFFED7665);
    expectColor(parseCssColor('oklch(62.8% 0.2577 29.23)'), 0xFFFF0000);
    expectColor(parseCssColor('oklab(0.5 0.1 -0.1)'), 0xFF81459A);
    expect(parseCssColor('oklch(0.7 0.15 30 / 50%)')!.a, closeTo(0.5, 0.001));
  });

  test('hwb mixes white and black into a hue, or greys out when they fill', () {
    expectColor(parseCssColor('hwb(120 20% 30%)'), 0xFF33B333);
    expectColor(parseCssColor('hwb(0 60% 60%)'), 0xFF808080);
  });

  test('color-mix blends in srgb and oklch', () {
    expectColor(parseCssColor('color-mix(in srgb, red 50%, blue)'), 0xFF800080);
    expectColor(
      parseCssColor('color-mix(in oklch, red, blue)'),
      0xFFBA00C2,
      tolerance: 2,
    );
  });

  test('color-mix with transparent keeps the colour and lowers its alpha', () {
    final c = parseCssColor('color-mix(in srgb, #000 8%, transparent)')!;
    expect(c.a, closeTo(0.08, 0.001));
    expect(c.r, closeTo(0, 0.001));
    expect(c.g, closeTo(0, 0.001));
    expect(c.b, closeTo(0, 0.001));
  });

  test('color-mix scales alpha when its percentages sum below 100', () {
    expect(
      parseCssColor('color-mix(in srgb, red 30%, blue 30%)')!.a,
      closeTo(0.6, 0.001),
    );
  });

  test('color-mix accepts a nested color-mix as an operand', () {
    expect(
      parseCssColor('color-mix(in srgb, color-mix(in srgb, red, blue), white)'),
      isNotNull,
    );
  });

  test('color-mix in an unsupported colour space is rejected', () {
    expect(parseCssColor('color-mix(in lab, red, blue)'), isNull);
  });

  test('currentColor and var() are not parsed as colours', () {
    expect(parseCssColor('currentColor'), isNull);
    expect(parseCssColor('var(--x)'), isNull);
  });

  test('inkHover is the ink mixed toward the canvas in oklch', () {
    expectColor(OpenUiTheme.light.inkHover, 0xFF242424);
    expectColor(OpenUiTheme.dark.inkHover, 0xFFCCCCCC);
  });

  test('withInk softens muted and faint text from the new ink', () {
    final themed = OpenUiTheme.light.withInk(const Color(0xFFFFFFFF));
    expect(themed.muted.a, closeTo(0.72, 0.001));
    expect(themed.faint.a, closeTo(0.55, 0.001));
  });

  test('faint is the muted colour unless the theme sets it', () {
    expect(OpenUiTheme.light.faint, OpenUiTheme.light.muted);
  });

  test('glass ring hover follows theme.css in both schemes', () {
    expect(OpenUiTheme.light.glassRingHover, const Color(0xD9FFFFFF));
    expect(OpenUiTheme.dark.glassRingHover, const Color(0x2EFFFFFF));
  });

  test('length resolves em, rem, vh and vw against the given sizes', () {
    const viewport = Size(400, 800);
    expect(OpenUiTheme.length('2em', fontSize: 15).px, 30);
    expect(OpenUiTheme.length('1.5rem').px, 24);
    expect(OpenUiTheme.length('50vh', viewport: viewport).px, 400);
    expect(OpenUiTheme.length('10vw', viewport: viewport).px, 40);
    expect(OpenUiTheme.length('50vh').px, isNull);
    expect(OpenUiTheme.length('1fr').px, isNull);
    expect(OpenUiTheme.length('auto').px, isNull);
  });

  test('monospace text uses Menlo on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(OpenUiTheme.light.monoFontFamily, 'Menlo');
  });

  testWidgets('text uses the bundled Inter font by default', (tester) async {
    await pumpProgram(tester, 'root = Text("plain")');
    final text = tester.renderObject<RenderParagraph>(find.text('plain'));
    expect(text.text.style?.fontFamily, 'packages/open_intelligent_ui/Inter');
  });

  test(
    'inkOn reads only hex and integer rgb() backgrounds, as contrastOn does',
    () {
      final t = OpenUiTheme.light;
      expect(t.inkOn(' #FFF '), const Color(0xFF0D0D0D));
      expect(t.inkOn('RGB(0, 0, 0)'), const Color(0xFFFFFFFF));
      expect(t.inkOn('rgb(255 255 255 / 50%)'), const Color(0xFF0D0D0D));
      expect(t.inkOn('rgba(300, 300, 300, 0.1)'), const Color(0xFF0D0D0D));
      for (final raw in [
        'transparent',
        'navy',
        'hsl(0, 0%, 100%)',
        '#ffff',
        '#ffffffff',
        'rgb(10.5, 20, 30)',
        'rgb(100%, 0%, 0%)',
        'linear-gradient(#fff, #000)',
        'surface',
      ]) {
        expect(t.inkOn(raw), isNull, reason: raw);
      }
    },
  );

  test('bgGradient takes CSS gradients only', () {
    final t = OpenUiTheme.light;
    expect(t.bgGradient('linear-gradient(red, blue)'), isA<CssGradient>());
    expect(t.bgGradient('#fff'), isNull);
    expect(t.bgGradient('surface'), isNull);
    expect(t.bgGradient(3), isNull);
  });

  group('CSS gradients', () {
    testWidgets('to right runs from the left edge to the right edge', (
      tester,
    ) async {
      final px = await _paintGradient(
        tester,
        'linear-gradient(to right, #ff0000, #0000ff)',
      );
      expect(px(0, 25), _pixel(254, 0, 1));
      expect(px(50, 25), _pixel(126, 0, 129));
      expect(px(99, 25), _pixel(1, 0, 254));
    });

    testWidgets(
      'to a corner puts the middle on the other diagonal, as CSS does',
      (tester) async {
        final px = await _paintGradient(
          tester,
          'linear-gradient(to top right, #ff0000 50%, #0000ff 50%)',
          width: 200,
        );
        expect(px(20, 2), _pixel(0, 0, 255));
        expect(px(180, 48), _pixel(255, 0, 0));
      },
    );

    testWidgets('px stops and repeating gradients', (tester) async {
      var px = await _paintGradient(
        tester,
        'linear-gradient(90deg, #ff0000 20px, #0000ff 20px)',
      );
      expect(px(10, 25), _pixel(255, 0, 0));
      expect(px(30, 25), _pixel(0, 0, 255));
      px = await _paintGradient(
        tester,
        'repeating-linear-gradient(90deg, #ff0000 0 10px, #0000ff 10px 20px)',
      );
      expect(px(5, 25), _pixel(255, 0, 0));
      expect(px(15, 25), _pixel(0, 0, 255));
      expect(px(25, 25), _pixel(255, 0, 0));
      expect(px(35, 25), _pixel(0, 0, 255));
    });

    testWidgets('a transparent stop fades the neighbour colour, not black', (
      tester,
    ) async {
      final px = await _paintGradient(
        tester,
        'linear-gradient(90deg, #ff0000, transparent)',
      );
      expect(px(50, 25), _pixel(255, 0, 0, 126));
    });

    testWidgets('radial circles and ellipses size from the box', (
      tester,
    ) async {
      var px = await _paintGradient(
        tester,
        'radial-gradient(circle closest-side, #ff0000, #0000ff)',
      );
      expect(px(50, 25), _pixel(248, 0, 7));
      expect(px(50, 0), _pixel(5, 0, 250));
      expect(px(95, 25), _pixel(0, 0, 255));
      px = await _paintGradient(tester, 'radial-gradient(#ff0000, #0000ff)');
      expect(px(85, 25), _pixel(127, 0, 128));
      expect(px(50, 42), _pixel(128, 0, 126));
    });

    test('parses the forms the reference passes through and nothing else', () {
      for (final css in [
        'linear-gradient(red, blue)',
        'linear-gradient(0.25turn, red 10%, blue)',
        'linear-gradient(1rad, 10% red, blue 20px 30px)',
        'linear-gradient(100grad, red, blue)',
        'linear-gradient(0, red, blue)',
        'linear-gradient(to left top, red, blue)',
        'linear-gradient(to bottom, red, blue)',
        'radial-gradient(circle at top left, red, blue)',
        'radial-gradient(farthest-side at 20% 30px, red, blue)',
        'radial-gradient(ellipse closest-corner, red, blue)',
        'radial-gradient(circle farthest-corner at right, red, blue)',
        'radial-gradient(10px 20%, red, blue)',
        'repeating-radial-gradient(circle 20px at bottom, red, blue)',
        'LINEAR-GRADIENT(RED, BLUE)',
        'linear-gradient(rgb(0 0 0 / 50%), hsl(0 100% 50%))',
      ]) {
        expect(parseCssGradient(css), isNotNull, reason: css);
      }
      for (final css in [
        'linear-gradient(red, 30%, blue)',
        'conic-gradient(red, blue)',
        'linear-gradient(red)',
        'linear-gradient(red, blue), #fff',
        'linear-gradient(red, blue), linear-gradient(red, blue)',
        'linear-gradient(to middle, red, blue)',
        'linear-gradient(45deg, var(--x), blue)',
        'linear-gradient(in oklab, red, blue)',
        'radial-gradient(ellipse 20px, red, blue)',
        'radial-gradient(circle 10%, red, blue)',
        'radial-gradient(circle circle, red, blue)',
        'radial-gradient(at 1px 2px 3px, red, blue)',
        'red',
      ]) {
        expect(parseCssGradient(css), isNull, reason: css);
      }
    });

    test(
      'equal sources give equal gradients, and scale and opacity fade them',
      () {
        final g = parseCssGradient('linear-gradient(red, blue)')!;
        expect(g, parseCssGradient(' linear-gradient(red,  blue) '));
        expect(
          g.hashCode,
          parseCssGradient('linear-gradient(red, blue)').hashCode,
        );
        expect(g, isNot(parseCssGradient('linear-gradient(blue, red)')));
        expect(g.scale(0.5).colors.first.a, closeTo(0.5, 0.01));
        expect(g.withOpacity(0.25).colors.last.a, closeTo(0.25, 0.01));
      },
    );
  });
}
