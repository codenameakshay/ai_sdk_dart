import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../theme.dart';
import '../view.dart';

typedef ChartRow = Map<String, Object?>;
typedef ChartFormat = String Function(num value, {bool compact});

const _types = ['bar', 'line', 'area', 'pie', 'donut', 'scatter'];

num _num(Object? v) {
  if (v is num && v.isFinite) return v;
  final n = v is String ? double.tryParse(v.trim()) : null;
  return n != null && n.isFinite ? n : 0;
}

String _label(ChartRow row, String x) => row[x] == null ? '' : jsString(row[x]);

/// SVG `rx`: one radius for both axes, each clamped to half the side.
Radius _svgRadius(Rect rect, double r) => Radius.elliptical(
  math.min(r, rect.width / 2),
  math.min(r, rect.height / 2),
);

/// `toFixed(1)`, as the reference writes path points.
double _fixed1(double v) => double.parse(v.toStringAsFixed(1));

/// `.iui-chart-tick`: faint 11px tabular figures in the theme font.
TextStyle chartTickStyle(OpenUiTheme theme) => TextStyle(
  fontSize: theme.typography.size(11),
  color: theme.faint,
  fontFamily: theme.fontFamily,
  fontFeatures: theme.typography.tabular,
);

/// `.iui-chart-category`: muted 12px in the theme font.
TextStyle chartCategoryStyle(OpenUiTheme theme) => TextStyle(
  fontSize: theme.typography.size(12),
  color: theme.muted,
  fontFamily: theme.fontFamily,
);

/// An area's fill: a top-to-bottom gradient over the area's own bounding
/// box (SVG objectBoundingBox), stop-opacity times the color's alpha.
({Rect rect, List<Color> colors}) areaFill(
  Path area,
  Color color, {
  required bool stacked,
}) => (
  rect: area.getBounds(),
  colors: [
    color.withValues(alpha: color.a * (stacked ? 0.5 : 0.24)),
    color.withValues(alpha: color.a * (stacked ? 0.3 : 0.02)),
  ],
);

/// The reference's `makeFormat`: compact axis ticks ("$2B"), two-decimal
/// tooltips ("$1.24B"), percent values like 45.
ChartFormat chartFormat(String? kind, String? currency) {
  final code = currency != null && RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)
      ? currency.toUpperCase()
      : 'USD';
  return (value, {compact = false}) {
    if (kind == 'percent') {
      return '${jsString(num.parse(value.toStringAsFixed(compact ? 1 : 2)))}%';
    }
    final big = value.abs() >= (compact ? 1000 : 1e6);
    final digits = compact && big ? 1 : 2;
    final NumberFormat f;
    if (kind == 'currency') {
      final symbol = NumberFormat.simpleCurrency(
        locale: 'en_US',
        name: code,
      ).currencySymbol;
      f = big
          ? NumberFormat.compactCurrency(locale: 'en_US', symbol: symbol)
          : NumberFormat.currency(locale: 'en_US', symbol: symbol);
    } else {
      f = big
          ? NumberFormat.compact(locale: 'en_US')
          : NumberFormat.decimalPattern('en_US');
    }
    f
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = digits;
    return f.format(value);
  };
}

double niceStep(double span) {
  if (span <= 0) return 1;
  final power = math.pow(10, (math.log(span) / math.ln10).floor()).toDouble();
  final n = span / power;
  return (n <= 1
          ? 1
          : n <= 2
          ? 2
          : n <= 2.5
          ? 2.5
          : n <= 5
          ? 5
          : 10) *
      power;
}

({double lo, double hi, List<double> ticks}) _axis(
  List<double> values, {
  required bool zero,
}) {
  final all = [...values, if (zero) 0.0];
  final min = all.isEmpty ? 0.0 : all.reduce(math.min),
      max = all.isEmpty ? 0.0 : all.reduce(math.max);
  final span = max - min;
  final step = niceStep(
    (span != 0 ? span : (max.abs() != 0 ? max.abs() : 1)) / 5,
  );
  final lo = (min / step).floorToDouble() * step;
  final hi = math.max(lo + step, (max / step).ceilToDouble() * step);
  return (
    lo: lo,
    hi: hi,
    ticks: [
      for (var k = 0; k <= ((hi - lo) / step).round(); k++) lo + k * step,
    ],
  );
}

