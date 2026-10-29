# Widget Gallery (advanced_app)

The Widget Gallery page of `examples/advanced_app` shows 12 `ai_sdk_flutter_ui` widgets (in 11 cards) with static sample data and one synthetic stream. It needs no key and no network. The user taps suggestions, approves or denies a tool call, copies a message, retries or dismisses an error, streams a sample object, and scrolls a list to the latest item.

## Sub-features

- `gallery-suggestions` shows `PromptSuggestions`. Tapping `Plan a trip to Kyoto` shows `Selected: Plan a trip to Kyoto`.
- `gallery-typing` shows `TypingIndicator` with the label `Assistant is typing`.
- `gallery-assistant-turn` shows `AssistantMessageView`: a collapsed `Reasoning` row, the answer text, a `getWeather` tool card with its result, and a source chip. `Reasoning` expands. The source chip shows `Open: https://weather.example.com/tokyo`.
- `gallery-approval` shows `ToolApprovalCard` with a `Reason (optional)` field. `Approve` shows `Approved — <reason>` and `Deny` shows `Denied — <reason>`.
- `gallery-tool-cards` shows `ToolCallCard` twice: `calculate` with `Result 63`, and `fetchUrl` with `Tool error` and `SocketException: failed host lookup`.
- `gallery-actions` shows `MessageActionsBar`. `Copy message` writes the text to the clipboard and shows `Copied to clipboard`. The other three buttons show `Regenerate` and the two thanks messages.
- `gallery-media` shows `MessageImage` with `Remote image blocked` (remote URLs are blocked by default) and `MessageAttachment` for `design-spec.pdf`. Tapping the attachment shows `Open attachment`.
- `gallery-usage` shows `UsageView` with `Input 1240 Output 318`.
- `gallery-error` shows `ChatErrorView` with `Connection timed out after 30s`. `Retry` shows `Retry` and `Dismiss` shows `Dismissed`.
- `gallery-object-stream` shows `ObjectStreamView`. `Stream a sample object` adds `country`, `capital`, `population` and `currency` one by one, 450 ms apart.
- `gallery-scroll-bottom` shows `ScrollToBottomButton` over a 30-row list. It shows at the top, jumps to `Message 30`, hides at the bottom, and shows again after scrolling up.
- `gallery-theme` renders the same page in the dark Material theme when the system asks for dark.

## How to get to it (user POV)

- Open the app, tap the menu button (`Open navigation menu`), and choose `Widget Gallery`.
- Open the web URL `/?page=widget-gallery`. The page is selected by the `page` query parameter, not by a hash route.

## Driving it with vfc

Preconditions:

- `VFC_APP=advanced_app` was exported in the **same call** as `$S build`. `$S doctor` prints `OK   app: advanced_app` and no `FAIL` line.
- No key and no backend are needed. `$S up` starts only the web server and Chromium.

- **Canned proof, all sections.** Run `$S scenario widget-gallery`. Output `PASS widget-gallery`. `widget-gallery.json` has one `click` step per snack bar text above, a `clipboard` step with `It is currently 22°C and sunny in Tokyo.`, `partial object observed` with `hasCurrency:false`, `final object observed`, and `jumped to latest; button hidden` then `scrolled up; button visible again`. Each section has `widget-gallery-<section>.{aria.txt,png}`, plus `widget-gallery-object-stream-view-partial.png`.
- **Canned proof, theme.** Run `$S scenario widget-gallery-dark`. Output `PASS widget-gallery-dark`. The `background luminance` step has `light` above 0.8 and `dark` below 0.2. Look at `widget-gallery-dark-approval.png`.
- **One section by hand.** Run `$S browser open widget-gallery`, then `$S browser scroll --to ToolApprovalCard --substring`, then `$S browser snapshot --name gallery-approval`.
- **Approve with a reason.** Run `$S browser type --name "Reason (optional)" --text "looks safe"` and `$S browser click --name Approve`. A snack bar `Approved — looks safe` shows for about one second. Snapshot it at once or use the scenario.
- **Stream the object.** Run `$S browser scroll --to ObjectStreamView --substring`, then `$S browser click --name "Stream a sample object"`. After 2 s, `$S browser aria` shows all four fields in one group.
- **Scroll list.** Run `$S browser click --name "Scroll to latest message"`. The text `Message 30` shows and the button is gone.

## Gotchas

- The page is long and Flutter builds only the rows near the viewport. Use `$S browser scroll --to <section title> --substring` before you read or click a lower section. A click on an off-screen widget times out.
- Snack bars last about one second. `scenario` asserts them with a tight poll. A separate `$S browser aria` call is too slow.
- A snack bar can merge with a hover tooltip into one text node (for example `Open: https://... Open source: Tokyo Weather`). Match the start of the text.
- The page description says the image falls back to a placeholder "offline". It is the default security block for any remote URL, so it shows `Remote image blocked` online too. The gallery sends no request for it.
- The tool approval card stays on screen after `Approve` or `Deny`. The gallery only shows a snack bar.
- Clipboard read-back needs a browser permission. The scenario grants it through CDP. This is a test setup, not an app change.
- The sample stream ends after about 1.8 s. The scenario polls every 40 ms to see the partial state. On a very slow machine, it can miss it and then fails with `Never observed a partial object`.
- `$S browser open` sets a 1280×900 window for that call only. Later `browser` calls can screenshot a shorter viewport. `scenario` keeps the size for the whole run.
- The font requests to `fonts.gstatic.com` in `events.jsonl` are normal.
