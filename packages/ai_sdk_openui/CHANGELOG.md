## 3.1.0 (unreleased)

- First release: OpenUI Lang 1.0 (a port of `@openuidev/lang-core` and the state, query and
  action handling of `@openuidev/react-lang` 1.0.0) and the Open Intelligent UI library spec
  (a port of thesysdev/open-intelligent-ui at `9df2e64`), with `OpenUiSession`,
  `OpenUiLibrary`, a schema DSL, the chat and dashboard prompts and demo data tools.
- `Js.stringify` (used for saved message context, store comparison and query keys) now writes
  numbers and integer-like object keys as `JSON.stringify` does.
