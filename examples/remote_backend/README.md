# Remote conversation backend

This directory documents the smallest trusted-backend shape for
`ai_sdk_remote`. The backend owns provider credentials and tools. It accepts a
conversation request and returns a Vercel AI SDK 7.0.111 UI-message stream with
`Content-Type: text/event-stream` and
`x-vercel-ai-ui-message-stream: v1`.

A production backend should use the pinned JavaScript SDK's
`createUIMessageStreamResponse`/`toUIMessageStream` helpers or reproduce the
pinned SSE framing exactly. The Dart client does not retry, replay, or resume a
stream after a disconnect, and it does not contain provider keys.

The `js/` directory pins `ai` to `7.0.111` and uses
`createUIMessageStreamResponse`. Run `npm install` and `node server.mjs` there
for a local reference endpoint. It uses static events so no provider key is
needed; when the request contains the scripted `delete` tool approval it emits
the approval request first, then resumes with deterministic approved or denied
tool output and final text. Replace the writer with an authorized
`streamText`/agent flow in a real backend.
