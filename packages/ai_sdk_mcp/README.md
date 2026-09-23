# ai_sdk_mcp

[Model Context Protocol (MCP)](https://modelcontextprotocol.io) client for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Connects to MCP servers over Streamable HTTP or stdio and exposes their tools as a typed `ToolSet`. The client has explicit legacy (`2025-06-18`) and modern (`2026-07-28`) protocol strategies.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^2.0.0
  ai_sdk_mcp: ^2.0.0
```

## Usage

### Streamable HTTP transport (remote server)

`StreamableHttpClientTransport` speaks the MCP Streamable HTTP transport
(protocol `2025-06-18`) against a single MCP endpoint such as
`https://example.com/mcp`. It:

- sends every JSON-RPC request as an HTTP `POST`
- accepts either `application/json` or `text/event-stream` responses
- sends `notifications/initialized` after protocol negotiation succeeds
- starts the optional `GET` SSE listener after initialization to surface
  server-pushed notifications
- reuses `Mcp-Session-Id` and `MCP-Protocol-Version` on later `POST` / `GET` /
  `DELETE` requests when the server negotiates a session
- reconnects the optional `GET` listener with `Last-Event-ID` after an
  unexpected disconnect
- sends a best-effort `notifications/cancelled` notification when a request
  times out

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final transport = StreamableHttpClientTransport(
  url: Uri.parse('https://mcp.example.com/mcp'),
  headers: {
    'Authorization': 'Bearer <short-lived-token>',
    'X-Tenant-Id': 'acme',
  },
  requestTimeout: const Duration(seconds: 20),
);

final client = MCPClient(transport: transport);
await client.initialize();

// Discover tools and use them in a generateText call
final tools = await client.tools();

final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'Search for "Dart programming"',
  tools: tools,
  maxSteps: 3,
);
print(result.text);

await client.close();
```

For a modern stateless server, select the modern strategy. It probes
`server/discover`, adds per-request protocol metadata, sends the required
Streamable HTTP routing headers, and does not use MCP sessions or GET/DELETE
lifecycle requests:

```dart
final client = MCPClient(
  transport: transport,
  protocolMode: MCPProtocolMode.modern,
);
await client.initialize();
```

Progress is opt-in per request. The host supplies a unique string or integer
token and listens to validated monotonic updates:

```dart
final updates = client.progress.listen((update) {
  print('${update.progress}/${update.total ?? '?'} ${update.message ?? ''}');
});
await client.callTool('long_task', {}, progressToken: 'task-1');
await updates.cancel();
```

HTTP authorization is host-owned. Pass `MCPAuthConfiguration` with token and
refresh callbacks; the transport sends bearer credentials on every request
and retries a rejected 401 once after a refresh. It does not store tokens or
open browser login flows. Use `validateAuthorizationIssuer` for RFC 9207
issuer binding and `validateRedirectUri` before handing a callback URI to a
host browser integration.

`headers` are copied onto the transport's `POST`, optional `GET`, and `DELETE`
requests. This is the place to put required credential or routing headers.
Do not ship long-lived secrets inside browser or mobile client builds. Prefer
short-lived tokens minted by your backend or a trusted proxy.

### Transport behavior notes

- `initialize()` negotiates MCP protocol version `2025-06-18`. Legacy
  HTTP+SSE servers that only speak older protocol versions are not supported
  by this transport.
- `protocolMode: MCPProtocolMode.modern` selects MCP `2026-07-28`; modern
  calls carry `_meta` protocol metadata and `tools/call` can return a typed
  `MCPInputRequiredResult` for a multi-round-trip request. Its
  `requestState` is an opaque server string: pass it back unchanged with the
  matching `inputResponses` in a subsequent `callTool` invocation. Modern
  result envelopes are validated before they reach the caller.
- Modern progress notifications are exposed through `client.progress`. They
  report progress only; MCP does not define arbitrary partial tool-output
  chunks, so this package does not synthesize such a stream.
- The official `io.modelcontextprotocol/tasks` extension is not implemented.
  Long-running work must use the host's own task/polling adapter until a
  versioned Tasks API is added. `ttlMs`/`cacheScope` cache hints are also not
  interpreted or used for client-side caching.
- If the server returns `Mcp-Session-Id` during initialize, the transport
  includes it on later requests and sends `DELETE` on `close()` to end the
  session. A server may reject `DELETE` with `405 Method Not Allowed`; that is
  treated as an allowed shutdown path.
- Server-pushed notifications are available on `transport.notifications`, and
  `notifications/resources/updated` are wired into `MCPClient`
  resource-subscription listeners automatically.

### Stdio transport (local process)

> Desktop/CLI only. `StdioMCPTransport` spawns an OS process and is not
> available on Flutter web — referencing it still compiles for web (via a
> stub), but constructing and using it on web throws `UnsupportedError`.

```dart
final transport = StdioMCPTransport(
  command: 'npx',
  args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
);

final client = MCPClient(transport: transport);
await client.initialize();

final tools = await client.tools();
// Use tools with any generateText / streamText call...

await client.close();
```

### Injecting your own `http.Client`

```dart
import 'package:http/http.dart' as http;

final sharedClient = http.Client();

final transport = StreamableHttpClientTransport(
  url: Uri.parse('https://mcp.example.com/mcp'),
  client: sharedClient,
);

final client = MCPClient(transport: transport);
await client.initialize();
await client.close();

// The injected client is still yours to manage.
sharedClient.close();
```

### Direct tool invocation

```dart
final result = await client.callTool('readFile', {'path': '/tmp/hello.txt'});
print(result); // file contents as string
```

## Error handling

```dart
try {
  await client.callTool('dangerousOp', {});
} on MCPException catch (e) {
  print('MCP server error: ${e.message}');
}
```

## License

MIT
