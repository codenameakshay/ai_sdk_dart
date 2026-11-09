# open_intelligent_ui_core

Core of the Open Intelligent UI Flutter renderer. It holds `OpenUiView`, layout, text, controls, charts,
tables, SVG, Markdown, code, the 13 built-in icons, and the builder and service APIs. It brings
`ai_sdk_openui`, `intl` and `path_parsing`, and no map, web view, TeX or chat dependency.

Install:

```sh
fvm flutter pub add open_intelligent_ui_core
```

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

## Services and fallbacks

- `OpenUiServices` carries host hooks: `openUrl`, `copyText`, `searchImages`, `streetRoute`, `mapTiles`,
  `embedReferrer` and `icons`.
- `openUrl` does nothing without a host function. Pass one, such as `url_launcher`, to open links.
- `OpenUiScope` gives services to a subtree. `OpenUiView.fallbackServices` fills whatever the nearest
  scope leaves unset. `OpenUiServices.orElse(fallback)` merges two sets the same way.
  `OpenUiScope` is an `InheritedTheme`, so routes and the expanded map keep the services.

## Fonts

Text uses the font family `packages/open_intelligent_ui/Inter` by default. That family exists only when
the umbrella package is present. Without it, Flutter uses the platform font. Bundle Inter or set
`fontFamily` on `OpenUiTheme` to choose a font.

Plugin authors import `package:open_intelligent_ui_core/components.dart` for `OutlineGlyph` and `Photo`.

Part of [open_intelligent_ui](https://pub.dev/packages/open_intelligent_ui); see its README.
