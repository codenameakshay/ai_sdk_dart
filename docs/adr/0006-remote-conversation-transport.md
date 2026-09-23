# ADR 0006: Remote UI-message stream transport

Status: proposed implementation target

## Decision

Add `ai_sdk_remote` as an optional companion for trusted backends that expose the
Vercel AI SDK 7.0.111 UI-message stream protocol. The package consumes a POST
response carrying SSE frames and reduces those frames into immutable
`ai_sdk_conversation` snapshots. It does not execute tools, persist data, or
provide resumption semantics.

The supported response protocol is pinned to `x-vercel-ai-ui-message-stream:
v1`. Frames use the `type` values from the pinned upstream
`ui-message-chunks.ts`: start/text/reasoning boundaries, tool input/output and
approval states, source/file parts, metadata, errors, finish and abort. Unknown
frames are retained as `UnknownPart` values. `[DONE]` is required; a response
ending without it is a truncation error. SSE supports CRLF, multiline `data:`
fields, comments, and arbitrary UTF-8 chunk boundaries.

## Security and lifetime

Authorization is supplied by an application callback for each request. Provider
keys and privileged tool execution stay on the backend. Cancellation stops
consumption and disposal closes the owned HTTP client. The transport never
retries, replays, or claims resume after disconnect; those behaviors require an
explicit server contract and stable call ledger.

## References

- Vercel AI SDK `7.0.111`, commit `e9c1d2f54da6bd01a16bb8a5fdfcb4b62f34e7d0`.
- `packages/ai/src/ui-message-stream/ui-message-chunks.ts`
- `content/docs/04-ai-sdk-ui/50-stream-protocol.mdx`
