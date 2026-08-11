## 2.0.0

- Hardened Streamable HTTP reconnection, session cleanup, cancellation
  notifications, response trust boundaries, and concurrent shutdown.
- Removed stdio lifecycle races and prevented cleanup from suppressing
  unexpected MCP client errors.
- Stdio JSON frames are capped at 1 MiB and terminate safely on overflow.

---

## 1.2.0

### Breaking

- Removed the legacy HTTP transport exports `SseClientTransport` and
  `HttpClientTransport`. Use `StreamableHttpClientTransport` for remote MCP
  servers.
- The HTTP client now negotiates and enforces MCP protocol `2025-06-18`.
  Deprecated HTTP+SSE servers that only speak `2024-11-05` are no longer a
  supported target.

### Transport behavior

- `StreamableHttpClientTransport` speaks the Streamable HTTP transport against
  a single MCP endpoint.
- Each client message is sent as an HTTP `POST`, and the server may answer with
  either JSON or SSE for that request.
- After initialize succeeds, the client sends
  `notifications/initialized`, reuses `MCP-Protocol-Version` on later HTTP
  requests, and starts the optional `GET` SSE listener for server-pushed
  notifications.
- If the server returns `Mcp-Session-Id`, the transport reuses it on later
  `POST` / `GET` / `DELETE` requests, reconnects the optional listener with
  `Last-Event-ID` after disconnects, and sends `DELETE` on `close()`.
- Request timeouts send a best-effort `notifications/cancelled` notification
  before the call fails locally.
- Custom headers and an injected `http.Client` are supported. Injected clients
  remain caller-owned; the transport closes only the client it creates.

### Web / native

- **Flutter-web compatible.** The package no longer imports `dart:io` at the
  top level. `StdioMCPTransport` (which spawns a process) now lives behind a
  conditional import: the real `dart:io` implementation is used on native
  platforms, and a stub that throws `UnsupportedError` is used on web.
- `MCPTransport` exposes a `notifications` stream for server-initiated
  messages. `notifications/resources/updated` continue to drive
  `subscribeResource()` listeners automatically.

### Migration

Replace remote transport construction like this:

```dart
final transport = StreamableHttpClientTransport(
  url: Uri.parse('https://mcp.example.com/mcp'),
  headers: {'Authorization': 'Bearer <token>'},
);
```

Notes:

- Point the transport at the MCP endpoint itself, not a legacy `/sse` endpoint.
- Keep required credential headers in `headers`, but avoid embedding
  long-lived secrets inside distributed browser or mobile clients.
- If you need a shared `http.Client`, inject it and close it yourself after the
  MCP client shuts down.

---

## 1.1.0

- Bumped `ai_sdk_dart` constraint to `^1.1.0`.
- No MCP client behaviour changes; version aligned with the rest of the monorepo.

---

## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Depends on `ai_sdk_dart` 1.0.0.

- `MCPClient` — manages a session with any MCP server via pluggable transport.
- `SseClientTransport` — HTTP SSE transport for remote MCP servers; supports custom headers and separate POST URL.
- `StdioMCPTransport` — stdio transport that spawns a local process and communicates via stdin/stdout.
- `initialize()` — MCP protocol 2024-11-05 handshake with idempotency guard.
- `tools()` — discovers available tools and returns a `ToolSet` compatible with `generateText` / `streamText`.
- `callTool()` — invokes a named tool with structured arguments; throws `MCPException` on server-side errors.
- `MCPException` — typed exception with `message` field.

---

## 0.2.0

- Initial release.
- `MCPClient` — manages a connection to an MCP server via any transport.
- `SseClientTransport` — HTTP SSE transport for remote MCP servers.
- `StdioMCPTransport` — stdio transport for local MCP server processes.
- `tools()` — discovers available tools and returns a typed `ToolSet`.
- `callTool()` — invokes a named tool with structured arguments.
- MCP protocol 2024-11-05 initialize handshake.
- `MCPException` for server-side errors.
