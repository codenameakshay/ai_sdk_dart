# Live provider screens

The Chat, Completion and Object tabs call OpenAI `gpt-4.1-mini` from the browser with the key compiled into the build. Chat is a multi-turn streaming chat in `AiChatScaffold`. Completion streams one answer from a free prompt or a quick-prompt chip. Object streams a typed country profile, and its fields fill in as they arrive.

## Sub-features

- `chat-stream` streams an assistant reply to a typed message. `Clear chat` empties the history.
- `chat-error` shows the provider error with `Retry` and `Dismiss` when the request fails.
- `completion-prompt` streams a response into the `Response` area for a typed prompt and `Generate`. `Clear` resets it.
- `completion-chips` fills and runs a quick-prompt chip (checkbox semantics).
- `object-stream` fills the `Country Profile` fields for a typed country and `Generate`. `Reset` clears it.

## How to get to it (user POV)

- Choose the `Chat`, `Completion` or `Object` tab. The app root opens on `Chat`.

## Driving it with vfc

Preconditions:

- To test real generation, `OPENAI_API_KEY` was exported in the **same call** as `$S build`, and `$S doctor` prints `INFO OpenAI key baked into build: yes`. Without a key, the live generation paths are not expected to succeed; error/layout behavior can be checked only when the network is available.
- You have the user's approval to spend tokens on their key.

- **Keyless error path (network-dependent).** Without a baked key, run `$S browser open /`, then `$S browser send "hi"`. If the request reaches OpenAI, wait for and inspect the provider error; the exact error text/status can vary. Do not treat this as an offline proof or require a particular status.
- **Chat stream (key).** Run `$S browser open /`, then `$S browser send "Reply with the word pineapple." --expect "pineapple" --timeout 60000`. `$S browser state` shows `assistantRows:1` and `composerEditable:true`. `events.jsonl` shows a `200` from `api.openai.com`.
- **Completion (key).** Run `$S browser tab Completion`, `$S browser type --name Prompt --text "Write a haiku about Flutter."`, `$S browser click --name Generate`, then `$S browser snapshot --name completion-result` after the text appears under `Response`. `type` replaces the current field value.
- **Quick prompt.** Run `$S browser click --role checkbox --name "Write a haiku about Flutter."`. The prompt runs, and the response area fills.
- **Object (key).** Run `$S browser tab Object`, `$S browser type --name Country --text Japan`, `$S browser click --name Generate`, then `$S browser wait-text "Capital" --timeout 60000` and `$S browser snapshot --name object-japan`. `type` replaces the current field value. The `Capital` row appears only after the streamed object has that field. The PNG shows the filled `Country Profile` rows (Country, Capital, Population, Currency).

## Gotchas

- `--dart-define` compiles the key into `main.dart.js` in the run's scratch directory. `$S down` deletes it. Never copy the `web/` directory into the evidence directory.
- A keyless send may make a request to `api.openai.com` if networking is available. Do not describe it as offline or assume a particular response.
- Live output is not deterministic. Assert on structure (one assistant row, filled fields, a `200` response) or on a word you asked the model to return. Do not assert on exact prose.
- Chip labels longer than 36 characters are cut and end with `…` (for example `Explain async/await in Dart in 3 sen…`). Use that exact name, or a shorter name with `--substring`. A chip puts its full prompt in the `Prompt` field and starts the stream at once.
- A chip or prompt cannot be sent while a stream is active. Wait for the stream to finish first.
