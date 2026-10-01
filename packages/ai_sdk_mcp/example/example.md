# ai_sdk_mcp examples

MCP (Model Context Protocol) client for AI SDK Dart — connect to any MCP server
and expose its tools directly to `generateText` / `streamText`.

## Installation

```sh
dart pub add ai_sdk_dart ai_sdk_openai ai_sdk_mcp
```

---

## Streamable HTTP transport — connect to an MCP endpoint

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

void main() async {
  final transport = StreamableHttpClientTransport(
    url: Uri.parse('https://mcp.example.com/mcp'),
    headers: {
      'Authorization': 'Bearer <short-lived-token>',
      'X-Workspace': 'demo',
    },
    requestTimeout: const Duration(seconds: 20),
  );
  final client = MCPClient(transport: transport);

  await client.initialize();

  // Discover tools from the MCP server and pass them to generateText.
  final tools = await client.tools();

  final result = await generateText(
    model: openai('gpt-4.1-mini'),
    prompt: 'What is the weather in Tokyo right now?',
    tools: tools,
    maxSteps: 5,
  );
  print(result.text);

  await client.close();
}
```

Notes:

- `initialize()` negotiates protocol `2025-06-18`, then the client sends
  `notifications/initialized`.
- Each request is an HTTP `POST`; the server may answer with JSON or an SSE
  stream for that request.
- After initialization, the transport starts the optional `GET` SSE listener
  so server-pushed notifications can arrive out-of-band. If the stream drops,
  it reconnects with `Last-Event-ID`.
- If the server returns `Mcp-Session-Id`, the transport reuses it on later
  `POST` / `GET` / `DELETE` requests and sends `DELETE` during `close()`.
- `headers` are where required credential headers belong. Do not embed
  long-lived secrets directly in distributed browser or mobile apps.

---

## Stdio transport — connect to a local process

```dart
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';

final transport = StdioMCPTransport(
  command: 'node',
  args: ['path/to/mcp-server.js'],
);
final client = MCPClient(transport: transport);

await client.initialize();
final tools = await client.tools();
print('Available tools: ${tools.keys.toList()}');
await client.close();
```

---

## Inspect available tools

```dart
final tools = await client.tools();

for (final entry in tools.entries) {
  print('Tool: ${entry.key}');
  // entry.value is a Tool<Map<String, dynamic>, dynamic>
}
```

---

## Direct tool invocation

```dart
final result = await client.callTool('getWeather', {'city': 'London'});
print(result); // e.g. "Cloudy, 14°C in London"
```

---

## Error handling

`MCPClient` throws `MCPException` when the MCP server returns an error response
(`isError: true`).

```dart
try {
  await client.callTool('unknownTool', {});
} on MCPException catch (e) {
  print('MCP error: ${e.message}');
}
```

---

## Custom headers (auth)

```dart
final transport = StreamableHttpClientTransport(
  url: Uri.parse('https://my-mcp-server.example.com/mcp'),
  headers: {
    'Authorization': 'Bearer my-secret-token',
    'X-Tenant-Id': 'acme',
  },
);
```

For server-side apps or CLIs, static credentials may be acceptable. For
browser or mobile apps, prefer backend-minted short-lived tokens or an auth
proxy so secrets are not recoverable from the shipped client.

---

## Inject an existing HTTP client

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

// StreamableHttpClientTransport only closes the client it creates itself.
sharedClient.close();
```

---

## Modern protocol mode

```dart
final client = MCPClient(transport: transport, protocolMode: MCPProtocolMode.modern);
```

`MCPProtocolMode` defaults to `MCPProtocolMode.legacy`. Modern mode is a
different strategy, not a version bump on the legacy handshake: it discovers
server capabilities via `server/discover`, attaches metadata per request, and
subscribes to resources over POST instead of the legacy `initialize` +
SSE-listener flow. Pick `modern` only against a server that supports it.

---

## Auth discovery and configuration

On a 401, discover the resource server's metadata, then give the transport a
callback that returns a live token:

```dart
final metadata = await MCPAuthDiscovery.discoverProtectedResource(
  Uri.parse('https://mcp.example.com/mcp'),
  wwwAuthenticate: response.headers['www-authenticate'],
);

final transport = StreamableHttpClientTransport(
  url: Uri.parse('https://mcp.example.com/mcp'),
  auth: MCPAuthConfiguration(
    resource: metadata.resource,
    accessToken: () async => hostMintedAccessToken(),
    retryAfterUnauthorized: false,
  ),
);
```

`MCPAuthConfiguration` is host-owned: it doesn't do browser login or store
tokens itself, it just gives the transport a way to ask for a current token
(and, optionally, `refreshAccessToken`). `retryAfterUnauthorized` gates
whether a request that got a 401 is safe to replay after a refresh — leave it
`false` for a mutating call. `MCPAuthDiscovery.discoverProtectedResource` does
RFC 9728 discovery for a resource URI, preferring a `resource_metadata` URL
from a 401's `WWW-Authenticate` header when one is present. This is
illustrative, not a full OAuth flow — token exchange and browser login stay
the host's responsibility.

---

## Progress updates

```dart
final subscription = client.progress.listen((update) {
  print('Progress: ${update.progress}${update.total != null ? '/${update.total}' : ''}');
});

await client.callTool('longRunningJob', {'input': 'data'}, progressToken: 'job-1');
await subscription.cancel();
```

Subscribe to `client.progress` before calling the tool so no updates are
missed. `MCPProgressUpdate.progress` is an in-progress numeric signal (with an
optional `total`), not partial tool output — the tool's actual result still
arrives from `callTool`.

---

## Handling ambiguous tool-call replies

A lost reply to `tools/call` is ambiguous: the server may already have
performed the action, so the SDK does not automatically retry it. Reconcile
`MCPAmbiguousToolCompletionException` explicitly:

```dart
try {
  await client.callTool('deleteRecord', {'id': '42'});
} on MCPAmbiguousToolCompletionException catch (e) {
  // The reply was lost, not necessarily the call. Check the remote outcome,
  // or ask the application's workflow to reconcile it.
  print('Unclear whether "${e.toolName}" completed: ${e.cause}');
}
```

Set `retryOnTransportFailure: true` only for a call whose replay is safe —
for example a read-only lookup — and leave it at its default `false` for a
mutating call like `deleteRecord` above. The flag only takes effect when the
client has a `reconnectPolicy`:

```dart
final client = MCPClient(
  transport: transport,
  reconnectPolicy: const MCPReconnectPolicy(maxAttempts: 1),
);

final price = await client.callTool(
  'lookupPrice',
  {'sku': 'ABC-123'},
  retryOnTransportFailure: true,
);
```

---

## Runnable example apps

- **[`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)** — Dart CLI with MCP tool discovery
