import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/painting.dart' show Gradient;

/// Parses a CSS color: hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`),
/// `rgb()`/`rgba()`, `hsl()`/`hsla()`, a named color, or `transparent`.
/// Anything else, including `url(...)` or `var(...)`, is null: in Flutter a
/// model-written string can only ever become a color.
Color? parseCssColor(String input) {
  final s = input.trim().toLowerCase();
  if (s == 'transparent') return Colors.transparent;
  if (_named[s] case final v?) return Color(v);
  final hex = RegExp(
    r'^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$',
  ).firstMatch(s);
  if (hex != null) {
    var h = hex.group(1)!;
    if (h.length <= 4) h = h.split('').map((c) => '$c$c').join();
    final rgb = int.parse(h.substring(0, 6), radix: 16);
    final a = h.length == 8 ? int.parse(h.substring(6), radix: 16) : 255;
    return Color((a << 24) | rgb);
  }
  final fn = RegExp(r'^(rgba?|hsla?)\(([^()]*)\)$').firstMatch(s);
  if (fn == null) return _modernColor(s);
  final parts = fn
      .group(2)!
      .split(RegExp(r'[\s,/]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length < 3 || parts.length > 4) return null;
  final alpha = parts.length == 4 ? _number(parts[3], 1) : 1.0;
  if (alpha == null) return null;
  final a = alpha.clamp(0.0, 1.0);
  if (fn.group(1)!.startsWith('rgb')) {
    final c = [for (final p in parts.take(3)) _number(p, 255)];
    if (c.contains(null)) return null;
    return Color.from(
      alpha: a,
      red: (c[0]! / 255).clamp(0, 1),
      green: (c[1]! / 255).clamp(0, 1),
      blue: (c[2]! / 255).clamp(0, 1),
    );
  }
  final h = double.tryParse(parts[0].replaceAll('deg', ''));
  final sat = _number(parts[1], 1), light = _number(parts[2], 1);
  if (h == null || !h.isFinite || sat == null || light == null) return null;
  final hue = (h % 360) / 360,
      sl = sat.clamp(0.0, 1.0),
      l = light.clamp(0.0, 1.0);
  double channel(double t) {
    final q = l < 0.5 ? l * (1 + sl) : l + sl - l * sl;
    final p = 2 * l - q;
    var x = t;
    if (x < 0) x += 1;
    if (x > 1) x -= 1;
    if (x < 1 / 6) return p + (q - p) * 6 * x;
    if (x < 1 / 2) return q;
    if (x < 2 / 3) return p + (q - p) * (2 / 3 - x) * 6;
    return p;
  }

  return Color.from(
    alpha: a,
    red: channel(hue + 1 / 3),
    green: channel(hue),
    blue: channel(hue - 1 / 3),
  );
}

/// Mixes [a] (weight [weightA]) with [b] in a CSS colour space, as `color-mix` does.
Color mixColors(Color a, double weightA, Color b, {required String space}) {
  if (!_mixSpaces.contains(space)) {
    throw ArgumentError.value(space, 'space', 'unsupported color space');
  }
  return _mixColors(a, b, weightA.clamp(0.0, 1.0), space, 1);
}

/// A CSS number, or a percentage scaled by [scale] (100% is `scale`).
double? _number(String p, double scale) {
  final v = double.tryParse(p.endsWith('%') ? p.substring(0, p.length - 1) : p);
  if (v == null || !v.isFinite) return null;
  return p.endsWith('%') ? v / 100 * scale : v;
}

/// A hue in degrees, with an optional `deg` unit.
double? _hue(String p) {
  final v = double.tryParse(
    p.endsWith('deg') ? p.substring(0, p.length - 3) : p,
  );
  return v != null && v.isFinite ? v : null;
}

/// `oklch()`, `oklab()`, `hwb()` and `color-mix()`; other functions are null.
Color? _modernColor(String s) {
  final open = s.indexOf('(');
  if (open <= 0 || !s.endsWith(')')) return null;
  final args = s.substring(open + 1, s.length - 1);
  if (_splitTopLevel(args) == null) return null;
  return switch (s.substring(0, open)) {
    'oklch' => _oklch(args),
    'oklab' => _oklab(args),
    'hwb' => _hwb(args),
    'color-mix' => _colorMix(args),
    _ => null,
  };
}

/// Splits [s] at commas outside parentheses; null when they do not balance.
List<String>? _splitTopLevel(String s) {
  final out = <String>[];
  var depth = 0, start = 0;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      if (--depth < 0) return null;
    } else if (ch == ',' && depth == 0) {
      out.add(s.substring(start, i));
      start = i + 1;
    }
  }
  if (depth != 0) return null;
  out.add(s.substring(start));
  return out;
}

