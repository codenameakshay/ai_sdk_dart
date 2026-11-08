# Open Intelligent UI for Flutter: design

This port renders [Open Intelligent UI](https://github.com/thesysdev/open-intelligent-ui) answers in Flutter. The
reference is pinned at commit `9df2e64bc44282f6305a47eb6dbbbd8f28139138` (2026-11-06), MIT. Its parser,
evaluator and prompt generator come from `@openuidev/lang-core` 1.0.0 and `@openuidev/react-lang` 1.0.0, which
this port also follows line by line.

The model does not answer in prose. It streams a program in OpenUI Lang 1.0. The client re-parses the full text
on every chunk, keeps `$state` locally, and renders components. Only `@ToAssistant` starts a new turn. The model's
output must work unchanged, so every component name, argument order, option value and color name is identical.

## Packages

```
packages/ai_sdk_openui              pure Dart, no Flutter
  ai_sdk_openui.dart                the language: schema DSL, library, session, elements, events
  intelligent_ui.dart               the library: IuiComponent, intelligentUi, optionalIuiComponents,
                                    intelligentUiWithout, chatPrompt, chatPromptFor, dashboardPrompt, demoTools
packages/open_intelligent_ui_core   Flutter; no map, web view, TeX or chat dependency
  open_intelligent_ui_core.dart     OpenUiView, OpenUiPreview, OpenUiScope, OpenUiServices, OpenUiTheme,
                                    openUiCoreBuilders, composeBuilders, intelligentUiFor
  components.dart                   OutlineGlyph, Photo, for builder and plugin authors
  lucide.dart                       lucideIconResolver (the lucide set; loaded only when imported)
packages/open_intelligent_ui_maps   Map, MapMarker, OsrmStreetRoute (flutter_map)
packages/open_intelligent_ui_web    HtmlView, YouTube (webview_flutter)
packages/open_intelligent_ui_math   Math (flutter_math_fork)
packages/open_intelligent_ui_chat   OpenUiChat, OpenUiUserMessage (ai_sdk_flutter_ui)
packages/open_intelligent_ui        umbrella: re-exports the packages above, bundles Inter, opens links
                                    in the browser, adds chat.dart and Wikimedia photo search
```

The umbrella keeps its name, so existing imports still work. Each plugin depends on the core and on one
heavy dependency set. Lucide is a library inside the core, not a package.

`OpenUiView` takes react-lang's Renderer slots as widgets: `OpenUiContent`, `OpenUiQueryLoading`, `OpenUiQueryError`
and `OpenUiRetry`, plus a `queryLoader`. `OpenUiView.queryOf` gives the query state, including `isRetrying`.
`OpenUiPreview` is the port of react-lang's `WithPreviewRenderer`, read with `OpenUiPreview.of`.

Data path for one answer:

```
model text ──► OpenUiSession.update(text, streaming)
                 │ StreamParser: cache finished statements, re-parse the tail
                 │ Store: $state (pristine keys follow new defaults)
                 │ QueryManager: Query/Mutation through OpenUiTool (only after streaming)
                 ▼
               session.root (lazy) ──► OpenUiView ──► one builder per IuiComponent
                                                        │ click
                 OpenUiSession.run(action) ◄────────────┘
                   @Set/@Reset/@Run here; ActionEvent out for @ToAssistant, @OpenUrl, @CopyToClipboard
```

## Decisions

1. **The lang core is a line-by-line Dart port of lang-core 1.0.0, in a pure-Dart package.** A prototype of each
   option ran on the reference's 45 gallery programs. `openui_lang` 0.18.2 failed 44 of 45: it hard-codes React
   content unions by component name, so `Card`, `Carousel`, `Form` and `Table` reject valid children, and its
   tokenizer reads a string literal `"-"` as an operator. A patched fork parsed all 45, but it imports `dart:ui`,
   implements Lang 1.1 with its own action model, has no edge-rule validation, and its prompt generator cannot
   produce the golden prompt. The direct port parsed all 45 clean (no errors, unresolved or orphaned names) and
   gave the same result when fed in 7-character chunks. It is pure Dart, so a Dart server can build the system
   prompt and check a program without Flutter. That is why the engine is its own package. `lang_core.dart`
   exports the low-level surface (lexer, parsers, `mergeStatements`, `jsonToOpenUI`, evaluator, store, query
   manager) under lang-core's names; the main barrel adds the message envelope, form validation, structured
   errors, the MCP helpers, `library.extend()` and the OpenUI Cloud prompt.
2. **One schema DSL describes every prop.** `S` mirrors Zod. Each node emits the JSON Schema the parser compiles
   and the function arguments validate against, and the type the prompt prints (`Color`, `Node[]`,
   `$binding<string | number>`, `ActionExpression`). Built-in functions and steps are specs too. Golden tests
   compare the whole `spec.json` and both system prompts byte for byte.
3. **Components are an enum.** `IuiComponent.values` is the library's list, groups reference enum values, and the
   Flutter builder table is an exhaustive `switch`, so a component without a builder does not compile.
   `ComponentSpec` stays an interface for other libraries (coach, chess, app-defined).
4. **Runtime values are JSON-shaped `Object?`** with JS semantics in one private helper (`Js`): one number type,
   string `+`, division by zero gives 0, loose `==`, JS truthiness, `String(4)` is `"4"`. Tool results, saved
   state and the 59 functions all speak JSON, so a sealed value type would wrap and unwrap at every boundary.
   Elements, actions and bindings are closed types, so model data cannot pose as a custom action, and builders
   only ever see evaluated values.
5. **`OpenUiSession` is the runtime**, in pure Dart: `update`, lazy `root`, `state` to persist, `issues`, a
   synchronous `listen`, `field`, `run`, `dispose`, `onParseResult`, `setTools`, `metadata`, `isGenerating`,
   `fieldValue`, `setDefaultValue`, `retryQueries` and `reportRenderError`. It ports react-lang's `useOpenUIState`:
   store initialization, form fields stored as react-lang's `{value}` wrapper (a `componentType` only when a
   component passes one to `setDefaultValue`), queries blocked while streaming, actions
   allowed while plain text streams (only an unfinished OpenUI Cloud bundle blocks them), structured `errors`
   with `onError` and `onStateUpdate`, and steps run in their original order (a failed Mutation stops the plan).
