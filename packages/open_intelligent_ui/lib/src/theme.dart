import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'css_color.dart';

Color _alpha(Color c, double opacity) => c.withValues(alpha: c.a * opacity);

const _statusNames = ['info', 'success', 'warning', 'danger', 'purple', 'pink'];

/// The reference's `theme.css` tokens, light and dark, plus the helpers that
/// turn model-written colors, lengths, radii and spacing into Flutter values.
@immutable
final class OpenUiTheme extends ThemeExtension<OpenUiTheme> {
  const OpenUiTheme({
    required this.brightness,
    required this.canvas,
    required this.ink,
    required this.onInk,
    required this.muted,
    Color? faint,
    required this.status,
    required this.statusSoft,
    required this.badge,
    required this.badgeSoft,
    required this.chart,
    required this.mapWater,
    required this.glass,
    required this.glassHover,
    required this.glassRing,
    required this.glassRingHover,
    required this.shadow,
    required this.shadowSmall,
    this.fontFamily = 'packages/open_intelligent_ui/Inter',
    String? monoFontFamily,
  }) : faint = faint ?? muted,
       _monoFontFamily = monoFontFamily;

  final Brightness brightness;
  final Color canvas;
  final Color ink;
  final Color onInk;
  final Color muted;
  final Color faint;

  /// `info`, `success`, `warning`, `danger`, `purple`, `pink`.
  final Map<String, Color> status;
  final Map<String, Color> statusSoft;

  /// Badge text and tint per status (no `info`: it is the neutral pill).
  final Map<String, Color> badge;
  final Map<String, Color> badgeSoft;

  /// `chart1` to `chart6`.
  final List<Color> chart;
  final Color mapWater;
  final Color glass;
  final Color glassHover;
  final Color glassRing;
  final Color glassRingHover;
  final List<BoxShadow> shadow;
  final List<BoxShadow> shadowSmall;
  final String? fontFamily;
  final String? _monoFontFamily;

