import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// The first points of [points], cut at [progress] (0 to 1) of its length.
List<LatLng> partialLine(List<LatLng> points, double progress) {
  final lengths = [
    for (var i = 1; i < points.length; i++)
      math.sqrt(
        math.pow(points[i].lat - points[i - 1].lat, 2).toDouble() +
            math.pow(points[i].lng - points[i - 1].lng, 2).toDouble(),
      ),
  ];
  var remaining = lengths.fold(0.0, (a, b) => a + b) * progress;
  final out = <LatLng>[points.first];
  for (var i = 0; i < lengths.length; i++) {
    final a = points[i], b = points[i + 1];
    if (remaining >= lengths[i]) {
      out.add(b);
      remaining -= lengths[i];
      continue;
    }
    final t = lengths[i] > 0 ? remaining / lengths[i] : 0.0;
    out.add((
      lat: a.lat + (b.lat - a.lat) * t,
      lng: a.lng + (b.lng - a.lng) * t,
    ));
    break;
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

const _glassShadow = [
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 12),
];

const _flyDuration = Duration(milliseconds: 920);

class _StreetMapState extends State<StreetMap> with TickerProviderStateMixin {
  final fm.MapController _controller = fm.MapController();
  final _portal = OverlayPortalController();
  final _mapKey = GlobalKey();
  late final AnimationController _line;
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: _flyDuration,
  );
  bool _expanded = false;
  bool _userMoved = false;
  Timer? _flyDone;
  final Map<int, Offset> _touches = {};
  String _group = 'all';
  bool _info = false;
  bool _ready = false;
  bool _hint = false;
  bool _lineDrawn = false;
  String _framed = '';
  String? _routeKey;
  List<LatLng>? _street;
  bool _routeFailed = false;
  String? _failedTiles;
  Timer? _routeDebounce;
  Timer? _hintTimer;

  List<Place> get _visible => [
    for (final p in widget.places)
      if (_group == 'all' || p.category == _group) p,
  ];

  List<String> get _categories => [
    ...{for (final p in widget.places) ?p.category},
  ];

  String get _routingKey => _visible.map((p) => '${p.lng},${p.lat}').join(';');

  List<LatLng> get _routePositions {
    if (!widget.route || _visible.length < 2) return const [];
    return _street ?? [for (final p in _visible) (lat: p.lat, lng: p.lng)];
  }

  @override
  void initState() {
    super.initState();
    _line = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
      value: 1,
    );
  }

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
    _hintTimer?.cancel();
    _flyDone?.cancel();
    _fly.dispose();
    _line.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _syncRoute() {
    final key = _routingKey;
    final service = OpenUiScope.servicesOf(context).streetRoute;
    if (!widget.route || key != _routeKey) {
      _routeDebounce?.cancel();
      _routeKey = null;
      _street = null;
      _routeFailed = false;
    }
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
      if (!mounted) return;
      if (_userMoved || MediaQuery.disableAnimationsOf(context)) {
        if (!_userMoved) {
          _fit(const EdgeInsets.fromLTRB(72, 70, 72, 50), maxZoom: 13);
        }
        _drawLine();
        return;
      }
      // As the reference clears the line, no route shows until framing ends.
      if (!_lineDrawn) _line.value = 0;
      _flyTo(const EdgeInsets.fromLTRB(72, 70, 72, 50), maxZoom: 13);
      _flyDone?.cancel();
      _flyDone = Timer(_flyDuration + const Duration(milliseconds: 40), () {
        if (mounted) _drawLine();
      });
    });
  }

  /// The camera that fits the visible places, or null with none.
  fm.MapCamera? _fitted(EdgeInsets padding, {required double maxZoom}) {
    final points = [for (final p in _visible) p.point];
    if (points.isEmpty) return null;
    final camera = _controller.camera;
    if (points.length == 1) {
      return camera.withPosition(center: points.single, zoom: maxZoom);
    }
    return fm.CameraFit.coordinates(
      coordinates: points,
      padding: padding,
      maxZoom: maxZoom,
    ).fit(camera);
  }

  /// Flies to the fitted camera as MapLibre's fitBounds does.
  void _flyTo(EdgeInsets padding, {required double maxZoom}) {
    final target = _fitted(padding, maxZoom: maxZoom);
    if (target == null) return;
    final start = _controller.camera;
    final curve = CurvedAnimation(parent: _fly, curve: Curves.easeInOut);
    void step() {
      final t = curve.value;
      _controller.move(
        ll.LatLng(
          start.center.latitude +
              (target.center.latitude - start.center.latitude) * t,
          start.center.longitude +
              (target.center.longitude - start.center.longitude) * t,
        ),
        start.zoom + (target.zoom - start.zoom) * t,
      );
    }

    _fly
      ..stop()
      ..value = 0;
    curve.addListener(step);
    _fly.forward().whenCompleteOrCancel(() {
      curve
        ..removeListener(step)
        ..dispose();
    });
  }

  void _mapEvent(fm.MapEvent event) {
    const userStarts = {
      fm.MapEventSource.dragStart,
      fm.MapEventSource.multiFingerGestureStart,
    };
    if (event is fm.MapEventMoveStart && userStarts.contains(event.source)) {
      _userMoved = true;
      _fly.stop();
    }
  }

  void _setExpanded(bool expanded) {
    if (expanded == _expanded) return;
    setState(() => _expanded = expanded);
    expanded ? _portal.show() : _portal.hide();
  }

  /// Draws the route once, after framing; later changes update it in place.
  void _drawLine() {
    if (_lineDrawn || _routePositions.length < 2) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _line.value = 1;
      _lineDrawn = true;
      return;
    }
    _line.forward(from: 0).then((_) {
      _lineDrawn = true;
    });
  }

  void _fit(EdgeInsets padding, {required double maxZoom}) {
    final target = _fitted(padding, maxZoom: maxZoom);
    if (target != null) _controller.move(target.center, target.zoom);
  }

  void _zoom(double by) {
    final camera = _controller.camera;
    _controller.move(camera.center, camera.zoom + by);
  }

  void _tilesFailed(String url) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _failedTiles != url) setState(() => _failedTiles = url);
    });
  }

  void _touchDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _touches[event.pointer] = event.position;
    _hintTimer?.cancel();
  }

  void _touchMove(PointerMoveEvent event) {
    final start = _touches[event.pointer];
    if (event.kind != PointerDeviceKind.touch ||
        start == null ||
        _hint ||
        _touches.length != 1 ||
        (event.position - start).distance <= 18) {
      return;
    }
    setState(() => _hint = true);
  }

  void _touchUp(PointerEvent event) {
    if (_touches.remove(event.pointer) == null ||
        _touches.isNotEmpty ||
        !_hint) {
      return;
    }
    _hintTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _hint = false);
    });
  }

  Widget _filter(OpenUiTheme theme, List<String> categories) => Semantics(
    label: 'Filter places',
    container: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: _Glass(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 30, 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _group,
                  isDense: true,
                  icon: const SizedBox.shrink(),
                  style: TextStyle(fontSize: 12, height: 1.5, color: theme.ink),
                  dropdownColor: theme.canvas,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text(
                        'All places',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c,
                        child: Text(
                          c,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() => _group = v ?? 'all');
                    _syncRoute();
                    _frame();
                  },
                ),
              ),
            ),
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Glyph('chevron-down', size: 14, color: theme.ink),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _zoomButton(OpenUiTheme theme, String label, String icon, double by) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: () => _zoom(by),
          child: SizedBox.square(
            dimension: 28,
            child: Center(child: Glyph(icon, size: 16, color: theme.ink)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final services = OpenUiScope.servicesOf(context);
    final tiles = services.mapTiles;
    final tileUrl = tiles == null
        ? null
        : theme.brightness == Brightness.dark
        ? tiles.dark
        : tiles.light;
    final tilesFailed = tileUrl != null && _failedTiles == tileUrl;
    final selected = widget.selection.value is String
        ? widget.selection.value as String
        : null;
    final visible = _visible;
    final categories = _categories;
    final positions = _routePositions;
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
    final routeStatus = switch (routeKind) {
      'street' => 'Street route loaded.',
      'overview' => 'Street routing unavailable. Showing direct connections.',
      'loading' => 'Street route loading.',
      _ => '',
    };
    final touch = switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    // Touch platforms scroll the page with one finger; two fingers move the map.
    final flags = touch
        ? fm.InteractiveFlag.all &
              ~fm.InteractiveFlag.drag &
              ~fm.InteractiveFlag.flingAnimation &
              ~fm.InteractiveFlag.rotate &
              ~fm.InteractiveFlag.scrollWheelZoom
        : fm.InteractiveFlag.all &
              ~fm.InteractiveFlag.rotate &
              ~fm.InteractiveFlag.scrollWheelZoom;
    // Pins with the selected one last, so it paints over its neighbours.
    final ordered = [
      ...visible.where((p) => p.label != selected),
      ...visible.where((p) => p.label == selected),
    ];
    final map = fm.FlutterMap(
      mapController: _controller,
      options: fm.MapOptions(
        initialCenter: visible.isEmpty
            ? const ll.LatLng(20, 0)
            : visible.first.point,
        initialZoom: visible.isEmpty ? 1 : 10.5,
        backgroundColor: theme.mapWater,
        interactionOptions: fm.InteractionOptions(flags: flags),
        onMapEvent: _mapEvent,
        onMapReady: () {
          _ready = true;
          _frame();
        },
      ),
      children: [
        if (tileUrl != null)
          fm.TileLayer(
            urlTemplate: tileUrl,
            userAgentPackageName: 'dev.ai_sdk_dart.open_intelligent_ui',
            errorTileCallback: (tile, error, stackTrace) =>
                _tilesFailed(tileUrl),
          ),
        if (positions.length > 1)
          ListenableBuilder(
            listenable: _line,
            builder: (context, _) => fm.PolylineLayer(
              polylines: [
                fm.Polyline(
                  points: _drawn(positions),
                  color: theme.ink,
                  strokeWidth: 3.2,
                  strokeCap: StrokeCap.round,
                ),
              ],
            ),
          ),
        fm.MarkerLayer(
          markers: [
            for (final p in ordered)
              fm.Marker(
                key: ValueKey('pin:${p.key}'),
                point: p.point,
                width: 160,
                height: 52,
                alignment: Alignment(0, 1 - 34 / 52),
                child: _Pin(
                  place: p,
                  selected: selected == p.label,
                  onTap: () {
                    widget.selection.set(p.label);
                    _setExpanded(false);
                  },
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
    final requested = (widget.height ?? 400).clamp(200.0, 720.0);
    // Phones get a shorter map so it never fills the whole screen.
    final height = math.min(
      requested,
      math.max(280.0, MediaQuery.sizeOf(context).width * 0.82),
    );
    final surface = KeyedSubtree(
      key: _mapKey,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OpenUiTheme.radius2xl),
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: _touchDown,
                onPointerMove: _touchMove,
                onPointerUp: _touchUp,
                onPointerCancel: _touchUp,
                child: map,
              ),
            ),
            if (_hint)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: Text(
                        'Use two fingers to move the map',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 12,
              left: 12,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  if (categories.length > 1) _filter(theme, categories),
                  SizedBox.square(
                    dimension: 34,
                    child: _Glass(
                      circle: true,
                      tooltip: 'Show every place',
                      onTap: () => MediaQuery.disableAnimationsOf(context)
                          ? _fit(
                              const EdgeInsets.fromLTRB(34, 55, 40, 35),
                              maxZoom: 14,
                            )
                          : _flyTo(
                              const EdgeInsets.fromLTRB(34, 55, 40, 35),
                              maxZoom: 14,
                            ),
                      child: Glyph('navigation', size: 22, color: theme.ink),
                    ),
                  ),
                  SizedBox.square(
                    dimension: 34,
                    child: _Glass(
                      circle: true,
                      tooltip: 'About this map',
                      onTap: () => setState(() => _info = !_info),
                      child: Glyph('info', size: 18, color: theme.ink),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                child: _Glass(
                  onTap: () => _setExpanded(!_expanded),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 6,
                    children: [
                      Text(
                        _expanded ? 'Collapse' : 'Expand',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          fontWeight: FontWeight.w500,
                          color: theme.ink,
                        ),
                      ),
                      Glyph('expand', size: 14, color: theme.ink),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                  boxShadow: _glassShadow,
                ),
                child: Material(
                  color: theme.glass,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: theme.glassRing),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _zoomButton(theme, 'Zoom in', 'plus', 1),
                      _zoomButton(theme, 'Zoom out', 'minus', -1),
                    ],
                  ),
                ),
              ),
            ),
            if (_info)
              Positioned(
                top: 56,
                left: 12,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 275),
                  child: _Card(
                    child: Text(
                      'Drag to explore and use + and − to zoom. Select a place to highlight it.$routeNote',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: theme.muted,
                      ),
                    ),
                  ),
                ),
              ),
            if (routeKind == 'overview')
              Positioned(
                bottom: 22,
                left: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.canvas.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Text(
                      'Route overview',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.6,
                        color: theme.muted,
                      ),
                    ),
                  ),
                ),
              ),
            if (tilesFailed)
              Positioned(
                bottom: 28,
                left: 12,
                child: Semantics(
                  liveRegion: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 275),
                    child: _Card(
                      child: Text(
                        'Map tiles are temporarily unavailable. The places are still shown.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              top: 0,
              child: Semantics(
                container: true,
                liveRegion: true,
                label: routeStatus,
                child: const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => _overlay(context, theme, surface),
      child: Semantics(
        container: true,
        label: 'Map',
        child: SizedBox(height: height, child: _expanded ? null : surface),
      ),
    );
  }

  Widget _overlay(BuildContext context, OpenUiTheme theme, Widget surface) {
    final inset = MediaQuery.sizeOf(context).width <= 520 ? 12.0 : 24.0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setExpanded(false);
      },
      child: Stack(
        children: [
          ModalBarrier(
            color: theme.canvas.withValues(alpha: 0.9),
            dismissible: false,
          ),
          Positioned.fill(
            left: inset,
            top: inset,
            right: inset,
            bottom: inset,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _setExpanded(false),
              },
              child: Focus(
                autofocus: true,
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: 'Map',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        OpenUiTheme.radius2xl,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x2E000000),
                          offset: Offset(0, 12),
                          blurRadius: 64,
                        ),
                      ],
                    ),
                    child: surface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<ll.LatLng> _drawn(List<LatLng> positions) {
    final t = _line.value;
    final points = t >= 1
        ? positions
        : partialLine(
            positions,
            t < 0.5 ? 2 * t * t : 1 - (2 - 2 * t) * (2 - 2 * t) / 2,
          );
    return [for (final p in points) ll.LatLng(p.lat, p.lng)];
  }
}

