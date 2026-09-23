import http from 'node:http';
import {
  createUIMessageStream,
  createUIMessageStreamResponse,
  validateUIMessages,
} from 'ai';

const server = http.createServer(async (request, response) => {
  const corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type, x-vercel-ai-ui-message-stream',
    'access-control-expose-headers': 'x-vercel-ai-ui-message-stream',
    'access-control-allow-methods': 'POST, OPTIONS',
  };
  if (request.method === 'OPTIONS') {
    response.writeHead(204, corsHeaders).end();
    return;
  }
  if (request.method !== 'POST' || request.url !== '/chat') {
    response.writeHead(404, corsHeaders).end();
    return;
  }
  let body = '';
  for await (const chunk of request) body += chunk;
  let messages;
  try {
    messages = JSON.parse(body).messages;
    messages = await validateUIMessages({ messages });
  } catch (error) {
    response.writeHead(400, { ...corsHeaders, 'content-type': 'text/plain' });
    response.end(`invalid UI messages: ${error.message}`);
    return;
  }
  const toolPart = messages
    .flatMap(message => message.parts)
    .find(part => part.type.startsWith('tool-'));
  const hasTool = toolPart != null;
  const requestsApproval = messages.some(message =>
    message.role === 'user' && message.parts.some(part =>
      part.type === 'text' && part.text.toLowerCase().includes('approval'),
    ),
  );
  const approval = toolPart?.approval;
  const hasDecision =
    approval != null && typeof approval.approved === 'boolean';
  const stream = createUIMessageStream({
    execute({ writer }) {
      writer.write({ type: 'start', messageId: 'js-example-assistant' });
      if ((hasTool || requestsApproval) && !hasDecision) {
        writer.write({
          type: 'tool-input-available',
          toolCallId: 'js-call-1',
          toolName: 'delete',
          input: { path: '/tmp/reference' },
        });
        writer.write({
          type: 'tool-approval-request',
          approvalId: 'js-approval-1',
          toolCallId: 'js-call-1',
          reason: 'Reference server approval',
        });
      } else if (hasTool && hasDecision) {
        writer.write({
          type: 'tool-input-available',
          toolCallId: 'js-call-1',
          toolName: 'delete',
          input: { path: '/tmp/reference' },
        });
        writer.write({
          type: 'tool-approval-request',
          approvalId: approval.id,
          toolCallId: 'js-call-1',
          reason: 'Reference server approval',
        });
        writer.write({
          type: 'tool-approval-response',
          approvalId: approval.id,
          approved: approval.approved,
          ...(approval.reason ? { reason: approval.reason } : {}),
        });
        if (approval.approved) {
          writer.write({
            type: 'tool-output-available',
            toolCallId: 'js-call-1',
            output: { ok: true, path: '/tmp/reference' },
          });
        } else {
          writer.write({
            type: 'tool-output-denied',
            toolCallId: 'js-call-1',
          });
        }
        writer.write({ type: 'text-start', id: 'js-example-text' });
        writer.write({
          type: 'text-delta',
          id: 'js-example-text',
          delta: approval.approved
            ? 'The scripted tool call was approved and resumed.'
            : 'The scripted tool call was denied and resumed safely.',
        });
        writer.write({ type: 'text-end', id: 'js-example-text' });
      } else {
        writer.write({ type: 'text-start', id: 'js-example-text' });
        writer.write({
          type: 'text-delta',
          id: 'js-example-text',
          delta: 'Hello from the pinned AI SDK backend.',
        });
        writer.write({ type: 'text-end', id: 'js-example-text' });
      }
      writer.write({ type: 'finish', finishReason: 'stop' });
    },
  });
  const sdkResponse = createUIMessageStreamResponse({ stream });
  response.writeHead(sdkResponse.status ?? 200, {
    ...corsHeaders,
    ...Object.fromEntries(sdkResponse.headers),
  });
  for await (const chunk of sdkResponse.body) response.write(chunk);
  response.end();
});

server.listen(8081, '127.0.0.1', () => {
  console.log('Listening on http://127.0.0.1:8081/chat');
});