/// Three components and an alpha from `a b c [/ alpha]`.
({List<String> parts, double alpha})? _colorArgs(String args) {
  final slash = args.indexOf('/');
  final body = (slash < 0 ? args : args.substring(0, slash)).trim();
  final parts = body.split(RegExp(r'\s+'));
  if (parts.length != 3) return null;
  if (slash < 0) return (parts: parts, alpha: 1.0);
  final alpha = _number(args.substring(slash + 1).trim(), 1);
  if (alpha == null) return null;
  return (parts: parts, alpha: alpha.clamp(0.0, 1.0));
}

Color? _oklch(String args) {
  final c = _colorArgs(args);
  if (c == null) return null;
  final l = _number(c.parts[0], 1);
  final chroma = _number(c.parts[1], 0.4);
  final h = _hue(c.parts[2]);
  if (l == null || chroma == null || h == null) return null;
  final rad = h * math.pi / 180;
  final cc = math.max(0.0, chroma);
  return _srgbColor(
    _labToSrgb([l.clamp(0.0, 1.0), cc * math.cos(rad), cc * math.sin(rad)]),
    c.alpha,
  );
}

Color? _oklab(String args) {
  final c = _colorArgs(args);
  if (c == null) return null;
  final l = _number(c.parts[0], 1);
  final a = _number(c.parts[1], 0.4);
  final b = _number(c.parts[2], 0.4);
  if (l == null || a == null || b == null) return null;
  return _srgbColor(_labToSrgb([l.clamp(0.0, 1.0), a, b]), c.alpha);
}

Color? _hwb(String args) {
  final c = _colorArgs(args);
  if (c == null) return null;
  final h = _hue(c.parts[0]);
  final w = _share(c.parts[1]);
  final b = _share(c.parts[2]);
  if (h == null || w == null || b == null) return null;
  if (w + b >= 1) {
    final grey = w / (w + b);
    return _srgbColor([grey, grey, grey], c.alpha);
  }
  final turn = h / 360;
  final scale = 1 - w - b;
  final pure = [_pureHue(turn + 1 / 3), _pureHue(turn), _pureHue(turn - 1 / 3)];
  return _srgbColor([for (final x in pure) x * scale + w], c.alpha);
}

/// A whiteness or blackness share, written as a percentage.
double? _share(String p) {
  if (!p.endsWith('%')) return null;
  final v = _number(p, 1);
  return v == null || v < 0 ? null : v;
}

/// One channel of a fully saturated hue at half lightness; [t] is in turns.
double _pureHue(double t) {
  final x = t - t.floorToDouble();
  if (x < 1 / 6) return 6 * x;
  if (x < 1 / 2) return 1;
  if (x < 2 / 3) return (2 / 3 - x) * 6;
  return 0;
}

const _mixSpaces = {'srgb', 'srgb-linear', 'oklab', 'oklch'};

Color? _colorMix(String args) {
  final parts = _splitTopLevel(args);
  if (parts == null || parts.length != 3) return null;
  final head = parts[0].trim();
  if (!head.startsWith('in ')) return null;
  final space = head.substring(3).trim();
  if (!_mixSpaces.contains(space)) return null;
  final first = _mixOperand(parts[1]);
  final second = _mixOperand(parts[2]);
  if (first == null || second == null) return null;
  final p1 = first.pct, p2 = second.pct;
  final a = p1 ?? (p2 == null ? 50.0 : 100 - p2);
  final b = p2 ?? 100 - a;
  final sum = a + b;
  if (a < 0 || b < 0 || sum <= 0) return null;
  final scale = sum < 100 ? sum / 100 : 1.0;
  return _mixColors(first.color, second.color, a / sum, space, scale);
}

