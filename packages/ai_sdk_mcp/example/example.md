# ai_sdk_mcp examples

MCP (Model Context Protocol) client for AI SDK Dart — connect to any MCP server
and expose its tools directly to `generateText` / `streamText`.

## Installation

```sh
dart pub add ai_sdk_dart ai_sdk_openai ai_sdk_mcp
export OPENAI_API_KEY=sk-...
```

---

## SSE transport — connect to an HTTP MCP server

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

void main() async {
  final transport = SseClientTransport(
    url: Uri.parse('http://localhost:3001/sse'),
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
final result = await client.callTool(
  name: 'getWeather',
  arguments: {'city': 'London'},
);
print(result); // e.g. "Cloudy, 14°C in London"
```

---

## Error handling

`MCPClient` throws `MCPException` when the MCP server returns an error response
(`isError: true`).

```dart
try {
  await client.callTool(name: 'unknownTool', arguments: {});
} on MCPException catch (e) {
  print('MCP error: ${e.message}');
}
```

---

## Custom headers (auth)

```dart
final transport = SseClientTransport(
  url: Uri.parse('https://my-mcp-server.example.com/sse'),
  headers: {
    'Authorization': 'Bearer my-secret-token',
  },
);
```

---

## Runnable example apps

- **[`examples/basic`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/basic)** — Dart CLI with MCP tool discovery
- **[`examples/advanced_app`](https://github.com/codenameakshay/ai_sdk_dart/tree/main/examples/advanced_app)** — Flutter app demonstrating MCP integration