  /// Code and monospace text: the platform's mono face when none is set.
  String get monoFontFamily =>
      _monoFontFamily ??
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
        TargetPlatform.windows => 'Consolas',
        _ => 'monospace',
      };

  Color get hover => _alpha(ink, 0.05);
  Color get pressed => _alpha(ink, 0.08);
  Color get surface => _alpha(ink, 0.04);
  Color get surfaceHover => _alpha(ink, 0.08);
  Color get surfaceStrong => _alpha(ink, 0.08);
  Color get border => _alpha(ink, 0.08);
  Color get borderStrong => _alpha(ink, 0.10);
  Color get rangeTrack => _alpha(ink, 0.06);
  Color get badgeNeutralSoft => _alpha(ink, 0.06);
  Color get inkHover => mixColors(ink, 0.82, canvas, space: 'oklch');

  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 12.0;
  static const radiusXl = 14.0;
  static const radius2xl = 20.0;
  static const spaceTight = 4.0;
  static const spaceInner = 8.0;
  static const spaceGroup = 12.0;
  static const spaceGroupLarge = 16.0;
  static const spaceSection = 24.0;
  static const controlGap = 8.0;
  static const fieldGap = 24.0;
  static const actionGap = 40.0;

  /// The reference's Inter weights. With the variable font a [FontWeight] of
  /// any value sets the `wght` axis, so these render exactly.
  static const weightNormal = FontWeight(440);
  static const weightMedium = FontWeight(560);
  static const weightSemibold = FontWeight(640);

  static final OpenUiTheme light = OpenUiTheme(
    brightness: Brightness.light,
    canvas: const Color(0xFFFDFDFD),
    ink: const Color(0xFF030303),
    onInk: const Color(0xFFFDFDFD),
    muted: const Color(0x99030303),
    status: const {
      'info': Color(0xFF030303),
      'success': Color(0xFF00805D),
      'warning': Color(0xFF8A5300),
      'danger': Color(0xFFC1322C),
      'purple': Color(0xFF7040C1),
      'pink': Color(0xFFB7377C),
    },
    statusSoft: const {
      'info': Color(0x0F030303),
      'success': Color(0xFFEDF9F2),
      'warning': Color(0xFFFFEFC7),
      'danger': Color(0xFFFFF0EE),
      'purple': Color(0xFFF4F0FF),
      'pink': Color(0xFFFFF0F6),
    },
    badge: const {
      'success': Color(0xFF1F6B4F),
      'warning': Color(0xFF8A5300),
      'danger': Color(0xFF9F3A33),
      'purple': Color(0xFF5D4596),
      'pink': Color(0xFF94456D),
    },
    badgeSoft: const {
      'success': Color(0xFFE8F3EC),
      'warning': Color(0xFFFFEFC7),
      'danger': Color(0xFFF8E8E5),
      'purple': Color(0xFFEFEBF7),
      'pink': Color(0xFFF7EAF1),
    },
    chart: const [
      Color(0xFF0285FF),
      Color(0xFF00A67D),
      Color(0xFF8B5CF6),
      Color(0xFFF4A340),
      Color(0xFFE46D91),
      Color(0xFF4B9CA6),
    ],
    mapWater: const Color(0xFFA9DFF0),
    glass: const Color(0xB3FDFDFD),
    glassHover: const Color(0xD9FDFDFD),
    glassRing: const Color(0xB3FFFFFF),
    glassRingHover: const Color(0xD9FFFFFF),
    shadow: const [
      BoxShadow(color: Color(0x0F000000), blurRadius: 20, offset: Offset(0, 4)),
    ],
    shadowSmall: const [
      BoxShadow(color: Color(0x0D000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  static final OpenUiTheme dark = OpenUiTheme(
    brightness: Brightness.dark,
    canvas: const Color(0xFF171717),
    ink: const Color(0xFFFAFAFA),
    onInk: const Color(0xFF171717),
    muted: const Color(0x99FAFAFA),
    status: const {
      'info': Color(0xFFFAFAFA),
      'success': Color(0xFF5BCF9C),
      'warning': Color(0xFFF0B84F),
      'danger': Color(0xFFFF7D74),
      'purple': Color(0xFFB49CFF),
      'pink': Color(0xFFF28CC0),
    },
    statusSoft: const {
      'info': Color(0x0FFAFAFA),
      'success': Color(0xFF13291F),
      'warning': Color(0xFF30250F),
      'danger': Color(0xFF3A1B19),
      'purple': Color(0xFF261F3A),
      'pink': Color(0xFF371B2A),
    },
    badge: const {
      'success': Color(0xFF8FD3B2),
      'warning': Color(0xFFE6C27C),
      'danger': Color(0xFFF0A39B),
      'purple': Color(0xFFC3B2F0),
      'pink': Color(0xFFEEAACB),
    },
    badgeSoft: const {
      'success': Color(0x2450B482),
      'warning': Color(0x24DCAA50),
      'danger': Color(0x24E66E64),
      'purple': Color(0x24A082F0),
      'pink': Color(0x24E682B4),
    },
    chart: const [
      Color(0xFF3D9DFF),
      Color(0xFF22BF91),
      Color(0xFFA07CFF),
      Color(0xFFF6AE55),
      Color(0xFFEC84A3),
      Color(0xFF5FB3BD),
    ],
    mapWater: const Color(0xFF1D3540),
    glass: const Color(0xB31C1C1E),
    glassHover: const Color(0xD128282A),
    glassRing: const Color(0x1FFFFFFF),
    glassRingHover: const Color(0x2EFFFFFF),
    shadow: const [
      BoxShadow(color: Color(0x59000000), blurRadius: 20, offset: Offset(0, 4)),
    ],
    shadowSmall: const [
      BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );

  /// The registered extension, else the light or dark tokens for the app's
  /// brightness.
  static OpenUiTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<OpenUiTheme>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  /// A foreground color: a token name (`ink`, `muted`, `faint`, `canvas`,
  /// `surface`, a status, `chart1`..`chart6`) or a CSS color.
  Color? fg(Object? value) {
    if (value is! String) return null;
    return _token(value) ?? parseCssColor(value);
  }

  /// A background color: as [fg], but statuses are soft tints, and
  /// `surface-strong` and `border` are allowed. A gradient is [bgGradient].
  Color? bg(Object? value) {
    if (value is! String) return null;
    if (_statusNames.contains(value)) return statusSoft[value];
    return switch (value) {
      'surface-strong' => surfaceStrong,
      'border' => border,
      _ => _token(value) ?? parseCssColor(value),
    };
  }

  /// A background gradient: a CSS `linear-gradient()` or `radial-gradient()`,
  /// plain or `repeating-`, which the reference's `bg` passes to CSS as is.
  Gradient? bgGradient(Object? value) =>
      value is String ? parseCssGradient(value) : null;

  Color? _token(String value) {
    if (status[value] case final c?) return c;
    final chartIndex = RegExp(r'^chart([1-6])$').firstMatch(value);
    if (chartIndex != null) return chart[int.parse(chartIndex.group(1)!) - 1];
    return switch (value) {
      'ink' => ink,
      'muted' => muted,
      'faint' => faint,
      'canvas' => canvas,
      'surface' => surface,
      _ => null,
    };
  }

  /// Ink for content on a model-written hex or `rgb()` background, or null.
  /// The reference's `contrastOn` reads only `#rgb`, `#rrggbb` and an
  /// `rgb()`/`rgba()` that starts with three integers; other colours keep the
  /// theme ink.
  Color? inkOn(Object? background) {
    if (background is! String || _isToken(background)) return null;
    final s = background.trim();
    List<double>? rgb;
    final hex = RegExp(
      r'^#([\da-f]{3}|[\da-f]{6})$',
      caseSensitive: false,
    ).firstMatch(s);
    if (hex != null) {
      var h = hex.group(1)!;
      if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
      rgb = [
        for (final i in [0, 2, 4])
          int.parse(h.substring(i, i + 2), radix: 16).toDouble(),
      ];
    } else {
      final m = RegExp(
        r'^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)',
        caseSensitive: false,
      ).firstMatch(s);
      if (m != null) {
        rgb = [for (var i = 1; i <= 3; i++) double.parse(m.group(i)!)];
      }
    }
    if (rgb == null) return null;
    double channel(double c) {
      final v = c / 255;
      return v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final luminance =
        0.2126 * channel(rgb[0]) +
        0.7152 * channel(rgb[1]) +
        0.0722 * channel(rgb[2]);
    return luminance > 0.36 ? const Color(0xFF0D0D0D) : const Color(0xFFFFFFFF);
  }

  bool _isToken(String value) =>
      _token(value) != null || value == 'surface-strong' || value == 'border';

  /// These tokens with [ink] replaced, for content on a raw-color background.
  OpenUiTheme withInk(Color ink) =>
      copyWith(ink: ink, muted: _alpha(ink, 0.72), faint: _alpha(ink, 0.55));

  /// Spacing counted in 4px steps.
  static double? space(Object? value) {
    if (value is! num || !value.isFinite) return null;
    final space = math.max(0.0, value.toDouble()) * 4;
    return space.isFinite ? space : null;
  }

  /// A CSS length. Percent lengths come back as fractions in [fraction];
  /// `em`, `rem`, `vh` and `vw` resolve against [fontSize] and [viewport].
  static ({double? px, double? fraction}) length(
    Object? value, {
    double fontSize = 16,
    Size? viewport,
  }) {
    if (value is num && value.isFinite) {
      return (px: math.max(0, value.toDouble()), fraction: null);
    }
    if (value is! String) return (px: null, fraction: null);
    final m = RegExp(
      r'^(\d+(?:\.\d+)?)(px|%|em|rem|vh|vw|fr)?$',
    ).firstMatch(value.trim());
    if (m == null) return (px: null, fraction: null);
    final n = double.parse(m.group(1)!);
    if (!n.isFinite) return (px: null, fraction: null);
    final px = switch (m.group(2)) {
      null || 'px' => n,
      'em' => n * fontSize,
      'rem' => n * 16,
      'vh' when viewport != null => n / 100 * viewport.height,
      'vw' when viewport != null => n / 100 * viewport.width,
      _ => null,
    };
    if (m.group(2) == '%') return (px: null, fraction: n / 100);
    return (px: px != null && px.isFinite ? px : null, fraction: null);
  }

  /// `sm`, `md`, `lg`, `xl`, `full` or px.
  static double? radius(Object? value) => switch (value) {
    'sm' => radiusSm,
    'md' => radiusMd,
    'lg' => radiusLg,
    'xl' => radiusXl,
    'full' => 999,
    _ => length(value).px,
  };

  @override
  OpenUiTheme copyWith({
    Color? canvas,
    Color? ink,
    Color? onInk,
    Color? muted,
    Color? faint,
    String? fontFamily,
  }) => OpenUiTheme(
    brightness: brightness,
    canvas: canvas ?? this.canvas,
    ink: ink ?? this.ink,
    onInk: onInk ?? this.onInk,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    status: status,
    statusSoft: statusSoft,
    badge: badge,
    badgeSoft: badgeSoft,
    chart: chart,
    mapWater: mapWater,
    glass: glass,
    glassHover: glassHover,
    glassRing: glassRing,
    glassRingHover: glassRingHover,
    shadow: shadow,
    shadowSmall: shadowSmall,
    fontFamily: fontFamily ?? this.fontFamily,
    monoFontFamily: _monoFontFamily,
  );

  @override
  OpenUiTheme lerp(covariant OpenUiTheme? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    Map<String, Color> m(Map<String, Color> a, Map<String, Color> b) => {
      for (final k in a.keys) k: c(a[k]!, b[k] ?? a[k]!),
    };
    return OpenUiTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      canvas: c(canvas, other.canvas),
      ink: c(ink, other.ink),
      onInk: c(onInk, other.onInk),
      muted: c(muted, other.muted),
      faint: c(faint, other.faint),
      status: m(status, other.status),
      statusSoft: m(statusSoft, other.statusSoft),
      badge: m(badge, other.badge),
      badgeSoft: m(badgeSoft, other.badgeSoft),
      chart: [
        for (var i = 0; i < chart.length; i++) c(chart[i], other.chart[i]),
      ],
      mapWater: c(mapWater, other.mapWater),
      glass: c(glass, other.glass),
      glassHover: c(glassHover, other.glassHover),
      glassRing: c(glassRing, other.glassRing),
      glassRingHover: c(glassRingHover, other.glassRingHover),
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? shadow,
      shadowSmall:
          BoxShadow.lerpList(shadowSmall, other.shadowSmall, t) ?? shadowSmall,
      fontFamily: t < 0.5 ? fontFamily : other.fontFamily,
      monoFontFamily: t < 0.5 ? _monoFontFamily : other._monoFontFamily,
    );
  }
}
