import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;

import '../services.dart';
import '../theme.dart';
import '../view.dart';
import 'glyph.dart';

/// Shapes and pins live inside a Map, which draws them; alone they are nothing.
Widget buildMapMarker(BuildContext context, OpenUiNode node) =>
    const SizedBox.shrink();

/// One place on the map, as plain data.
final class Place {
  const Place({
    required this.key,
    required this.label,
    required this.lat,
    required this.lng,
    required this.order,
    this.category,
    this.icon,
  });
  final String key;
  final String label;
  final double lat;
  final double lng;
  final int order;
  final String? category;
  final String? icon;

  ll.LatLng get point => ll.LatLng(lat, lng);
}

/// The first character of [value] when it is an emoji, so a word from the
/// model cannot overflow the round pin.
String? pinEmoji(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final first = trimmed.characters.first;
  return first.runes.any(_pictographic) ? first : null;
}

// ponytail: the main Extended_Pictographic blocks, not the full Unicode table.
bool _pictographic(int cp) =>
    (cp >= 0x1F000 && cp <= 0x1FAFF) ||
    (cp >= 0x2600 && cp <= 0x27BF) ||
    (cp >= 0x2190 && cp <= 0x21FF) ||
    (cp >= 0x2300 && cp <= 0x23FF) ||
    (cp >= 0x25A0 && cp <= 0x25FF) ||
    (cp >= 0x2B00 && cp <= 0x2BFF) ||
    const {
      0xA9,
      0xAE,
      0x203C,
      0x2049,
      0x2122,
      0x2139,
      0x24C2,
      0x3030,
      0x303D,
      0x3297,
      0x3299,
    }.contains(cp);

/// The markers as places. While streaming, only finished markers count, so
/// a half-written coordinate never moves a pin. Repeated labels get "(2)".
List<Place> placesOf(List<OpenUiElement> markers, {required bool streaming}) {
  final seen = <String, int>{};
  final out = <Place>[];
  for (final (order, el) in markers.indexed) {
    if (el.typeName != 'MapMarker' || (streaming && el.isPartial)) continue;
    final label = el.props.string('label');
    final lat = el.props.number('lat'), lng = el.props.number('lng');
    if (label == null ||
        label.trim().isEmpty ||
        lat == null ||
        lng == null ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      continue;
    }
    final count = seen[label] ?? 0;
    seen[label] = count + 1;
    final category = el.props.string('category')?.trim();
    out.add(
      Place(
        key: count > 0 ? '$label (${count + 1})' : label,
        label: label,
        lat: lat.toDouble(),
        lng: lng.toDouble(),
        order: order,
        category: category == null || category.isEmpty ? null : category,
        icon: pinEmoji(el.props['icon']),
      ),
    );
  }
  return out;
}

/// `Map(markers, route?, selected?, height?)`.
Widget buildMap(BuildContext context, OpenUiNode node) => StreetMap(
  places: placesOf(node.props.elements('markers'), streaming: node.isStreaming),
  route: node.props.boolean('route') ?? false,
  selection: node.field('selected', name: node.element.statementId),
  height: node.props.number('height')?.toDouble(),
  streaming: node.isStreaming,
);

class StreetMap extends StatefulWidget {
  const StreetMap({
    super.key,
    required this.places,
    required this.route,
    required this.selection,
    required this.streaming,
    this.height,
  });
  final List<Place> places;
  final bool route;
  final FieldState selection;
  final bool streaming;
  final double? height;

  @override
  State<StreetMap> createState() => _StreetMapState();
}

class _StreetMapState extends State<StreetMap> {
  final fm.MapController _controller = fm.MapController();
  String _group = 'all';
  bool _info = false;
  bool _ready = false;
  String _framed = '';
  String? _routeKey;
  List<LatLng>? _street;
  bool _routeFailed = false;
  Timer? _routeDebounce;

  List<Place> get _visible => [
    for (final p in widget.places)
      if (_group == 'all' || p.category == _group) p,
  ];

