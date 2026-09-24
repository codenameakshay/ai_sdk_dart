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

## Current deterministic qualification

The parent reran the complete realtime suite with pinned Dart 3.12.2:
21 tests passed (`/tmp/v3-parent-realtime-contract-current.log`). The current
implementation includes typed server/semantic VAD, function tools, transcript
completion/failure, and response/token usage. Tests cover typed serialization,
transcript/usage parsing, startup identity matching, loopback WebSocket
handshake, paused event queues, and cancellation cleanup.

Tool-call and cancelled-response identities now have configurable session
limits (`maxRememberedToolCalls` and `maxRememberedCancelledResponses`, both
8192 by default). The implementation refuses unsafe eviction and reports the
limit instead of forgetting identities and permitting duplicate execution.
This bounds retained identities but requires the application to recover or
start a new session when its limit is reached.

README, changelog, license and a preview example now exist. The package remains
`publish_to: none` at version `3.0.0-dev.1`. Stable workspace packages use
`3.0.0`; the realtime preview is excluded from the stable publication set.

## Remaining W18 work

- Validate the typed protocol against current official fixtures and a live
  provider, including actual audio and tool exchanges. Deterministic fixtures
  alone do not establish service acceptance.
- The default authenticated WebSocket connector uses `dart:io`. Browser callers
  must supply an appropriate connector/ephemeral-credential flow; a conditional
  stub is not a verified browser session implementation.
- Microphone permission, capture/playback, audio-route interruptions, and
  physical or simulator device behavior have not been verified. Deterministic
  transport/queue tests do not satisfy the approved device-audio requirement.
- Complete the full release coverage gate; the passing functional suite is
  not a coverage measurement.

Keep the separate preview scope. W18 remains incomplete until its required
live and device evidence exists.