/// A colour with its optional `color-mix` percentage (0 to 100).
({Color color, double? pct})? _mixOperand(String text) {
  final m = RegExp(r'^(.*?)\s+(\d+(?:\.\d+)?)%$').firstMatch(text.trim());
  final color = parseCssColor(m == null ? text : m.group(1)!);
  final pct = m == null ? null : double.parse(m.group(2)!);
  if (color == null || (pct != null && pct > 100)) return null;
  return (color: color, pct: pct);
}

/// Premultiplied mix; [scale] multiplies the result alpha (`color-mix` under 100%).
Color _mixColors(Color a, Color b, double wa, String space, double scale) {
  final wb = 1 - wa;
  final alpha = wa * a.a + wb * b.a;
  if (alpha <= 0) return Colors.transparent;
  final List<double> srgb;
  if (space == 'oklch') {
    final p = _lch(a), q = _lch(b);
    var hueA = p[2], hueB = q[2];
    if (p[1] < 1e-6) hueA = hueB;
    if (q[1] < 1e-6) hueB = hueA;
    final turn = hueB - hueA;
    if (turn > 180) hueB -= 360;
    if (turn < -180) hueB += 360;
    final l = (wa * p[0] * a.a + wb * q[0] * b.a) / alpha;
    final c = (wa * p[1] * a.a + wb * q[1] * b.a) / alpha;
    final h = (wa * hueA + wb * hueB) * math.pi / 180;
    srgb = _labToSrgb([l, c * math.cos(h), c * math.sin(h)]);
  } else {
    final x = _components(a, space), y = _components(b, space);
    final mixed = [
      for (var i = 0; i < 3; i++) (wa * x[i] * a.a + wb * y[i] * b.a) / alpha,
    ];
    srgb = _fromComponents(mixed, space);
  }
  return _srgbColor(srgb, alpha * scale);
}

/// The channels of [c] in [space]: sRGB, linear sRGB, or OKLab.
List<double> _components(Color c, String space) {
  if (space == 'srgb') return [c.r, c.g, c.b];
  final linear = [_toLinear(c.r), _toLinear(c.g), _toLinear(c.b)];
  return space == 'srgb-linear' ? linear : _toLab(linear);
}

List<double> _fromComponents(List<double> v, String space) {
  if (space == 'srgb') return v;
  if (space == 'srgb-linear') return [for (final x in v) _fromLinear(x)];
  return _labToSrgb(v);
}

/// OKLCH of [c]: lightness, chroma, and hue in degrees within [0, 360).
List<double> _lch(Color c) {
  final lab = _components(c, 'oklab');
  final h = math.atan2(lab[2], lab[1]) * 180 / math.pi;
  return [
    lab[0],
    math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]),
    h < 0 ? h + 360 : h,
  ];
}

Color _srgbColor(List<double> srgb, double alpha) => Color.from(
  alpha: alpha.clamp(0.0, 1.0),
  red: _clip(srgb[0]),
  green: _clip(srgb[1]),
  blue: _clip(srgb[2]),
);

double _clip(double v) => v.clamp(0.0, 1.0);

