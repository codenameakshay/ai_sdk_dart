## 3.1.0 (unreleased)

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