6. **Events keep lang-core's payload:** `ActionEvent(type, params, humanFriendlyMessage, formState, formName)`.
   One `run` accepts a step plan, a legacy `{type, ...}` action object, or no action (a Button without an action
   sends its label). `buildActionUserMessage` writes react-ui's user turn for a `continue_conversation` event: the
   message as content, `["User clicked: msg", formState, context?]` as context.
7. **Host services are injected.** `OpenUiServices` covers opening URLs, the clipboard, image search, street
   routing and map tiles. The package hard-codes none of the reference's `/api` routes.
8. **The umbrella keeps its name; the renderer moves to `open_intelligent_ui_core`.** Every existing import,
   `intelligentUiBuilders`, `OpenUiView(...)`, `chat.dart`, Inter and the icons keep working with no host change,
   so 3.1.0 is a minor release. All tests stay in the umbrella, which can import every plugin.
9. **Specs stay in `ai_sdk_openui`; the library is derived from the builders.** A plugin is a
   `Map<String, OpenUiBuilder>`. `intelligentUiFor(builders)` removes each optional component the builders cannot
   draw (Math, Map, MapMarker, YouTube, HtmlView). With every plugin it returns `intelligentUi` itself, so the spec
   and prompt goldens do not move. `chatPromptFor(library)` drops the "Pick the medium" clauses for missing
   components. No `OpenUiPlugin` class: a builder map and one derive function cover it.
