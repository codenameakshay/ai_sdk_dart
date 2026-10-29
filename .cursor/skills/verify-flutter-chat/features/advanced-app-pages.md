# Advanced app pages (advanced_app)

`examples/advanced_app` is a drawer app with 12 pages. With no key, a user can use the drawer, the five Tools Chat fixture states, the local controls of the Conversation page, and the missing-key messages on six provider pages. The Widget Gallery has its own file. Sending a message or request on any other page calls OpenAI, Anthropic or Google and needs a key baked in at build time.

## Sub-features

- `adv-nav` opens each of the 12 pages from the drawer. The first page is `Provider Chat`.
- `adv-fixture-normal` shows `Tools Chat` with one user message, `Offline fixture reply`, and a composer that clears on Send. Its `onSend` is a no-op; this does not prove a real model turn.
- `adv-fixture-approval` shows an approval card for `deleteFile`, a locked composer (`Approval pending…`) and a disabled `Send message`. `Approve` shows `Approved fixture action` and `Deny` shows `Denied fixture action`.
- `adv-fixture-error` shows `Bad state: Fixture request failed` with `Retry` (snack `Retry`) and `Dismiss` (snack `Dismissed fixture error`).
- `adv-fixture-sources` shows a user message, an expanded reasoning row, a `getWeather` tool card with `Sunny, 22°C in Tokyo.`, the answer, and `Sources` with `Example Weather Feed`.
- `adv-fixture-history` shows 12 messages. `Conversation history 12` is reachable by scrolling.
- `adv-conversation-controls` runs `Retry last turn` (snack `There is no failed assistant turn to retry.`), `Save snapshot` (`Saved (0 messages).`), `Restore snapshot` (`Conversation restored.`) and `New conversation` with no key.
- `adv-conversation-rtl` toggles Arabic strings and RTL. `Send message` becomes `إرسال` and moves left of the field.
- `adv-guards` shows the exact missing-key message on Image Gen, Embeddings (OpenAI and Google), Text-to-Speech, Speech-to-Text and Responses, and sends no provider request. Multimodal keeps `Analyze` disabled until an image is picked.
- `adv-live-*` are the pages that need a key. See `Live-only paths` below.

## How to get to it (user POV)

- Tap `Open navigation menu` and choose a page.
- Open `/?page=<slug>` with the slug `provider-chat`, `tools-chat`, `image-gen`, `multimodal`, `embeddings`, `tts`, `stt`, `completion`, `object-stream`, `conversation`, `responses` or `widget-gallery`.
- Open `/?page=tools-chat&state=<fixture>` with `normal`, `approval`, `error`, `sources-tool` or `long-history`. The app uses the fixture and ignores the key.

## Driving it with vfc

Preconditions:

- `VFC_APP=advanced_app` was exported in the **same call** as `$S build`. `$S doctor` prints `OK   app: advanced_app` and no `FAIL` line.
- For `adv-guards`, the build has no key at all (`INFO provider keys baked into build: none`). The guards only exist without a key.

- **Drawer.** Run `$S scenario drawer-nav`. Output `PASS drawer-nav`. It has one `page` step and one `drawer-nav-<page>.png` for each of the 11 pages after `Provider Chat`.
- **Fixtures.** Run `$S scenario tools-chat-fixtures`. Output `PASS tools-chat-fixtures`. Look at `tools-chat-approval-pending.png` (locked composer) and `tools-chat-sources-tool.png`.
- **One fixture by hand.** Run `$S browser open "tools-chat?state=approval"`. `$S browser aria` shows `group "Tool approval required for deleteFile"`, the buttons `Deny` and `Approve`, `textbox "Approval pending…" [disabled]` and `button "Send message" [disabled]`.
- **Conversation controls and RTL.** Run `$S scenario conversation-ui`. Output `PASS conversation-ui`. The `arabic layout` step has `sendX` smaller than `fieldX`. Look at `conversation-ui-arabic.png`.
- **Missing-key guards.** Run `$S scenario keyless-guards`. Output `PASS keyless-guards`. The `provider requests` step has `count:0`. Look at `keyless-embeddings.png`.
- **Open by hand.** Run `$S browser nav "Object Stream"` to use the drawer, or `$S browser open object-stream` to use the URL. Both are separate entry points.

### Live-only paths

