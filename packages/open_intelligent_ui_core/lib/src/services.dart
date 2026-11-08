import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A place on a map.
typedef LatLng = ({double lat, double lng});

/// Draws icon [name] (lucide kebab-case: "map-pin") at [size] in [color], or
/// returns null when it has no such icon.
typedef OpenUiIconResolver =
    Widget? Function(String name, double size, Color color, double strokeWidth);

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
    this.embedReferrer,
    this.icons,
  }) : _openUrl = openUrl,
       _copyText = copyText;

  /// The Referer native YouTube embeds send, such as https://com.example.app.
  final String? embedReferrer;

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

  /// Icons by name, tried before the built-in set. Null or a null result
  /// falls back to the built-in icons, and a name neither draws shows nothing.
  final OpenUiIconResolver? icons;

  /// Opens an http(s) URL; without an openUrl it does nothing.
  Future<void> openUrl(Uri url) => _openUrl?.call(url) ?? Future<void>.value();

  /// Copies text; the default uses the system clipboard.
  Future<void> copyText(String text) =>
      _copyText?.call(text) ?? Clipboard.setData(ClipboardData(text: text));

  /// These services, with [fallback]'s openUrl, copyText, searchImages,
  /// streetRoute, embedReferrer and icons wherever this sets none. mapTiles is
  /// always this one's. Returns this when [fallback] fills nothing.
  OpenUiServices orElse(OpenUiServices fallback) {
    final fills =
        (_openUrl == null && fallback._openUrl != null) ||
        (_copyText == null && fallback._copyText != null) ||
        (searchImages == null && fallback.searchImages != null) ||
        (streetRoute == null && fallback.streetRoute != null) ||
        (embedReferrer == null && fallback.embedReferrer != null) ||
        (icons == null && fallback.icons != null);
    if (!fills) return this;
    return OpenUiServices(
      openUrl: _openUrl ?? fallback._openUrl,
      copyText: _copyText ?? fallback._copyText,
      searchImages: searchImages ?? fallback.searchImages,
      streetRoute: streetRoute ?? fallback.streetRoute,
      mapTiles: mapTiles,
      embedReferrer: embedReferrer ?? fallback.embedReferrer,
      icons: icons ?? fallback.icons,
    );
  }
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

/// Provides [OpenUiServices] to the components below it, into routes too.
class OpenUiScope extends InheritedTheme {
  const OpenUiScope({super.key, required this.services, required super.child});
  final OpenUiServices services;

  static OpenUiServices servicesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OpenUiScope>()?.services ??
      const OpenUiServices();

  @override
  bool updateShouldNotify(OpenUiScope old) => services != old.services;

  @override
  Widget wrap(BuildContext context, Widget child) =>
      OpenUiScope(services: services, child: child);
}
