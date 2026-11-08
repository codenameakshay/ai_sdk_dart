import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// A place on a map.
typedef LatLng = ({double lat, double lng});

/// What components need from the host app. Nothing here calls a server the
/// host did not choose.
@immutable
final class OpenUiServices {
  const OpenUiServices({
    Future<void> Function(Uri url)? openUrl,
    Future<void> Function(String text)? copyText,
    this.searchImages,
    this.streetRoute,
    this.mapTiles = esriStreetTiles,
  }) : _openUrl = openUrl,
       _copyText = copyText;

  final Future<void> Function(Uri url)? _openUrl;
  final Future<void> Function(String text)? _copyText;

  /// Photo URLs for a query such as "Belém Tower Lisbon", best first. Without
  /// it, `SearchImage` shows an empty photo.
  final Future<List<Uri>> Function(String query)? searchImages;

  /// The street path through [stops] in order, or null when routing fails.
  /// Without it, a `Map` route draws straight segments.
  final Future<List<LatLng>?> Function(List<LatLng> stops)? streetRoute;

  /// Raster tiles for `Map`, chosen by brightness; null shows no tiles.
  final MapTiles? mapTiles;

  /// Opens an http(s) URL; the default opens it outside the app.
  Future<void> openUrl(Uri url) =>
      _openUrl?.call(url) ??
      launchUrl(url, mode: LaunchMode.externalApplication).then((_) {});

  /// Copies text; the default uses the system clipboard.
  Future<void> copyText(String text) =>
      _copyText?.call(text) ?? Clipboard.setData(ClipboardData(text: text));
}

/// A raster tile source: a URL template with `{z}`, `{x}` and `{y}`.
@immutable
final class MapTiles {
  const MapTiles({
    required this.light,
    required this.dark,
    required this.attribution,
  });
  final String light;
  final String dark;
  final String attribution;
}

/// The reference's raster basemap (Esri World Street Map and Dark Gray).
const esriStreetTiles = MapTiles(
  light:
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
  dark:
      'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
  attribution: 'Tiles © Esri · OpenStreetMap contributors',
);

/// Provides [OpenUiServices] to the components below it.
class OpenUiScope extends InheritedWidget {
  const OpenUiScope({super.key, required this.services, required super.child});
  final OpenUiServices services;

  static OpenUiServices servicesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OpenUiScope>()?.services ??
      const OpenUiServices();

  @override
  bool updateShouldNotify(OpenUiScope old) => services != old.services;
}
