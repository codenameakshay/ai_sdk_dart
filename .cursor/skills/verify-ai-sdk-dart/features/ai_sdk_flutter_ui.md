# ai_sdk_flutter_ui

The Flutter layer of the SDK. A developer gets four controllers (`ChatController`, `CompletionController`, `ObjectStreamController`, `ConversationController`) and 20 prebuilt Material widgets that render their state: a chat scaffold, message rows, tool and approval cards, reasoning, sources, media, usage, errors, and a scroll-to-latest button. `AiSdkUiStrings` translates the labels, and the widgets follow the app theme and the text direction. The package has no screen of its own. It can only be verified through apps that use it: `examples/flutter_chat` and `examples/advanced_app`, driven as web builds with the `verify-flutter-chat` skill.

## Sub-features

- `ui-chat-controller` streams a reply into `AiChatScaffold`, keeps one assistant message per turn, and supports stop, clear, retry and tool approval.
- `ui-completion-controller` streams one completion for a prompt, with stop and clear.
- `ui-object-controller` binds a stream of partial objects and fills `ObjectStreamView` field by field.
- `ui-conversation-controller` runs a conversation through `LocalConversationBackend` or `RemoteConversationBackend`, with tool approval, save and restore, and retry info.
- `ui-scaffold` composes `AiChatScaffold`, `ChatMessageList` and `ChatComposer`, locks the composer while an approval is pending, and shows `ChatErrorView`.
- `ui-messages` renders `ChatMessageBubble`, `AssistantMessageView`, `ReasoningView`, `SourceCitations`, `StreamingTextView` and `TypingIndicator`.
- `ui-tools` renders `ToolCallCard` (result and error) and `ToolApprovalCard` (reason field, approve, deny).
- `ui-media` renders `MessageImage` (remote URLs blocked by default), `MessageAttachment` and `MessageReasoningFileAttachment`.
- `ui-extras` renders `PromptSuggestions`, `MessageActionsBar`, `UsageView`, `ObjectStreamView` and `ScrollToBottomButton`.
- `ui-strings` swaps every built-in label through `AiSdkUiStringsScope`.
- `ui-rtl` mirrors the composer and rows in a right-to-left `Directionality`.
- `ui-theme` takes its colors from `Theme.of(context)`, so light and dark schemes both work.
- `ui-frame` coalesces stream updates per frame (`FrameNotifier`).

## How to get to it (user POV)

- Add `ai_sdk_flutter_ui`, create a controller, and put `AiChatScaffold(controller: ...)` or `AiChatScaffold.conversation(...)` in a screen. Use the other widgets alone with your own data.
- In `examples/flutter_chat`, choose the `Chat`, `Completion`, `Object`, `Local` or `Remote` tab, or open the `/conversation` or `/remote` route. Chat, Completion and Object need `OPENAI_API_KEY`.
- In `examples/advanced_app`, tap `Open navigation menu` and choose a page, or open `/?page=<slug>`. `Widget Gallery`, the `Tools Chat` fixtures (`/?page=tools-chat&state=approval`), `Conversation` (without sending) and the drawer need no key. Provider Chat, Tools Chat, Conversation, Completion, Object Stream and Responses need a key to send.

## Driving it with verify

Preconditions:

- `S=.cursor/skills/verify-flutter-chat/scripts/vfc`. Every call needs `VERIFY_RUN_ID=<id>` (from `$S new`). Read `.cursor/skills/verify-flutter-chat/SKILL.md` first.
- For flutter_chat: `$S build`, `$S up`, `$S doctor` print no `FAIL` line. For advanced_app, use a second run id and put `VFC_APP=advanced_app` on the `$S build` call. `$S doctor` prints `OK   app: advanced_app`.
- Live-only paths are marked **(live)**. They need the keys exported in the **same call** as `$S build`: `OPENAI_API_KEY` for flutter_chat, and `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` and `GOOGLE_API_KEY` for the matching advanced_app providers. Also get the user's approval to spend tokens. `$S doctor` shows which keys were baked in.