double _toLinear(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _fromLinear(double v) => v <= 0.0031308
    ? v * 12.92
    : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;

const _m1 = [
  [0.4122214708, 0.5363325363, 0.0514459929],
  [0.2119034982, 0.6806995451, 0.1073969566],
  [0.0883024619, 0.2817188376, 0.6299787005],
];

const _m2 = [
  [0.2104542553, 0.7936177850, -0.0040720468],
  [1.9779984951, -2.4285922050, 0.4505937099],
  [0.0259040371, 0.7827717662, -0.8086757660],
];

const _m3 = [
  [4.0767416621, -3.3077115913, 0.2309699292],
  [-1.2684380046, 2.6097574011, -0.3413193965],
  [-0.0041960863, -0.7034186147, 1.7076147010],
];

List<double> _mul(List<List<double>> m, List<double> v) => [
  for (final row in m) row[0] * v[0] + row[1] * v[1] + row[2] * v[2],
];

double _cbrt(double x) =>
    x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

/// Linear sRGB to OKLab.
List<double> _toLab(List<double> linear) =>
    _mul(_m2, [for (final x in _mul(_m1, linear)) _cbrt(x)]);

/// OKLab to gamma-encoded sRGB, unclipped.
List<double> _labToSrgb(List<double> lab) {
  final l = lab[0], a = lab[1], b = lab[2];
  final cube = [
    for (final x in [
      l + 0.3963377774 * a + 0.2158037573 * b,
      l - 0.1055613458 * a - 0.0638541728 * b,
      l - 0.0894841775 * a - 1.2914855480 * b,
    ])
      x * x * x,
  ];
  return [for (final x in _mul(_m3, cube)) _fromLinear(x)];
}

/// A CSS `linear-gradient()` or `radial-gradient()`, plain or `repeating-`,
/// as a [CssGradient]; null for anything else, including colour hints,
/// `conic-gradient()` and layered backgrounds.
CssGradient? parseCssGradient(String input) {
  final m = RegExp(
    r'^(repeating-)?(linear|radial)-gradient\((.*)\)$',
  ).firstMatch(input.trim().toLowerCase());
  if (m == null) return null;
  final args = _splitTopLevel(m.group(3)!);
  if (args == null || args.isEmpty) return null;
  final config = _colorStops([args.first]) == null ? args.first.trim() : null;
  final stops = _colorStops(config == null ? args : args.sublist(1));
  if (stops == null || stops.length < 2) return null;
  final repeating = m.group(1) != null;
  if (m.group(2) == 'linear') {
    final direction = config == null
        ? (angle: math.pi, corner: Offset.zero)
        : _linearDirection(config);
    if (direction == null) return null;
    return CssGradient._(
      stops,
      repeating: repeating,
      angle: direction.angle,
      corner: direction.corner,
    );
  }
  final radial = _radialShape(config ?? '');
  if (radial == null) return null;
  return CssGradient._(stops, repeating: repeating, radial: radial);
}

/// One colour stop: px, or a fraction of the gradient length; null [at] is
/// placed by the CSS fix-up rules.
typedef _Stop = ({Color color, double? at, bool px});

/// A length: [value] px, or a fraction of a reference length.
typedef _Len = ({double value, bool fraction});

/// A radial gradient's ending shape, its size and its centre.
typedef _Radial = ({
  bool circle,
  String extent,
  _Len? rx,
  _Len? ry,
  _Len cx,
  _Len cy,
});

final _dimension = RegExp(
  r'^([+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)(%|px|deg|rad|grad|turn)?$',
);

({double value, String unit})? _measure(String text) {
  final m = _dimension.firstMatch(text);
  if (m == null) return null;
  final value = double.parse(m.group(1)!);
  return value.isFinite ? (value: value, unit: m.group(2) ?? '') : null;
}

/// `10px`, `25%` or a unitless `0`.
_Len? _length(String text) {
  final d = _measure(text);
  return switch (d?.unit) {
    'px' => (value: d!.value, fraction: false),
    '%' => (value: d!.value / 100, fraction: true),
    '' when d!.value == 0 => (value: 0.0, fraction: false),
    _ => null,
  };
}

/// An angle in radians: `deg`, `rad`, `grad`, `turn`, or a unitless `0`.
double? _angle(String text) {
  final d = _measure(text);
  return switch (d?.unit) {
    'deg' => d!.value * math.pi / 180,
    'rad' => d!.value,
    'grad' => d!.value * math.pi / 200,
    'turn' => d!.value * 2 * math.pi,
    '' when d!.value == 0 => 0.0,
    _ => null,
  };
}

/// Splits [s] at whitespace outside parentheses.
List<String> _words(String s) {
  final out = <String>[];
  var depth = 0, start = -1;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '(') depth++;
    if (ch == ')') depth--;
    if (depth == 0 && (ch == ' ' || ch == '\t' || ch == '\n')) {
      if (start >= 0) out.add(s.substring(start, i));
      start = -1;
    } else if (start < 0) {
      start = i;
    }
  }
  if (start >= 0) out.add(s.substring(start));
  return out;
}

