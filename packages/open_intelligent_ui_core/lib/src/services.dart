import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'image_host_provider.dart';

/// A place on a map.
typedef LatLng = ({double lat, double lng});

/// Draws icon [name] (lucide kebab-case: "map-pin") at [size] in [color], or
/// returns null when it has no such icon.
typedef OpenUiIconResolver =
    Widget? Function(String name, double size, Color color, double strokeWidth);

/// Returns the image for [url], or null to block it.
typedef OpenUiImageLoader = ImageProvider? Function(Uri url);

/// What components need from the host app. Nothing here calls a server the
/// host did not choose: by default there are no map tiles and no images.
@immutable
final class OpenUiServices {
  const OpenUiServices({
    Future<void> Function(Uri url)? openUrl,
    Future<void> Function(String text)? copyText,
    this.searchImages,
    this.streetRoute,
    this.mapTiles,
    this.imageLoader,
    this.embedReferrer,
    this.icons,
    this.fontFamily,
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

  /// Raster tiles for `Map`, chosen by brightness. Null (the default) draws no
  /// tiles; pass [esriStreetTiles] to opt in.
  final MapTiles? mapTiles;

  /// Images for `Image`, `SearchImage` and YouTube thumbnails. Null (the
  /// default) blocks them all; see [networkImages] and [allowImageHosts].
  final OpenUiImageLoader? imageLoader;

  /// Icons by name, tried before the built-in set. Null or a null result
  /// falls back to the built-in icons, and a name neither draws shows nothing.
  final OpenUiIconResolver? icons;

  /// The text font when the view's theme sets none, like [icons] a bundled
  /// resource: the open_intelligent_ui package supplies its Inter here.
  final String? fontFamily;

  /// Opens an http(s) URL; without an openUrl it does nothing.
  Future<void> openUrl(Uri url) => _openUrl?.call(url) ?? Future<void>.value();

  /// Copies text; the default uses the system clipboard.
  Future<void> copyText(String text) =>
      _copyText?.call(text) ?? Clipboard.setData(ClipboardData(text: text));

  /// These services, with [fallback]'s openUrl, copyText, searchImages,
  /// streetRoute, imageLoader, embedReferrer, icons and fontFamily wherever
  /// this sets none.
  /// mapTiles is always this one's. Returns this when [fallback] fills nothing.
  OpenUiServices orElse(OpenUiServices fallback) {
    final fills =
        (_openUrl == null && fallback._openUrl != null) ||
        (_copyText == null && fallback._copyText != null) ||
        (searchImages == null && fallback.searchImages != null) ||
        (streetRoute == null && fallback.streetRoute != null) ||
        (imageLoader == null && fallback.imageLoader != null) ||
        (embedReferrer == null && fallback.embedReferrer != null) ||
        (icons == null && fallback.icons != null) ||
        (fontFamily == null && fallback.fontFamily != null);
    if (!fills) return this;
    return OpenUiServices(
      openUrl: _openUrl ?? fallback._openUrl,
      copyText: _copyText ?? fallback._copyText,
      searchImages: searchImages ?? fallback.searchImages,
      streetRoute: streetRoute ?? fallback.streetRoute,
      mapTiles: mapTiles,
      imageLoader: imageLoader ?? fallback.imageLoader,
      embedReferrer: embedReferrer ?? fallback.embedReferrer,
      icons: icons ?? fallback.icons,
      fontFamily: fontFamily ?? fallback.fontFamily,
    );
  }
}

/// Loads every http(s) image.
ImageProvider? networkImages(Uri url) => _httpImage(url);

/// Loads images only from [hosts] and their subdomains; other hosts are
/// blocked. Host names are case-insensitive. Redirects are rejected so an
/// allowed server cannot load an image from a different host. Only HTTP and
/// HTTPS URLs are accepted. On web, the image server must allow the app's
/// origin with CORS; otherwise the image fails closed. An image larger than
/// [maxBytes], or whose fetch takes longer than [timeout], fails.
OpenUiImageLoader allowImageHosts(
  Iterable<String> hosts, {
  int maxBytes = defaultImageMaxBytes,
  Duration timeout = defaultImageTimeout,
}) {
  final allowed = {for (final h in hosts) h.toLowerCase()};
  return (url) {
    if (url.scheme != 'http' && url.scheme != 'https') return null;
    final host = url.host.toLowerCase();
    final ok = allowed.any((h) => host == h || host.endsWith('.$h'));
    return ok
        ? AllowlistedImageProvider(url, maxBytes: maxBytes, timeout: timeout)
        : null;
  };
}

ImageProvider? _httpImage(Uri url) => switch (url.scheme) {
  'http' || 'https' => NetworkImage(url.toString()),
  _ => null,
};

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
