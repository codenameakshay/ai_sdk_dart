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
   prompt and check a program without Flutter. That is why the engine is its own package. Lang-core's telemetry
   is not ported.
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
   initialization, form state as `{value, componentType}` wrappers, queries blocked while streaming, and steps
   run in their original order (a failed Mutation stops the plan).
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

## Follow-up work

- Phase 2: `ai_sdk_flutter_ui` renders assistant messages through `OpenUiSession` and `OpenUiView`, keeps one
  session per message, and sends `@ToAssistant` events (with form values) as the next user turn.
- The reference's coach (`/clash`) and chess libraries, as their own `ComponentSpec` sets.
