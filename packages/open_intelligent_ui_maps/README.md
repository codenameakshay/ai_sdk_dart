# open_intelligent_ui_maps

Map, MapMarker and OsrmStreetRoute components for Open Intelligent UI, drawn with flutter_map. It brings
flutter_map, latlong2 and http.

Install:

```sh
fvm flutter pub add open_intelligent_ui_maps
```

## Use

```dart
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';
import 'package:open_intelligent_ui_maps/open_intelligent_ui_maps.dart';

final builders = composeBuilders([mapBuilders]);
final library = intelligentUiFor(builders);
final session = OpenUiSession(library)..update(textSoFar, streaming: true);

OpenUiScope(
  services: OpenUiServices(
    mapTiles: esriStreetTiles, // optional: draws street tiles
    streetRoute: OsrmStreetRoute().call, // optional: follows streets
  ),
  child: OpenUiView(session: session, builders: builders),
);
```

Map tiles are off by default, so a map draws only its markers and route. Pass `mapTiles: esriStreetTiles`
to draw Esri's street tiles from server.arcgisonline.com, or your own `MapTiles` with light and dark URL
templates. Without `streetRoute` a route draws straight segments; `OsrmStreetRoute` routes through
router.project-osrm.org.

The library from `intelligentUiFor` lists `Map` and `MapMarker`, so `library.systemPrompt(chatPromptFor(library))`
tells the model they exist.

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