  List<String> get _categories => [
    ...{for (final p in widget.places) ?p.category},
  ];

  String get _routingKey => _visible.map((p) => '${p.lng},${p.lat}').join(';');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRoute();
  }

  @override
  void didUpdateWidget(StreetMap old) {
    super.didUpdateWidget(old);
    if (!_categories.contains(_group)) _group = 'all';
    _syncRoute();
    _frame();
  }

  @override
  void dispose() {
    _routeDebounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _syncRoute() {
    final key = _routingKey;
    final service = OpenUiScope.servicesOf(context).streetRoute;
    if (!widget.route ||
        widget.streaming ||
        key == _routeKey ||
        !key.contains(';')) {
      return;
    }
    _routeKey = key;
    _street = null;
    _routeFailed = service == null;
    if (service == null) return;
    _routeDebounce?.cancel();
    final stops = [for (final p in _visible) (lat: p.lat, lng: p.lng)];
    _routeDebounce = Timer(const Duration(milliseconds: 700), () async {
      List<LatLng>? points;
      try {
        points = await service(stops);
      } on Object {
        points = null;
      }
      if (!mounted || _routeKey != key) return;
      setState(() {
        _street = points != null && points.length >= 2 ? points : null;
        _routeFailed = _street == null;
      });
    });
  }

  /// Once streaming ends (or the filter changes), fit the markers.
  void _frame() {
    if (!_ready || widget.streaming || _visible.isEmpty) return;
    final signature = jsonEncode([_group, _routingKey]);
    if (signature == _framed) return;
    _framed = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fit(const EdgeInsets.fromLTRB(72, 70, 72, 50), maxZoom: 13);
    });
  }

  void _fit(EdgeInsets padding, {required double maxZoom}) {
    final points = [for (final p in _visible) p.point];
    if (points.isEmpty) return;
    if (points.length == 1) {
      _controller.move(points.single, maxZoom);
      return;
    }
    _controller.fitCamera(
      fm.CameraFit.coordinates(
        coordinates: points,
        padding: padding,
        maxZoom: maxZoom,
      ),
    );
  }

  Future<void> _expand() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Map')),
        body: StreetMap(
          places: widget.places,
          route: widget.route,
          selection: widget.selection,
          streaming: widget.streaming,
          height: double.infinity,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final services = OpenUiScope.servicesOf(context);
    final tiles = services.mapTiles;
    final selected = widget.selection.value is String
        ? widget.selection.value as String
        : null;
    final visible = _visible;
    final categories = _categories;
    final linePoints = !widget.route || visible.length < 2
        ? const <ll.LatLng>[]
        : _street != null
        ? [for (final p in _street!) ll.LatLng(p.lat, p.lng)]
        : [for (final p in visible) p.point];
    final routeKind = !widget.route
        ? 'none'
        : _street != null
        ? 'street'
        : (_routeFailed ? 'overview' : 'loading');
    final routeNote = switch (routeKind) {
      'street' =>
        ' The line follows streets; it is an overview, not turn-by-turn directions.',
      'none' => '',
      _ =>
        ' The line joins the places in order. Street routing is loading or unavailable.',
    };
    final map = fm.FlutterMap(
      mapController: _controller,
      options: fm.MapOptions(
        initialCenter: visible.isEmpty
            ? const ll.LatLng(20, 0)
            : visible.first.point,
        initialZoom: visible.isEmpty ? 1 : 10.5,
        backgroundColor: theme.mapWater,
        interactionOptions: const fm.InteractionOptions(
          flags:
              fm.InteractiveFlag.all &
              ~fm.InteractiveFlag.rotate &
              ~fm.InteractiveFlag.scrollWheelZoom,
        ),
        onMapReady: () {
          _ready = true;
          _frame();
        },
      ),
      children: [
        if (tiles != null)
          fm.TileLayer(
            urlTemplate: theme.brightness == Brightness.dark
                ? tiles.dark
                : tiles.light,
            userAgentPackageName: 'dev.ai_sdk_dart.open_intelligent_ui',
          ),
        if (linePoints.length > 1)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(
                points: linePoints,
                color: theme.ink,
                strokeWidth: 3.2,
                strokeCap: StrokeCap.round,
              ),
            ],
          ),
        fm.MarkerLayer(
          markers: [
            for (final p in visible)
              fm.Marker(
                key: ValueKey(p.key),
                point: p.point,
                width: 120,
                height: 64,
                alignment: const Alignment(0, 0.45),
                child: _Pin(
                  place: p,
                  selected: selected == p.label,
                  onTap: () => widget.selection.set(p.label),
                ),
              ),
          ],
        ),
        if (tiles != null)
          fm.RichAttributionWidget(
            attributions: [fm.TextSourceAttribution(tiles.attribution)],
            alignment: fm.AttributionAlignment.bottomLeft,
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final requested = (widget.height ?? 400).clamp(200.0, 720.0);
        final height = widget.height == double.infinity
            ? constraints.maxHeight
            : math.min(requested, math.max(280.0, width * 0.82));
        return Semantics(
          container: true,
          label: 'Map',
          child: SizedBox(
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(OpenUiTheme.radius2xl),
              child: Stack(
                children: [
                  Positioned.fill(child: map),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        if (categories.length > 1) ...[
                          Flexible(
                            child: _Glass(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _group,
                                  isDense: true,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.ink,
                                  ),
                                  dropdownColor: theme.canvas,
                                  items: [
                                    const DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All places'),
                                    ),
                                    for (final c in categories)
                                      DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                  ],
                                  isExpanded: true,
                                  onChanged: (v) =>
                                      setState(() => _group = v ?? 'all'),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        _Glass(
                          tooltip: 'Show every place',
                          onTap: () => _fit(
                            const EdgeInsets.fromLTRB(34, 55, 40, 35),
                            maxZoom: 14,
                          ),
                          child: Glyph(
                            'navigation',
                            size: 16,
                            color: theme.ink,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Glass(
                          tooltip: 'About this map',
                          onTap: () => setState(() => _info = !_info),
                          child: Glyph('info', size: 16, color: theme.ink),
                        ),
                        const Spacer(),
                        if (widget.height != double.infinity)
                          _Glass(
                            onTap: _expand,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Expand',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.ink,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Glyph('expand', size: 14, color: theme.ink),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_info)
                    Positioned(
                      top: 56,
                      left: 12,
                      right: 12,
                      child: _Glass(
                        child: Text(
                          'Drag to explore and pinch to zoom. Select a place to highlight it.$routeNote',
                          style: TextStyle(fontSize: 12, color: theme.ink),
                        ),
                      ),
                    ),
                  if (routeKind == 'overview')
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: _Glass(
                        child: Text(
                          'Route overview',
                          style: TextStyle(fontSize: 12, color: theme.ink),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.onTap, this.tooltip});
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    Widget box = Material(
      color: theme.glass,
      shape: StadiumBorder(side: BorderSide(color: theme.glassRing)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: child,
        ),
      ),
    );
    if (tooltip != null) {
      box = Tooltip(
        message: tooltip!,
        child: Semantics(button: true, label: tooltip, child: box),
      );
    }
    return box;
  }
}

class _Pin extends StatelessWidget {
  const _Pin({
    required this.place,
    required this.selected,
    required this.onTap,
  });
  final Place place;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: place.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 34 : 30,
              height: selected ? 34 : 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected || place.icon == null
                    ? theme.ink
                    : theme.canvas,
                border: Border.all(color: theme.canvas, width: 2),
                boxShadow: theme.shadowSmall,
              ),
              child: Text(
                place.icon ?? '${place.order + 1}',
                style: TextStyle(
                  fontSize: place.icon != null ? 16 : 13,
                  fontWeight: FontWeight.w600,
                  color: selected || place.icon == null
                      ? theme.onInk
                      : theme.ink,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.glass,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                place.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: theme.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