- **Keyless scenarios, flutter_chat.** Run `$S scenario local-approve`, `local-deny`, `remote-text`, `remote-approve`, `remote-deny`, `remote-unreachable`, `rtl-toggle` and `shell-nav`. Each prints `PASS <name>`.
- **Keyless scenarios, advanced_app.** Run `$S scenario widget-gallery`, `widget-gallery-dark`, `tools-chat-fixtures`, `conversation-ui`, `keyless-guards` and `drawer-nav`. Each prints `PASS <name>`. Evidence is in `/tmp/verify-flutter-chat/evidence/<id>/`.
- **ChatController (live).** In flutter_chat run `$S browser open /`, then `$S browser send "Reply with the word pineapple." --expect pineapple --timeout 60000`. `$S browser state` shows `assistantRows:1` and `composerEditable:true`. `events.jsonl` has a `200` from `api.openai.com`. Click `Clear chat` to empty the list. In advanced_app, run `$S browser open provider-chat` and send the same text.
- **ChatController, keyless.** `ConversationChatController` is a `ChatController`. `$S scenario local-approve` proves its turn loop, its pending-approval state and `assistantRows:1`.
- **CompletionController (live).** In flutter_chat run `$S browser tab Completion`, `$S browser type --name Prompt --text "Write a haiku about Flutter."`, `$S browser click --name Generate`, then `$S browser snapshot --name completion-result`. The text shows under `Response`. In advanced_app, use `$S browser open completion` and the same two commands.
- **ObjectStreamController, keyless.** `$S scenario widget-gallery` presses `Stream a sample object`. The steps `partial object observed` (`hasCurrency:false`) and `final object observed` prove that fields arrive one by one. See `widget-gallery-object-stream-view-partial.png` and `widget-gallery-object-stream-view.png`.
- **ObjectStreamController (live).** In flutter_chat run `$S browser tab Object`, `$S browser type --name Country --text Japan`, `$S browser click --name Generate`, then `$S browser wait-text "Capital" --timeout 60000`.
- **ConversationController, LocalConversationBackend.** `$S scenario local-approve` and `local-deny` show the result `Tool result: deleted /tmp/example` or `Tool denied; no local action ran.`. `$S scenario conversation-ui` (advanced_app) shows the snack bars `Saved (0 messages).`, `Conversation restored.` and `There is no failed assistant turn to retry.`.
- **RemoteConversationBackend.** `$S scenario remote-text`, `remote-approve`, `remote-deny` and `remote-unreachable` show `POST /chat` with `200`, the `x-vercel-ai-ui-message-stream: v1` header, `"approved":true` or `false` in the resume request, and the error banner.
- **ConversationRetryInfo (live).** In advanced_app run `$S browser open conversation`, `$S browser send "Delete q3.pdf" --hint "Ask about weather, or request a file deletion…" --expect Approve --timeout 60000`, then `$S browser click --name "Retry last turn"`. The snack bar says `Respond to the pending tool approval to continue.` (taken from the controller code; not run without a key).
- **AiChatScaffold, ChatMessageList, ChatComposer.** `$S scenario local-approve` has `approval pending` with `composerEditable:false` and `sendEnabled:false`, then `final` with `assistantRows:1`. `$S scenario tools-chat-fixtures` types `hello` into `Ask about weather or math…`, clicks `Send message`, and the field is empty again.
- **ChatMessageBubble.** `$S scenario tools-chat-fixtures` shows `User message What can this page do?` and `Assistant message` in `tools-chat-normal.aria.txt`.
- **AssistantMessageView.** `$S scenario widget-gallery` checks the text, `Tool call: getWeather`, `Tool result` and the source chip from one message. The PNG is `widget-gallery-assistant-message-view.png`.
- **ReasoningView.** `$S scenario widget-gallery` shows it collapsed, then clicks `Reasoning` and the reasoning text shows. `$S scenario tools-chat-fixtures` shows it expanded with `Use the weather tool and cite the source.`
- **SourceCitations.** `$S scenario widget-gallery` taps the chip and the snack bar says `Open: https://weather.example.com/tokyo`. The `sources-tool` fixture shows the non-tappable `Source: Example Weather Feed`.
- **StreamingTextView (live).** In flutter_chat, the Completion steps above stream into it. In advanced_app, run `$S browser open responses`, type a `Prompt`, click `Ask` and watch the text grow under the prompt.
- **TypingIndicator.** `$S scenario widget-gallery` shows the label `Assistant is typing` and `widget-gallery-typing-indicator.png`. The in-chat appearance before the first token is a live view; see Not covered.
- **ToolCallCard.** `$S scenario widget-gallery` checks `Result 63` for `calculate`, and `Tool error` with `SocketException: failed host lookup` for `fetchUrl`.
- **ToolApprovalCard.** `$S scenario widget-gallery` types a reason, clicks `Approve` (snack `Approved — looks safe`), then `Deny` (snack `Denied — too risky`). `$S scenario tools-chat-fixtures` shows the card with a locked composer. `$S scenario local-approve` and `remote-deny` drive it inside the scaffold.
- **ChatErrorView.** `$S scenario widget-gallery` clicks `Retry` and `Dismiss`. `$S scenario tools-chat-fixtures` shows `Bad state: Fixture request failed`. `$S scenario remote-unreachable` shows the banner with `Dismiss` and no `Retry`.
- **MessageImage.** `$S scenario widget-gallery` shows `Remote image blocked` for a remote URL, and `widget-gallery-media.png` shows the placeholder.
- **MessageAttachment.** `$S scenario widget-gallery` finds `Attachment: design-spec.pdf application/pdf` and taps it (snack `Open attachment`).
- **MessageActionsBar.** `$S scenario widget-gallery` clicks `Copy message` and reads the clipboard back (`It is currently 22°C and sunny in Tokyo.`). It also clicks `Regenerate response`, `Good response` and `Bad response`.
- **PromptSuggestions.** `$S scenario widget-gallery` taps `Plan a trip to Kyoto` (snack `Selected: Plan a trip to Kyoto`). Live: `$S browser open provider-chat` in advanced_app shows the chips `Explain async/await in Dart`, `Write a haiku about Flutter` and `Compare REST and GraphQL` with no key. `$S browser click --role checkbox --name "Compare REST and GraphQL"` then starts a turn, which needs a key.
- **UsageView.** `$S scenario widget-gallery` waits for `Input 1240 Output 318`.
- **ObjectStreamView.** See the ObjectStreamController steps above. It also shows `Press Stream to watch fields arrive live.` before the stream.
- **ScrollToBottomButton.** `$S scenario widget-gallery` checks the button at the top, clicks it so `Message 30` shows and the button is gone, then scrolls up and the button is back. PNGs: `widget-gallery-scroll-to-bottom-button-top.png`, `-bottom.png` and `widget-gallery-scroll-to-bottom-button.png`.
- **AiSdkUiStrings, AiSdkUiStringsScope.** `$S scenario rtl-toggle` (flutter_chat) shows `رسالة…`, `إرسال الرسالة`, `موافقة` and `رفض`. `$S scenario conversation-ui` (advanced_app) shows `إرسال` for Send.
- **RTL.** `$S scenario rtl-toggle` has `sendX < fieldX` in Arabic and `sendX > fieldX` in English. `$S scenario conversation-ui` has the same result. Look at `rtl-toggle-arabic-final.png` and `conversation-ui-arabic.png`.
- **Theme.** `$S scenario widget-gallery-dark` has a `background luminance` step with `light` above 0.8 and `dark` below 0.2. Look at `widget-gallery-dark-approval.png` and `widget-gallery-dark-error.png`.

