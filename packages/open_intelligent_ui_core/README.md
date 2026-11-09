# open_intelligent_ui_core

Core of the Open Intelligent UI Flutter renderer. It holds `OpenUiView`, layout, text, controls, charts,
tables, SVG, Markdown, code, the 13 built-in icons, and the builder and service APIs. It brings
`ai_sdk_openui`, `intl` and `path_parsing`, and no map, web view, TeX or chat dependency.

Install:

```sh
fvm flutter pub add open_intelligent_ui_core
```

Before a release is on pub.dev, pin `ai_sdk_openui` and `open_intelligent_ui_core` to one commit as git
dependencies, with no overrides: see [docs/git-dependencies.md](../../docs/git-dependencies.md).

## Use

```dart
import 'package:open_intelligent_ui_core/lucide.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';

final library = intelligentUiFor(openUiCoreBuilders);
final session = OpenUiSession(library, tools: myTools)
  ..update(textSoFar, streaming: true);

OpenUiScope(
  services: OpenUiServices(
    icons: lucideIconResolver,
    openUrl: (url) => launchUrl(url),
  ),
  child: OpenUiView(session: session, builders: openUiCoreBuilders),
);
```

`intelligentUiFor` removes the components this core cannot draw (Map, MapMarker, Math, HtmlView and
YouTube). Add them with `composeBuilders` and the plugin packages.

## Icons

An icon name (lucide kebab-case, such as `map-pin`) resolves in this order:

1. `OpenUiServices.icons`, the resolver you pass.
2. The 13 built-in glyphs: `app-window`, `arrow-up-right`, `calendar`, `check`, `chevron-down`,
   `chevron-left`, `chevron-right`, `copy`, `expand`, `image`, `info`, `navigation` and `play`. They are
   lucide's outlines, copied verbatim.
3. Nothing. A `Badge` or `Button` with any other name shows no icon.

The full lucide set is a library inside this package, not a separate package. Import it to use the
resolver. Only that import loads the 318 KB of path data, so an app that does not import it does not ship it.

```dart
import 'package:open_intelligent_ui_core/lucide.dart';

final services = OpenUiServices(icons: lucideIconResolver);
```

## Network

Nothing reaches the network until the host allows it. The core makes no calls of its own. Each row names
a place that can, and how to turn it on.

| Where | Touches the network when | Off by default | How to opt in |
|---|---|---|---|
| Image, SearchImage, YouTube thumbnail (`Photo`) | `imageLoader` returns a provider | yes (`imageLoader: null`) | `imageLoader: networkImages`, or `allowImageHosts(['example.com'])` |
| Map tiles (`Map` is in `open_intelligent_ui_maps`) | `mapTiles` is set | yes (`mapTiles: null`) | `mapTiles: esriStreetTiles`, or your own `MapTiles` |
| Street routes (`OsrmStreetRoute` in `open_intelligent_ui_maps`) | `streetRoute` is set | yes | `streetRoute: OsrmStreetRoute().call` |
| Photo search | `searchImages` is set | yes | a host function, such as `WikimediaImageSearch().call` from the umbrella |
| `@OpenUrl`, Link, Markdown links, map attribution, YouTube fallback card | the user taps, and the URL goes to `openUrl` | yes: nothing opens without `openUrl` | pass `openUrl`, such as `launchUrl` |
| HtmlView, YouTube (web package) | HtmlView's page may load scripts from cdn.jsdelivr.net, unpkg.com, cdnjs.cloudflare.com and esm.sh, and fonts from fonts.googleapis.com and fonts.gstatic.com; YouTube embeds load from www.youtube-nocookie.com | not in the core | depend on `open_intelligent_ui_web`, or leave it out to keep them off |
| Flutter web engine | CanvasKit and fallback fonts load from Google's CDN | no | build with `--no-web-resources-cdn` (an engine flag, not this package's) |

## Services and fallbacks

- `OpenUiServices` carries host hooks: `openUrl`, `copyText`, `searchImages`, `streetRoute`, `mapTiles`,
  `imageLoader`, `embedReferrer` and `icons`.
- `openUrl` does nothing without a host function. Pass one, such as `url_launcher`, to open links.
- `OpenUiScope` gives services to a subtree. `OpenUiView.fallbackServices` fills whatever the nearest
  scope leaves unset. `OpenUiServices.orElse(fallback)` merges two sets the same way.
  `OpenUiScope` is an `InheritedTheme`, so routes and the expanded map keep the services.

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
`openUiCoreBuilders` is the base set:

```dart
import 'package:flutter/material.dart';
import 'package:open_intelligent_ui_core/components.dart';
import 'package:open_intelligent_ui_core/open_intelligent_ui_core.dart';

final builders = composeBuilders([
  {
    'Card': (context, node) =>
        Material(elevation: 2, child: buildCard(context, node)),
  },
], base: openUiCoreBuilders);

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

## Fonts

Text uses the font family `packages/open_intelligent_ui/Inter` by default. That family exists only when
the umbrella package is present. Without it, Flutter uses the platform font. Bundle Inter or set
`fontFamily` on `OpenUiTheme` to choose a font.

Plugin authors import `package:open_intelligent_ui_core/components.dart` for `OutlineGlyph` and `Photo`.

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