/// A chart, resolved from props as the reference's `toSpec`.
final class ChartSpec {
  ChartSpec._(
    this.type,
    this.rows,
    this.x,
    this.series,
    this.stacked,
    this.height,
    this.format,
  );
  final String type;
  final List<ChartRow> rows;
  final String x;
  final List<String> series;
  final bool stacked;
  final double height;
  final ChartFormat format;

  static ChartSpec? from(Props props) {
    final rows = [
      for (final r in props.list('data'))
        if (r is Map) r.cast<String, Object?>(),
    ];
    if (rows.isEmpty) return null;
    final first = rows.first;
    final requested = props.string('type');
    final type = _types.contains(requested) ? requested! : 'bar';
    final px = props.string('x');
    final x = px != null && first.containsKey(px)
        ? px
        : first.keys.firstWhere(
            (k) => type == 'scatter' ? first[k] is num : first[k] is String,
            orElse: () => first.keys.first,
          );
    final requestedSeries = [
      for (final s in props.list('series'))
        if (s is String) s,
    ];
    final series =
        (requestedSeries.isNotEmpty
                ? requestedSeries
                : [
                    for (final k in first.keys)
                      if (k != x && first[k] is num) k,
                  ])
            .take(8)
            .toList();
    return ChartSpec._(
      type,
      rows,
      x,
      series,
      props.boolean('stacked') ?? false,
      (props.number('height')?.toDouble() ?? 240).clamp(140, 480).toDouble(),
      chartFormat(props.string('format'), props.string('currency')),
    );
  }
}

