# Realtime qualification checkpoint

This is an implementation review, not live or device qualification.

## Specific response cancellation

The official OpenAI Node request type at revision
[`645c5ad06d097712958b51016165b5277c931a84`](https://github.com/openai/openai-node/blob/645c5ad06d097712958b51016165b5277c931a84/src/resources/realtime/realtime.ts#L4514)
declares optional `response_id`: when omitted, cancellation targets the active
response in the default conversation. Retrieved 2026-09-23.

The Dart session accepted a response ID and used it to suppress subsequent
events locally, but omitted it from the outgoing command. The parent test
`cancel and interrupt target the requested response ID` reproduced the missing
key. The request now forwards the ID; omitting it still emits the default form.
The test also checks interruption orders cancellation before truncation with
the supplied item ID, content index, and played audio duration.

The same pinned official SDK's
[`src/realtime/ws.ts`](https://github.com/openai/openai-node/blob/645c5ad06d097712958b51016165b5277c931a84/src/realtime/ws.ts#L70)
uses bearer authentication without the old `OpenAI-Beta: realtime=v1` header.
The Dart connector now follows that current handshake for its GA session
configuration. Its actual loopback WebSocket test first observed the old
header, then passed after removal. This establishes the emitted request shape,
not acceptance by a live OpenAI endpoint.

## Remaining W18 work

- Session configuration exposes raw maps for turn detection/tools; response
  usage is a raw map. These need the planned typed protocol qualification and
  current official fixtures, including transcript completion and tool results.
- Session-wide tool-call and cancelled-response ID sets currently grow without
  a configured bound. Queue byte/count limits do not cover those sets. Define
  their lifetime/budget without silently permitting duplicate tool execution.
- The default authenticated WebSocket connector uses `dart:io`. Browser callers
  must supply an appropriate connector/ephemeral-credential flow; a conditional
  stub is not a verified browser session implementation.
- The package is still `publish_to: none`, version 2.0.0, and lacks a README,
  changelog, and license copy. Preview packaging/version decisions remain.
- Microphone permission, capture/playback, audio-route interruptions, and
  physical or simulator device behavior have not been verified. Deterministic
  transport/queue tests do not satisfy the approved device-audio requirement.

Keep the separate preview scope and the session lifetime/queue tests already
implemented. Do not mark W18 complete from this targeted cancellation fix.