/// `<color> <length>{0,2}` items, the colour first or last; null when one
/// is not a colour stop.
List<_Stop>? _colorStops(List<String> items) {
  final out = <_Stop>[];
  for (final item in items) {
    final words = _words(item.trim());
    if (words.isEmpty || words.length > 3) return null;
    var color = parseCssColor(words.first);
    var lengths = words.skip(1);
    if (color == null) {
      color = parseCssColor(words.last);
      lengths = words.take(words.length - 1);
    }
    if (color == null) return null;
    final at = [for (final w in lengths) _length(w)];
    if (at.contains(null)) return null;
    if (at.isEmpty) out.add((color: color, at: null, px: false));
    for (final l in at) {
      out.add((color: color, at: l!.value, px: !l.fraction));
    }
  }
  return out;
}

/// An angle, or `to` a side or a corner. A corner's angle depends on the
/// box, so it stays as signs: `to top right` is `Offset(1, -1)`.
({double? angle, Offset corner})? _linearDirection(String config) {
  final angle = _angle(config);
  if (angle != null) return (angle: angle, corner: Offset.zero);
  final words = _words(config);
  if (words.length < 2 || words.length > 3 || words.first != 'to') return null;
  var x = 0.0, y = 0.0;
  for (final w in words.skip(1)) {
    switch (w) {
      case 'left' when x == 0:
        x = -1;
      case 'right' when x == 0:
        x = 1;
      case 'top' when y == 0:
        y = -1;
      case 'bottom' when y == 0:
        y = 1;
      default:
        return null;
    }
  }
  if (x != 0 && y != 0) return (angle: null, corner: Offset(x, y));
  return (angle: math.atan2(x, -y), corner: Offset.zero);
}

const _center = (value: 0.5, fraction: true);
const _extents = {
  'closest-side',
  'closest-corner',
  'farthest-side',
  'farthest-corner',
};

/// `[circle | ellipse] [<extent> | <length>{1,2}] [at <position>]`.
_Radial? _radialShape(String config) {
  final words = _words(config);
  final at = words.indexOf('at');
  final center = at < 0
      ? (cx: _center, cy: _center)
      : _position(words.sublist(at + 1));
  if (center == null) return null;
  bool? circle;
  String? extent;
  final sizes = <_Len>[];
  for (final w in at < 0 ? words : words.sublist(0, at)) {
    final size = _length(w);
    if ((w == 'circle' || w == 'ellipse') && circle == null) {
      circle = w == 'circle';
    } else if (_extents.contains(w) && extent == null && sizes.isEmpty) {
      extent = w;
    } else if (size != null &&
        size.value >= 0 &&
        extent == null &&
        sizes.length < 2) {
      sizes.add(size);
    } else {
      return null;
    }
  }
  final round = circle ?? sizes.length == 1;
  if (round
      ? sizes.length > 1 || sizes.any((s) => s.fraction)
      : sizes.length == 1) {
    return null;
  }
  return (
    circle: round,
    extent: extent ?? 'farthest-corner',
    rx: sizes.firstOrNull,
    ry: sizes.length == 2 ? sizes[1] : null,
    cx: center.cx,
    cy: center.cy,
  );
}

/// One or two of `left`, `center`, `right`, `top`, `bottom` or a length.
({_Len cx, _Len cy})? _position(List<String> words) {
  if (words.isEmpty || words.length > 2) return null;
  var x = words.first, y = words.length == 2 ? words[1] : 'center';
  if (x == 'top' || x == 'bottom' || y == 'left' || y == 'right') {
    (x, y) = (y, x);
  }
  _Len? place(String w, String start, String end) => switch (w) {
    'center' => _center,
    _ when w == start => (value: 0.0, fraction: true),
    _ when w == end => (value: 1.0, fraction: true),
    _ => _length(w),
  };
  final cx = place(x, 'left', 'right');
  final cy = place(y, 'top', 'bottom');
  return cx == null || cy == null ? null : (cx: cx, cy: cy);
}

/// A CSS gradient. Angles to corners, ending-shape sizes and stop lengths
/// depend on the painted box, so they resolve in [createShader].
final class CssGradient extends Gradient {
  CssGradient._(
    this._stops, {
    required this.repeating,
    this.angle,
    this.corner = Offset.zero,
    _Radial? radial,
  }) : _radial = radial,
       super(colors: [for (final s in _stops) s.color]);

