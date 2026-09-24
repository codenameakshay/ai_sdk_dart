import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';

const server = new Server(
  { name: 'dart-sdk-reference', version: '1.0.0' },
  { capabilities: { tools: {} } },
);
server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [{
    name: 'echo',
    description: 'Return fixture text or an explicit tool failure.',
    inputSchema: {
      type: 'object',
      properties: { text: { type: 'string' }, fail: { type: 'boolean' } },
      required: ['text'],
    },
  }],
}));
server.setRequestHandler(CallToolRequestSchema, async ({ params }) => {
  if (params.name !== 'echo') throw new Error('Unknown fixture tool');
  if (params.arguments?.fail) {
    return { content: [{ type: 'text', text: 'fixture tool failed' }], isError: true };
  }
  return { content: [{ type: 'text', text: `echo:${params.arguments?.text ?? ''}` }] };
});
await server.connect(new StdioServerTransport());
