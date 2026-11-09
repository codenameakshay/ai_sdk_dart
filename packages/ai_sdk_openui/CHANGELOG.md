## 3.1.0 (unreleased)

- `OpenUiSession(policy: ValidationPolicy(...))` applies the validator's policy at runtime. With
  `unknownComponents: UnknownComponentPolicy.fail`, a program that names a component the library lacks has no
  `root`. `maxNodes` caps the evaluated tree, `@Each` expansions included (an item that builds no component,
  such as a string, still counts as one): past it the session stops
  evaluating, has no `root`, and reports a `too-many-nodes` error. `OpenUiErrorCode` gains `tooManyNodes`, so an
  exhaustive `switch` over it needs a new case.
- `OpenUiAnswers` keeps one session per message for any transport: feed it full text, deltas, edit-mode patches or a
  `Stream<OpenUiMessageEvent>`, save with `onSave`, and replay a saved message with `update(id, text, streaming: false)`.
  `messageWithState` and `messageState` read and write an answer's saved state.
- Async host actions: `ActionSpec(handler:)` runs a library action in the session and returns `ActionSuccess` or
  `ActionFailure(message)`. Each run gets an `idempotencyKey` that stays the same for retries of the same write,
  and `OpenUiSession.actionStatus(action, nodeId:)` reports pending, done or failed per triggering node.
  `confirm:` makes `run` wait for `confirmed: true`, and `disableAfterSuccess:` stops repeats. Statuses are saved
  in `session.state` under `__openui_actions` and restored from `initialState`; a run cut off mid-flight restores
  as failed. Actions without a handler still reach the host as events.
- A handled action's idempotency key and status come from the message scope, the action name and its resolved
  params, never from the control's position: an `@Each` row keeps its key, and a `disableAfterSuccess` row stays
  disabled, when a restore adds rows around it. Two controls with the same action and params share one key.
- `OpenUiSession(resolveAction:)` settles a handled run that a restore cut off mid-flight: it gets the run's name,
  params and original idempotency key, and the run reads as the new `ActionPhase.unknown` (disabled, never
  retried) until it returns done or failed. Without it, such a run still restores as failed.
- `ActionSuccess(data)` carries the host's JSON receipt, such as the id of the record it wrote. It is saved with
  the session state, and later steps of the same plan read it from `ActionInvocation.results` and
  `ActionEvent.results`, keyed by action name, also after a restore.
- `Impure` (the clock and random seams that `@Today`, `@Now` and `@Random` use) is public, so hosts and tests can pin time and randomness.
- `OpenUiSession` and `OpenUiAnswers` take `clock`, `random` and `timeZone`, so two sessions in one process can
  read their own time, randomness and zone; the `Impure` hooks are now only the defaults. `OpenUiTimeZone` is a
  host-supplied offset per instant (`OpenUiTimeZone.fixed`, `OpenUiTimeZone.utc`); null keeps the device zone.
- `intelligentUiWithout(optionalIuiComponents)` gives a library without Math, Map, MapMarker, YouTube and HtmlView, and `chatPromptFor(library)` / `dashboardPrompt(library:)` drop the medium-rule clauses for components the library lacks. `intelligentUi` and `chatPrompt` are unchanged.
- The system prompt follows the library: `chatPromptFor` and `dashboardPrompt(library:)` leave out rules and
  examples that use a component or `@call` the library lacks, `extend` drops group notes that name a removed
  component, and component, function and action descriptions lose the sentences that call a missing component or
  name an unlisted step. `PromptOptions(allowedActions:)` (the same set as `ValidationPolicy.allowedActions`) lists
  only those steps and actions, takes the others out of component signatures (leaving out a component whose
  step slot keeps none), and the fixed text (action examples, `@Run` refresh and Mutation, Forms, and the
  "tables, charts, forms" hints) names only steps and components the prompt offers. `intelligentUi`'s prompts are unchanged.
- `library.validate(program, policy: ValidationPolicy(...))` and `validateProgram` (from a spec's JSON Schema
  alone) return a `ValidationReport`: parse issues plus node, depth and string limits, unknown-component handling
  (drop or fail) and allowed actions, each with its statement id. `toJson()` is the wire form.
- `dart run ai_sdk_openui:openui validate <spec.json> <program>` prints that report for any spec exported with
  `toSpecJson()`, including host extensions.
- `conformance/vectors.json`: programs and the parse results `@openuidev/lang-core` 1.0.0 gives them, for any
  server; `make test-openui-conformance` checks them against lang-core, and the Dart tests check this port.