10. **Icons come from a resolver.** `OpenUiServices.icons` draws a name. Lookup order: `services.icons`, then
    the 13 built-in glyphs in the core (lucide's outlines, copied verbatim), then nothing. The full lucide set is
    a library inside the core, `package:open_intelligent_ui_core/lucide.dart`, which provides `lucideIconResolver`.
    Only a file that imports it pulls in its 318 KB of path data.
11. **Defaults come through `fallbackServices`.** `OpenUiView.fallbackServices` fills whatever the nearest
    `OpenUiScope` leaves unset (`OpenUiServices.orElse`), and `OpenUiScope` is an `InheritedTheme`, so routes keep
    the services. The umbrella's view passes Lucide icons and a `url_launcher` `openUrl`, so the core has no
    `url_launcher`. With no `openUrl` function, links do nothing.
12. **Inter stays in the umbrella.** The core's default font family is `packages/open_intelligent_ui/Inter`. With
    the umbrella it resolves to Inter. Without it, Flutter uses the platform font. `fontFamily: null` inherits the
    host font.

## Chat integration

`package:open_intelligent_ui/chat.dart` is the adapter for `ai_sdk_flutter_ui`. It is a separate
library so `ai_sdk_flutter_ui` does not depend on the map and web view packages. That package
gained three generic hooks, and the adapter needs nothing else from it:

```
ChatController ── streamingMessageId ──► row id while streaming ═ committed ChatMessage.id
      │                                         │
      │ chatMessageBuilder(ChatMessage)         ▼
      └──────────────────────────────► OpenUiChat: one OpenUiSession per id
                                                │ @ToAssistant
   sendMessage(buildActionUserMessage(e)) ◄─────┘
   updateMessage(id, content + ]]>openui:context [state]) ◄── session.onStateUpdate
```

1. **One session per message id.** The streaming row gets the id that the answer commits under,
   so `$state` typed while the answer streams carries over. Sessions of answers that leave the
   transcript (reload, clear, a failed run) are disposed, which stops their Query timers.
2. **Turns use the reference's envelope.** Messages are read and written with lang-core's
   `parseMessage` and `buildMessage`. A `@ToAssistant` turn is react-ui's
   `buildActionUserMessage`, which the engine exports:
   `["User clicked: …", formState, context?]` after the message.
3. **State lives in the transcript.** The chat prompt tells the model to start an edited page
   from "that answer's context and form values", so, like react-ui, user edits are written into
   the answer's `]]>openui:context` with `updateMessage`. Only user changes are written
   (`onStateUpdate`, as in react-lang), and a restored message starts from its saved state.
4. **Clicks while the chat is loading are ignored**, as the composer does.
5. **An answer with no component after streaming shows as text.** The reference renders
   nothing; text keeps a model's plain refusal readable.

`ConversationChatController` keeps its transcript in the backend, so its `updateMessage`
returns false and edits are not saved there.

## Hard widgets

| Widget | Choice | Fallback |
|---|---|---|
| Map | `flutter_map` raster tiles, markers, route polyline, category filter | straight segments when no route |
| HtmlView | `webview_flutter`, opaque origin (checked by the page), the reference's CSP, storage/cookies/dialogs fail as in the sandboxed frame, permissions denied, navigation blocked, one height channel | titled card where no web view runs |
| YouTube | its own embed policy (`youtube-nocookie`, after the id check) | a card that opens the video |
| Chart | hand port of `chart.tsx` to `CustomPainter` | none |
| Markdown | hand port of the reference's restricted parser | none |
| Svg | `CustomPainter`, `path_parsing` for `d` | a bad path draws up to its first error |
| Math | `flutter_math_fork` | the TeX source in monospace |

## Reviews

Two design candidates (Opus and Grok 4.7, written independently) converged on the whole shape above. The
combined design then went to two independent reviewers with the same brief.

- **Sol (`gpt-6.1-sol`, high effort):** approve with changes. Its five blocking points were all adopted:
  compare the whole spec, not one `$def` at a time; one action interface that keeps the full event payload and
  the original step order; react-lang's form identity and field storage; a real HtmlView security design,
  with YouTube on a separate embed policy; and a port of the reference's own Markdown parser instead of a general
  one. Its other notes (expose a parse-only check for servers, test fakes for platform widgets, inject time and
  randomness) are in the build.
- **Muse Wonder Full (`muse-wonder-full-1.0`, high effort):** did not run. Four attempts, through `delegate_task`
  and through the Codex CLI with every MCP server turned off, failed with the provider error "Recursive JSON
  schemas are not currently supported". The model rejects one of Codex's built-in tool schemas. No other model
  was substituted.

## Code review

The finished diff went to the same two reviewers.

- **Sol (`gpt-6.1-sol`, high effort, on Boat):** 19 findings (4 P1, 14 P2, 1 P3), all fixed with a
  regression test each. The P1s: HtmlView could navigate before its first load finished,
  re-applying `initialState` overwrote user edits, a shared Query lost its answer when the
  statement that started it went away, and a replaced Mutation accepted a stale answer.
- **Muse Wonder Full:** did not run, for the same provider error as in the design round.

## Port audit

A later audit read the port side by side with lang-core, react-lang and the reference, and found exports the
first pass had skipped, functions whose output differed from JavaScript, and rendering gaps. The follow-up
closed them, each with a test that fails on the earlier code:

- **Engine:** the message envelope, `mergeStatements`, `jsonToOpenUI`, form validation, `enrichErrors` and
  structured errors, the MCP helpers, `library.extend()`, restricted step refs, the OpenUI Cloud prompt and
  artifact tool, response bundles, per-prop evaluation errors, and lang-core's query manager names.
- **Functions:** `@Format` and `@Plural` round like `Intl`, currencies print en-US prefixes (`CA$`, `A$`),
  date strings parse like V8's `Date`, case mapping follows JavaScript, and arithmetic keeps doubles past
  2^53. The engine's tests also run compiled to JavaScript (`make test-web`). `patterns.test.ts`, the fourth
  reference test file, is ported.
- **Renderer:** tables lay out like HTML tables, grid rows share a height, card typography and the card-title
  rule apply, Markdown tables and links match, Svg overflows its box and composites opacity as a layer,
  `SvgText` no longer crashes on `currentColor`, the map flies between frames, Inter is bundled as the variable
  font, icons are drawn from lucide-react's outlines at the reference's stroke, and lists and tables carry list
  and table semantics.

## Parity

Every component, function and action of the reference library is ported, with its name, argument order and
option values unchanged. The spec golden proves the names and signatures; the function tests, ported case for
case from the reference's four test files and checked against Node, prove the behaviour.

**Kept on purpose.** These differ from react-lang because matching it would bring back a bug:

- Re-applying `initialState` fills only keys the store does not have, so a user's edits survive.
- A Query shared by several statements keeps its answer and loading state when the statement that started it
  goes away. Its failure is reported once and retried with one fetch per cache key, where react-lang reports one
  error per statement and refetches the key once per statement.
- Data shaped like an action step, or a `{steps: [...]}` plan read from data, runs only `open_url` (with a string
  URL) and `continue_conversation` steps, so tool data cannot set state or fire Mutations. react-lang also runs
  its Run, Set and Reset steps.
- The store compares array and object defaults by value, so a re-parse does not notify on every chunk.
- A prop whose expression throws evaluates to null (with its runtime error) instead of lang-core's raw
  expression, so builders only ever see JSON values.
- Member access reads only data: members a JS value inherits (`toString`, `constructor`, `__proto__`, string
  methods) are null, not functions or prototypes, so a tool result cannot reach them.
- An object literal keeps `__proto__` as an ordinary key. lang-core's materializer would assign it as the
  prototype, which is prototype pollution.
- A replaced Mutation is a new object. react-lang mutates it in place when its tool changes, so an answer from
  the old tool would still land and report success for a call that no longer exists.
- A Query's loading state resets when its statement re-evaluates. react-lang clears loading only for a fetch
  whose key is still current, so a Query that goes A to B to A can stay loading forever.
- A stored null stays null. react-lang falls back to the prop for a null field, so a cleared number Input would
  show the old value while the form submits null.
- `dispose` stops the rest of a plan. react-lang would still run the remaining `@Set` and host steps after
  unmount, and a disposed session has no host left to receive them.
- `onStateUpdate` fires once per change. react-lang's second call repeats the first with the same snapshot, so
  it carries nothing new.
- A whole evaluation that throws gives a null root. react-lang would return unevaluated AST nodes, and builders
  here only receive evaluated values.
- The expanded map's scrim takes taps. The reference's outline lets them reach the page behind its modal dialog.
- A chart reads `Infinity` as 0. The reference's chart breaks on it.

**Known differences:**

- Maps draw raster tiles with `flutter_map`, not the reference's MapLibre vector style. A vector basemap needs
  `flutter_map_vector_tiles`, a new third-party package, so it is left out until it is vetted.
- Math uses `flutter_math_fork`, which supports less TeX than KaTeX; unsupported input shows the source.
- `@Sort` compares text with CLDR's root collation exactly as Node 26's `localeCompare` (ICU 78); the reference
  uses the viewer's default locale, the port always the root (en) order.
- The native YouTube embed sends `https://www.youtube-nocookie.com/` as its Referer unless
  `OpenUiServices.embedReferrer` names the host app's site.
- A Popover trigger stays on one line: its text wraps beside its icons instead of overflowing them.
- Table cells measure min-content with Flutter's intrinsic widths. A nowrap label inside a component (a Button in
  a Row) reports its longest word, so such a cell can be narrower than in the browser; a LayoutBuilder inside a
  cell counts as 0 wide.
