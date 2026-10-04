import 'dart:io';

import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';
import 'package:test/test.dart';

void main() {
  test(
    'legacy client interoperates with pinned TypeScript SDK over stdio',
    () async {
      final client = MCPClient(
        transport: StdioMCPTransport(
          command: 'node',
          args: ['examples/mcp_reference/js/server.mjs'],
        ),
        protocolMode: MCPProtocolMode.legacy,
      );
      addTearDown(client.close);
      await client.initialize();
      final tools = await client.tools();
      expect(tools.keys, ['echo']);
      expect(await client.callTool('echo', {'text': 'snow ☃'}), 'echo:snow ☃');
      await expectLater(
        client.callTool('echo', {'text': 'failure', 'fail': true}),
        throwsA(
          isA<MCPException>().having(
            (error) => error.message,
            'tool failure',
            contains('fixture tool failed'),
          ),
        ),
      );
      expect(await client.callTool('echo', {'text': 'after'}), 'echo:after');
      await client.close();
    },
    skip: Platform.environment['AI_SDK_MCP_REFERENCE'] != '1'
        ? 'Run make test-mcp-reference to install the pinned reference SDK.'
        : false,
  );
}
