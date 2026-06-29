## 1.2.0

Turns `ai_sdk_flutter_ui` into a one-stop Flutter UI hub: prebuilt widgets, hardened controllers,
and full test coverage.

### Prebuilt widget library (new)

18 composable, themeable Material widgets that read only the controllers' public state and
`Theme.of(context)`. No heavy platform dependencies — attachment rendering and link-opening are
exposed as callbacks.

**Scaffolding & message list**

- `AiChatScaffold` — drop-in chat body (`ChatMessageList` + `ChatComposer`) wired to a
  `ChatController` + `ToolLoopAgent`.
- `ChatMessageList` — renders message history + an optimistic streaming bubble; auto-scrolls;
  optional `messageBuilder`.
- `ChatMessageBubble` — a single message styled by role, with selectable text.
- `AssistantMessageView` — a rich assistant turn composing text, reasoning, tool calls, sources,
  and media together.
- `MessageMedia` / `MessageImage` / `MessageAttachment` — render image and file attachments on a
  message, with an `onOpen` callback.
- `MessageActionsBar` — a per-message action row (copy, retry, …) with callbacks.

**Streaming & status**

- `StreamingTextView` — streaming text with a subtle blinking cursor.
- `TypingIndicator` — animated "assistant is typing" dots.
- `UsageView` — a compact token-usage summary (prompt / completion / total).

**Reasoning, tools & sources**

- `ReasoningView` — a collapsible panel for reasoning / "thinking" text.
- `ToolCallCard` — a tool call (name + pretty-printed JSON args) and its result/error.
- `ToolApprovalCard` — approve/reject UI for tools gated by `needsApproval`.
- `SourceCitations` — a wrap of citation chips for source parts, with an `onTap` callback.

**Input & navigation**

- `ChatComposer` — text field + send button; disabled while loading; optional `onStop`/`onAttach`.
- `PromptSuggestions` — tappable starter-prompt chips.
- `ScrollToBottomButton` — appears when the list is scrolled up; jumps to the latest message.
- `ChatErrorView` — an inline error banner with a retry callback.

**Object streaming**

- `ObjectStreamView` — renders an `ObjectStreamController`'s partial JSON as it streams.

### Controller improvements

- `ObjectStreamController` — added a `useObject`-style convenience: pass `model`/`schema` to the
  constructor and call `submit(prompt)`, which runs `streamText(output: Output.object(schema:))`
  and binds the partial-output stream. `bind(Stream<T>)` is still available for full flexibility.
  `submit` throws a clear `StateError` if `model`/`schema` are missing.
- `ChatController` — added an `isStreaming` getter (`status == ChatStatus.streaming`) for
  consistency with `CompletionController` and `ObjectStreamController`.
- `ChatController` and `CompletionController` now surface streaming errors. Errors raised during a
  `streamText` run arrive on the full event stream rather than the text stream; both controllers
  now watch it, so `error`/`onError` (and `ChatStatus.error`) fire on streaming failures, not just
  setup failures. Subscriptions are cleaned up on `stop`/`clear`/`dispose`.

### Tests

- Added the package's first test suite: **121 tests** (controller + widget) covering state
  transitions, `streamingContent`, `append`/`reload`/`clear`/`stop`, `onFinish`/`onError`,
  `isStreaming`, `ObjectStreamController.submit`/`bind`, and a `testWidgets` pass for every widget.
  **99.6%** line coverage.

## 1.1.0

- Bumped `ai_sdk_dart` constraint to `^1.1.0` to pick up `timeout`, `onAbort`, and all other 1.1.0 core improvements.
- No controller-level behaviour changes; version aligned with the rest of the monorepo.

---

## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Package renamed from `ai_sdk_flutter` → `ai_sdk_flutter_ui` to avoid conflicts with existing pub.dev packages. Depends on `ai_sdk_dart` 1.0.0.

- `ChatController` — manages a chat message list, streams assistant replies, handles optimistic UI updates. Implements `Listenable` for use with `ListenableBuilder`.
- `CompletionController` — single-turn text completion with streaming and status tracking.
- `ObjectStreamController<T>` — streams partial structured objects, providing live partial updates as JSON arrives.
- Full hook parity with Vercel AI SDK v6 React hooks: `append`, `reload`, `clear` / `reset`, `isStreaming`, `onFinish`, `onError`.

---

## 0.2.0

- Initial release.
- `ChatController` — manages a chat message list, streams assistant replies, handles optimistic UI updates.
- `CompletionController` — single-turn text completion with streaming support.
- `ObjectStreamController` — streams partial structured objects with live UI updates.
- Full hook parity: `append`, `reload`, `clear`/`reset`, `isStreaming`, `onFinish`, `onError`.