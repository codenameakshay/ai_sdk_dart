# ai_sdk_mcp

[Model Context Protocol (MCP)](https://modelcontextprotocol.io) client for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Connects to MCP servers over HTTP SSE or stdio and exposes their tools as a typed `ToolSet`.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^1.1.0
  ai_sdk_mcp: ^1.1.0
```

## Usage

### SSE transport (remote server)

`SseClientTransport` speaks the MCP HTTP+SSE transport (protocol 2024-11-05):
it opens a streaming `GET` to the SSE endpoint, POSTs requests to the endpoint
the server advertises, and receives responses and server-pushed notifications
(including `resources/updated`) over the event stream. It uses only web-safe
HTTP, so it works on Flutter web. For a server that exposes a single plain
JSON-RPC endpoint without SSE, use `HttpClientTransport` instead.

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final transport = SseClientTransport(
  url: Uri.parse('http://localhost:3000/sse'),
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
