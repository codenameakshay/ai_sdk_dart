## 3.1.0 (unreleased)

- First release: OpenUI Lang 1.0 (a port of `@openuidev/lang-core` and the state, query and
  action handling of `@openuidev/react-lang` 1.0.0) and the Open Intelligent UI library spec
  (a port of thesysdev/open-intelligent-ui at `9df2e64`), with `OpenUiSession`,
  `OpenUiLibrary`, a schema DSL, the chat and dashboard prompts and demo data tools.
- `OpenUiMessage` parses and builds lang-core's `]]>openui:` message sections and writes the
  user turn for a `@ToAssistant` event. `OpenUiSession.onStateUpdate` reports user changes to
  `$state` and form fields.