  final List<_Stop> _stops;
  final bool repeating;

  /// A linear gradient's angle in radians (0 points up, clockwise), or null
  /// for a gradient to [corner].
  final double? angle;
  final Offset corner;
  final _Radial? _radial;

  TileMode get _tileMode => repeating ? TileMode.repeated : TileMode.clamp;

  @override
  Shader createShader(Rect rect, {TextDirection? textDirection}) {
    final radial = _radial;
    if (radial == null) {
      final a =
          angle ?? math.atan2(corner.dx * rect.height, -corner.dy * rect.width);
      final dir = Offset(math.sin(a), -math.cos(a));
      final length =
          (rect.width * math.sin(a)).abs() + (rect.height * math.cos(a)).abs();
      final (colors, at) = _resolve(length);
      final span = math.max(at.last - at.first, 1e-3);
      final start = rect.center - dir * (length / 2) + dir * at.first;
      return ui.Gradient.linear(start, start + dir * span, colors, [
        for (final p in at) (p - at.first) / span,
      ], _tileMode);
    }
    double px(_Len l, double of) => l.fraction ? l.value * of : l.value;
    final center = Offset(
      rect.left + px(radial.cx, rect.width),
      rect.top + px(radial.cy, rect.height),
    );
    final (rx, ry) = _radii(radial, rect, center, px);
    final (colors, at) = _resolve(rx);
    final last = math.max(at.last, 1e-3);
    final scaleY = ry / rx;
    return ui.Gradient.radial(
      center,
      last,
      colors,
      [for (final p in at) (p / last).clamp(0.0, 1.0)],
      _tileMode,
      Float64List(16)
        ..[0] = 1
        ..[5] = scaleY
        ..[10] = 1
        ..[13] = center.dy * (1 - scaleY)
        ..[15] = 1,
    );
  }

  /// The ending shape's radii: explicit, or from the extent keyword measured
  /// from [center] to the box's sides or corners.
  (double, double) _radii(
    _Radial r,
    Rect rect,
    Offset center,
    double Function(_Len, double) px,
  ) {
    var rx = 0.0, ry = 0.0;
    if (r.rx != null) {
      rx = px(r.rx!, rect.width);
      ry = r.circle ? rx : px(r.ry!, rect.height);
    } else {
      final dx = [center.dx - rect.left, rect.right - center.dx];
      final dy = [center.dy - rect.top, rect.bottom - center.dy];
      final closest = r.extent.startsWith('closest');
      final x = closest
          ? dx.map((v) => v.abs()).reduce(math.min)
          : dx.map((v) => v.abs()).reduce(math.max);
      final y = closest
          ? dy.map((v) => v.abs()).reduce(math.min)
          : dy.map((v) => v.abs()).reduce(math.max);
      final corner = r.extent.endsWith('corner');
      if (r.circle) {
        rx = ry = corner
            ? math.sqrt(x * x + y * y)
            : (closest ? math.min(x, y) : math.max(x, y));
      } else {
        rx = corner ? x * math.sqrt2 : x;
        ry = corner ? y * math.sqrt2 : y;
      }
    }
    return (math.max(rx, 1e-3), math.max(ry, 1e-3));
  }

  /// Colours and px positions after the CSS fix-up: a missing first or last
  /// position is 0% or 100%, no position goes back, and stops without one
  /// share the space between their neighbours. A transparent stop takes each
  /// neighbour's colour at zero alpha, as premultiplied interpolation shows it.
  (List<Color>, List<double>) _resolve(double length) {
    final at = [
      for (final s in _stops)
        s.at == null ? null : (s.px ? s.at! : s.at! * length),
    ];
    at.first ??= 0;
    at.last ??= length;
    var max = at.first!;
    for (var i = 1; i < at.length; i++) {
      if (at[i] != null) max = at[i] = math.max(at[i]!, max);
    }
    for (var i = 1; i < at.length; i++) {
      if (at[i] != null) continue;
      var j = i;
      while (at[j] == null) {
        j++;
      }
      final from = at[i - 1]!, to = at[j]!;
      for (var k = i; k < j; k++) {
        at[k] = from + (to - from) * (k - i + 1) / (j - i + 1);
      }
    }
    final colors = <Color>[];
    final positions = <double>[];
    for (var i = 0; i < _stops.length; i++) {
      final color = _stops[i].color;
      final neighbours = color.a > 0
          ? [color]
          : [
              if (i > 0) _stops[i - 1].color.withValues(alpha: 0),
              if (i < _stops.length - 1)
                _stops[i + 1].color.withValues(alpha: 0),
            ];
      for (final c in neighbours) {
        colors.add(c);
        positions.add(at[i]!);
      }
    }
    return (colors, positions);
  }

