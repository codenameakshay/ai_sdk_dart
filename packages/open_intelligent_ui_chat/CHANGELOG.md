## 3.1.0 (unreleased)

- First release: OpenUiChat and OpenUiUserMessage, split from open_intelligent_ui.
- `OpenUiChat` takes `send` instead of an agent for any transport (`agent` is now optional), renders answers
  stored as text parts (as `ConversationChatController` stores them), passes `locale` and `records` to each
  answer's session, and scopes action keys to the message id. `OpenUiAnswerView` renders an `OpenUiAnswers`
  message.
- Migration: `OpenUiChat.agent` is nullable; code that reads it needs `!` or a null check.
