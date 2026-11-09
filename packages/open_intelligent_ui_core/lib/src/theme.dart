import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'css_color.dart';

Color _alpha(Color c, double opacity) => c.withValues(alpha: c.a * opacity);

const _statusNames = ['info', 'success', 'warning', 'danger', 'purple', 'pink'];

/// Corner radii. The defaults are the reference's values.
@immutable
final class OpenUiRadii {
  const OpenUiRadii({
    this.sm = 6,
    this.md = 10,
    this.lg = 12,
    this.xl = 14,
    this.xxl = 20,
    this.full = 999,
  });

  final double sm, md, lg, xl, xxl, full;
}

/// Spacing steps in px. The defaults are the reference's values.
@immutable
final class OpenUiSpacing {
  const OpenUiSpacing({
    this.unit = 4,
    this.tight = 4,
    this.inner = 8,
    this.group = 12,
    this.groupLarge = 16,
    this.section = 24,
    this.controlGap = 8,
    this.fieldGap = 24,
    this.actionGap = 40,
  });

  /// The base step that `spaceOf` multiplies model values by.
  final double unit;
  final double tight,
      inner,
      group,
      groupLarge,
      section,
      controlGap,
      fieldGap,
      actionGap;
}

/// A text size: its font size, line height and letter spacing, and the size
/// used on compact (phone-width) layouts.
@immutable
final class OpenUiTextSize {
  const OpenUiTextSize(
    this.fontSize,
    this.height, {
    this.letterSpacing = 0,
    double? compactFontSize,
  }) : compactFontSize = compactFontSize ?? fontSize;

  final double fontSize, height, letterSpacing, compactFontSize;
}

/// The Text sizes by name, as the reference sets them.
const Map<String, OpenUiTextSize> referenceTextSizes = {
  'xs': OpenUiTextSize(12, 1.6),
  'sm': OpenUiTextSize(14, 1.55),
  'md': OpenUiTextSize(16, 1.6),
  'lg': OpenUiTextSize(18, 1.55),
};

/// The Title sizes by name, as the reference sets them.
const Map<String, OpenUiTextSize> referenceTitleSizes = {
  'sm': OpenUiTextSize(15, 1.5),
  'md': OpenUiTextSize(17, 1.4, letterSpacing: -0.2),
  'lg': OpenUiTextSize(21, 1.3, letterSpacing: -0.55, compactFontSize: 19),
  'xl': OpenUiTextSize(25, 1.2, letterSpacing: -0.8),
  '2xl': OpenUiTextSize(32, 1.15, letterSpacing: -1, compactFontSize: 28),
  '3xl': OpenUiTextSize(40, 1.1, letterSpacing: -1.4, compactFontSize: 34),
};

/// Type: a [scale] for every built-in font size, the Text and Title metrics,
/// the three font weights, whether numbers use tabular figures, and whether
/// all text does ([tabularNums]).
@immutable
final class OpenUiTypography {
  const OpenUiTypography({
    this.scale = 1,
    this.text = referenceTextSizes,
    this.title = referenceTitleSizes,
    this.normal = const FontWeight(440),
    this.medium = const FontWeight(560),
    this.semibold = const FontWeight(640),
    this.tabularFigures = true,
    this.tabularNums = false,
  });

  final double scale;
  final Map<String, OpenUiTextSize> text, title;
  final FontWeight normal, medium, semibold;
  final bool tabularFigures;

  /// Tabular figures on all text, as if every Text set `tabularNums`, so
  /// every number lines up.
  final bool tabularNums;

  /// [px] scaled by [scale].
  double size(double px) => px * scale;

  List<FontFeature>? get tabular =>
      tabularFigures ? const [FontFeature.tabularFigures()] : null;

  /// [tabular] when [tabularNums] is set, else null.
  List<FontFeature>? get allText => tabularNums ? tabular : null;
}

