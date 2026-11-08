# open_intelligent_ui

Renders [Open Intelligent UI](https://github.com/thesysdev/open-intelligent-ui) answers in
Flutter. The model writes a small OpenUI Lang program; this package shows it as native widgets
while it streams, keeps its `$state` local, and sends only `@ToAssistant` back to your chat.

It ports every component of the reference library (layout, text, inputs, media, tables, charts,
maps, drawings, games) with its light and dark theme tokens. The language and the library spec
live in the pure-Dart [`ai_sdk_openui`](../ai_sdk_openui), which this package re-exports.

## Use

```dart
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

final session = OpenUiSession(intelligentUi, tools: myTools)
  ..update(textSoFar, streaming: true);

OpenUiScope(
  services: OpenUiServices(
    searchImages: WikimediaImageSearch().call, // optional photo search
    streetRoute: OsrmStreetRoute().call, // optional street routes
  ),
  child: OpenUiView(
    session: session,
    builders: intelligentUiBuilders,
    onToAssistant: (event) => sendUserTurn(event.humanFriendlyMessage, event.formState),
  ),
);
```

Nothing calls a network service unless you pass it: without `searchImages` a `SearchImage`
shows an empty photo, without `streetRoute` a map route draws straight segments, and
`mapTiles: null` shows no tiles. `@OpenUrl` opens only http(s) URLs.

## Platforms

`HtmlView` and `YouTube` use a web view on Android, iOS and macOS (only the initial page loads,
no bridge except a height report) and a sandboxed `<iframe>` on the web; elsewhere they show a
titled card. Maps use `flutter_map`, math uses `flutter_math_fork`, and icons come from a
bundled Lucide font with the reference's names and aliases.

The [example](example) app renders the reference's 45 gallery programs offline, in light and
dark. [`DESIGN.md`](DESIGN.md) records the architecture and its reviews.
