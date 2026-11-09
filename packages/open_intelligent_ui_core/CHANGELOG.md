## 3.1.0 (unreleased)

- Theme tokens: `OpenUiTheme` takes `radii`, `spacing`, `typography` (scale, Text and Title sizes, weights,
  tabular figures) and `components` (per-component styles for Card, Button, Badge and Table), and builds from a
  host theme with `OpenUiTheme.fromColorScheme` or `fromMaterial`. Defaults are the reference's values, so nothing
  changes until you set them. The static radius, spacing and weight constants stay as the reference values.
- Stock builders (`buildCard`, `buildButton`, ...) are exported from `components.dart` so a host can wrap one.
- First release: the core renderer (`OpenUiView`, layout, text, controls, charts, tables, SVG, Markdown,
  code), the 13 built-in icons and the lucide icon library (`package:open_intelligent_ui_core/lucide.dart`),
  split from open_intelligent_ui.
