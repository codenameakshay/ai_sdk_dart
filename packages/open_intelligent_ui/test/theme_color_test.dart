import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/css_color.dart';

void expectColor(Color? actual, int argb, {double tolerance = 1.5}) {
  expect(actual, isNotNull);
  final c = actual!;
  expect(c.a, closeTo(((argb >> 24) & 0xFF) / 255, tolerance / 255));
  expect(c.r, closeTo(((argb >> 16) & 0xFF) / 255, tolerance / 255));
  expect(c.g, closeTo(((argb >> 8) & 0xFF) / 255, tolerance / 255));
  expect(c.b, closeTo((argb & 0xFF) / 255, tolerance / 255));
}

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

  test('text uses the bundled Inter font by default', () {
    expect(OpenUiTheme.light.fontFamily, 'packages/open_intelligent_ui/Inter');
  });
}