## Gotchas

- Open the PNGs. A text assertion does not prove that a card is readable, aligned or not clipped.
- Snack bars last about one second, so only a scenario (tight poll) can prove them.
- The gallery and the fixtures use sample data. They prove the widgets, not the controllers. Controller behavior needs the live paths or the flutter_chat Local and Remote scenarios.
- Chat, Completion and Object in flutter_chat, and every advanced_app provider page, are live-only. Without a key, report them as not run. Do not count the keyless missing-key guards (`keyless-guards`) as proof of generation.
- The Widget Gallery says its image "falls back to a placeholder offline". The block is the default for every remote URL, so it also shows online.
- Not covered: `FrameNotifier` and `SchedulerBindingFrameNotificationScheduler`: they are internal throttles with no user-visible effect, so the web build cannot tell them from direct notification.
- Not covered: `StreamingControllerBase` and `ChatStatus` as types: they are visible only through the controllers above.
- Not covered: `ScrollBottomPolicy`: it only decides auto-scroll while a live response streams, and the keyless pages do not stream into a list.
- Not covered: `MessageReasoningFileAttachment`: no app sends a reasoning file part, so no screen renders it.
- Not covered: a loaded `MessageImage` (inline bytes, or `remoteImageProviderBuilder`) and the image-failed state: no app passes image bytes or a provider builder. The Multimodal page needs a picked file, which vfc cannot choose.
- Not covered: `ChatMessageList` custom `messageBuilder`, and its auto-scroll during a stream: no app sets a custom builder, and a stream needs a key.
- Not covered: `TypingIndicator` and `AiSdkUiStrings.assistantResponding` inside a running chat: they show only for the first moments of a live turn.
- Not covered: the retry states `unsafe`, `unsupported` and `RetryUnsafeError`/`RetryUnsupportedError`: no app can create them. The iOS integration suite covers a failed local turn.
- Not covered: translations of strings that the demo Arabic sets do not override (for example `toolError`, `remoteImageBlocked`, `sources`): they show in English in every app.
- Not covered: per-message content direction (English text in an Arabic UI keeps its own direction): the scenarios do not assert it.
- Not covered: reduced-motion behavior, haptics and press-scale animation (`AiMotion`, `AiHaptics`): these are internal and not exported, and headless Chromium shows no haptics.
- Not covered: a public theme API: the package has none. Only `Theme.of(context)` is used, and the dark scheme is the only second theme that an app offers.
- Not covered: iOS and Android rendering, screen readers and real keyboard behavior: the web build proves only the semantics tree and the pixels.
- Not covered: `CodeBlock` and `prettyJson`: they are not exported. They show inside the tool and object cards.
