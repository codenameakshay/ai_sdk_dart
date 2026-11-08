import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui_core/src/theme.dart';

void main() {
  group('OpenUiTheme interpolation', () {
    test('interpolates charts when the target palette is longer', () {
      final source = OpenUiTheme.light.copyWith(
        chart: const [Color(0xFF000000)],
      );
      final target = OpenUiTheme.dark.copyWith(
        chart: const [Color(0xFFFFFFFF), Color(0xFF123456), Color(0xFFABCDEF)],
      );

      final middle = source.lerp(target, 0.5);

      expect(middle.chart, hasLength(3));
      expect(
        middle.chart[0],
        Color.lerp(source.chart[0], target.chart[0], 0.5),
      );
      expect(middle.chart[1], target.chart[1]);
      expect(middle.chart[2], target.chart[2]);
    });

    test('interpolates charts when the target palette is shorter', () {
      final source = OpenUiTheme.light.copyWith(
        chart: const [Color(0xFF000000), Color(0xFF123456), Color(0xFFABCDEF)],
      );
      final target = OpenUiTheme.dark.copyWith(
        chart: const [Color(0xFFFFFFFF)],
      );

      final middle = source.lerp(target, 0.5);

      expect(middle.chart, hasLength(3));
      expect(
        middle.chart[0],
        Color.lerp(source.chart[0], target.chart[0], 0.5),
      );
      expect(middle.chart[1], source.chart[1]);
      expect(middle.chart[2], source.chart[2]);
    });

    test('preserves custom map keys and every field at exact endpoints', () {
      final source = OpenUiTheme.light.copyWith(
        status: const {'source-status': Color(0xFF010101)},
        statusSoft: const {'source-status-soft': Color(0xFF020202)},
        badge: const {'source-badge': Color(0xFF030303)},
        badgeSoft: const {'source-badge-soft': Color(0xFF040404)},
        chart: const [Color(0xFF050505)],
      );
      final target = OpenUiTheme.dark.copyWith(
        status: const {'target-status': Color(0xFF111111)},
        statusSoft: const {'target-status-soft': Color(0xFF121212)},
        badge: const {'target-badge': Color(0xFF131313)},
        badgeSoft: const {'target-badge-soft': Color(0xFF141414)},
        chart: const [Color(0xFF151515), Color(0xFF161616)],
      );

      final atStart = source.lerp(target, 0);
      final atEnd = source.lerp(target, 1);

      _expectSameThemeFields(atStart, source);
      _expectSameThemeFields(atEnd, target);
    });

    test('interpolates the union of custom status and badge keys', () {
      final source = OpenUiTheme.light.copyWith(
        status: const {
          'source': Color(0xFF000000),
          'shared': Color(0xFF222222),
        },
        statusSoft: const {'source': Color(0xFF000000)},
        badge: const {'source': Color(0xFF000000)},
        badgeSoft: const {'source': Color(0xFF000000)},
      );
      final target = OpenUiTheme.dark.copyWith(
        status: const {
          'target': Color(0xFFFFFFFF),
          'shared': Color(0xFFEEEEEE),
        },
        statusSoft: const {'target': Color(0xFFFFFFFF)},
        badge: const {'target': Color(0xFFFFFFFF)},
        badgeSoft: const {'target': Color(0xFFFFFFFF)},
      );

      final middle = source.lerp(target, 0.5);

      expect(middle.status.keys, containsAll(['source', 'target', 'shared']));
      expect(middle.status['source'], source.status['source']);
      expect(middle.status['target'], target.status['target']);
      expect(
        middle.status['shared'],
        Color.lerp(source.status['shared'], target.status['shared'], 0.5),
      );
      for (final colors in [
        middle.statusSoft,
        middle.badge,
        middle.badgeSoft,
      ]) {
        expect(colors.keys, containsAll(['source', 'target']));
        expect(colors['source'], const Color(0xFF000000));
        expect(colors['target'], const Color(0xFFFFFFFF));
      }
    });

    test('copyWith preserves every customized field', () {
      final source = OpenUiTheme.light.copyWith(
        canvas: const Color(0xFF010101),
        ink: const Color(0xFF020202),
        onInk: const Color(0xFF030303),
        muted: const Color(0xFF040404),
        faint: const Color(0xFF050505),
        status: const {'custom-status': Color(0xFF060606)},
        statusSoft: const {'custom-status-soft': Color(0xFF070707)},
        badge: const {'custom-badge': Color(0xFF080808)},
        badgeSoft: const {'custom-badge-soft': Color(0xFF090909)},
        chart: const [Color(0xFF0A0A0A), Color(0xFF0B0B0B)],
        mapWater: const Color(0xFF0C0C0C),
        glass: const Color(0xFF0D0D0D),
        glassHover: const Color(0xFF0E0E0E),
        glassRing: const Color(0xFF0F0F0F),
        glassRingHover: const Color(0xFF101010),
        shadow: const [BoxShadow(color: Color(0x11111111))],
        shadowSmall: const [BoxShadow(color: Color(0x22222222))],
        radii: const OpenUiRadii(sm: 1, md: 2, lg: 3, xl: 4, xxl: 5, full: 6),
        spacing: const OpenUiSpacing(
          unit: 2,
          tight: 3,
          inner: 4,
          group: 5,
          groupLarge: 6,
          section: 7,
          controlGap: 8,
          fieldGap: 9,
          actionGap: 10,
        ),
        typography: const OpenUiTypography(
          scale: 1.5,
          text: {'custom': OpenUiTextSize(20, 1.2)},
          title: {'custom': OpenUiTextSize(30, 1.1)},
          normal: FontWeight.w300,
          medium: FontWeight.w500,
          semibold: FontWeight.w700,
          tabularFigures: false,
        ),
        components: const {
          'Card': OpenUiComponentStyle(
            background: Color(0xFF121212),
            foreground: Color(0xFF131313),
            border: Color(0xFF141414),
            radius: 15,
            padding: EdgeInsets.all(16),
          ),
        },
        fontFamily: 'Custom Sans',
        monoFontFamily: 'Custom Mono',
      );

      final copied = source.copyWith(canvas: const Color(0xFF151515));

      expect(copied.canvas, const Color(0xFF151515));
      expect(copied.brightness, source.brightness);
      expect(copied.ink, source.ink);
      expect(copied.onInk, source.onInk);
      expect(copied.muted, source.muted);
      expect(copied.faint, source.faint);
      expect(copied.status, source.status);
      expect(copied.statusSoft, source.statusSoft);
      expect(copied.badge, source.badge);
      expect(copied.badgeSoft, source.badgeSoft);
      expect(copied.chart, source.chart);
      expect(copied.mapWater, source.mapWater);
      expect(copied.glass, source.glass);
      expect(copied.glassHover, source.glassHover);
      expect(copied.glassRing, source.glassRing);
      expect(copied.glassRingHover, source.glassRingHover);
      expect(copied.shadow, source.shadow);
      expect(copied.shadowSmall, source.shadowSmall);
      expect(copied.radii, source.radii);
      expect(copied.spacing, source.spacing);
      expect(copied.typography, source.typography);
      expect(copied.components, source.components);
      expect(copied.fontFamily, source.fontFamily);
      expect(copied.monoFontFamily, source.monoFontFamily);
    });
  });
}

void _expectSameThemeFields(OpenUiTheme actual, OpenUiTheme expected) {
  expect(actual.brightness, expected.brightness);
  expect(actual.canvas, expected.canvas);
  expect(actual.ink, expected.ink);
  expect(actual.onInk, expected.onInk);
  expect(actual.muted, expected.muted);
  expect(actual.faint, expected.faint);
  expect(actual.status, expected.status);
  expect(actual.statusSoft, expected.statusSoft);
  expect(actual.badge, expected.badge);
  expect(actual.badgeSoft, expected.badgeSoft);
  expect(actual.chart, expected.chart);
  expect(actual.mapWater, expected.mapWater);
  expect(actual.glass, expected.glass);
  expect(actual.glassHover, expected.glassHover);
  expect(actual.glassRing, expected.glassRing);
  expect(actual.glassRingHover, expected.glassRingHover);
  expect(actual.shadow, expected.shadow);
  expect(actual.shadowSmall, expected.shadowSmall);
  expect(actual.radii, expected.radii);
  expect(actual.spacing, expected.spacing);
  expect(actual.typography, expected.typography);
  expect(actual.components, expected.components);
  expect(actual.fontFamily, expected.fontFamily);
  expect(actual.monoFontFamily, expected.monoFontFamily);
}