These steps come from the page code. No key was available when this file was written, so the steps were not run. Preconditions for all of them: the keys were exported in the **same call** as `$S build`, `$S doctor` prints the key names under `provider keys baked into build`, and you have the user's approval to spend tokens. Live output is not deterministic. Assert on structure, not prose.

- **Provider Chat** (`ChatController`, `AiChatScaffold`). Needs `OPENAI_API_KEY` for `openai`, `ANTHROPIC_API_KEY` for `anthropic`, `GOOGLE_API_KEY` for `google`. Run `$S browser open provider-chat`, then `$S browser send "Reply with the word pineapple." --expect pineapple --timeout 60000`. `$S browser state` shows `assistantRows:1`. The app bar dropdown shows the current provider (`openai` at first). Run `$S browser click --name openai`, then `$S browser aria` to see the other entries, and click one by name.
- **Tools Chat, live** (`ChatMessageBubble`, `ToolCallCard`, `ReasoningView`, `ToolApprovalCard`, `SourceCitations`). Needs `OPENAI_API_KEY`. Run `$S browser open tools-chat`, then `$S browser send "What is 42 * 1.5?" --hint "Ask about weather or math…" --expect "63" --timeout 60000` for a tool card. Run `$S browser send "Delete q3.pdf from reports." --hint "Ask about weather or math…" --expect "Approve" --timeout 60000`, then `$S browser click --name Approve`. The result shows `Deleted /workspace/`.
- **Conversation, live** (`ConversationController`, `LocalConversationBackend`). Needs `OPENAI_API_KEY`. Run `$S browser open conversation`, then `$S browser send "Delete q3.pdf" --hint "Ask about weather, or request a file deletion…" --expect "Approve" --timeout 60000`, then `$S browser click --name Approve`. Then `$S browser click --name "Save snapshot"`; the snack shows `Saved (2 messages).` or a larger count.
- **Completion** (`CompletionController`, `StreamingTextView`). Needs `OPENAI_API_KEY`. Run `$S browser open completion`, `$S browser type --name Prompt --text "Write a haiku about Flutter."`, `$S browser click --name Generate`, then `$S browser wait-text Response --timeout 60000`.
- **Object Stream** (JSON patch and validated profile). Needs `OPENAI_API_KEY`. Run `$S browser open object-stream`, `$S browser type --name Country --text Japan`, `$S browser click --name Generate`, then `$S browser wait-text "Country Profile (validated)" --timeout 60000`.
- **Responses** (`ReasoningView`, `SourceCitations`). Needs the key of the selected provider. Run `$S browser open responses`, `$S browser type --name Prompt --text "What is Dart 3?"`, `$S browser click --name Ask`, then `$S browser wait-text Sources --timeout 90000`. With web search on, a source chip shows.
- **Image Gen, Embeddings.** Need `OPENAI_API_KEY` (Embeddings also takes `GOOGLE_API_KEY` after you click `Google`). Run `$S browser open image-gen`, run `$S browser type --name Prompt --text "A lighthouse at dawn" --substring`, click `Generate`, and snapshot. For Embeddings run `$S browser open embeddings`, click `Compare`, and read the similarity text.
- **Text-to-Speech.** Needs `OPENAI_API_KEY`. Run `$S browser open tts`, then `$S browser click --name Speak`. The page plays audio. Headless Chromium has no audible output, so only the absence of an error is observable.
- **Multimodal and Speech-to-Text.** Not driven by vfc. Multimodal needs a picked image from the gallery or camera, and Speech-to-Text needs a microphone. Neither has a keyless proof beyond `adv-guards`.

## Gotchas

- `tools-chat` pages show two app bars (the shell and the page). Both have the same title, so `$S browser aria` lists the heading twice. Use `heading … .first()`.
- An empty field shows its placeholder in its accessible name (Image Gen shows `Prompt A futuristic city at sunset…`). Pass `--substring` to `$S browser type` for such a field, or the exact name match times out.
- The Conversation page passes its own `hintText`, which wins over the Arabic strings. The field keeps its English hint in RTL. Only the buttons change.
- The approval fixture puts the approval card above the user message it belongs to. That is the fixture layout, not a streaming order.
- `keyless-guards` fails on purpose when a key was baked in. Build again without keys.
- The drawer closes after a choice. A second `nav` call opens it again.
- Do not run `build` for flutter_chat and advanced_app at the same time. They share the workspace `pub get` and `.dart_tool`.