class _Glass extends StatefulWidget {
  const _Glass({
    required this.child,
    this.onTap,
    this.tooltip,
    this.circle = false,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool circle;
  final EdgeInsetsGeometry padding;

  @override
  State<_Glass> createState() => _GlassState();
}

class _GlassState extends State<_Glass> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final ring = _hover ? theme.glassRingHover : theme.glassRing;
    final OutlinedBorder shape = widget.circle
        ? CircleBorder(side: BorderSide(color: ring))
        : StadiumBorder(side: BorderSide(color: ring));
    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: widget.circle ? null : BorderRadius.circular(999),
        boxShadow: _glassShadow,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: _hover ? theme.glassHover : theme.glass,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: widget.onTap,
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      box = Tooltip(
        message: widget.tooltip!,
        child: Semantics(button: true, label: widget.tooltip, child: box),
      );
    }
    return box;
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.canvas,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(OpenUiTheme.radiusLg),
        boxShadow: theme.shadow,
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
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
    final compact = MediaQuery.sizeOf(context).width <= 520;
    final numbered = place.icon == null;
    final face = numbered
        ? SizedBox.square(
            dimension: 26,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.ink,
                border: Border.all(color: theme.canvas, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    offset: Offset(0, 2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${place.order + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: theme.onInk,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          )
        : SizedBox.square(
            dimension: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.canvas,
                border: Border.all(color: theme.glassRing),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24000000),
                    offset: Offset(0, 2),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  place.icon!,
                  style: const TextStyle(fontSize: 18, height: 1),
                ),
              ),
            ),
          );
    final pin = Stack(
      clipBehavior: Clip.none,
      children: [
        face,
        if (selected)
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.ink, width: 3),
              ),
            ),
          ),
      ],
    );
    final fontSize = compact ? 10.0 : 12.0;
    final halo = [
      for (final offset in const [
        Offset(0, 1),
        Offset(0, -1),
        Offset(1, 0),
        Offset(-1, 0),
      ])
        Shadow(color: theme.canvas, offset: offset, blurRadius: 2),
    ];
    return Semantics(
      button: true,
      selected: selected,
      label: place.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 160,
          height: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              numbered
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: pin,
                    )
                  : pin,
              const SizedBox(height: 3),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 120 : 160),
                child: Text(
                  place.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: fontSize,
                    height: 15 / fontSize,
                    fontWeight: FontWeight.w600,
                    color: theme.ink,
                    shadows: halo,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
