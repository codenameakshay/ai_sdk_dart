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

## Runnable example apps

- **[`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)** — Dart CLI with MCP tool discovery
