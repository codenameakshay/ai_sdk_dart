import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

import '../services.dart';
import 'builtin_glyphs.dart';

/// The kebab-case name [value] gives: "MapPin", "map_pin" and "map pin" all
/// mean "map-pin". Null when [value] is not a string.
String? _kebab(Object? value) {
  if (value is! String) return null;
  return value
      .trim()
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .toLowerCase();
}

/// An icon by name, drawn from its outline as lucide-react draws it: round-
/// capped strokes on a 24 by 24 grid scaled to [size]. The scope's icon
/// resolver draws first, then the built-in icons; a name neither has renders
/// nothing.
class Glyph extends StatelessWidget {
  const Glyph(
    this.name, {
    super.key,
    this.size = 18,
    this.color,
    this.strokeWidth = 1.8,
  });
  final Object? name;
  final double size;
  final Color? color;

  /// In grid units, so it scales with [size]: the reference's `Glyph` uses
  /// 1.8, lucide-react's own icon components 2.
  final double strokeWidth;

  /// Whether [name] draws an icon here.
  static bool has(BuildContext context, Object? name) =>
      _resolve(context, name) != null;

  @override
  Widget build(BuildContext context) =>
      _resolve(
        context,
        name,
        size: size,
        color: color,
        strokeWidth: strokeWidth,
      ) ??
      const SizedBox.shrink();
}

Widget? _resolve(
  BuildContext context,
  Object? name, {
  double size = 18,
  Color? color,
  double strokeWidth = 1.8,
}) {
  final n = _kebab(name);
  if (n == null) return null;
  final c =
      color ??
      DefaultTextStyle.of(context).style.color ??
      const Color(0xFF000000);
  final w =
      OpenUiScope.servicesOf(context).icons?.call(n, size, c, strokeWidth) ??
      _builtin(n, size, c, strokeWidth);
  return w == null ? null : ExcludeSemantics(child: w);
}

Widget? _builtin(String name, double size, Color color, double strokeWidth) {
  final d = builtinGlyphs[name];
  return d == null
      ? null
      : OutlineGlyph(
          stroke: d.$1,
          fill: d.$2,
          size: size,
          color: color,
          strokeWidth: strokeWidth,
        );
}

/// An icon drawn from SVG path data on lucide's 24-unit grid (round caps and
/// joins). [stroke] and [fill] are '|'-separated path data.
class OutlineGlyph extends StatelessWidget {
  const OutlineGlyph({
    super.key,
    required this.stroke,
    this.fill,
    this.size = 18,
    required this.color,
    this.strokeWidth = 1.8,
  });
  final String stroke;
  final String? fill;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GlyphPainter(stroke, fill, color, strokeWidth),
  );
}

final Map<(String, String?), (Path, Path?)> _paths = {};

/// The stroked and the filled outline, parsed once.
(Path, Path?) _outline(String stroke, String? fill) =>
    _paths[(stroke, fill)] ??= () {
      Path parse(String parts) {
        final path = Path();
        for (final d in parts.split('|')) {
          writeSvgPathDataToPath(d, _PathProxy(path));
        }
        return path;
      }

      return (parse(stroke), fill == null ? null : parse(fill));
    }();

final class _PathProxy extends PathProxy {
  _PathProxy(this.path);
  final Path path;

  @override
  void close() => path.close();

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}

final class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.stroke, this.fill, this.color, this.strokeWidth);
  final String stroke;
  final String? fill;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final (strokePath, fillPath) = _outline(stroke, fill);
    canvas.scale(size.width / 24, size.height / 24);
    if (fillPath != null) canvas.drawPath(fillPath, Paint()..color = color);
    canvas.drawPath(
      strokePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.stroke != stroke ||
      old.fill != fill ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
