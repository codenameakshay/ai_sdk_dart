// MCP conformance tests cover the publicly accessible API surface.
// MCPTransport.send uses private types (_JsonRpcRequest/_JsonRpcResponse) so
// transport-level behavior tests are omitted; they require integration tests
// against a real MCP server.
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP conformance', () {
    // ── MCPException ──────────────────────────────────────────────────────

    group('MCPException', () {
      test('has a message field', () {
        const err = MCPException('something went wrong');
        expect(err.message, 'something went wrong');
        expect(err.message, isNotEmpty);
      });

      test('toString includes class name and message', () {
        const err = MCPException('bad response');
        expect(err.toString(), contains('MCPException'));
        expect(err.toString(), contains('bad response'));
      });

      test('implements Exception', () {
        expect(const MCPException('err'), isA<Exception>());
      });

      test('can be caught as MCPException', () {
        try {
          throw const MCPException('test error');
        } on MCPException catch (e) {
          expect(e.message, 'test error');
        }
      });
    });

    // ── SseClientTransport construction ───────────────────────────────────

    group('SseClientTransport', () {
      test('can be constructed with url', () {
        final transport = SseClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
        );
        expect(transport, isA<MCPTransport>());
        expect(transport.url.toString(), 'http://localhost:3000/mcp');
      });

      test('uses url as postUrl by default', () {
        final url = Uri.parse('http://localhost:3000/mcp');
        final transport = SseClientTransport(url: url);
        expect(transport.postUrl, url);
      });

      test('accepts custom postUrl', () {
        final url = Uri.parse('http://localhost:3000/events');
        final postUrl = Uri.parse('http://localhost:3000/rpc');
        final transport = SseClientTransport(url: url, postUrl: postUrl);
        expect(transport.postUrl, postUrl);
      });

      test('accepts custom headers', () {
        final transport = SseClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
          headers: {'Authorization': 'Bearer token123'},
        );
        expect(transport.headers?['Authorization'], 'Bearer token123');
      });

      test('headers is null when not provided', () {
        final transport = SseClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
        );
        expect(transport.headers, isNull);
      });
    });

    // ── StdioMCPTransport construction ────────────────────────────────────

    group('StdioMCPTransport', () {
      test('can be constructed with command', () {
        final transport = StdioMCPTransport(command: 'mcp-server');
        expect(transport, isA<MCPTransport>());
        expect(transport.command, 'mcp-server');
      });

      test('default args is empty list', () {
        final transport = StdioMCPTransport(command: 'server');
        expect(transport.args, isEmpty);
      });

      test('accepts args list', () {
        final transport = StdioMCPTransport(
          command: 'npx',
          args: ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
        );
        expect(transport.args, [
          '-y',
          '@modelcontextprotocol/server-filesystem',
          '/tmp',
        ]);
      });

      test('stores command correctly', () {
        final transport = StdioMCPTransport(
          command: '/usr/local/bin/mcp-server',
        );
        expect(transport.command, '/usr/local/bin/mcp-server');
      });
    });

    // ── MCPClient construction ────────────────────────────────────────────

    group('MCPClient', () {
      test('can be constructed with a transport', () {
        final transport = SseClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
        );
        final client = MCPClient(transport: transport);
        expect(client, isNotNull);
        expect(client.transport, same(transport));
      });

      test('transport property is accessible', () {
        final transport = SseClientTransport(
          url: Uri.parse('http://localhost:3000/mcp'),
        );
        final client = MCPClient(transport: transport);
        expect(client.transport, isA<MCPTransport>());
      });
    });

    // ── MCPToolInfo ───────────────────────────────────────────────────────

    group('MCPToolInfo', () {
      test('can be constructed with name and inputSchema', () {
        const info = MCPToolInfo(
          name: 'search',
          inputSchema: {'type': 'object'},
        );
        expect(info.name, 'search');
        expect(info.inputSchema['type'], 'object');
        expect(info.description, isNull);
      });

      test('accepts optional description', () {
        const info = MCPToolInfo(
          name: 'calculate',
          description: 'Perform math operations',
          inputSchema: {'type': 'object'},
        );
        expect(info.description, 'Perform math operations');
      });
    });
  });
}
