# ai_sdk_mcp

[Model Context Protocol (MCP)](https://modelcontextprotocol.io) client for [AI SDK Dart](https://pub.dev/packages/ai). Connects to MCP servers over HTTP SSE or stdio and exposes their tools as a typed `ToolSet`.

## Installation

```yaml
dependencies:
  ai: ^0.1.0
  ai_sdk_mcp: ^0.1.0
```

## Usage

### SSE transport (remote server)

```dart
import 'package:ai/ai.dart';
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
