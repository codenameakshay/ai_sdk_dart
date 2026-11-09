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

## In a chat

`package:open_intelligent_ui/chat.dart` plugs answers into `ai_sdk_flutter_ui`:

```dart
import 'package:open_intelligent_ui/chat.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

final agent = ToolLoopAgent(
  model: model,
  instructions: intelligentUi.systemPrompt(chatPrompt),
);
final chat = OpenUiChat(controller: controller, agent: agent, tools: myTools);

AiChatScaffold(
  controller: controller,
  agent: agent,
  chatMessageBuilder: chat.buildMessage,
);
```

Each answer keeps one session from its first token to the committed message. A `@ToAssistant`
click sends the next user turn in the reference's `]]>openui:` format, with the form values,
and the user row shows the message with the values folded under it. Edits are saved into the
answer's context, so the model sees them on the next turn and a restored transcript starts
from them. An answer that is not a program shows as text. Call `chat.dispose()` with the
controller.

## Packages

The renderer is split so an app pays only for the parts it draws. This umbrella depends on all of
them and keeps the old names working.

| Package | What it holds | Heavy dependencies it brings |
| --- | --- | --- |
| `open_intelligent_ui_core` | `OpenUiView`, layout, text, controls, charts, tables, SVG, Markdown, code, 13 built-in icons, the lucide icon library (`package:open_intelligent_ui_core/lucide.dart`) | `ai_sdk_openui`, `intl`, `path_parsing` |
| `open_intelligent_ui_maps` | `Map`, `MapMarker`, `OsrmStreetRoute` | `flutter_map`, `latlong2`, `http` |
| `open_intelligent_ui_web` | `HtmlView`, `YouTube` | `webview_flutter`, `web` |
| `open_intelligent_ui_math` | `Math` | `flutter_math_fork` (bundles KaTeX fonts) |
| `open_intelligent_ui_chat` | `OpenUiChat`, `OpenUiUserMessage` | `ai_sdk_dart`, `ai_sdk_flutter_ui` |
| `open_intelligent_ui` | All of the above, Inter, link opening, Wikimedia search, `package:open_intelligent_ui/chat.dart` | `url_launcher`, `http` |

## Lean setup

For an app that needs only some components, depend on `open_intelligent_ui_core` and add the plugins
you use. The snippet below opens links with `url_launcher`, which the app adds itself.

```dart
import 'package:open_intelligent_ui_core/lucide.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';
import 'package:open_intelligent_ui_maps/open_intelligent_ui_maps.dart';
import 'package:url_launcher/url_launcher.dart';

final builders = composeBuilders([mapBuilders]);
final library = intelligentUiFor(builders);
final session = OpenUiSession(library, tools: myTools)
  ..update(textSoFar, streaming: true);
final instructions = library.systemPrompt(chatPromptFor(library)); // the agent's instructions

OpenUiView(
  session: session,
  builders: builders,
  fallbackServices: OpenUiServices(
    icons: lucideIconResolver,
    openUrl: (url) => launchUrl(url).then((_) {}),
  ),
);
```

`intelligentUiFor` leaves out each optional component the builders cannot draw, and the prompt names only
the components the library has. Without the umbrella, text uses the platform font unless the host
bundles Inter or sets `fontFamily`.

## Platforms

`HtmlView` and `YouTube` use a web view on Android, iOS and macOS (only the initial page loads,
no bridge except a height report) and a sandboxed `<iframe>` on the web; elsewhere they show a
titled card. Maps use `flutter_map`, math uses `flutter_math_fork`, and text uses the bundled
Inter 4.1 variable font (OFL). Icons come from the lucide library, `package:open_intelligent_ui_core/lucide.dart`
(lucide-react 0.562.0's outlines, drawn at the reference's 1.8 stroke, with its names and aliases). The umbrella turns
them on. An `OpenUiTheme` built with `fontFamily: null` uses the platform font.

The [example](example) app renders the reference's 45 gallery programs offline, in light and
dark, and has a chat demo that runs on a scripted offline model. [`DESIGN.md`](DESIGN.md)
records the architecture, its reviews and every known difference from the reference.