- Gradients: linear and radial, plain or repeating. Colour hints, conic gradients, interpolation spaces and
  layered backgrounds draw no background. Stops interpolate in sRGB with transparent stops premultiplied; CSS
  would use Oklab for non-sRGB colours. A repeating radial gradient whose first stop is past 0 repeats from the
  centre.
- A Spacer in a fixed-height column Box keeps its flow margins and gaps but does not grow, and a column Box with
  `wrap` never wraps into a second column.
- Flutter has no timer role: a Timer is a labelled semantics group (the reference's timer role is not a live
  region either).
- Carousel arrows show on desktop platforms, standing in for `@media (hover: none)`.
- DatePicker opens a Cupertino date wheel on iOS and the Material calendar elsewhere, as `<input type=date>` does
  on each platform.
- Markdown links have no 3px underline offset and are not reached with Tab (Flutter text spans cannot).
- Pie slices have no hover title (the reference's SVG `<title>`).
- A native HtmlView runs only where the web view gives it an opaque origin; elsewhere its markup shows as inert
  text. The web path does not add the reference's `loading="lazy"` or its parent "measure" handshake.
- The expanded map is a modal route, so screen readers see only the map while it is open. A change pushed from
  the parent (streamed places, a theme switch) reaches the open expanded map one frame late.
- On the Dart VM, local time before 1901-12-13 uses the zone's standard offset, not ICU's local mean time (Flutter
  web matches). The VM reads the OS zone only inside the 32-bit `time_t` window.
- Integers past 2^53 handed to a host's own `jsonEncode` print as Dart ints. Everything the engine serialises
  prints like JavaScript.
- Only a builder's own throw reaches `onError` as `render-error`. Flutter catches a descendant widget's build
  error inside that widget.
- Flutter `validateForm` unwraps any `{value}` map; react-lang unwraps only maps with a `componentType` key, which
  a field restored from JSON lacks.
- `setDefaultValue` skips a null default; react-lang skips only `undefined`, and Dart has no undefined.
- `buildActionUserMessage` always writes the form-state slot: `ActionEvent.formState` is never absent in Dart.
- An empty `tools` list means no tool provider; react-lang treats `{}` as a provider whose calls fail with
  tool-not-found.
- `OpenUiRetry` and the preview buttons have no `preventDefault`; the preview has no `contentId` or
  `aria-controls` (it uses `Semantics(expanded:)` and a labelled container).
- `{steps: <non-list>}` as an action: react-lang iterates it (a string has no steps, a number throws); the port
  reads it as a legacy object and sends its label.
- `fieldValue('')` with an empty form name reads the form `''`; react-lang treats `''` as no form.
- `isGenerating` is true before the first `update`; react-lang's prop defaults to false. Nothing renders before
  the first update.
- Map canvas keyboard navigation goes only as far as flutter_map's own keys, not MapLibre's arrow and plus keys.
  The map cannot pan past the poles, because flutter_map's latitude limit asserts when its options change.
- A separate, non-persistent web view data store is not exposed by `webview_flutter` 4.14.
- `generateSystemPrompt` takes an `OpenUiLibrary`; Dart has no `LibrarySpec` input path.

**Not ported:** lang-core telemetry and devtools, React rendering and hooks, MCP client auto-detection,
`console.warn` output, react-ui `runChatAction` (the view already routes events by type), react-lang's devtools
and library publish tests, and observability hooks.

## Follow-up work

- Saving edits for `ConversationChatController` transcripts needs a backend message update.
- Host `ToolSet` tools as `OpenUiTool`s, if apps want one tool list for the agent and for Query.
- The reference's coach (`/clash`) and chess libraries, as their own `ComponentSpec` sets.
