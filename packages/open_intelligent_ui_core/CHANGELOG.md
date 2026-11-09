## 3.1.0 (unreleased)

- An app can depend on `ai_sdk_openui` and this package from git at one commit, with no
  `dependency_overrides`: unreleased siblings are path dependencies (see `docs/git-dependencies.md`).
- A component with no builder reports a `render-error` to the session's `onError` instead of rendering
  nothing silently. `OpenUiView(fallback:)` shows a widget when the settled answer has errors and no root, as
  when a `ValidationPolicy` fails it. `intelligentUiFor(builders, library:)` takes a host library and throws
  an `ArgumentError` naming each host-added component the lookup cannot build.
- Theming without Material: `OpenUiThemeScope` gives a subtree its own `OpenUiTheme` (a dark view in a
  light app) with no Material `Theme` needed, and reaches the date picker and menus. The default
  `fontFamily` is now null (the platform font); `OpenUiServices.fontFamily` sets a fallback. Every colour
  comes from a token: new `onTone`, `checkInk`, `chevron`, `floatShadow`, `inkOnLight` and `inkOnDark`, and
  `copyWith` takes `brightness`. `OpenUiComponentStyle` takes `fontSize` and `size` per component (for
  example `Button`, `Checkbox`, `Input`, `Carousel.arrow`), and `OpenUiTypography(tabularNums: true)` sets
  tabular figures on all text. The iOS date popup in a dark view is now legible in a light app.
- Button, IconButton and Pressable show a handled action's pending, done and failed states, ask for an inline
  confirmation when the action has `confirm`, and stay disabled after success with `disableAfterSuccess`.
  `OpenUiNode` gains `actionStatus(prop)` and `run(confirmed:)`.
- A handled action in the unknown phase (cut off by a restore, being checked by the host) shows a spinner and a
  "Checking…" note (`OpenUiLocalizations.checkingAction`), and takes no tap: it reads as neither failed nor retryable.
- Every rendered element has a stable key from its statement id (inline elements: parent id and
  position). `OpenUiView(semanticsIdentifiers: true)` also sets Semantics identifiers for UI tests.
- An unnamed field or Form is named after that element id, not a process-wide `field-N` counter, so what
  the user typed or picked survives a remount, a restore from `initialState` and other views rendered first.
  Two controls with the same label in one form keep separate values: the later one is named `<label>~<id>`.
- Elements are keyed by statement id, so a statement that is renamed or moved inline mounts a new
  widget and drops its local widget state (an expanded map, a scroll position).
- Chart values, tooltips and axis ticks follow the session's locale: `OpenUiSession(locale: 'en_IN')` writes
  `₹2,34,567` and compacts to `₹12.35L`. With no locale they stay en-US. `OpenUiNode.locale` exposes it.
- All user-visible text comes from `OpenUiLocalizations` (English by default). Register
  `OpenUiLocalizationsDelegate({'fr': MyFrenchStrings()})` in `localizationsDelegates` to translate.
- Right-to-left: layout, padding and positioned controls follow `Directionality`. Charts, drawings
  and the map canvas stay left-to-right.
- The engine's clock and random seams are public as `Impure` (`Impure.now`, `Impure.random`);
  DatePicker's today uses them.
- The golden tests (light and dark, every component) run on Linux only; regenerate with
  `fvm flutter test --update-goldens test/goldens` on Linux.
- Theme tokens: `OpenUiTheme` takes `radii`, `spacing`, `typography` (scale, Text and Title sizes, weights,
  tabular figures) and `components` (per-component styles for Card, Button, Badge and Table), and builds from a
  host theme with `OpenUiTheme.fromColorScheme` or `fromMaterial`. Defaults are the reference's values, so nothing
  changes until you set them. The static radius, spacing and weight constants stay as the reference values.
- Stock builders (`buildCard`, `buildButton`, ...) are exported from `components.dart` so a host can wrap one.
- First release: the core renderer (`OpenUiView`, layout, text, controls, charts, tables, SVG, Markdown,
  code), the 13 built-in icons and the lucide icon library (`package:open_intelligent_ui_core/lucide.dart`),
  split from open_intelligent_ui.
- Behaviour change: no network by default. Map tiles and images no longer load until you allow them:
  `OpenUiServices(mapTiles: esriStreetTiles, imageLoader: networkImages)`, or allow a few hosts with
  `imageLoader: allowImageHosts(['upload.wikimedia.org'])`. A blocked image shows the photo placeholder.
  The README's Network section lists every place that can reach the network.
- DatePicker opens on today in its session's clock and time zone. `OpenUiNode` gains `localNow`.
