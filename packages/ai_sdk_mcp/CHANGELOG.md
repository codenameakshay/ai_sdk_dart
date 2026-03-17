## 0.2.0

- Initial release.
- `MCPClient` — manages a connection to an MCP server via any transport.
- `SseClientTransport` — HTTP SSE transport for remote MCP servers.
- `StdioMCPTransport` — stdio transport for local MCP server processes.
- `tools()` — discovers available tools and returns a typed `ToolSet`.
- `callTool()` — invokes a named tool with structured arguments.
- MCP protocol 2024-11-05 initialize handshake.
- `MCPException` for server-side errors.
