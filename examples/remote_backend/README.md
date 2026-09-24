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

The Dart fixture validates that the request is a JSON object with a non-empty
`messages` array. Each message must have a string `role` and an array `parts`.
Malformed requests receive a JSON `400` response with an `error` field. The
fixture binds to loopback and accepts `PORT` or `--port=<port>`; use port `0`
from a test to request an ephemeral port:

```sh
PORT=8080 dart run bin/server.dart
dart run bin/server.dart --port=8080
```

It sends a scripted text response and does not call a model provider or execute
tools. The wildcard CORS headers, including exposure of the
`x-vercel-ai-ui-message-stream` response header, are suitable for local browser
development only. A deployed backend must restrict the allowed origin and
authenticate the request before forwarding it to a provider.

The `js/` directory pins `ai` to `7.0.111` and uses
`createUIMessageStreamResponse`. Run `npm install` and `node server.mjs` there
for a local reference endpoint. It uses static events so no provider key is
needed; when the request contains the scripted `delete` tool approval it emits
the approval request first, then resumes with deterministic approved or denied
tool output and final text. Replace the writer with an authorized
`streamText`/agent flow in a real backend.

The Dart smoke tests start the Dart fixture on an ephemeral loopback port and
exercise it through `RemoteConversationTransport`. They qualify the transport
and SSE framing, request validation, lifecycle, and local CORS preflight only;
they do not qualify hosted authentication or a real provider connection.
