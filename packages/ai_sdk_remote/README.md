# ai_sdk_remote

Optional Dart transport for trusted backends that emit the Vercel AI SDK
7.0.111 UI-message stream protocol. It converts conversation history to the
validated UIMessage request shape, consumes version `v1` SSE responses, and
reduces text, reasoning, tool, approval, source, file, metadata, error, and
unknown events into immutable `ai_sdk_conversation` snapshots.

```dart
final transport = RemoteConversationTransport(
  endpoint: Uri.parse('https://example.test/api/chat'),
  authHeaders: () => {'Authorization': 'Bearer $sessionToken'},
);
final snapshots = transport.send(conversation);
```

The package does not execute tools, contain provider keys, retry, replay, or
claim stream resumption. A response must use `text/event-stream`, the
`x-vercel-ai-ui-message-stream: v1` header, include `finish` or `abort`, and
terminate with `data: [DONE]`. Cancellation uses `http.AbortableRequest` and
disposal aborts active requests. Applications own persistence and server-side
authorization; injected HTTP clients remain owned by the caller.

The transport requires `http` 1.6 or newer for abortable requests and the
browser fix for cancelling a response while waiting for its next chunk.

Run the included Dart example against the repository's pinned reference server:

```sh
dart run example/example.dart http://127.0.0.1:8081/chat
```

The reference server lives in `examples/remote_backend/js` at the repository
root. Run `npm ci` and `node server.mjs` there first. It uses static events and
requires no provider key. The Dart example sends a typed conversation, prints
updated assistant text, and disposes its owned transport when the stream ends.
