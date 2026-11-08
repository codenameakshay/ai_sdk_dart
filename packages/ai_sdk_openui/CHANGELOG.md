## 3.1.0 (unreleased)

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
