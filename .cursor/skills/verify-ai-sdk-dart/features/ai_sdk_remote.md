# ai_sdk_remote

Optional Dart transport for a trusted backend that streams the Vercel AI SDK 7.0.111 UI-message protocol. `RemoteConversationTransport.send(conversation)` POSTs the history as UIMessages, reads the `v1` SSE reply, and yields immutable `ai_sdk_conversation` snapshots as the reply grows. The backend holds the provider keys and runs the tools. The package runs no tool and does not retry or resume a stream.

## Sub-features

- `remote-interop` shows that the pinned JS reference backend (real `ai` 7.0.111 output) sends `text/event-stream`, the `x-vercel-ai-ui-message-stream: v1` header, ordered events and a final `[DONE]`.
- `remote-text` sends a user message to that backend and yields snapshots that end with one completed assistant message.
- `remote-approval` reads a tool call and approval request from the backend, then continues the same assistant message after an approve or a deny.
- `remote-request` POSTs `{messages: [...]}` with `accept`, `content-type`, the stream version header, static `headers` and a fresh `authHeaders` result for each send, and maps text, reasoning, files, sources and tool states to UIMessage parts.
- `remote-reduce` turns text, reasoning, tool input and output, tool errors, sources, files, metadata, `reset-step`, unknown `data-*` events, `error` and `abort` events into snapshot parts and message status.
- `remote-errors` raises `RemoteProtocolException` for HTTP 4xx and 5xx, bad headers, malformed frames, a missing terminal event or `[DONE]`, and a delta without a start. A closed port raises a client or socket error.
- `remote-cancel` stops the HTTP request on `StreamSubscription.cancel`, `RemoteCancellationToken.cancel` and `dispose()`, and sends nothing for a token that is already cancelled.
- `remote-lifecycle` leaves an injected `http.Client` open on `dispose()`.

## How to get to it (user POV)

- Build `RemoteConversationTransport(endpoint: Uri.parse(...), authHeaders: () => {...})`. Call `send(conversation, cancellation: token)` and listen to the snapshots.
- Run your own backend with `createUIMessageStreamResponse`. This repo ships one in `examples/remote_backend/js`. The Flutter chat example reaches it from its Remote tab.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- Node is installed and `$V setup` has run `npm ci` in `examples/remote_backend/js`. The `js-` checks start that server on a free loopback port with `ctx.spawn`. No key is necessary.

- **All checks.** Run `$V run remote`. Output `14 passed, 0 failed, 0 skipped`.
- **Real backend wire.** Run `$V run remote --check js-backend-wire-format`. In `ai_sdk_remote/js-backend-wire-format.json`, `observed.headers['x-vercel-ai-ui-message-stream']` is `v1` and `observed.body` holds the SSE text ending in `data: [DONE]`.
- **Text turn.** Run `$V run remote --check js-text-turn`. `observed.snapshotCount` is at least `3`. The check requires the assistant text `Hello from the pinned AI SDK backend.`
- **Approval request.** Run `$V run remote --check js-approval-request`. `observed.status` is `pendingApproval` and `observed.parts` has a `delete` tool call and a `pending` approval.
- **Approve.** Run `$V run remote --check js-approval-approved-continuation`. `observed.parts` ends with a `tool_result` of `{ok: true, path: /tmp/reference}` and the text `The scripted tool call was approved and resumed.`
- **Deny.** Run `$V run remote --check js-approval-denied-continuation`. The result part has `outputKind` `execution_denied` and the text says `denied and resumed safely`.
- **Real 400.** Run `$V run remote --check js-rejects-malformed-request`. `observed.rawStatus` is `400` and `observed.rawBody` starts with `invalid UI messages`.
- **Headers and auth.** Run `$V run remote --check request-headers-and-auth`. `exchanges` has two POSTs. Their `authorization` headers are redacted, and the check asserts `Bearer token-1` then `Bearer token-2`. The `x-app` header is `verify`.
- **Body mapping.** Run `$V run remote --check request-body-mapping`. `exchanges[0].requestBody.messages[1].parts` has `state` values `approval-responded` and `output-available`.
- **Reduction.** Run `$V run remote --check stream-reduction`. `observed.parts` has one reasoning, one text, a source, a source document, a file, two tool calls with their results, and the unknown `data-weather` and `future-event` parts. The `data-progress` event is absent.
- **Error and abort.** Run `$V run remote --check error-and-abort-streams`. `observed.failedMetadata.error` is `Model overloaded`.
- **Protocol violations.** Run `$V run remote --check protocol-violations`. `observed` has one `.error` line for each of the eight paths.
- **Unreachable.** Run `$V run remote --check unreachable-endpoint`. `observed.errorType` is a client or socket error type, not `RemoteProtocolException`.
- **Cancellation.** Run `$V run remote --check cancellation`. The check passes only when the server socket closes after each of the cancel, token and dispose cases.
- **Injected client.** Run `$V run remote --check injected-client-ownership`. The injected client sent one request and was not closed.

## Gotchas

- The JS backend runs as a subprocess and does not log requests, so the `js-` checks have no `exchanges`. The request side is proven by the fixture-server checks `request-headers-and-auth` and `request-body-mapping`.
- The JS backend replays static events. It shows that the transport reads real Vercel AI SDK 7.0.111 framing. It does not call a model.
- The server must send `text/event-stream`, `x-vercel-ai-ui-message-stream: v1`, a `finish` or `abort` event and `data: [DONE]`. Anything else is a `RemoteProtocolException`.
- A continuation needs the assistant message from the previous snapshot with the `ApprovalPart` set to approved or rejected. The backend then reuses the same message id.
- A closed port gives an `http.ClientException`, not a `RemoteProtocolException`.
- Not covered: browser builds, and cancelling a response while waiting for its next chunk on the web. The driver runs on the Dart VM only.
- Not covered: stream resumption and retry. The package does not offer them.
