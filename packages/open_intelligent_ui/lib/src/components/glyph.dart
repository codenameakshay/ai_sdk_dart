import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

import 'lucide_icons.dart';

/// The lucide icon [value] names, or null: "MapPin", "map_pin" and
/// "map pin" all mean "map-pin", and lucide-react's aliases resolve.
String? lucideIcon(Object? value) {
  if (value is! String) return null;
  final name = value
      .trim()
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}-${m[2]}')
      .replaceAll(RegExp(r'[\s_]+'), '-')
      .toLowerCase();
  final icon = lucideAliases[name] ?? name;
  return lucideIcons.containsKey(icon) ? icon : null;
}

/// Whether [value] names a lucide icon.
bool isLucideIcon(Object? value) => lucideIcon(value) != null;

/// A lucide icon by name, drawn from its outline as lucide-react draws it:
/// round-capped strokes on a 24 by 24 grid scaled to [size]. Unknown names
/// render nothing.
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

  @override
  Widget build(BuildContext context) {
    final icon = lucideIcon(name);
    if (icon == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _GlyphPainter(
          icon,
          color ??
              DefaultTextStyle.of(context).style.color ??
              const Color(0xFF000000),
          strokeWidth,
        ),
      ),
    );
  }
}

final Map<String, (Path, Path?)> _paths = {};

/// The stroked and the filled outline of [icon], parsed once.
(Path, Path?) _outline(String icon) => _paths[icon] ??= () {
  Path parse(String parts) {
    final path = Path();
    for (final d in parts.split('|')) {
      writeSvgPathDataToPath(d, _PathProxy(path));
    }
    return path;
  }

  final (stroke, fill) = lucideIcons[icon]!;
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
  const _GlyphPainter(this.icon, this.color, this.strokeWidth);
  final String icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final (stroke, fill) = _outline(icon);
    canvas.scale(size.width / 24, size.height / 24);
    if (fill != null) canvas.drawPath(fill, Paint()..color = color);
    canvas.drawPath(
      stroke,
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
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}
