## 3.1.0 (unreleased)

- `Impure` (the clock and random seams that `@Today`, `@Now` and `@Random` use) is public, so hosts and tests can pin time and randomness.
- `intelligentUiWithout(optionalIuiComponents)` gives a library without Math, Map, MapMarker, YouTube and HtmlView, and `chatPromptFor(library)` / `dashboardPrompt(library:)` drop the medium-rule clauses for components the library lacks. `intelligentUi` and `chatPrompt` are unchanged.
- `library.validate(program, policy: ValidationPolicy(...))` and `validateProgram` (from a spec's JSON Schema
  alone) return a `ValidationReport`: parse issues plus node, depth and string limits, unknown-component handling
  (drop or fail) and allowed actions, each with its statement id. `toJson()` is the wire form.
- `dart run ai_sdk_openui:openui validate <spec.json> <program>` prints that report for any spec exported with
  `toSpecJson()`, including host extensions.
- `conformance/vectors.json`: programs and the parse results `@openuidev/lang-core` 1.0.0 gives them, for any
  server; `make test-openui-conformance` checks them against lang-core, and the Dart tests check this port.
- `Money`: an exact amount in integer minor units with an ISO 4217 code (scale from CLDR), parsed from
  `{minor, currency}` or `{amount: "12.34", currency}`, with `+`, `-` and `format({locale})`. It never uses a
  double. `formatMoney` adds `@FormatMoney` to a library through `extend`.
- `OpenUiSession(locale: 'de-DE')` formats `@Format`, `@Plural` and `@FormatDate` for that locale
  (en-IN groups 12,34,567.00; de-DE writes 1.234,56 €). No locale, or en-US, keeps the reference's output.
  `FunctionSpec.localized` lets a library function do the same.
- Host-bound records: `OpenUiSession(records: [BoundRecord('order', json)])` gives a program a read-only
  `$order`. Props, action params and function params marked `.boundOnly()` take only a path into a record
  (`$order.total`, `$orders[0]`, an `@Each` item); a literal is rejected with the new `bound-only` error
  (also checked by `library.parse(program, bound: {...})`). The JSON Schema marks them `"x-openui-bound": true`,
  which lang-core ignores.
- `PromptOptions.records` adds a "Bound Data" section and `PromptOptions.state` a "Current State" section for
  seeded `$variables`; `describeBoundRecords` returns the first for per-turn use. Default prompts are unchanged.
- Migration: `ValidationCode` and `OpenUiErrorCode` gain `boundOnly`. An exhaustive `switch` over either enum
  needs a case for it.
- First release: OpenUI Lang 1.0 (a port of `@openuidev/lang-core` and the state, query and
  action handling of `@openuidev/react-lang` 1.0.0) and the Open Intelligent UI library spec
  (a port of thesysdev/open-intelligent-ui at `9df2e64`), with `OpenUiSession`,
  `OpenUiLibrary`, a schema DSL, the chat and dashboard prompts and demo data tools.
- The engine's tests also run compiled to JavaScript: `make test-web` runs them on Node with `TZ=UTC`.
- Runtime values follow lang-core's JavaScript semantics: negative zero, integers past 2^53, object key order
  and `__proto__` handling, and `Js.stringify` output like `JSON.stringify`.
- `@Sort` on text compares exactly as ICU `localeCompare` (CLDR root order), not an approximation.
- JSON forms: `jsonToOpenUI` accepts plain JSON element maps, and element nodes and the AST have JSON forms.
- OpenUI Cloud config runs the full `validateChatLibrary` checks the Dart DSL can reach.
- New lang-core exports from `lang_core.dart`: `parse`, `actionSteps`, `generatePrompt`, `buildSignature`,
  `resolveStateField`, and the mutation and tool types.
- `Schema.withDefault` (Zod's `.default()`): the JSON Schema carries the default and an omitted argument takes it.
- `buildActionUserMessage` writes the user turn for a `continue_conversation` event.
- `ResponseMetadata` exposes the response's OpenUI Cloud metadata, such as its name.
- `OpenUiSession` gains `onParseResult`, `setTools`, `metadata`, `isGenerating`, `fieldValue`,
  `setDefaultValue`, `retryQueries` and `reportRenderError`.
- `retryQueries` with nothing failed refetches every Query, as react-lang does.
- `Js.stringify` (used for saved message context, store comparison and query keys) now writes
  numbers and integer-like object keys as `JSON.stringify` does.
