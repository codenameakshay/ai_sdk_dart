import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';
import 'package:path_parsing/path_parsing.dart';

import '../theme.dart';
import '../view.dart';

// Every attribute is checked here, as in the reference: nothing malformed
// reaches the painter.
double? _n(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
double? _opacity(Object? v) => _n(v)?.clamp(0, 1).toDouble();
final _points = RegExp(r'^[\d\s,.eE+-]*$');
final _path = RegExp(r'^[MmLlHhVvCcSsQqTtAaZz\d\s,.eE+-]*$');
final _viewBox = RegExp(r'^\s*[-\d.]+(\s*[\s,]\s*[-\d.]+){3}\s*$');
const _transformArgs = {
  'translate': [1, 2],
  'rotate': [1, 3],
  'scale': [1, 2],
  'skewX': [1],
  'skewY': [1],
  'matrix': [6],
};

String? _ok(Object? v, RegExp pattern) =>
    v is String && v.length < 20000 && pattern.hasMatch(v) ? v : null;

/// A G's transform, parsed like the reference: an invalid list is dropped.
Matrix4? parseTransform(Object? value) {
  if (value is! String || value.length > 500) return null;
  final parts = RegExp(
    r'\s*([a-zA-Z]+)\(([^()]*)\)\s*',
  ).allMatches(value).toList();
  if (parts.isEmpty || parts.map((p) => p[0]).join() != value) return null;
  final m = Matrix4.identity();
  for (final p in parts) {
    final name = p[1]!;
    final args = p[2]!
        .trim()
        .split(RegExp(r'\s*,\s*|\s+'))
        .where((s) => s.isNotEmpty)
        .map(double.tryParse)
        .toList();
    if (!(_transformArgs[name]?.contains(args.length) ?? false) ||
        args.any((a) => a == null || !a.isFinite)) {
      return null;
    }
    final a = args.cast<double>();
    switch (name) {
      case 'translate':
        m.translateByDouble(a[0], a.length > 1 ? a[1] : 0, 0, 1);
      case 'rotate':
        final r = a[0] * math.pi / 180;
        if (a.length == 3) {
          m
            ..translateByDouble(a[1], a[2], 0, 1)
            ..rotateZ(r)
            ..translateByDouble(-a[1], -a[2], 0, 1);
        } else {
          m.rotateZ(r);
        }
      case 'scale':
        m.scaleByDouble(a[0], a.length > 1 ? a[1] : a[0], 1, 1);
      case 'skewX':
        m.multiply(Matrix4.skewX(a[0] * math.pi / 180));
      case 'skewY':
        m.multiply(Matrix4.skewY(a[0] * math.pi / 180));
      case 'matrix':
        m.multiply(
          Matrix4(
            a[0],
            a[1],
            0,
            0,
            a[2],
            a[3],
            0,
            0,
            0,
            0,
            1,
            0,
            a[4],
            a[5],
            0,
            1,
          ),
        );
    }
  }
  return m;
}

/// Shapes draw only inside an Svg, which paints them; alone they are nothing.
Widget _shapeOutsideSvg(BuildContext context, OpenUiNode node) =>
    const SizedBox.shrink();

Widget buildCircle(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildEllipse(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildRect(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildLine(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildPath(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildPolyline(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildPolygon(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildG(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);
Widget buildSvgText(BuildContext context, OpenUiNode node) =>
    _shapeOutsideSvg(context, node);

/// `Svg(children, viewBox, width?, height?)`.
Widget buildSvg(BuildContext context, OpenUiNode node) {
  final theme = node.theme;
  final ink = DefaultTextStyle.of(context).style.color ?? theme.ink;
  final box = (_ok(node.props['viewBox'], _viewBox) ?? '0 0 100 100')
      .trim()
      .split(RegExp(r'[\s,]+'))
      .map(double.parse)
      .toList();
  final viewBox = Rect.fromLTWH(box[0], box[1], box[2], box[3]);
  final scene = [
    for (final e in node.props.elements('children')) ?_shape(e, theme, ink),
  ];
  final width = OpenUiTheme.length(node.props['width']);
  final height = OpenUiTheme.length(node.props['height']).px;
  final maxWidth = node.props['width'] == null && viewBox.width > 0
      ? math.max(280.0, viewBox.width * 1.5)
      : double.infinity;
  return LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : 320.0;
      final w = math.min(
        width.px ?? available * (width.fraction ?? 1),
        maxWidth,
      );
      final h =
          height ??
          (viewBox.width > 0 && viewBox.height > 0
              ? w * viewBox.height / viewBox.width
              : w);
      return Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: Semantics(
          image: true,
          child: SizedBox(
            width: w,
            height: h,
            child: CustomPaint(painter: SvgScenePainter(viewBox, scene)),
          ),
        ),
      );
    },
  );
}

sealed class SvgShape {
  const SvgShape(this.paint);
  final SvgPaint paint;
}

final class SvgPaint {
  const SvgPaint({this.fill, this.stroke, this.strokeWidth, this.opacity});
  final Color? fill;
  final Color? stroke;
  final double? strokeWidth;
  final double? opacity;
}

final class _PathShape extends SvgShape {
  const _PathShape(this.path, super.paint);
  final Path path;
}

final class _TextShape extends SvgShape {
  const _TextShape(
    this.text,
    this.at,
    this.size,
    this.anchor,
    this.weight,
    super.paint,
  );
  final String text;
  final Offset at;
  final double size;
  final String anchor;
  final FontWeight weight;
}

final class _GroupShape extends SvgShape {
  const _GroupShape(this.children, this.transform, super.paint);
  final List<SvgShape> children;
  final Matrix4? transform;
}

/// Filled shapes default to the text color; with only a stroke they stay
/// unfilled. Lines and polylines stroke in the text color, 2 wide.
SvgPaint _paintOf(
  Props p,
  OpenUiTheme theme,
  Color ink, {
  required bool filled,
}) {
  final hasFill = p['fill'] != null, hasStroke = p['stroke'] != null;
  return SvgPaint(
    fill: hasFill ? theme.fg(p['fill']) : (filled && !hasStroke ? ink : null),
    stroke: hasStroke ? theme.fg(p['stroke']) : (filled ? null : ink),
    strokeWidth: _n(p['strokeWidth']) ?? (filled ? null : 2),
    opacity: _opacity(p['opacity']),
  );
}

List<Offset>? _pointList(Object? v) {
  final s = _ok(v, _points);
  if (s == null) return null;
  final numbers = s
      .trim()
      .split(RegExp(r'[\s,]+'))
      .where((x) => x.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (numbers.any((x) => x == null)) return null;
  return [
    for (var i = 0; i + 1 < numbers.length; i += 2)
      Offset(numbers[i]!, numbers[i + 1]!),
  ];
}

SvgShape? _shape(OpenUiElement e, OpenUiTheme theme, Color ink) {
  final p = e.props;
  double v(String name) => _n(p[name]) ?? 0;
  double pos(String name) => math.max(0, v(name));
  switch (e.typeName) {
    case 'Circle':
      return _PathShape(
        Path()..addOval(
          Rect.fromCircle(center: Offset(v('cx'), v('cy')), radius: pos('r')),
        ),
        _paintOf(p, theme, ink, filled: true),
      );
    case 'Ellipse':
      return _PathShape(
        Path()..addOval(
          Rect.fromCenter(
            center: Offset(v('cx'), v('cy')),
            width: pos('rx') * 2,
            height: pos('ry') * 2,
          ),
        ),
        _paintOf(p, theme, ink, filled: true),
      );
    case 'Rect':
      final rect = Rect.fromLTWH(v('x'), v('y'), pos('width'), pos('height'));
      final rx = _n(p['rx']);
      return _PathShape(
        Path()..addRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, rx ?? 0))),
        ),
        _paintOf(p, theme, ink, filled: true),
      );
    case 'Line':
      return _PathShape(
        Path()
          ..moveTo(v('x1'), v('y1'))
          ..lineTo(v('x2'), v('y2')),
        _paintOf(p, theme, ink, filled: false),
      );
    case 'Path':
      final d = _ok(p['d'], _path);
      if (d == null) return null;
      final path = Path();
      try {
        writeSvgPathDataToPath(d, _PathProxy(path));
      } on Object {
        return null;
      }
      return _PathShape(
        path,
        _paintOf(p, theme, ink, filled: p['fill'] != null),
      );
    case 'Polyline' || 'Polygon':
      final points = _pointList(p['points']);
      if (points == null) return null;
      final path = Path()..addPolygon(points, e.typeName == 'Polygon');
      return _PathShape(
        path,
        _paintOf(p, theme, ink, filled: e.typeName == 'Polygon'),
      );
    case 'G':
      return _GroupShape(
        [
          for (final child in p.elements('children'))
            ?_shape(child, theme, ink),
        ],
        parseTransform(p['transform']),
        SvgPaint(opacity: _opacity(p['opacity'])),
      );
    case 'SvgText':
      return _TextShape(
        jsString(p['text'] ?? ''),
        Offset(v('x'), v('y')),
        _n(p['size']) ?? 12,
        p.string('anchor') ?? 'start',
        switch (p.string('weight')) {
          'semibold' => FontWeight.w600,
          'medium' => FontWeight.w500,
          _ => FontWeight.w400,
        },
        SvgPaint(fill: p['fill'] != null ? theme.fg(p['fill']) : ink),
      );
  }
  return null;
}

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

/// Paints an Svg scene into its box, fitting the viewBox (xMidYMid meet).
class SvgScenePainter extends CustomPainter {
  SvgScenePainter(this.viewBox, this.scene);
  final Rect viewBox;
  final List<SvgShape> scene;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewBox.width <= 0 || viewBox.height <= 0) return;
    final scale = math.min(
      size.width / viewBox.width,
      size.height / viewBox.height,
    );
    final dx = (size.width - viewBox.width * scale) / 2,
        dy = (size.height - viewBox.height * scale) / 2;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..translate(dx, dy)
      ..scale(scale)
      ..translate(-viewBox.left, -viewBox.top);
    for (final s in scene) {
      _draw(canvas, s, 1);
    }
    canvas.restore();
  }

  void _draw(Canvas canvas, SvgShape shape, double opacity) {
    final alpha = opacity * (shape.paint.opacity ?? 1);
    Color fade(Color c) => c.withValues(alpha: c.a * alpha);
    switch (shape) {
      case _GroupShape(:final children, :final transform):
        canvas.save();
        if (transform != null) canvas.transform(transform.storage);
        for (final c in children) {
          _draw(canvas, c, alpha);
        }
        canvas.restore();
      case _PathShape(:final path, paint: final p):
        if (p.fill != null) {
          canvas.drawPath(path, Paint()..color = fade(p.fill!));
        }
        if (p.stroke != null && (p.strokeWidth ?? 1) > 0) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..color = fade(p.stroke!)
              ..strokeWidth = p.strokeWidth ?? 1
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
      case _TextShape(
        :final text,
        :final at,
        :final size,
        :final anchor,
        :final weight,
        paint: final p,
      ):
        final painter = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: size,
              fontWeight: weight,
              color: fade(p.fill!),
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final x = switch (anchor) {
          'middle' => at.dx - painter.width / 2,
          'end' => at.dx - painter.width,
          _ => at.dx,
        };
        painter.paint(
          canvas,
          Offset(
            x,
            at.dy -
                painter.computeDistanceToActualBaseline(
                  TextBaseline.alphabetic,
                ),
          ),
        );
        painter.dispose();
    }
  }

  @override
  bool shouldRepaint(SvgScenePainter old) => true;
}