/// A restyle of one component: any null field keeps the built-in value.
@immutable
final class OpenUiComponentStyle {
  const OpenUiComponentStyle({
    this.background,
    this.foreground,
    this.border,
    this.radius,
    this.padding,
    this.fontSize,
    this.size,
  });

  final Color? background, foreground, border;
  final double? radius;
  final EdgeInsetsGeometry? padding;

  /// The text size in px, before [OpenUiTypography.scale].
  final double? fontSize;

  /// The fixed or minimum extent: a checkbox's box, a round button's
  /// diameter, a field's minimum height.
  final double? size;

  /// This style with [other]'s non-null fields on top.
  OpenUiComponentStyle merge(OpenUiComponentStyle? other) {
    if (other == null) return this;
    return OpenUiComponentStyle(
      background: other.background ?? background,
      foreground: other.foreground ?? foreground,
      border: other.border ?? border,
      radius: other.radius ?? radius,
      padding: other.padding ?? padding,
      fontSize: other.fontSize ?? fontSize,
      size: other.size ?? size,
    );
  }
}

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
    Color? onTone,
    Color? checkInk,
    Color? chevron,
    List<BoxShadow>? floatShadow,
    this.inkOnLight = const Color(0xFF0D0D0D),
    this.inkOnDark = const Color(0xFFFFFFFF),
    this.radii = const OpenUiRadii(),
    this.spacing = const OpenUiSpacing(),
    this.typography = const OpenUiTypography(),
    this.components = const {},
    this.fontFamily,
    String? monoFontFamily,
  }) : faint = faint ?? muted,
       _onTone = onTone,
       _checkInk = checkInk,
       _chevron = chevron,
       _floatShadow = floatShadow,
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
  final Color? _onTone, _checkInk, _chevron;
  final List<BoxShadow>? _floatShadow;

  /// Text and icons on a solid `danger` or `success` button; [onInk] when
  /// unset.
  Color get onTone => _onTone ?? onInk;

  /// The check on a selected Pressable's [ink] dot; [onInk] when unset.
  Color get checkInk => _checkInk ?? onInk;

  /// Select's chevron; [muted] when unset.
  Color get chevron => _chevron ?? muted;

  /// The shadow under floating controls such as Carousel's arrows;
  /// [shadowSmall] when unset.
  List<BoxShadow> get floatShadow => _floatShadow ?? shadowSmall;

  /// Ink for content on a light model-written background (see [inkOn]).
  final Color inkOnLight;

  /// Ink for content on a dark model-written background (see [inkOn]).
  final Color inkOnDark;

  final OpenUiRadii radii;
  final OpenUiSpacing spacing;
  final OpenUiTypography typography;

  /// Per-component styles keyed `Card`, `Card.soft`, `Button.outline`, ...
  final Map<String, OpenUiComponentStyle> components;

  /// The text font. Null uses the font of the text style around the view,
  /// or the platform font; the open_intelligent_ui package supplies Inter
  /// through `OpenUiServices.fontFamily`.
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

  /// Selected text behind a text field's cursor.
  Color get selection => _alpha(ink, 0.2);

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
    onTone: const Color(0xFFFFFFFF),
    checkInk: const Color(0xFFFFFFFF),
    chevron: const Color(0xFF676767),
    floatShadow: _floatShadowDefault,
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
    onTone: const Color(0xFF121212),
    checkInk: const Color(0xFF171717),
    chevron: const Color(0xFFABABAB),
    floatShadow: _floatShadowDefault,
  );

  static const _floatShadowDefault = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 2)),
  ];

  /// The nearest [OpenUiThemeScope]'s theme, else the Material theme's
  /// extension, else the light or dark tokens for the app's brightness.
  static OpenUiTheme of(BuildContext context) {
    final scoped = context
        .dependOnInheritedWidgetOfExactType<OpenUiThemeScope>()
        ?.theme;
    if (scoped != null) return scoped;
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
    return luminance > 0.36 ? inkOnLight : inkOnDark;
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

  /// The token set for a host's [ColorScheme]: the reference's chart, badge,
  /// map and shadow tokens, with the surface and text colors from [scheme].
  factory OpenUiTheme.fromColorScheme(
    ColorScheme scheme, {
    String? fontFamily,
  }) {
    final base = scheme.brightness == Brightness.dark ? dark : light;
    return OpenUiTheme(
      brightness: base.brightness,
      canvas: scheme.surface,
      ink: scheme.onSurface,
      onInk: scheme.surface,
      muted: scheme.onSurface.withValues(alpha: 0.6),
      status: {
        ...base.status,
        'info': scheme.onSurface,
        'danger': scheme.error,
      },
      statusSoft: {
        ...base.statusSoft,
        'info': scheme.onSurface.withValues(alpha: 0.06),
        'danger': scheme.errorContainer,
      },
      badge: base.badge,
      badgeSoft: base.badgeSoft,
      chart: base.chart,
      mapWater: base.mapWater,
      glass: scheme.surface.withValues(alpha: 0.7),
      glassHover: scheme.surface.withValues(alpha: 0.85),
      glassRing: base.glassRing,
      glassRingHover: base.glassRingHover,
      shadow: base.shadow,
      shadowSmall: base.shadowSmall,
      fontFamily: fontFamily,
    );
  }

  /// [fromColorScheme] with the font family of [theme]'s body text.
  factory OpenUiTheme.fromMaterial(ThemeData theme) =>
      OpenUiTheme.fromColorScheme(
        theme.colorScheme,
        fontFamily: theme.textTheme.bodyMedium?.fontFamily,
      );

  /// The style for [component], with the `'$component.$variant'` style on top.
  OpenUiComponentStyle styleOf(String component, [String? variant]) {
    final base = components[component] ?? const OpenUiComponentStyle();
    return base.merge(
      variant == null ? null : components['$component.$variant'],
    );
  }

  /// The font size for [component] (a component name, or `Name.part` for one
  /// of its parts): its style's fontSize, else [px], scaled.
  double fontSizeOf(String component, double px) =>
      typography.size(components[component]?.fontSize ?? px);

  /// A radius from a name (`sm`..`xl`, `full`) or a CSS length, as [radius]
  /// with this theme's radii.
  double? radiusOf(Object? value) => switch (value) {
    'sm' => radii.sm,
    'md' => radii.md,
    'lg' => radii.lg,
    'xl' => radii.xl,
    'full' => radii.full,
    _ => length(value).px,
  };

  /// A model spacing value in [spacing.unit] steps, as [space] in 4px steps.
  double? spaceOf(Object? value) {
    if (value is! num || !value.isFinite) return null;
    final space = math.max(0.0, value.toDouble()) * spacing.unit;
    return space.isFinite ? space : null;
  }

  /// These tokens with the given ones replaced. [onTone] and [checkInk]
  /// follow a new [onInk], [chevron] a new [muted], and [floatShadow] a new
  /// [shadowSmall], unless they are given too.
  @override
  OpenUiTheme copyWith({
    Brightness? brightness,
    Color? canvas,
    Color? ink,
    Color? onInk,
    Color? muted,
    Color? faint,
    Map<String, Color>? status,
    Map<String, Color>? statusSoft,
    Map<String, Color>? badge,
    Map<String, Color>? badgeSoft,
    List<Color>? chart,
    Color? mapWater,
    Color? glass,
    Color? glassHover,
    Color? glassRing,
    Color? glassRingHover,
    List<BoxShadow>? shadow,
    List<BoxShadow>? shadowSmall,
    Color? onTone,
    Color? checkInk,
    Color? chevron,
    List<BoxShadow>? floatShadow,
    Color? inkOnLight,
    Color? inkOnDark,
    String? fontFamily,
    String? monoFontFamily,
    OpenUiRadii? radii,
    OpenUiSpacing? spacing,
    OpenUiTypography? typography,
    Map<String, OpenUiComponentStyle>? components,
  }) => OpenUiTheme(
    brightness: brightness ?? this.brightness,
    canvas: canvas ?? this.canvas,
    ink: ink ?? this.ink,
    onInk: onInk ?? this.onInk,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    status: status ?? this.status,
    statusSoft: statusSoft ?? this.statusSoft,
    badge: badge ?? this.badge,
    badgeSoft: badgeSoft ?? this.badgeSoft,
    chart: chart ?? this.chart,
    mapWater: mapWater ?? this.mapWater,
    glass: glass ?? this.glass,
    glassHover: glassHover ?? this.glassHover,
    glassRing: glassRing ?? this.glassRing,
    glassRingHover: glassRingHover ?? this.glassRingHover,
    shadow: shadow ?? this.shadow,
    shadowSmall: shadowSmall ?? this.shadowSmall,
    onTone: onTone ?? (onInk == null ? _onTone : null),
    checkInk: checkInk ?? (onInk == null ? _checkInk : null),
    chevron: chevron ?? (muted == null ? _chevron : null),
    floatShadow: floatShadow ?? (shadowSmall == null ? _floatShadow : null),
    inkOnLight: inkOnLight ?? this.inkOnLight,
    inkOnDark: inkOnDark ?? this.inkOnDark,
    fontFamily: fontFamily ?? this.fontFamily,
    monoFontFamily: monoFontFamily ?? _monoFontFamily,
    radii: radii ?? this.radii,
    spacing: spacing ?? this.spacing,
    typography: typography ?? this.typography,
    components: components ?? this.components,
  );

  @override
  OpenUiTheme lerp(covariant OpenUiTheme? other, double t) {
    if (other == null) return this;
    if (t == 0) return this;
    if (t == 1) return other;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    Map<String, Color> m(Map<String, Color> a, Map<String, Color> b) => {
      for (final k in {...a.keys, ...b.keys})
        k: a[k] != null && b[k] != null ? c(a[k]!, b[k]!) : (a[k] ?? b[k]!),
    };
    final chartLength = math.max(chart.length, other.chart.length);
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
      chart: List.generate(chartLength, (i) {
        if (i >= chart.length) return other.chart[i];
        if (i >= other.chart.length) return chart[i];
        return c(chart[i], other.chart[i]);
      }),
      mapWater: c(mapWater, other.mapWater),
      glass: c(glass, other.glass),
      glassHover: c(glassHover, other.glassHover),
      glassRing: c(glassRing, other.glassRing),
      glassRingHover: c(glassRingHover, other.glassRingHover),
      shadow: BoxShadow.lerpList(shadow, other.shadow, t) ?? shadow,
      shadowSmall:
          BoxShadow.lerpList(shadowSmall, other.shadowSmall, t) ?? shadowSmall,
      onTone: c(onTone, other.onTone),
      checkInk: c(checkInk, other.checkInk),
      chevron: c(chevron, other.chevron),
      floatShadow:
          BoxShadow.lerpList(floatShadow, other.floatShadow, t) ?? floatShadow,
      inkOnLight: c(inkOnLight, other.inkOnLight),
      inkOnDark: c(inkOnDark, other.inkOnDark),
      fontFamily: t < 0.5 ? fontFamily : other.fontFamily,
      monoFontFamily: t < 0.5 ? _monoFontFamily : other._monoFontFamily,
      radii: t < 0.5 ? radii : other.radii,
      spacing: t < 0.5 ? spacing : other.spacing,
      typography: t < 0.5 ? typography : other.typography,
      components: t < 0.5 ? components : other.components,
    );
  }
}

/// Provides an [OpenUiTheme] to the views and components below it, with no
/// Material [Theme] needed. It wins over a Material theme extension, and like
/// `OpenUiScope` it reaches into routes such as date pickers and menus.
class OpenUiThemeScope extends InheritedTheme {
  const OpenUiThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });
  final OpenUiTheme theme;

  @override
  bool updateShouldNotify(OpenUiThemeScope old) => !identical(theme, old.theme);

  @override
  Widget wrap(BuildContext context, Widget child) =>
      OpenUiThemeScope(theme: theme, child: child);
}
