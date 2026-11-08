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
packages/ai_sdk_openui         pure Dart, no Flutter
  ai_sdk_openui.dart           the language: schema DSL, library, session, elements, events
  intelligent_ui.dart          the library: IuiComponent, intelligentUi, chatPrompt, dashboardPrompt, demoTools
packages/open_intelligent_ui   Flutter; depends on ai_sdk_openui and re-exports it
  open_intelligent_ui.dart     OpenUiView, OpenUiScope, OpenUiServices, OpenUiTheme
```

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
   synchronous `listen`, `field`, `run`, `dispose`. It ports react-lang's `useOpenUIState`: store
   initialization, form state as `{value, componentType}` wrappers, queries blocked while streaming, actions
   allowed while plain text streams (only an unfinished OpenUI Cloud bundle blocks them), structured `errors`
   with `onError` and `onStateUpdate`, and steps run in their original order (a failed Mutation stops the plan).
6. **Events keep lang-core's payload:** `ActionEvent(type, params, humanFriendlyMessage, formState, formName)`.
   One `run` accepts a step plan, a legacy `{type, ...}` action object, or no action (a Button without an action
   sends its label).
7. **Host services are injected.** `OpenUiServices` covers opening URLs, the clipboard, image search, street
   routing and map tiles. The package hard-codes none of the reference's `/api` routes.

## Hard widgets

| Widget | Choice | Fallback |
|---|---|---|
| Map | `flutter_map` raster tiles, markers, route polyline, category filter | straight segments when no route |
| HtmlView | `webview_flutter` with the reference's CSP, navigation blocked, no bridges | titled card where no web view runs |
| YouTube | its own embed policy (`youtube-nocookie`, after the id check) | a card that opens the video |
| Chart | hand port of `chart.tsx` to `CustomPainter` | none |
| Markdown | hand port of the reference's restricted parser | none |
| Svg | `CustomPainter`, `path_parsing` for `d` | a bad path is skipped |
| Math | `flutter_math_fork` | the TeX source in monospace |

## Reviews

Two design candidates (Opus and Grok 4.7, written independently) converged on the whole shape above. The
combined design then went to two independent reviewers with the same brief.

- **Sol (`gpt-6.1-sol`, high effort):** approve with changes. Its five blocking points were all adopted:
  compare the whole spec, not one `$def` at a time; one action interface that keeps the full event payload and
  the original step order; react-lang's exact form identity and field storage; a real HtmlView security design,
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
  2^53. `patterns.test.ts`, the fourth reference test file, is ported.
- **Renderer:** tables lay out like HTML tables, grid rows share a height, card typography and the card-title
  rule apply, Markdown tables and links match, Svg overflows its box and composites opacity as a layer,
  `SvgText` no longer crashes on `currentColor`, the map expands in place and flies between frames, and
  Inter is bundled.

## Parity

Every component, function and action of the reference library is ported, with its name, argument order and
option values unchanged. The spec golden proves the names and signatures; the function tests, ported case for
case from the reference's four test files and checked against Node, prove the behaviour.

**Kept on purpose.** These differ from react-lang because matching it would bring back a bug:

- Re-applying `initialState` fills only keys the store does not have, so a user's edits survive.
- A Query shared by several statements keeps its answer and loading state when the statement that started it
  goes away.
- Data shaped like an action step runs only as `open_url` (with a string URL) or `continue_conversation`, so
  tool data cannot set state or fire Mutations.
- The store compares array and object defaults by value, so a re-parse does not notify on every chunk.
- A prop whose expression throws evaluates to null (with its runtime error) instead of lang-core's raw
  expression, so builders only ever see JSON values.

**Known differences:**

- Maps draw raster tiles with `flutter_map`, not the reference's MapLibre vector style. Vector tiles would need
  `vector_map_tiles` and its renderer, which is heavy on mobile.
- Inter ships as static 400, 500 and 600 faces; the reference's CSS asks for 440, 560 and 640.
- Math uses `flutter_math_fork`, which supports less TeX than KaTeX; unsupported input shows the source.
- `@Sort` on text folds Latin accents and orders punctuation before digits, an approximation of ICU
  `localeCompare`; map pins detect emoji by the main Unicode blocks.
- A Table cell holding a component other than Badge, Button, IconButton, Icon or Link has no measured
  min-content width, so a narrow table may squeeze it.
- The native YouTube embed sends `https://www.youtube-nocookie.com/` as its Referer unless
  `OpenUiServices.embedReferrer` names the host app's site.
- A Popover trigger wraps instead of overflowing when its row is narrower than its content.
- The expanded map covers the page with a scrim but does not hide the page from screen readers, as
  `aria-modal` does: `BlockSemantics` inside an `OverlayPortal` also hides the map itself.

**Not ported:** lang-core telemetry and devtools, React rendering and hooks, the deprecated `generatePrompt`,
MCP client auto-detection, and `console.warn` output.

## Follow-up work

- Phase 2: `ai_sdk_flutter_ui` renders assistant messages through `OpenUiSession` and `OpenUiView`, keeps one
  session per message, and sends `@ToAssistant` events (with form values) as the next user turn.
- The reference's coach (`/clash`) and chess libraries, as their own `ComponentSpec` sets.
