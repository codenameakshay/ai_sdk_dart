## 3.1.0 (unreleased)

- `OpenUiView` passes `fallback:` through to the core view.
- Views keep the bundled Inter font by default through `OpenUiServices.fontFamily`, now that the core
  theme's default font is the platform font. A theme that sets `fontFamily` still wins.
- `OpenUiChat` takes `send` for any transport, `locale` and `records`; `agent` is optional. The chat
  renders answers stored as text parts, and `package:open_intelligent_ui/chat.dart` exports
  `OpenUiAnswerView`.
- Button, IconButton and Pressable show a handled action's pending, done and failed states, ask for an inline
  confirmation when the action has `confirm`, and stay disabled after success with `disableAfterSuccess`.
  `OpenUiNode` gains `actionStatus(prop)` and `run(confirmed:)`.
- Every rendered element has a stable key from its statement id (inline elements: parent id and
  position). `OpenUiView(semanticsIdentifiers: true)` also sets Semantics identifiers for UI tests.
- Elements are keyed by statement id, so a statement that is renamed or moved inline mounts a new
  widget and drops its local widget state (an expanded map, a scroll position).
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
- The renderer is split into packages. `open_intelligent_ui` still includes everything: every
  component, Inter, Lucide icons, links that open in the browser, and `package:open_intelligent_ui/chat.dart`.
  Nothing changes for apps that use it.
  For a smaller app, depend on `open_intelligent_ui_core` and add only what you need:
  `open_intelligent_ui_maps` (Map, MapMarker, OsrmStreetRoute), `open_intelligent_ui_web` (HtmlView, YouTube),
  `open_intelligent_ui_math` (Math), `package:open_intelligent_ui_core/lucide.dart` (icons) and `open_intelligent_ui_chat` (OpenUiChat).
  Migrating from `open_intelligent_ui` to the core:
    builders: intelligentUiBuilders            -> builders = composeBuilders([mapBuilders, ...])
    OpenUiSession(intelligentUi, ...)           -> OpenUiSession(intelligentUiFor(builders), ...)
    intelligentUi.systemPrompt(chatPrompt)      -> library.systemPrompt(chatPromptFor(library))
    (icons)                                     -> OpenUiServices(icons: lucideIconResolver)
    (links)                                     -> OpenUiServices(openUrl: (u) => launchUrl(u))
  Without the umbrella, text uses the platform font unless you bundle Inter or set `fontFamily`.
- `OpenUiServices.icons` replaces the built-in icon set; `OpenUiView.fallbackServices` and
  `OpenUiServices.orElse` fill services a scope leaves unset. `OpenUiScope` carries into routes.
- `OpenUiChat` given only `builders` now advertises only the components those builders draw.
- First release: Flutter renderer for Open Intelligent UI answers (a port of
  thesysdev/open-intelligent-ui at `9df2e64`), with `OpenUiView`, a builder per component,
  `OpenUiTheme` light and dark tokens, injectable `OpenUiServices`, optional Wikimedia and OSRM
  clients, and a gallery example app.
- Renderer slots: `OpenUiView` takes `OpenUiContent`, `OpenUiQueryLoading`, `OpenUiQueryError`, `OpenUiRetry`
  and a `queryLoader`, and `OpenUiView.queryOf` gives the query state, including `isRetrying`.
- `OpenUiPreview` (with `OpenUiPreview.of`) renders a response's preview, as react-lang's preview renderer does.
- A builder's own render error reaches `onError` as `render-error`.
- Inter ships as the variable Inter 4.1 font, so weights 440, 560 and 640 render as the reference sets them.
- Icons are lucide-react 0.562.0's outlines, drawn at the reference's 1.8 stroke. `Glyph` gains `strokeWidth`,
  and the icon font is removed.
- CSS gradient backgrounds draw as Flutter gradients (linear and radial, plain or repeating).
- Maps match the reference's camera, zoom, pins and modal. The expanded map is a modal route, so its focus
  stays inside and Escape returns focus to Expand.
- The native HtmlView sandbox refuses to run unless the page has an opaque origin, and denies storage, cookies,
  caches, service workers and BroadcastChannel. The web view denies camera and microphone requests.
- Keyboard and screen-reader access: links, pins, popovers, flashcards and carousel arrows are focusable, timers
  are labelled, and lists, tables and radio groups carry their semantics.
- Phone breakpoints: layout, table and segmented controls change at 640px width, as the reference's CSS does.
- Markdown: inline code draws as a box, and list markers follow Chrome's placement.
- Svg: a bad path draws up to its first error.
- Charts and tables: chart hover follows pointer movement, and tables lay out with min-content widths and
  list and table semantics.
- `package:open_intelligent_ui/chat.dart`: `OpenUiChat` renders answers in
  `ai_sdk_flutter_ui` chats, and `OpenUiUserMessage` shows `@ToAssistant` turns with their form
  values. The example has an offline chat demo.
- Behaviour change: no network by default. Map tiles and images no longer load until you allow them:
  `OpenUiServices(mapTiles: esriStreetTiles, imageLoader: networkImages)`, or allow a few hosts with
  `imageLoader: allowImageHosts(['upload.wikimedia.org'])`. A blocked image shows the photo placeholder.
  The README's Network section lists every place that can reach the network.