/// `Chart(type, data, x?, series?, format?, currency?, stacked?, height?)`.
Widget buildChart(BuildContext context, OpenUiNode node) {
  final spec = ChartSpec.from(node.props);
  if (spec == null) return const SizedBox(height: 240);
  final pie = spec.type == 'pie' || spec.type == 'donut';
  return Semantics(
    label: pie
        ? '${spec.type} chart of ${spec.series.firstOrNull ?? 'values'} by ${spec.x}'
        : '${spec.type} chart of ${spec.series.join(', ')} by ${spec.x}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pie) _PieChart(spec) else _PlotChart(spec),
        if (!pie && spec.series.length > 1) ...[
          const SizedBox(height: 10),
          _Legend(spec.series),
        ],
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.series);
  final List<String> series;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        for (final (i, s) in series.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(theme.chart[i % 6]),
              const SizedBox(width: 7),
              Text(
                s,
                style: TextStyle(
                  fontSize: theme.typography.size(12),
                  color: theme.muted,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Bar, line, area and scatter plots, with a hover or tap tooltip.
class _PlotChart extends StatefulWidget {
  const _PlotChart(this.spec);
  final ChartSpec spec;
  @override
  State<_PlotChart> createState() => _PlotChartState();
}

class _PlotChartState extends State<_PlotChart> {
  ({int i, int si})? _hover;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final spec = widget.spec;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final geometry = spec.type == 'scatter'
            ? _ScatterGeometry(spec, width)
            : _CartesianGeometry(spec, width);
        void move(Offset p) {
          final hit = geometry.hit(p, _hover);
          if (hit != _hover) setState(() => _hover = hit);
        }

        void leave() {
          if (_hover != null) setState(() => _hover = null);
        }

        final tip = _hover == null ? null : geometry.tooltip(_hover!, theme);
        return MouseRegion(
          onExit: (_) => leave(),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerHover: (e) => move(e.localPosition),
            onPointerMove: (e) => move(e.localPosition),
            // A touch enters a scatter dot as it lands (pointerenter).
            onPointerDown: (e) {
              if (geometry is _ScatterGeometry) move(e.localPosition);
            },
            // A finger leaves the chart as it lifts (pointerleave).
            onPointerUp: (e) {
              if (e.kind != PointerDeviceKind.mouse) leave();
            },
            onPointerCancel: (_) => leave(),
            child: GestureDetector(
              // touch-action: pan-y; a sideways drag stays on the chart.
              onHorizontalDragUpdate: (_) {},
              child: SizedBox(
                height: spec.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _PlotPainter(geometry, theme, _hover),
                      ),
                    ),
                    if (tip != null)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, box) => CustomSingleChildLayout(
                            delegate: _TipLayout(tip.anchor),
                            child: _ShrinkToFit(
                              available: box.maxWidth - tip.anchor.dx,
                              child: _Tooltip(
                                title: tip.title,
                                lines: tip.lines,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `position: absolute; left; top; transform: translateX(-50%)` with a
/// shrink-to-fit width of at least 110 (border-box).
class _TipLayout extends SingleChildLayoutDelegate {
  const _TipLayout(this.anchor);
  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints(minWidth: 110);

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      Offset(anchor.dx - childSize.width / 2, anchor.dy);

  @override
  bool shouldRelayout(_TipLayout old) => old.anchor != anchor;
}

/// CSS shrink-to-fit: the max-content width, narrowed to [available] but
/// never below the min-content width.
class _ShrinkToFit extends SingleChildRenderObjectWidget {
  const _ShrinkToFit({required this.available, required super.child});
  final double available;

  @override
  _RenderShrinkToFit createRenderObject(BuildContext context) =>
      _RenderShrinkToFit(available);

  @override
  void updateRenderObject(BuildContext context, _RenderShrinkToFit render) =>
      render.available = available;
}

class _RenderShrinkToFit extends RenderProxyBox {
  _RenderShrinkToFit(this._available);
  double _available;

  set available(double value) {
    if (value == _available) return;
    _available = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final box = child!;
    final width = math.min(
      math.max(box.getMinIntrinsicWidth(double.infinity), _available),
      box.getMaxIntrinsicWidth(double.infinity),
    );
    box.layout(
      constraints.tighten(width: constraints.constrainWidth(width)),
      parentUsesSize: true,
    );
    size = box.size;
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.title, required this.lines});
  final String title;
  final List<(Color?, String, String)> lines;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return IgnorePointer(
      child: IntrinsicWidth(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.canvas,
            border: Border.all(color: theme.border),
            borderRadius: BorderRadius.circular(theme.radii.lg),
            boxShadow: theme.shadow,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: theme.typography.size(12),
              color: theme.muted,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: theme.typography.semibold,
                    color: theme.ink,
                  ),
                ),
                for (final (color, name, value) in lines)
                  Row(
                    children: [
                      if (color != null) ...[
                        _Dot(color),
                        const SizedBox(width: 6),
                      ],
                      if (name.isNotEmpty) ...[
                        Expanded(child: Text(name)),
                        const SizedBox(width: 6 + 8),
                      ] else ...[
                        const Spacer(),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        value,
                        style: TextStyle(
                          color: theme.ink,
                          fontWeight: theme.typography.medium,
                          fontFeatures: theme.typography.tabular,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Tip = ({
  Offset anchor,
  String title,
  List<(Color?, String, String)> lines,
});

sealed class _Geometry {
  _Geometry(this.spec, this.width);
  final ChartSpec spec;
  final double width;
  ({int i, int si})? hit(Offset p, ({int i, int si})? current);
  _Tip tooltip(({int i, int si}) hover, OpenUiTheme theme);
}

final class _CartesianGeometry extends _Geometry {
  _CartesianGeometry(super.spec, super.width) {
    final rows = spec.rows, series = spec.series;
    stacked = spec.stacked && spec.type != 'line';
    tops = [
      for (final row in rows)
        () {
          var total = 0.0;
          return [
            for (final s in series)
              total += math.max(0, _num(row[s])).toDouble(),
          ];
        }(),
    ];
    final values = stacked
        ? [for (final t in tops) t.isEmpty ? 0.0 : t.last]
        : [
            for (final row in rows)
              for (final s in series) _num(row[s]).toDouble(),
          ];
    final maxV = math.max(0.0, values.fold(0.0, math.max));
    final minV = math.min(0.0, values.fold(0.0, math.min));
    final step = niceStep((maxV - minV) / 5);
    lo = (minV / step).floorToDouble() * step;
    hi = math.max(lo + step, (maxV / step).ceilToDouble() * step);
    ticks = [
      for (var k = 0; k <= ((hi - lo) / step).round(); k++) lo + k * step,
    ];
    final left =
        ticks
                .map((t) => spec.format(t, compact: true).length)
                .fold(0, math.max) *
            6.4 +
        12;
    pad = EdgeInsets.fromLTRB(left, 10, 4, 26);
    w = math.max(10, width - pad.left - pad.right);
    h = math.max(10, spec.height - pad.top - pad.bottom);
    band = w / math.max(1, rows.length);
    final longest = rows.map((r) => _label(r, spec.x).length).fold(1, math.max);
    every = math.max(1, ((longest * 6.6 + 10) / band).ceil());
  }

  late final bool stacked;
  late final List<List<double>> tops;
  late final double lo, hi;
  late final List<double> ticks;
  late final EdgeInsets pad;
  late final double w, h, band;
  late final int every;

  double xAt(int i) => pad.left + band * i + band / 2;
  double y(double v) => pad.top + h - ((v - lo) / (hi - lo)) * h;
  double top(int i, int si) =>
      stacked ? tops[i][si] : _num(spec.rows[i][spec.series[si]]).toDouble();
  double base(int i, int si) => stacked && si > 0 ? tops[i][si - 1] : 0;

  @override
  ({int i, int si})? hit(Offset p, ({int i, int si})? current) {
    final i = ((p.dx - pad.left) / band).floor();
    return i >= 0 && i < spec.rows.length ? (i: i, si: 0) : null;
  }

  @override
  _Tip tooltip(({int i, int si}) hover, OpenUiTheme theme) {
    final row = spec.rows[hover.i];
    return (
      anchor: Offset(math.min(math.max(xAt(hover.i), 70), width - 70), pad.top),
      title: _label(row, spec.x),
      lines: [
        for (final (si, s) in spec.series.indexed)
          (
            theme.chart[si % 6],
            spec.series.length > 1 ? s : '',
            spec.format(_num(row[s])),
          ),
      ],
    );
  }
}

final class _ScatterGeometry extends _Geometry {
  _ScatterGeometry(super.spec, super.width) {
    final rows = spec.rows, x = spec.x;
    final first = rows.first;
    name = first.keys.where((k) => k != x && first[k] is String).firstOrNull;
    ya = _axis([
      for (final r in rows)
        for (final s in spec.series) _num(r[s]).toDouble(),
    ], zero: false);
    xa = _axis([for (final r in rows) _num(r[x]).toDouble()], zero: false);
    final left =
        ya.ticks
                .map((t) => spec.format(t, compact: true).length)
                .fold(0, math.max) *
            6.4 +
        12;
    pad = EdgeInsets.fromLTRB(left, 10, 8, 26);
    w = math.max(10, width - pad.left - pad.right);
    h = math.max(10, spec.height - pad.top - pad.bottom);
    every = math.max(1, (xa.ticks.length * 44 / w).ceil());
  }

  late final String? name;
  late final ({double lo, double hi, List<double> ticks}) ya, xa;
  late final EdgeInsets pad;
  late final double w, h;
  late final int every;

  double px(double v) => pad.left + ((v - xa.lo) / (xa.hi - xa.lo)) * w;
  double py(double v) => pad.top + h - ((v - ya.lo) / (ya.hi - ya.lo)) * h;
  Offset point(int i, int si) => Offset(
    px(_num(spec.rows[i][spec.x]).toDouble()),
    py(_num(spec.rows[i][spec.series[si]]).toDouble()),
  );

  @override
  ({int i, int si})? hit(Offset p, ({int i, int si})? current) {
    for (var si = spec.series.length - 1; si >= 0; si--) {
      for (var i = spec.rows.length - 1; i >= 0; i--) {
        final r = (current == (i: i, si: si) ? 6.5 : 5.0) + 0.75;
        if ((point(i, si) - p).distance <= r) return (i: i, si: si);
      }
    }
    return current;
  }

  @override
  _Tip tooltip(({int i, int si}) hover, OpenUiTheme theme) {
    final row = spec.rows[hover.i];
    final s = spec.series[hover.si];
    final xValue = NumberFormat.decimalPattern('en_US')
      ..maximumFractionDigits = 2;
    return (
      anchor: Offset(
        math.min(math.max(px(_num(row[spec.x]).toDouble()), 70), width - 70),
        math.max(0, py(_num(row[s]).toDouble()) - 70),
      ),
      title: name != null ? jsString(row[name]) : s,
      lines: [
        (null, spec.x, xValue.format(_num(row[spec.x]))),
        (theme.chart[hover.si % 6], s, spec.format(_num(row[s]))),
      ],
    );
  }
}

class _PlotPainter extends CustomPainter {
  _PlotPainter(this.g, this.theme, this.hover);
  final _Geometry g;
  final OpenUiTheme theme;
  final ({int i, int si})? hover;

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    String anchor = 'start',
  }) {
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = switch (anchor) {
      'middle' => at.dx - p.width / 2,
      'end' => at.dx - p.width,
      _ => at.dx,
    };
    p.paint(
      canvas,
      Offset(
        x,
        at.dy - p.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      ),
    );
    p.dispose();
  }

  void _dashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    double on = 3,
    double off = 4,
  }) {
    final total = (b - a).distance;
    final dir = (b - a) / total;
    for (var d = 0.0; d < total; d += on + off) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + on, total), paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tick = chartTickStyle(theme);
    final grid = Paint()
      ..color = theme.border
      ..strokeWidth = 1;
    final spec = g.spec;
    switch (g) {
      case final _CartesianGeometry c:
        for (final t in c.ticks) {
          final y = c.y(t);
          final a = Offset(c.pad.left, y), b = Offset(c.pad.left + c.w, y);
          t == 0 ? canvas.drawLine(a, b, grid) : _dashed(canvas, a, b, grid);
          _text(
            canvas,
            spec.format(t, compact: true),
            Offset(c.pad.left - 10, y + 4),
            tick,
            anchor: 'end',
          );
        }
        for (var i = 0; i < spec.rows.length; i++) {
          if (i % c.every == 0) {
            _text(
              canvas,
              _label(spec.rows[i], spec.x),
              Offset(c.xAt(i), spec.height - 6),
              chartCategoryStyle(theme),
              anchor: 'middle',
            );
          }
        }
        if (hover != null && spec.type == 'bar') {
          canvas.drawRect(
            Rect.fromLTWH(
              c.pad.left + c.band * hover!.i,
              c.pad.top,
              c.band,
              c.h,
            ),
            Paint()..color = theme.surface,
          );
        }
        if (spec.type == 'bar') _bars(canvas, c);
        if (spec.type == 'line' || spec.type == 'area') _lines(canvas, c);
        if (hover != null && spec.type != 'bar') {
          final x = c.xAt(hover!.i);
          _dashed(
            canvas,
            Offset(x, c.pad.top),
            Offset(x, c.pad.top + c.h),
            Paint()..color = theme.borderStrong,
            on: 3,
            off: 3,
          );
        }
      case final _ScatterGeometry s:
        for (final t in s.ya.ticks) {
          final y = s.py(t);
          _dashed(
            canvas,
            Offset(s.pad.left, y),
            Offset(s.pad.left + s.w, y),
            grid,
          );
          _text(
            canvas,
            spec.format(t, compact: true),
            Offset(s.pad.left - 10, y + 4),
            tick,
            anchor: 'end',
          );
        }
        for (final (k, t) in s.xa.ticks.indexed) {
          if (k % s.every != 0) continue;
          final value = num.parse(t.toStringAsFixed(6));
          final f = value.abs() >= 1e4
              ? NumberFormat.compact(locale: 'en_US')
              : NumberFormat.decimalPattern('en_US');
          _text(
            canvas,
            f.format(value),
            Offset(s.px(t), spec.height - 6),
            tick,
            anchor: 'middle',
          );
        }
        for (var si = 0; si < spec.series.length; si++) {
          for (var i = 0; i < spec.rows.length; i++) {
            final r = hover == (i: i, si: si) ? 6.5 : 5.0;
            final p = s.point(i, si);
            canvas
              ..drawCircle(
                p,
                r,
                Paint()..color = theme.chart[si % 6].withValues(alpha: 0.78),
              )
              ..drawCircle(
                p,
                r,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.5
                  ..color = theme.canvas,
              );
          }
        }
    }
  }

  void _bars(Canvas canvas, _CartesianGeometry c) {
    final spec = c.spec;
    for (var i = 0; i < spec.rows.length; i++) {
      final inner = math.min(
        c.band * 0.7,
        72.0 * math.max(1, c.stacked ? 1 : spec.series.length),
      );
      if (c.stacked) {
        for (var si = 0; si < spec.series.length; si++) {
          final top = c.y(c.tops[i][si]);
          final base = c.y(si > 0 ? c.tops[i][si - 1] : 0);
          final rect = Rect.fromLTWH(
            c.xAt(i) - inner / 2,
            top,
            inner,
            math.max(0, base - top),
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              rect,
              _svgRadius(rect, si == spec.series.length - 1 ? 4 : 0),
            ),
            Paint()..color = theme.chart[si % 6],
          );
        }
        continue;
      }
      final each = inner / spec.series.length;
      for (var si = 0; si < spec.series.length; si++) {
        final v = _num(spec.rows[i][spec.series[si]]).toDouble();
        final rect = Rect.fromLTWH(
          c.xAt(i) - inner / 2 + each * si + 1,
          math.min(c.y(v), c.y(0)),
          math.max(1, each - 2),
          (c.y(0) - c.y(v)).abs(),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, _svgRadius(rect, 4)),
          Paint()..color = theme.chart[si % 6],
        );
      }
    }
  }

  void _lines(Canvas canvas, _CartesianGeometry c) {
    final spec = c.spec;
    final n = spec.rows.length;
    for (var si = 0; si < spec.series.length; si++) {
      final color = theme.chart[si % 6];
      final points = [
        for (var i = 0; i < n; i++) Offset(c.xAt(i), c.y(c.top(i, si))),
      ];
      final path = [
        for (final p in points) Offset(_fixed1(p.dx), _fixed1(p.dy)),
      ];
      if (spec.type == 'area' && n > 1) {
        final under = [
          for (var i = n - 1; i >= 0; i--)
            Offset(_fixed1(c.xAt(i)), _fixed1(c.y(c.base(i, si)))),
        ];
        final area = Path()..addPolygon([...path, ...under], true);
        final fill = areaFill(area, color, stacked: c.stacked);
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: fill.colors,
            ).createShader(fill.rect),
        );
      }
      canvas.drawPath(
        Path()..addPolygon(path, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      for (var i = 0; i < n; i++) {
        if (n > 16 && hover?.i != i) continue;
        final r = hover?.i == i ? 4.5 : 3.0;
        canvas
          ..drawCircle(points[i], r, Paint()..color = color)
          ..drawCircle(
            points[i],
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = theme.canvas,
          );
      }
    }
  }

  @override
  bool shouldRepaint(_PlotPainter old) =>
      old.hover != hover || old.g != g || old.theme != theme;
}

class _PieChart extends StatelessWidget {
  const _PieChart(this.spec);
  final ChartSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final key = spec.series.firstOrNull;
    final items = [
      for (final row in spec.rows)
        (
          label: _label(row, spec.x),
          value: math.max(0, key == null ? 0 : _num(row[key])).toDouble(),
        ),
    ];
    final sum = items.fold(0.0, (a, b) => a + b.value);
    final total = sum == 0 ? 1.0 : sum;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final size = (width < 420 ? width * 0.62 : 200.0).clamp(80.0, 200.0);
        final legend = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 9,
          children: [
            for (final (i, item) in items.indexed)
              Row(
                children: [
                  _Dot(theme.chart[i % 6]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: theme.typography.size(13),
                        color: theme.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${jsString((item.value / total * 1000).round() / 10)}%',
                    style: TextStyle(
                      fontSize: theme.typography.size(13),
                      fontWeight: theme.typography.medium,
                      color: theme.ink,
                      fontFeatures: theme.typography.tabular,
                    ),
                  ),
                ],
              ),
          ],
        );
        final chart = SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _PiePainter(
              [for (final i in items) i.value / total],
              spec.type == 'donut',
              theme,
            ),
          ),
        );
        // .iui-pie: flex-wrap with a 24 gap; the legend's basis is 160.
        return size + 24 + 160 <= width
            ? Row(
                children: [
                  chart,
                  const SizedBox(width: 24),
                  Expanded(child: legend),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [chart, const SizedBox(height: 24), legend],
              );
      },
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.shares, this.donut, this.theme);
  final List<double> shares;
  final bool donut;
  final OpenUiTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    final inner = donut ? r * 0.62 : 0.0;
    var angle = -math.pi / 2;
    for (final (i, share) in shares.indexed) {
      final sweep = share * math.pi * 2;
      final color = theme.chart[i % 6];
      final path = Path();
      if (sweep >= math.pi * 2 - 1e-6) {
        path.addOval(Rect.fromCircle(center: center, radius: r));
        if (donut) {
          path
            ..addOval(Rect.fromCircle(center: center, radius: inner))
            ..fillType = PathFillType.evenOdd;
        }
      } else {
        final outer = Rect.fromCircle(center: center, radius: r);
        if (donut) {
          path
            ..arcTo(outer, angle, sweep, true)
            ..arcTo(
              Rect.fromCircle(center: center, radius: inner),
              angle + sweep,
              -sweep,
              false,
            )
            ..close();
        } else {
          path
            ..moveTo(r, r)
            ..arcTo(outer, angle, sweep, false)
            ..close();
        }
      }
      canvas.drawPath(path, Paint()..color = color);
      if (sweep < math.pi * 2 - 1e-6) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = theme.canvas,
        );
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) => true;
}
