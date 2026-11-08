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

Nothing reaches the network until you allow it. Without `imageLoader` every image shows its
placeholder, and without `mapTiles` a `Map` draws no tiles. Without `searchImages` a `SearchImage`
shows an empty photo, and without `streetRoute` a map route draws straight segments. `@OpenUrl`
opens only http(s) URLs. The [Network](#network) section lists every place that can reach the network.

## Network

Nothing reaches the network until the host allows it. Each row names a place that can, what makes it
do so, and how to turn it on.

| Where | Touches the network when | Off by default | How to opt in |
|---|---|---|---|
| Image, SearchImage, YouTube thumbnail (`Photo`) | `imageLoader` returns a provider | yes (`imageLoader: null`) | `imageLoader: networkImages`, or `allowImageHosts(['example.com'])` |
| Map tiles (`Map`, flutter_map) | `mapTiles` is set | yes (`mapTiles: null`) | `mapTiles: esriStreetTiles`, or your own `MapTiles` |
| Street routes | `streetRoute` is set (`OsrmStreetRoute`, router.project-osrm.org) | yes | `streetRoute: OsrmStreetRoute().call` |
| Photo search | `searchImages` is set (`WikimediaImageSearch`, en.wikipedia.org, commons.wikimedia.org) | yes | `searchImages: WikimediaImageSearch().call` |
| `@OpenUrl`, Link, Markdown links, map attribution, YouTube fallback card | the user taps, and the URL goes to `openUrl` | nothing opens without `openUrl`; the umbrella opens the browser on tap | already set in the umbrella |
| HtmlView (web package) | renders after streaming; its page may load scripts from cdn.jsdelivr.net, unpkg.com, cdnjs.cloudflare.com and esm.sh, styles and fonts from fonts.googleapis.com and fonts.gstatic.com, and images from any https host (the reference's CSP) | not in the core; the umbrella includes the web package | leave `open_intelligent_ui_web` out of the app |
| YouTube (web package) | renders an embed from www.youtube-nocookie.com | same as HtmlView | same as HtmlView |
| Flutter web engine | CanvasKit and fallback fonts load from Google's CDN | no | build with `--no-web-resources-cdn` (an engine flag, not this package's) |

The YouTube thumbnail is an image, so `imageLoader` blocks it too.

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

## Theming

`OpenUiTheme` is a `ThemeExtension`. Register one on the app theme and the components read their
tokens from it. Without a registered theme, the reference's light or dark tokens apply.

Build the theme from the host, so colors and the body font follow the app:

```dart
final host = ThemeData(colorSchemeSeed: Colors.indigo);
final app = ThemeData(
  colorScheme: host.colorScheme,
  extensions: [OpenUiTheme.fromMaterial(host)],
);
```

Inside a widget, `OpenUiTheme.fromMaterial(Theme.of(context))` builds the same tokens from the current
theme. `OpenUiTheme.fromColorScheme(scheme, fontFamily: ...)` builds them from a `ColorScheme` and a font
family. Change single tokens with `copyWith`:

```dart
final theme = OpenUiTheme.fromMaterial(Theme.of(context)).copyWith(
  radii: const OpenUiRadii(md: 6),
  typography: const OpenUiTypography(scale: 1.1),
);
```

| Group | Field | What it holds |
| --- | --- | --- |
| Colors | `canvas`, `ink`, `onInk`, `muted`, `faint`, `status`, `statusSoft`, `badge`, `badgeSoft`, `chart`, `mapWater`, `glass`, `glassHover`, `glassRing`, `glassRingHover` | Surfaces, text, status tints, chart and map colors |
| Radii | `radii` (`OpenUiRadii`) | `sm` 6, `md` 10, `lg` 12, `xl` 14, `xxl` 20, `full` 999 |
| Spacing | `spacing` (`OpenUiSpacing`) | `unit` 4 is the step that `spaceOf` multiplies model values by. The named steps (`tight`, `inner`, `group`, `section`, `actionGap`, ...) are px values. |
| Typography | `typography` (`OpenUiTypography`) | `scale` multiplies every built-in font size through `size(px)`. `text` holds the Text sizes `xs` to `lg`, and `title` the Title sizes `sm` to `3xl`. Each size has a line height, a letter spacing and an optional `compactFontSize` for phone widths. `normal`, `medium` and `semibold` are weights 440, 560 and 640. `tabularFigures` is on by default. |
| Elevation | `shadow`, `shadowSmall` | Box shadows for cards and small surfaces |
| Components | `components` (`Map<String, OpenUiComponentStyle>`) | Per-component styles, keyed as below |

A component style sets `background`, `foreground`, `border`, `radius` or `padding`. Unset fields keep the
built-in value. A key with a variant after a dot overrides its base key. The keys are:

- `'Card'`, `'Card.soft'`
- `'Button'`, `'Button.outline'`
- `'Badge'`, `'Badge.success'`
- `'Table'`

### Override one component

Wrap a stock builder with `composeBuilders`. The stock builders are in `components.dart`, and
`intelligentUiBuilders` is the base set:

```dart
import 'package:flutter/material.dart';
import 'package:open_intelligent_ui/components.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

final builders = composeBuilders([
  {
    'Card': (context, node) =>
        Material(elevation: 2, child: buildCard(context, node)),
  },
], base: intelligentUiBuilders);

OpenUiView(session: session, builders: builders);
```

To restyle a component without code, register a theme with `components`:

```dart
Theme(
  data: ThemeData(
    extensions: [
      OpenUiTheme.light.copyWith(
        components: {
          'Card': OpenUiComponentStyle(radius: 4, border: Colors.indigo),
          'Button.outline': OpenUiComponentStyle(
            foreground: Colors.indigo,
            radius: 8,
          ),
        },
      ),
    ],
  ),
  child: child,
);
```

## Testing

Pin the clock and the randomness so output does not change between runs. `Impure` is exported from
`package:ai_sdk_openui/intelligent_ui.dart`, so add `ai_sdk_openui` to the test's dependencies if it is not already there.

```dart
import 'package:ai_sdk_openui/intelligent_ui.dart';

setUp(() {
  Impure.useUtc();
  Impure.now = () => DateTime.utc(2026, 1, 15, 12);
  Impure.random = () => 0.5;
});

tearDown(Impure.reset);
```

- `Impure.now` sets the clock. `Impure.useUtc()` reads and formats dates in UTC, as the reference's tests
  do. `Impure.reset()` restores the real clock and randomness.
- DatePicker's "today" and `@Today` read the same clock, so pinning `Impure.now` moves both.
- Each element has a stable key, `ValueKey('openui:<id>')`. The id is the statement's id in the
  program. An inline element gets `<parent id>/<slot>.<index>`, and a repeat within one parent gets
  `~2`, `~3`. Find an element with `find.byKey(const ValueKey('openui:<id>'))`.
- For UI tests, pass `semanticsIdentifiers: true` to `OpenUiView`. Each element then carries the
  semantics identifier `openui:<id>`. It is off by default because each element adds a container
  node to the semantics tree.

## Localization

Every user-visible string comes from `OpenUiLocalizations`. English is the default, so an app with no
delegate shows English. To translate, subclass `OpenUiLocalizations`, override the getters you change,
and register a delegate with your other delegates:

```dart
class MyFrench extends OpenUiLocalizations {
  const MyFrench();

  @override
  String get loadingData => 'Chargement des données';

  @override
  String get copy => 'Copier';
}

MaterialApp(
  localizationsDelegates: const [
    OpenUiLocalizationsDelegate({'fr': MyFrench()}),
  ],
  supportedLocales: const [Locale('en'), Locale('fr')],
  // ...
);
```

The delegate serves the subclass for each language code in its map. Other languages get the English
base. A getter you do not override keeps its English text. Your own widgets read strings with
`OpenUiLocalizations.of(context)`.

## Right-to-left

Layout follows the ambient `Directionality`. In an RTL locale, rows and tables mirror their children,
and padding and positioned controls use start and end. Charts, Svg and the map canvas stay
left-to-right, because their data and drawings keep their own axes. The controls around them follow
the text direction.

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
