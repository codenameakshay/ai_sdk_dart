import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

const _userAgent = {
  'User-Agent':
      'open_intelligent_ui (https://github.com/codenameakshay/ai_sdk_dart)',
};

/// Street geometry between stops from an OSRM server (by default the public
/// demo server, a road overview, not walking directions). A port of the
/// reference's `/api/street-route` route. Pass an instance as
/// [OpenUiServices.streetRoute].
final class OsrmStreetRoute {
  OsrmStreetRoute({
    http.Client? client,
    this.baseUrl = 'https://router.project-osrm.org',
  }) : _client = client ?? http.Client();
  final http.Client _client;
  final String baseUrl;
  final Map<String, List<LatLng>> _cache = {};

  static const maxStops = 25;

  Future<List<LatLng>?> call(List<LatLng> stops) async {
    if (stops.length < 2 || stops.length > maxStops) return null;
    if (stops.any((p) => p.lat.abs() > 90 || p.lng.abs() > 180)) return null;
    final key = stops.map((p) => '${p.lng},${p.lat}').join(';');
    if (_cache[key] case final hit?) return hit;
    try {
      final url = Uri.parse(
        '$baseUrl/route/v1/driving/$key?overview=full&geometries=geojson&steps=false',
      );
      final response = await _client
          .get(url, headers: _userAgent)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final coordinates = _list(
        _path(data, ['routes', 0, 'geometry', 'coordinates']),
      );
      if (_path(data, ['code']) != 'Ok' || coordinates.length < 2) return null;
      final route = <LatLng>[
        for (final c in coordinates)
          if (c is List && c.length >= 2 && c[0] is num && c[1] is num)
            (lat: (c[1] as num).toDouble(), lng: (c[0] as num).toDouble()),
      ];
      if (route.length < 2) return null;
      if (_cache.length >= 200) _cache.remove(_cache.keys.first);
      return _cache[key] = route;
    } on Object {
      return null;
    }
  }
}

Object? _path(Object? v, List<Object> keys) {
  var cur = v;
  for (final k in keys) {
    if (k is int && cur is List && k < cur.length) {
      cur = cur[k];
    } else if (k is String && cur is Map) {
      cur = cur[k];
    } else {
      return null;
    }
  }
  return cur;
}

List<Object?> _list(Object? v) => v is List ? v : const [];
