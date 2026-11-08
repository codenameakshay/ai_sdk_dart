import 'dart:math' as math;
import 'dart:ui';

/// Parses a CSS color: hex (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`),
/// `rgb()`/`rgba()`, `hsl()`/`hsla()`, a named color, or `transparent`.
/// Anything else, including `url(...)` or `var(...)`, is null: in Flutter a
/// model-written string can only ever become a color.
Color? parseCssColor(String input) {
  final s = input.trim().toLowerCase();
  if (s == 'transparent') return const Color(0x00000000);
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
  if (alpha <= 0) return const Color(0x00000000);
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
