import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import net from 'node:net';
import test from 'node:test';

const port = 18000 + Math.floor(Math.random() * 10000);
const child = spawn(process.execPath, ['server.mjs'], {
  cwd: new URL('.', import.meta.url),
  env: { ...process.env, PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe'],
});
const serverExit = once(child, 'exit');
let output = '';
child.stdout.setEncoding('utf8').on('data', chunk => output += chunk);
child.stderr.setEncoding('utf8').on('data', chunk => output += chunk);
const endpoint = `http://127.0.0.1:${port}/chat`;

async function waitForServer() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (child.exitCode != null) throw new Error(`server exited: ${output}`);
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ messages: [user('probe', 'hello')] }),
      });
      await response.arrayBuffer();
      return;
    } catch {
      await new Promise(resolve => setTimeout(resolve, 50));
    }
  }
  throw new Error(`server did not start: ${output}`);
}

function user(id, text) {
  return { id, role: 'user', parts: [{ type: 'text', text }] };
}

async function send(messages) {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ messages }),
  });
  const body = await response.text();
  assert.equal(response.status, 200, body);
  return [...body.matchAll(/^data: (.+)$/gm)]
    .map(match => match[1])
    .filter(data => data !== '[DONE]')
    .map(data => JSON.parse(data));
}

test.before(async () => waitForServer());
test.after(async () => {
  if (child.exitCode == null && child.signalCode == null) child.kill('SIGTERM');
  await serverExit;
});

test('assigns a fresh assistant ID to each ordinary user turn', async () => {
  const firstMessages = [user('ordinary-1', 'Hello.')];
  const first = await send(firstMessages);
  const firstStart = first.find(part => part.type === 'start');
  const second = await send([
    ...firstMessages,
    {
      id: firstStart.messageId,
      role: 'assistant',
      parts: [{ type: 'text', text: 'Hello from the pinned AI SDK backend.' }],
    },
    user('ordinary-2', 'Hello again.'),
  ]);
  const secondStart = second.find(part => part.type === 'start');
  assert.ok(firstStart.messageId);
  assert.ok(secondStart.messageId);
  assert.notEqual(secondStart.messageId, firstStart.messageId);
});

test('starts fresh tool IDs for a new turn after approval', async () => {
  const first = await send([user('u1', 'Please do this with approval.')]);
  const firstStart = first.find(part => part.type === 'start');
  const firstCall = first.find(part => part.type === 'tool-input-available');
  const firstApproval = first.find(part => part.type === 'tool-approval-request');
  assert.ok(firstStart.messageId);
  assert.ok(firstCall.toolCallId);
  assert.ok(firstApproval.approvalId);

  const continued = await send([
    user('u1', 'Please do this with approval.'),
    {
      id: firstStart.messageId,
      role: 'assistant',
      parts: [{
        type: 'tool-delete',
        toolCallId: firstCall.toolCallId,
        state: 'approval-responded',
        input: { path: '/tmp/reference' },
        approval: { id: firstApproval.approvalId, approved: true },
      }],
    },
  ]);
  assert.equal(continued.find(part => part.type === 'start').messageId, firstStart.messageId);
  assert.equal(continued.find(part => part.type === 'tool-input-available').toolCallId, firstCall.toolCallId);

  const second = await send([
    user('u1', 'Please do this with approval.'),
    {
      id: firstStart.messageId,
      role: 'assistant',
      parts: [{
        type: 'tool-delete',
        toolCallId: firstCall.toolCallId,
        state: 'output-available',
        input: { path: '/tmp/reference' },
        output: { ok: true, path: '/tmp/reference' },
        approval: { id: firstApproval.approvalId, approved: true },
      }],
    },
    user('u2', 'Another approval is required.'),
  ]);
  const secondCall = second.find(part => part.type === 'tool-input-available');
  assert.notEqual(second.find(part => part.type === 'start').messageId, firstStart.messageId);
  assert.notEqual(secondCall.toolCallId, firstCall.toolCallId);
  assert.notEqual(second.find(part => part.type === 'tool-approval-request').approvalId, firstApproval.approvalId);

  const replayedCompletedHistory = await send([
    user('u1', 'Please do this with approval.'),
    {
      id: firstStart.messageId,
      role: 'assistant',
      parts: [{
        type: 'tool-delete',
        toolCallId: firstCall.toolCallId,
        state: 'output-available',
        input: { path: '/tmp/reference' },
        output: { ok: true, path: '/tmp/reference' },
        approval: { id: firstApproval.approvalId, approved: true },
      }],
    },
  ]);
  assert.notEqual(replayedCompletedHistory.find(part => part.type === 'start').messageId, firstStart.messageId);
  assert.equal(replayedCompletedHistory.some(part => part.type === 'tool-input-available'), false);
});

test('survives a client disconnect while reading a request body', async () => {
  const socket = net.createConnection(port, '127.0.0.1');
  await once(socket, 'connect');
  socket.write('POST /chat HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: 1000\r\n\r\n{"messages":');
  socket.destroy();
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.equal(child.exitCode, null, `server exited after disconnect: ${output}`);
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ messages: [user('after', 'hello')] }),
  });
  const body = await response.text();
  assert.equal(response.status, 200, body);
  assert.match(body, /Hello from the pinned AI SDK backend/);
});