- `openui spec <spec.json|intelligent-ui>` prints a library spec as canonical JSON (sorted keys; schema
  `properties` keep their positional order), and `canonicalJson(library.toSpec())` prints the same bytes for a
  host library. Policy flags add a `policy` block, which `openui validate` applies under its own flags;
  `ValidationPolicy.toJson`/`fromJson` read and write it.
- Bound record schemas: `library.validate(program, boundSchemas: {r'$order': jsonSchema})` (also
  `library.parse`, `validateProgram` and `openui validate --bound-schemas=<file>`) checks every bound path
  against its record's schema: a path the schema lacks is the new `unknown-bound-path` error, and a value
  whose type does not fit the prop is `type-mismatch`. A computed index into a record (`$order[$k]`) is no
  longer a bound path, so it cannot feed a bound-only prop, in sessions too.
- `Steps.set` and `Steps.reset` let an action slot list `@Set` and `@Reset`. Every `@` step given to a
  restricted slot (directly, in `Action([...])` or in a ternary branch) must be one the slot lists, or it is a
  `type-mismatch` and the prop is dropped, so the Dart validator agrees with one that reads `spec.json`.
- Migration: `ValidationCode` and `OpenUiErrorCode` gain `unknownBoundPath`. An exhaustive `switch` over
  either needs a case.
- Validator vectors: `conformance/vectors.json` gains vectors with `bound`, `policy` and `expectReport`, run
  against `conformance/validator-spec.json`, for every report code. `doc/validation.md` documents the report
  (codes, severities, path syntax) as a stable contract for validators in other languages.
- `Money`: an exact amount in integer minor units with an ISO 4217 code (scale from CLDR), parsed from
  `{minor, currency}` or `{amount: "12.34", currency}`, with `+`, `-` and `format({locale})`. It never uses a
  double. `formatMoney` adds `@FormatMoney` to a library through `extend`.
- `Money.format(trimZeroFraction: true)` writes whole amounts without the zero fraction (`₹1,23,456` in en-IN;
  `₹1,23,456.50` keeps it). `formatMoneyWith(boundOnly: true, trimZeroFraction: true)` builds an `@FormatMoney`
  that takes only host-bound amounts and/or trims. `Money` rejects codes outside ISO 4217 (`XYZ`).
  `@Format(x, "currency")` stays double-based for the reference and is documented as not money-safe.
- `OpenUiSession(locale: 'de-DE')` formats `@Format`, `@Plural` and `@FormatDate` for that locale
  (en-IN groups 12,34,567.00; de-DE writes 1.234,56 €). No locale, or en-US, keeps the reference's output.
  `FunctionSpec.localized` lets a library function do the same.
- Host-bound records: `OpenUiSession(records: [BoundRecord('order', json)])` gives a program a read-only
  `$order`. Props, action params and function params marked `.boundOnly()` take only a path into a record
  (`$order.total`, `$orders[0]`, an `@Each` item); a literal is rejected with the new `bound-only` error
  (also checked by `library.parse(program, bound: {...})`). The JSON Schema marks them `"x-openui-bound": true`,
  which lang-core ignores.
- Bound-only fields nested in a prop are enforced too: an object field or list item marked `.boundOnly()`
  (`S.object({'amount': S.any().boundOnly()})`, `S.list(S.string().boundOnly())`) takes only a bound path,
  reported at its own path (`/payment/amount`, `/ids/0`), and the whole prop is dropped. A computed container
  (state, a ternary, a call) around such fields is rejected unless it is itself a bound path.
- `PromptOptions.records` adds a "Bound Data" section and `PromptOptions.state` a "Current State" section for
  seeded `$variables`; `describeBoundRecords` returns the first for per-turn use. Default prompts are unchanged.
- Migration: `ValidationCode` and `OpenUiErrorCode` gain `boundOnly`. An exhaustive `switch` over either enum
  needs a case for it.
- A `pattern` validation rule that repeats a repeating group, such as `^(a+)+$`, is ignored like a pattern that
  does not compile, so model-written input cannot freeze the UI thread with catastrophic backtracking.
- `OpenUiAnswers.listen(events, onError:)`: an error on the event stream cancels it and goes to `onError` with the
  id of the message it was feeding, which stays unfinished, instead of becoming an uncaught zone error.
- Streaming is cheaper per delta: an unframed answer is no longer split into message sections twice per update, the
  streaming parser no longer scans the whole text for a trailing `$name`, and the initial state is serialised once.
  A 20 KB answer in 1-character deltas went from about 15 s to under 3 s.
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
