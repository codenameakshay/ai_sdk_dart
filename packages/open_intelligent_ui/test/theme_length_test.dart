import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

void main() {
  test('length resolves CSS units like style.ts', () {
    const viewport = Size(400, 800);
    expect(OpenUiTheme.length('24'), (px: 24.0, fraction: null));
    expect(OpenUiTheme.length('24px'), (px: 24.0, fraction: null));
    expect(OpenUiTheme.length('50%'), (px: null, fraction: 0.5));
    expect(OpenUiTheme.length('2em', fontSize: 14), (px: 28.0, fraction: null));
    expect(OpenUiTheme.length('2rem', fontSize: 14), (
      px: 32.0,
      fraction: null,
    ));
    expect(OpenUiTheme.length('25vh', viewport: viewport), (
      px: 200.0,
      fraction: null,
    ));
    expect(OpenUiTheme.length('25vw', viewport: viewport), (
      px: 100.0,
      fraction: null,
    ));
    expect(OpenUiTheme.length('25vw'), (px: null, fraction: null));
    expect(OpenUiTheme.length('1fr'), (px: null, fraction: null));
    expect(OpenUiTheme.length('auto'), (px: null, fraction: null));
  });

  test('glass ring hover follows theme.css in both schemes', () {
    expect(OpenUiTheme.light.glassRingHover, const Color(0xD9FFFFFF));
    expect(OpenUiTheme.dark.glassRingHover, const Color(0x2EFFFFFF));
  });
}
