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
  services: OpenUiServices(streetRoute: OsrmStreetRoute().call),
  child: OpenUiView(session: session, builders: builders),
);
```

The library from `intelligentUiFor` lists `Map` and `MapMarker`, so `library.systemPrompt(chatPromptFor(library))`
tells the model they exist.

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
