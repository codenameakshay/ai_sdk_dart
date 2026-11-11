## 3.1.0 (unreleased)

- An answer that is not a program renders as Markdown (`MarkdownBlocks`) inside the answer's `OpenUiView`, not
  as plain text, so it takes the view's theme, font and services. Fences registered in
  `OpenUiServices.markdownFences` draw there too.
- `OpenUiChat(library:)` passes the host library through `intelligentUiFor`, so a host component with no
  builder throws an `ArgumentError` and a built-in component the builders cannot draw is left out.
- First release: OpenUiChat and OpenUiUserMessage, split from open_intelligent_ui.
- `OpenUiChat` takes `send` instead of an agent for any transport (`agent` is now optional), renders answers
  stored as text parts (as `ConversationChatController` stores them), passes `locale` and `records` to each
  answer's session, and scopes action keys to the message id. `OpenUiAnswerView` renders an `OpenUiAnswers`
  message.
- Migration: `OpenUiChat.agent` is nullable; code that reads it needs `!` or a null check.
