# ai_sdk_realtime

Experimental typed session adapter for the OpenAI Realtime WebSocket API (GA wire shapes). `RealtimeSession.connect` opens the socket, waits for `session.created`, sends `session.update`, and returns a session. The app sends text, audio, tool results and cancellations. It reads typed server events from `session.events`. The package does not capture or play audio.

## Sub-features

- `rt-session` connects with a `Bearer` header on the model URL, sends the default `session.update`, and is `ready` only after `session.updated`.
- `rt-config` serializes model, instructions, modalities, voice, audio formats, server and semantic turn detection and function tools, and rejects invalid config before any frame is sent.
- `rt-send` sends `sendText`, `sendAudio`, `commitAudio`, `createResponse`, `cancelResponse`, `clearAudio`, `submitToolResult` and `interrupt` as the documented client events.
- `rt-events` turns server events into typed classes (text, audio, transcripts with usage, speech boundaries, `response.done` with token usage) and keeps unknown types as `RealtimeUnknownEvent`. Events sent while nobody listens are dropped. A paused listener has a bounded queue.
- `rt-tools` surfaces each function call once and sends tool output back with `submitToolResult` and `createResponse`.
- `rt-errors` delivers a server `error` event, a malformed frame, an oversize frame and a malformed tool call without closing the session, and fails `connect` on a startup error, a timeout, a closed port or a cancelled signal.
- `rt-audio` drops audio beyond `maxBufferedAudioBytes` until the app calls `acknowledgeAudio`.
- `rt-cancel` drops late events of a response after `cancelResponse(responseId:)` and keeps its `response.done`.
- `rt-close` ends the stream and the socket on `close()`, on a server close and on a cancelled `abortSignal`, and makes later sends fail.
- `rt-transport` runs the session over a host-supplied `RealtimeTransportConnector`, which is the browser path.

## How to get to it (user POV)

- Call `RealtimeSession.connect(apiKey: ..., config: RealtimeSessionConfig(...))`. Listen to `session.events`, then call `sendText` and `createResponse`.
- Pass `endpoint:` to point at another server, and `connector:` to bring your own socket.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Session checks use an in-process `dart:io` WebSocket server on loopback. `custom-transport` uses an in-memory host transport instead.

- **All checks.** Run `$V run realtime`. Output `13 passed, 0 failed, 0 skipped`.
- **Handshake.** Run `$V run realtime --check connect-handshake`. In `ai_sdk_realtime/connect-handshake.json`, `observed.upgrades[0].path` is `/v1/realtime`, and `observed.clientFrames` is one `session.update` with `session.model` `gpt-realtime-2.1`. `observed.upgrades[0].authorization` is `Bearer rt-test-key`.
- **Config.** Run `$V run realtime --check session-config-wire`. `observed.clientFrames[0].session` has `tools`, `output_modalities` `[audio]` and `audio.input.turn_detection.type` `server_vad`.
- **Client events.** Run `$V run realtime --check client-events-wire`. `observed.clientFrames` lists 14 frames. The tool result `{"temp":18}` is sent as the string `{"temp":18}`.
- **Server events.** Run `$V run realtime --check server-events-typed`. `observed.eventTypes` lists 13 events, with `rate_limits.updated` kept as an unknown event.
- **Event buffer.** Run `$V run realtime --check event-buffer-bounds`. `observed.errors` has one `RealtimeEventBufferOverflowException`, and `observed.seen` is `[heard]`.
- **Tool calls.** Run `$V run realtime --check tool-call-round-trip`. `observed.toolCalls` has two calls, `call_weather_1` once and `call_weather_2`. `observed.clientFrames` ends with `conversation.item.create` and `response.create`.
- **Provider errors.** Run `$V run realtime --check provider-error-events`. `observed.errorMessage` is `Invalid value: bogus.` and `observed.streamErrors` has three lines.
- **Startup failures.** Run `$V run realtime --check startup-failures`. The check passes only if each failure raised its own typed error. `observed.unreachableErrorType` names the error for the closed port.
- **Audio.** Run `$V run realtime --check audio-backpressure`. `observed.errors` has one `audio buffer limit exceeded`.
- **Cancelled response.** Run `$V run realtime --check cancelled-response-filtered`. Only the `fresh` delta and the cancelled `response.done` arrive.
- **Close.** Run `$V run realtime --check close-lifecycle`. The check passes only if both the client close and the server close end the stream.
- **Abort signal.** Run `$V run realtime --check abort-signal-closes-session`. The session state becomes `closed` after `token.cancel()`.
- **Custom transport.** Run `$V run realtime --check custom-transport`. `observed.connectorUri` is `wss://realtime.example.test/v1/realtime` and `observed.sent` has the two frames sent through the host transport.

## Gotchas

- No live realtime check exists. The local WebSocket server and in-memory transport prove the adapter against the documented GA shapes, not against OpenAI. The package README also says live service behavior and audio devices need separate qualification.
- `session.created` is read during `connect`, before a listener can attach, so `session.events` does not repeat it. Events sent when nobody listens are dropped.
- The package is a preview. Its CHANGELOG says it is not published until transport, device and lifecycle qualification is done.
- `acknowledgeAudio(audio.length)` is required after each `RealtimeAudioDelta`. Without it the 4 MiB budget fills and further deltas are dropped.
- Not covered: microphone capture, audio playback and routing. The package leaves them to the host.
- Not covered: `RealtimeClock` injection, `maxRememberedToolCalls` and `maxRememberedCancelledResponses` limits. They exist for tests and for very long sessions.
