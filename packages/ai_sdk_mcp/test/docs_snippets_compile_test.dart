import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('mcp README and example snippets compile', () {
    final transport = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.example.com/mcp'),
      headers: {
        'Authorization': 'Bearer <short-lived-token>',
        'X-Workspace': 'demo',
      },
      requestTimeout: const Duration(seconds: 20),
    );
    final client = MCPClient(transport: transport);

    final stdio = StdioMCPTransport(
      command: 'node',
      args: ['path/to/mcp-server.js'],
    );

    final sharedClient = http.Client();
    final injected = StreamableHttpClientTransport(
      url: Uri.parse('https://mcp.example.com/mcp'),
      client: sharedClient,
    );

    expect(client, isA<MCPClient>());
    expect(stdio, isA<StdioMCPTransport>());
    expect(injected, isA<StreamableHttpClientTransport>());

    sharedClient.close();
  });
}
