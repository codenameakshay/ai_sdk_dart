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