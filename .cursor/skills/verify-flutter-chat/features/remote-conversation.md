# Remote conversation

The Remote screen sends the conversation to a trusted backend over `ai_sdk_remote` and renders the Vercel AI SDK UI-message stream that comes back. Against the pinned JS reference backend, ordinary text gets a scripted answer. A message that contains `approval` asks the user to approve the `delete` tool for `/tmp/reference`, and the backend then resumes the turn with the decision. If the backend is unreachable, the user sees a banner with the endpoint and the startup command.

## Sub-features

- `remote-text` streams `Hello from the pinned AI SDK backend.` for ordinary text.
- `remote-approval` shows an approval card for `delete` when the message contains `approval`.
- `remote-approve` resumes with `The scripted tool call was approved and resumed.`
- `remote-deny` resumes with `The scripted tool call was denied and resumed safely.`
- `remote-unreachable` shows `Can't reach <url>` with the `node server.mjs` hint, a `Dismiss` action and no `Retry`.
- `remote-dismiss` removes the banner and keeps the composer editable.

## How to get to it (user POV)

- Choose the `Remote` tab in the bottom navigation.
- Open the `/remote` named route (`#/remote` on web).

## Driving it with vfc

Preconditions:

- `$S doctor` shows `backend pid ... owns :<port>` and the CORS preflight check is `OK`.
- The build targets this run's backend (`doctor`: `build targets backend http://127.0.0.1:<port>/chat`).

- **Canned text proof.** Run `$S scenario remote-text`. Output `PASS remote-text`. In `remote-text.json`, `network` has one `POST .../chat` with status `200`, `uiMessageStream` `v1`, and a `body` that contains `Hello from the pinned AI SDK backend.` This scenario opens `/remote` (named route), not the Remote shell tab.
- **Canned approve.** Run `$S scenario remote-approve`. Output `PASS remote-approve`. `network` has two `POST /chat` calls. The second request's `postData` contains `"approved":true`.
- **Canned deny.** Run `$S scenario remote-deny`. It uses 390×844. Output `PASS remote-deny`. The second request carries `"approved":false`.
- **Tab entry.** Run `$S browser open /` and `$S browser tab Remote`, then `$S browser send "Hello" --expect "Hello from the pinned AI SDK backend."`. The command prints a state with `assistantRows:1`. `events.jsonl` has the `POST` for that `send` command. This proves the shell tab, separately from canned named-route scenarios.
- **Unreachable backend.** Run `$S backend stop`, then `$S scenario remote-unreachable`. Output `PASS remote-unreachable`. `remote-unreachable-error.png` shows the red banner with the URL and `cd examples/remote_backend/js && npm ci && node server.mjs`.
- **Restore.** Run `$S backend start`. Output `backend ready on :<port>`. `$S doctor` passes again.

## Gotchas

- The approval trigger is the word `approval` anywhere in the user text, with any letter case. `Request approval` works and `Approve this` does not.
- The remote conversation has no retry. The banner must show only `Dismiss`. If `Retry` appears, that is a defect.
- Each run's build has the run's backend port compiled in. A backend on `8081`, or one from another run, is not the backend this app calls.
- The browser needs the backend to allow and expose `x-vercel-ai-ui-message-stream` in its CORS headers. Without that header, the CORS preflight fails in the browser (this happened before, see `plans/v3-research/evidence/browser/README.md`). `doctor` checks the header.
- Remote tool execution is scripted in the backend. This feature proves transport, stream framing and approval continuation, not a real provider or a real tool.