  CssGradient _map(Color Function(Color) f) => CssGradient._(
    [for (final s in _stops) (color: f(s.color), at: s.at, px: s.px)],
    repeating: repeating,
    angle: angle,
    corner: corner,
    radial: _radial,
  );

  @override
  CssGradient scale(double factor) => _map((c) => Color.lerp(null, c, factor)!);

  @override
  CssGradient withOpacity(double opacity) =>
      _map((c) => c.withValues(alpha: c.a * opacity));

  @override
  bool operator ==(Object other) =>
      other is CssGradient &&
      listEquals(other._stops, _stops) &&
      other.repeating == repeating &&
      other.angle == angle &&
      other.corner == corner &&
      other._radial == _radial;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(_stops), repeating, angle, corner, _radial);
}

const Map<String, int> _named = {
  'aliceblue': 0xFFF0F8FF,
  'antiquewhite': 0xFFFAEBD7,
  'aqua': 0xFF00FFFF,
  'aquamarine': 0xFF7FFFD4,
  'azure': 0xFFF0FFFF,
  'beige': 0xFFF5F5DC,
  'bisque': 0xFFFFE4C4,
  'black': 0xFF000000,
  'blanchedalmond': 0xFFFFEBCD,
  'blue': 0xFF0000FF,
  'blueviolet': 0xFF8A2BE2,
  'brown': 0xFFA52A2A,
  'burlywood': 0xFFDEB887,
  'cadetblue': 0xFF5F9EA0,
  'chartreuse': 0xFF7FFF00,
  'chocolate': 0xFFD2691E,
  'coral': 0xFFFF7F50,
  'cornflowerblue': 0xFF6495ED,
  'cornsilk': 0xFFFFF8DC,
  'crimson': 0xFFDC143C,
  'cyan': 0xFF00FFFF,
  'darkblue': 0xFF00008B,
  'darkcyan': 0xFF008B8B,
  'darkgoldenrod': 0xFFB8860B,
  'darkgray': 0xFFA9A9A9,
  'darkgreen': 0xFF006400,
  'darkgrey': 0xFFA9A9A9,
  'darkkhaki': 0xFFBDB76B,
  'darkmagenta': 0xFF8B008B,
  'darkolivegreen': 0xFF556B2F,
  'darkorange': 0xFFFF8C00,
  'darkorchid': 0xFF9932CC,
  'darkred': 0xFF8B0000,
  'darksalmon': 0xFFE9967A,
  'darkseagreen': 0xFF8FBC8F,
  'darkslateblue': 0xFF483D8B,
  'darkslategray': 0xFF2F4F4F,
  'darkslategrey': 0xFF2F4F4F,
  'darkturquoise': 0xFF00CED1,
  'darkviolet': 0xFF9400D3,
  'deeppink': 0xFFFF1493,
  'deepskyblue': 0xFF00BFFF,
  'dimgray': 0xFF696969,
  'dimgrey': 0xFF696969,
  'dodgerblue': 0xFF1E90FF,
  'firebrick': 0xFFB22222,
  'floralwhite': 0xFFFFFAF0,
  'forestgreen': 0xFF228B22,
  'fuchsia': 0xFFFF00FF,
  'gainsboro': 0xFFDCDCDC,
  'ghostwhite': 0xFFF8F8FF,
  'gold': 0xFFFFD700,
  'goldenrod': 0xFFDAA520,
  'gray': 0xFF808080,
  'green': 0xFF008000,
  'greenyellow': 0xFFADFF2F,
  'grey': 0xFF808080,
  'honeydew': 0xFFF0FFF0,
  'hotpink': 0xFFFF69B4,
  'indianred': 0xFFCD5C5C,
  'indigo': 0xFF4B0082,
  'ivory': 0xFFFFFFF0,
  'khaki': 0xFFF0E68C,
  'lavender': 0xFFE6E6FA,
  'lavenderblush': 0xFFFFF0F5,
  'lawngreen': 0xFF7CFC00,
  'lemonchiffon': 0xFFFFFACD,
  'lightblue': 0xFFADD8E6,
  'lightcoral': 0xFFF08080,
  'lightcyan': 0xFFE0FFFF,
  'lightgoldenrodyellow': 0xFFFAFAD2,
  'lightgray': 0xFFD3D3D3,
  'lightgreen': 0xFF90EE90,
  'lightgrey': 0xFFD3D3D3,
  'lightpink': 0xFFFFB6C1,
  'lightsalmon': 0xFFFFA07A,
  'lightseagreen': 0xFF20B2AA,
  'lightskyblue': 0xFF87CEFA,
  'lightslategray': 0xFF778899,
  'lightslategrey': 0xFF778899,
  'lightsteelblue': 0xFFB0C4DE,
  'lightyellow': 0xFFFFFFE0,
  'lime': 0xFF00FF00,
  'limegreen': 0xFF32CD32,
  'linen': 0xFFFAF0E6,
  'magenta': 0xFFFF00FF,
  'maroon': 0xFF800000,
  'mediumaquamarine': 0xFF66CDAA,
  'mediumblue': 0xFF0000CD,
  'mediumorchid': 0xFFBA55D3,
  'mediumpurple': 0xFF9370DB,
  'mediumseagreen': 0xFF3CB371,
  'mediumslateblue': 0xFF7B68EE,
  'mediumspringgreen': 0xFF00FA9A,
  'mediumturquoise': 0xFF48D1CC,
  'mediumvioletred': 0xFFC71585,
  'midnightblue': 0xFF191970,
  'mintcream': 0xFFF5FFFA,
  'mistyrose': 0xFFFFE4E1,
  'moccasin': 0xFFFFE4B5,
  'navajowhite': 0xFFFFDEAD,
  'navy': 0xFF000080,
  'oldlace': 0xFFFDF5E6,
  'olive': 0xFF808000,
  'olivedrab': 0xFF6B8E23,
  'orange': 0xFFFFA500,
  'orangered': 0xFFFF4500,
  'orchid': 0xFFDA70D6,
  'palegoldenrod': 0xFFEEE8AA,
  'palegreen': 0xFF98FB98,
  'paleturquoise': 0xFFAFEEEE,
  'palevioletred': 0xFFDB7093,
  'papayawhip': 0xFFFFEFD5,
  'peachpuff': 0xFFFFDAB9,
  'peru': 0xFFCD853F,
  'pink': 0xFFFFC0CB,
  'plum': 0xFFDDA0DD,
  'powderblue': 0xFFB0E0E6,
  'purple': 0xFF800080,
  'rebeccapurple': 0xFF663399,
  'red': 0xFFFF0000,
  'rosybrown': 0xFFBC8F8F,
  'royalblue': 0xFF4169E1,
  'saddlebrown': 0xFF8B4513,
  'salmon': 0xFFFA8072,
  'sandybrown': 0xFFF4A460,
  'seagreen': 0xFF2E8B57,
  'seashell': 0xFFFFF5EE,
  'sienna': 0xFFA0522D,
  'silver': 0xFFC0C0C0,
  'skyblue': 0xFF87CEEB,
  'slateblue': 0xFF6A5ACD,
  'slategray': 0xFF708090,
  'slategrey': 0xFF708090,
  'snow': 0xFFFFFAFA,
  'springgreen': 0xFF00FF7F,
  'steelblue': 0xFF4682B4,
  'tan': 0xFFD2B48C,
  'teal': 0xFF008080,
  'thistle': 0xFFD8BFD8,
  'tomato': 0xFFFF6347,
  'turquoise': 0xFF40E0D0,
  'violet': 0xFFEE82EE,
  'wheat': 0xFFF5DEB3,
  'white': 0xFFFFFFFF,
  'whitesmoke': 0xFFF5F5F5,
  'yellow': 0xFFFFFF00,
  'yellowgreen': 0xFF9ACD32,
};
