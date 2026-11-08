## 3.1.0 (unreleased)

- First release: Flutter renderer for Open Intelligent UI answers (a port of
  thesysdev/open-intelligent-ui at `9df2e64`), with `OpenUiView`, a builder per component,
  `OpenUiTheme` light and dark tokens, injectable `OpenUiServices`, optional Wikimedia and OSRM
  clients, and a gallery example app.
- `package:open_intelligent_ui/chat.dart`: `OpenUiChat` renders answers in
  `ai_sdk_flutter_ui` chats, and `OpenUiUserMessage` shows `@ToAssistant` turns with their form
  values. The example has an offline chat demo.
