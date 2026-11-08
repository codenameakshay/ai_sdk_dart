import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:path_parsing/path_parsing.dart';

import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

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

final _pictographic = RegExp(r'\p{Extended_Pictographic}', unicode: true);

/// The first character of [value] when it is an emoji, so a word from the
/// model cannot overflow the round pin.
String? pinEmoji(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final first = trimmed.characters.first;
  return _pictographic.hasMatch(first) ? first : null;
}

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

/// MapLibre's flyTo path (van Wijk and Nuij 2003; maplibre-gl 6.14
/// `Camera.flyTo`, curve 1.42): a flight of [u1] pixels at the start zoom
/// [z0] to zoom [z1], in a viewport whose larger side is [w0]. [length] is S
/// in ρ-screenfuls (the default duration is 1000·S/1.2 ms); [at] gives the
/// zoom and the fraction of the ground path at eased progress k. Null when
/// the camera would not move.
({double length, ({double zoom, double along}) Function(double k) at})?
flyPath({
  required double w0,
  required double u1,
  required double z0,
  required double z1,
  required double minZoom,
}) {
  double cosh(double n) => (math.exp(n) + math.exp(-n)) / 2;
  double sinh(double n) => (math.exp(n) - math.exp(-n)) / 2;
  double tanh(double n) => sinh(n) / cosh(n);
  final w1 = w0 / math.pow(2, z1 - z0);
  final wMax = w0 / math.pow(2, math.min(minZoom, math.min(z0, z1)) - z0);
  final rho = math.min(1.42, math.sqrt(wMax / u1 * 2));
  final rho2 = rho * rho;
  double zoomOut(bool descent) {
    final b =
        (w1 * w1 - w0 * w0 + (descent ? -1 : 1) * rho2 * rho2 * u1 * u1) /
        (2 * (descent ? w1 : w0) * rho2 * u1);
    return math.log(math.sqrt(b * b + 1) - b);
  }

  final r0 = zoomOut(false);
  var w = (double s) => cosh(r0) / cosh(r0 + rho * s);
  var u = (double s) =>
      w0 * ((cosh(r0) * tanh(r0 + rho * s) - sinh(r0)) / rho2) / u1;
  var length = (zoomOut(true) - r0) / rho;
  if (u1.abs() < 0.000002 || !length.isFinite) {
    if ((w0 - w1).abs() < 0.000001) return null;
    final k = w1 < w0 ? -1 : 1;
    length = math.log(w1 / w0).abs() / rho;
    u = (_) => 0;
    w = (s) => math.exp(k * rho * s);
  }
  final total = length;
  return (
    length: total,
    at: (double k) => k == 1
        ? (zoom: z1, along: 1.0)
        : (
            zoom: z0 + math.log(1 / w(k * total)) / math.ln2,
            along: u(k * total),
          ),
  );
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

/// CSS `saturate(1.4)`.
const _saturate = <double>[
  1.3148,
  -0.286,
  -0.0288,
  0,
  0,
  -0.0852,
  1.114,
  -0.0288,
  0,
  0,
  -0.0852,
  -0.286,
  1.3712,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

/// `backdrop-filter: blur(12px) saturate(1.4)`.
final _glassFilter = ui.ImageFilter.compose(
  outer: const ColorFilter.matrix(_saturate),
  inner: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
);

const _flyDuration = Duration(milliseconds: 920);

// flutter_map zooms are MapLibre's plus one: 256px tiles against 512px.
const _zoomOffset = 1.0;
const _minZoom = 0 + _zoomOffset;
const _maxZoom = 22 + _zoomOffset;
const _worldZoom = 1 + _zoomOffset;
const _anchorZoom = 10.5 + _zoomOffset;
const _frameMaxZoom = 13 + _zoomOffset;
const _recenterMaxZoom = 14 + _zoomOffset;

/// map.tsx FRAME_PADDING: room for the controls and the pin labels.
const _framePadding = EdgeInsets.fromLTRB(72, 70, 72, 50);

/// The "Show every place" padding.
const _recenterPadding = EdgeInsets.fromLTRB(34, 55, 40, 35);

/// MapLibre's NavigationControl icons (maplibre-gl.css), in a 29px box.
const _zoomInIcon =
    'M14.5 8.5c-.75 0-1.5.75-1.5 1.5v3h-3c-.75 0-1.5.75-1.5 1.5S9.25 16 10 16h3v3c0 .75.75 1.5 1.5 1.5S16 19.75 16 19v-3h3c.75 0 1.5-.75 1.5-1.5S19.75 13 19 13h-3v-3c0-.75-.75-1.5-1.5-1.5';
const _zoomOutIcon =
    'M10 13c-.75 0-1.5.75-1.5 1.5S9.25 16 10 16h9c.75 0 1.5-.75 1.5-1.5S19.75 13 19 13z';

class _StreetMapState extends State<StreetMap> with TickerProviderStateMixin {
  final fm.MapController _controller = fm.MapController();

  /// The expanded map: a dialog route, so its barrier hides the page from
  /// screen readers as aria-modal does.
  ModalRoute<void>? _route;
  final _overlayTick = ValueNotifier(0);
  bool _active = true;
  final _mapKey = GlobalKey();
  late final AnimationController _line;
  late final AnimationController _fly = AnimationController(
    vsync: this,
    duration: _flyDuration,
  );
  bool _expanded = false;
  final Set<String> _popped = {};
  FocusNode? _restoreFocus;
  bool _userMoved = false;
  Timer? _flyDone;
  VoidCallback? _flight;
  bool _anchored = false;
  bool _atMin = false;
  bool _atMax = false;
  bool _mouseOver = false;
  bool _touchOver = false;
  bool _focusWithin = false;
  final Map<int, Offset> _touches = {};
  String _group = 'all';
  bool _info = false;
  bool _ready = false;
  bool _hint = false;
  bool _lineDrawn = false;
  bool _routeVisible = false;
  String _framed = '';
  String? _routeKey;
  int _routeGeneration = 0;
  Future<List<LatLng>?> Function(List<LatLng>)? _routeService;
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
    _anchored = widget.places.isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRoute();
    _overlayChanged();
  }

  @override
  void didUpdateWidget(StreetMap old) {
    super.didUpdateWidget(old);
    _overlayChanged();
    if (!_categories.contains(_group)) _group = 'all';
    _syncRoute();
    _anchor();
    _frame();
  }

  /// The expanded map is built by its route, so it rebuilds with this state.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _overlayTick.value++;
  }

  /// A rebuild from above (new places, theme) reaches the route a frame
  /// later: marking it dirty during this build is not allowed.
  void _overlayChanged() {
    if (_route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _overlayTick.value++;
    });
  }

  // The navigator can rebuild the route while this state is inactive (moving,
  // or about to be disposed); it shows nothing until the state is back.
  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    _overlayChanged();
  }

  @override
  void dispose() {
    if (_expanded) _refocus();
    final route = _route;
    if (route != null) {
      // The navigator cannot change while the tree is being finalized.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator!.removeRoute(route);
      });
    }
    _overlayTick.dispose();
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
    if (!widget.route || key != _routeKey || service != _routeService) {
      _routeService = service;
      _routeGeneration++;
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
    final generation = _routeGeneration;
    _routeDebounce = Timer(const Duration(milliseconds: 700), () async {
      List<LatLng>? points;
      try {
        points = await service(stops);
      } on Object {
        points = null;
      }
      if (!mounted || _routeGeneration != generation || _routeKey != key) {
        return;
      }
      setState(() {
        _street = points != null && points.length >= 2 ? points : null;
        _routeFailed = _street == null;
      });
    });
  }

  /// Once streaming ends (or the filter changes), fit the markers.
  void _frame() {
    if (!_ready) return;
    if (widget.streaming || _visible.isEmpty) {
      _flyDone?.cancel();
      _flyDone = null;
      return;
    }
    final signature = jsonEncode([_group, _routingKey]);
    if (signature == _framed) return;
    _framed = signature;
    _flyDone?.cancel();
    _flyDone = null;
    _routeVisible = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.streaming ||
          _visible.isEmpty ||
          _framed != signature ||
          jsonEncode([_group, _routingKey]) != signature) {
        return;
      }
      if (_userMoved || MediaQuery.disableAnimationsOf(context)) {
        if (!_userMoved) {
          _fit(_framePadding, maxZoom: _frameMaxZoom);
        }
        if (!_routeVisible) setState(() => _routeVisible = true);
        _drawLine();
        return;
      }
      _flyTo(_framePadding, maxZoom: _frameMaxZoom, duration: _flyDuration);
      _flyDone = Timer(_flyDuration + const Duration(milliseconds: 40), () {
        if (!mounted ||
            widget.streaming ||
            _visible.isEmpty ||
            _framed != signature ||
            jsonEncode([_group, _routingKey]) != signature) {
          return;
        }
        if (!_routeVisible) setState(() => _routeVisible = true);
        _drawLine();
      });
    });
  }

  /// The camera that fits the visible places (MapLibre cameraForBounds), or
  /// null with none or when the padding leaves no room.
  fm.MapCamera? _fitted(EdgeInsets padding, {required double maxZoom}) {
    final points = [for (final p in _visible) p.point];
    final camera = _controller.camera;
    final size = camera.nonRotatedSize;
    if (points.isEmpty ||
        size.width < padding.horizontal ||
        size.height < padding.vertical) {
      return null;
    }
    return fm.CameraFit.coordinates(
      coordinates: points,
      padding: padding,
      maxZoom: maxZoom,
    ).fit(camera);
  }

  /// MapLibre's flyTo to the fitted camera; without a [duration] it flies at
  /// MapLibre's default speed (1.2 screenfuls a second).
  void _flyTo(
    EdgeInsets padding, {
    required double maxZoom,
    Duration? duration,
  }) {
    final target = _fitted(padding, maxZoom: maxZoom);
    if (target == null) return;
    final start = _controller.camera;
    final from = start.projectAtZoom(start.center, start.zoom);
    final delta = start.projectAtZoom(target.center, start.zoom) - from;
    final size = start.nonRotatedSize;
    final path = flyPath(
      w0: math.max(size.width, size.height),
      u1: delta.distance,
      z0: start.zoom,
      z1: target.zoom,
      minZoom: _minZoom,
    );
    if (path == null) {
      _endFlight();
      _controller.move(target.center, target.zoom);
      return;
    }
    _animate(
      duration ?? Duration(microseconds: (path.length / 1.2 * 1e6).round()),
      (k) {
        if (k == 1) {
          _controller.move(target.center, target.zoom);
          return;
        }
        final at = path.at(k);
        _controller.move(
          start.unprojectAtZoom(from + delta * at.along, start.zoom),
          at.zoom,
        );
      },
    );
  }

  /// Runs one camera animation with MapLibre's ease curve, replacing any
  /// running one.
  void _animate(Duration duration, void Function(double k) frame) {
    _endFlight();
    void tick() => frame(Curves.ease.transform(_fly.value));
    _fly
      ..duration = duration
      ..value = 0
      ..addListener(tick);
    _flight = tick;
    _fly.forward();
  }

  void _endFlight() {
    _fly.stop();
    final flight = _flight;
    if (flight != null) _fly.removeListener(flight);
    _flight = null;
  }

  /// map.tsx: the camera jumps to the first place once, as soon as it exists.
  void _anchor() {
    if (_anchored || !_ready || _visible.isEmpty) return;
    _anchored = true;
    _endFlight();
    _controller.move(_visible.first.point, _anchorZoom);
  }

  void _mapEvent(fm.MapEvent event) {
    const userStarts = {
      fm.MapEventSource.dragStart,
      fm.MapEventSource.multiFingerGestureStart,
    };
    if (event is fm.MapEventMoveStart && userStarts.contains(event.source)) {
      _userMoved = true;
      _endFlight();
    }
    final zoom = event.camera.zoom;
    final atMin = zoom <= _minZoom, atMax = zoom >= _maxZoom;
    if (atMin != _atMin || atMax != _atMax) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _atMin = atMin;
            _atMax = atMax;
          });
        }
      });
    }
  }

  void _setExpanded(bool expanded) {
    if (expanded == _expanded) return;
    if (expanded) {
      // use-dialog: remember what had focus, then focus the dialog itself.
      _restoreFocus = FocusManager.instance.primaryFocus;
      _restoreFocus?.unfocus();
      final route = _route = RawDialogRoute<void>(
        barrierColor: null,
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => ListenableBuilder(
          listenable: _overlayTick,
          builder: (context, _) =>
              _active ? _overlay(context) : const SizedBox.shrink(),
        ),
      );
      Navigator.of(context).push(route);
      // Popped by anything else (Navigator.pop, popUntil): back to the page.
      route.popped.whenComplete(() {
        if (mounted && _route == route) _setExpanded(false);
      });
    } else {
      _refocus();
      final route = _route;
      _route = null;
      if (route != null && route.isActive) route.navigator!.removeRoute(route);
    }
    setState(() => _expanded = expanded);
  }

  void _refocus() {
    final node = _restoreFocus;
    _restoreFocus = null;
    if (node == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.context != null && node.canRequestFocus) node.requestFocus();
    });
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
    if (target == null) return;
    _endFlight();
    _controller.move(target.center, target.zoom);
  }

  /// NavigationControl: easeTo one level in or out over 500ms.
  void _zoom(double by) {
    final camera = _controller.camera;
    final target = (camera.zoom + by).clamp(_minZoom, _maxZoom).toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      _endFlight();
      _controller.move(camera.center, target);
      return;
    }
    final center = camera.center, from = camera.zoom;
    _animate(
      const Duration(milliseconds: 500),
      (k) => _controller.move(center, from + (target - from) * k),
    );
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
                  style: TextStyle(
                    fontSize: theme.typography.size(12),
                    height: 1.5,
                    color: theme.ink,
                  ),
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
                    _anchor();
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
                child: Glyph(
                  'chevron-down',
                  size: 14,
                  color: theme.ink,
                  strokeWidth: 2.4,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// The map and its controls, in the page or in the expanded route; it
  /// always reads this state's [context].
  Widget _surface() {
    final context = this.context;
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
    final pinOrder = {for (final (i, p) in visible.indexed) p.key: i};
    _popped.retainAll(pinOrder.keys);
    final map = fm.FlutterMap(
      mapController: _controller,
      options: fm.MapOptions(
        initialCenter: visible.isEmpty
            ? const ll.LatLng(20, 0)
            : visible.first.point,
        initialZoom: visible.isEmpty ? _worldZoom : _anchorZoom,
        minZoom: _minZoom,
        maxZoom: _maxZoom,
        backgroundColor: theme.mapWater,
        interactionOptions: fm.InteractionOptions(
          flags: flags,
          keyboardOptions: const fm.KeyboardOptions(autofocus: false),
        ),
        onMapEvent: _mapEvent,
        onMapReady: () {
          _ready = true;
          _anchor();
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
        if (positions.length > 1 && _routeVisible)
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
                child: FocusTraversalOrder(
                  order: NumericFocusOrder(pinOrder[p.key]!.toDouble()),
                  child: _Pin(
                    place: p,
                    selected: selected == p.label,
                    popIn: _popped.add(p.key),
                    onTap: () {
                      widget.selection.set(p.label);
                      _setExpanded(false);
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    return KeyedSubtree(
      key: _mapKey,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focusWithin = focused),
        child: TapRegion(
          onTapInside: (e) {
            if (e.kind != PointerDeviceKind.mouse && !_touchOver) {
              setState(() => _touchOver = true);
            }
          },
          onTapOutside: (e) {
            if (e.kind != PointerDeviceKind.mouse && _touchOver) {
              setState(() => _touchOver = false);
            }
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _mouseOver = true),
            onExit: (_) => setState(() => _mouseOver = false),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(theme.radii.xxl),
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Listener(
                        onPointerDown: _touchDown,
                        onPointerMove: _touchMove,
                        onPointerUp: _touchUp,
                        onPointerCancel: _touchUp,
                        child: FocusTraversalOrder(
                          order: const NumericFocusOrder(-1),
                          child: map,
                        ),
                      ),
                    ),
                    if (tiles != null)
                      Positioned(
                        left: 0,
                        right: 50,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.canvas.withValues(
                                alpha: theme.canvas.a * 0.9,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              child: Text(
                                tiles.attribution,
                                style: TextStyle(
                                  fontSize: theme.typography.size(8),
                                  height: 10 / 8,
                                  color: theme.muted,
                                  fontFamily: 'Helvetica Neue',
                                  fontFamilyFallback: const [
                                    'Arial',
                                    'Helvetica',
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_hint)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Color(0x66000000),
                            child: Center(
                              child: Text(
                                'Use two fingers to move the map',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: theme.typography.size(20),
                                ),
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
                          if (categories.length > 1)
                            FocusTraversalOrder(
                              order: const NumericFocusOrder(2000),
                              child: _filter(theme, categories),
                            ),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(2001),
                            child: SizedBox.square(
                              dimension: 34,
                              child: _Glass(
                                circle: true,
                                tooltip: 'Show every place',
                                onTap: () =>
                                    MediaQuery.disableAnimationsOf(context)
                                    ? _fit(
                                        _recenterPadding,
                                        maxZoom: _recenterMaxZoom,
                                      )
                                    : _flyTo(
                                        _recenterPadding,
                                        maxZoom: _recenterMaxZoom,
                                      ),
                                child: Glyph(
                                  'navigation',
                                  size: 22,
                                  color: theme.ink,
                                  strokeWidth: 1.6,
                                ),
                              ),
                            ),
                          ),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(2002),
                            child: SizedBox.square(
                              dimension: 34,
                              child: _Glass(
                                circle: true,
                                tooltip: 'About this map',
                                expanded: _info,
                                onTap: () => setState(() => _info = !_info),
                                child: Glyph(
                                  'info',
                                  size: 18,
                                  color: theme.ink,
                                  strokeWidth: 1.8,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(3000),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 28),
                          child: _Glass(
                            expanded: _expanded,
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
                                    fontSize: theme.typography.size(12),
                                    height: 1.5,
                                    fontWeight: theme.typography.medium,
                                    color: theme.ink,
                                  ),
                                ),
                                Glyph(
                                  'expand',
                                  size: 14,
                                  color: theme.ink,
                                  strokeWidth: 1.92,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: AnimatedOpacity(
                        opacity: _mouseOver || _touchOver || _focusWithin
                            ? 1
                            : 0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.ease,
                        alwaysIncludeSemantics: true,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                            boxShadow: _glassShadow,
                          ),
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(10),
                            ),
                            child: BackdropFilter(
                              filter: _glassFilter,
                              child: Material(
                                color: theme.glass,
                                clipBehavior: Clip.antiAlias,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    theme.radii.md,
                                  ),
                                  side: BorderSide(color: theme.glassRing),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(1000),
                                      child: _ZoomButton(
                                        label: 'Zoom in',
                                        icon: _zoomInIcon,
                                        divider: false,
                                        enabled: !_atMax,
                                        onTap: () => _zoom(1),
                                      ),
                                    ),
                                    FocusTraversalOrder(
                                      order: const NumericFocusOrder(1001),
                                      child: _ZoomButton(
                                        label: 'Zoom out',
                                        icon: _zoomOutIcon,
                                        divider: true,
                                        enabled: !_atMin,
                                        onTap: () => _zoom(-1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
                                fontSize: theme.typography.size(12),
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
                            borderRadius: BorderRadius.circular(theme.radii.sm),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            child: Text(
                              'Route overview',
                              style: TextStyle(
                                fontSize: theme.typography.size(10),
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
                                  fontSize: theme.typography.size(12),
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
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requested = (widget.height ?? 400).clamp(200.0, 720.0);
    // Phones get a shorter map so it never fills the whole screen.
    final height = math.min(
      requested,
      math.max(280.0, MediaQuery.sizeOf(context).width * 0.82),
    );
    return Semantics(
      container: true,
      label: 'Map',
      child: SizedBox(height: height, child: _expanded ? null : _surface()),
    );
  }

  /// The expanded map, built in its route under the page's themes and media
  /// query (as an OverlayPortal child would be), with the route's insets.
  Widget _overlay(BuildContext context) {
    final page = this.context;
    final theme = OpenUiTheme.of(page);
    final inset = MediaQuery.sizeOf(context).width <= 520 ? 12.0 : 24.0;
    // A phone's status bar and home indicator sit inside the reference's inset.
    final safe = MediaQuery.paddingOf(context);
    final overlay = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _setExpanded(false);
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(color: theme.canvas.withValues(alpha: 0.9)),
            ),
          ),
          Positioned.fill(
            left: inset + safe.left,
            top: inset + safe.top,
            right: inset + safe.right,
            bottom: inset + safe.bottom,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _setExpanded(false),
              },
              child: FocusScope(
                autofocus: true,
                child: Semantics(
                  scopesRoute: true,
                  namesRoute: true,
                  explicitChildNodes: true,
                  label: 'Map',
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(theme.radii.xxl),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x2E000000),
                          offset: Offset(0, 12),
                          blurRadius: 64,
                        ),
                      ],
                    ),
                    child: _surface(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return InheritedTheme.capture(
      from: page,
      to: Navigator.of(page).context,
    ).wrap(
      MediaQuery(
        data: MediaQuery.of(page).copyWith(
          padding: safe,
          viewPadding: MediaQuery.viewPaddingOf(context),
          viewInsets: MediaQuery.viewInsetsOf(context),
        ),
        child: overlay,
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
    this.expanded,
    this.circle = false,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  /// `aria-expanded`: null for a control that opens nothing.
  final bool? expanded;
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
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: BackdropFilter(
            filter: _glassFilter,
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
        ),
      ),
    );
    box = MergeSemantics(
      child: Semantics(
        button: true,
        expanded: widget.expanded,
        label: widget.tooltip,
        child: box,
      ),
    );
    if (widget.tooltip != null) {
      box = Tooltip(message: widget.tooltip!, child: box);
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
        borderRadius: BorderRadius.circular(theme.radii.lg),
        boxShadow: theme.shadow,
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

class _Pin extends StatefulWidget {
  const _Pin({
    required this.place,
    required this.selected,
    required this.popIn,
    required this.onTap,
  });
  final Place place;
  final bool selected;

  /// The pin is new: run the reference's pop-in.
  final bool popIn;
  final VoidCallback onTap;

  @override
  State<_Pin> createState() => _PinState();
}

class _PinState extends State<_Pin> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 104),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _in,
    curve: const Cubic(0.2, 0.7, 0.3, 1),
  );
  late final Animation<double> _scale = Tween<double>(
    begin: 0.75,
    end: 1,
  ).animate(_curve);
  bool _started = false;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.popIn && !MediaQuery.disableAnimationsOf(context)) {
      _in.forward();
    } else {
      _in.value = 1;
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final compact = MediaQuery.sizeOf(context).width <= 520;
    final place = widget.place;
    final selected = widget.selected;
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
                    fontSize: theme.typography.size(12),
                    height: 1,
                    fontWeight: theme.typography.semibold,
                    color: theme.onInk,
                    fontFeatures: theme.typography.tabular,
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
                  style: TextStyle(
                    fontSize: theme.typography.size(18),
                    height: 1,
                  ),
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
    final content = SizedBox(
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
                fontFamily: 'Arial',
                fontFamilyFallback: const ['Helvetica'],
                fontSize: theme.typography.size(fontSize),
                height: 15 / fontSize,
                fontWeight: theme.typography.semibold,
                color: theme.ink,
                shadows: halo,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: place.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: Tooltip(
          message: place.label,
          excludeFromSemantics: true,
          triggerMode: TooltipTriggerMode.manual,
          waitDuration: const Duration(milliseconds: 500),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                FadeTransition(
                  opacity: _curve,
                  child: ScaleTransition(
                    scale: _scale,
                    // transform-origin: 50% 17px of the 52px-high content.
                    alignment: const Alignment(0, 17 / 26 - 1),
                    child: content,
                  ),
                ),
                // :focus-visible: 2px at a 3px offset around the 34x52 marker.
                if (_focused)
                  Positioned(
                    left: 80 - 17 - 5,
                    top: -5,
                    width: 44,
                    height: 62,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.ink, width: 2),
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
  }
}

/// One button of MapLibre's zoom control.
class _ZoomButton extends StatefulWidget {
  const _ZoomButton({
    required this.label,
    required this.icon,
    required this.divider,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final String icon;
  final bool divider;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ZoomButton> createState() => _ZoomButtonState();
}

class _ZoomButtonState extends State<_ZoomButton> {
  bool _hover = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = OpenUiTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    Widget button = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: widget.enabled && (_hover || _pressed)
            ? const Color(0x0D000000)
            : null,
        border: widget.divider
            ? const Border(top: BorderSide(color: Color(0xFFDDDDDD)))
            : null,
      ),
      child: Center(
        child: OverflowBox(
          maxWidth: 29,
          maxHeight: 29,
          child: Opacity(
            opacity: widget.enabled ? 1 : 0.25,
            child: CustomPaint(
              size: const Size.square(29),
              painter: _IconPainter(
                widget.icon,
                dark ? const Color(0xFFCCCCCC) : const Color(0xFF333333),
              ),
            ),
          ),
        ),
      ),
    );
    if (_focused) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF0096FF),
                    blurRadius: 2,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
          button,
          Positioned(
            left: -5,
            top: -5,
            right: -5,
            bottom: -5,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: theme.ink, width: 2),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        mouseCursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) widget.onTap();
              return null;
            },
          ),
        },
        child: Tooltip(
          message: widget.label,
          excludeFromSemantics: true,
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.enabled ? widget.onTap : null,
            child: button,
          ),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.d, this.color);
  final String d;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    writeSvgPathDataToPath(d, _ToPath(path));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.d != d || old.color != color;
}

final class _ToPath extends PathProxy {
  _ToPath(this.path);
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
