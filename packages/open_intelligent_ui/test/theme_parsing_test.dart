import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/css_color.dart';

void main() {
  test('CSS colors reject non-finite channels and hues', () {
    for (final value in [
      'rgb(NaN 0 0)',
      'rgb(1e309 0 0)',
      'rgba(0 0 0 / 1e309)',
      'hsl(1e309 100% 50%)',
      'hsl(0 1e309% 50%)',
    ]) {
      expect(parseCssColor(value), isNull, reason: value);
    }
  });

  test('length and spacing reject numeric overflow', () {
    final overflowing = List.filled(400, '9').join();
    expect(OpenUiTheme.length('${overflowing}px'), (px: null, fraction: null));
    expect(OpenUiTheme.length('$overflowing%'), (px: null, fraction: null));
    expect(OpenUiTheme.space(1e308), isNull);
  });
}
