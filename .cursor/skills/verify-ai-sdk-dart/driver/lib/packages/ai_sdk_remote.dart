// Verification checks for package:ai_sdk_remote. See features/ai_sdk_remote.md.
//
// Two kinds of backend are used:
//
//  * The REAL pinned JavaScript reference backend in
//    examples/remote_backend/js (Vercel AI SDK 7.0.111, started with
//    ctx.spawn on a free port). It proves the transport reads real SDK
//    output. It does not log requests.
//  * A ctx.server fixture that replays UI-message stream events. It proves
//    the request side (headers, body) and the error and cancellation paths
//    a real backend will not produce on demand.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
// The driver cannot change its pubspec; `http` is the package's own dependency.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;

import '../harness.dart';

const _package = 'ai_sdk_remote';
const _streamHeader = {'x-vercel-ai-ui-message-stream': 'v1'};

Conversation _userConversation(String text, {String id = 'conversation-1'}) =>
    Conversation(
      id: id,
      messages: [
        ConversationMessage(
          id: 'user-1',
          role: ConversationRole.user,
          parts: [TextPart(id: 'user-1-text', text: text)],
        ),
      ],
    );

/// Starts the JS reference backend on a free loopback port and waits until
/// `OPTIONS /chat` answers 204. Returns the `/chat` endpoint.
Future<Uri> _startJsBackend(CheckContext ctx) async {
  final directory = '${ctx.repoRoot}/examples/remote_backend/js';
  if (!Directory('$directory/node_modules/ai').existsSync()) {
    throw CheckFailure(
      'JS reference backend dependencies are missing; run `npm ci` in '
      '$directory (scripts/verify setup does this).',
    );
  }
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  final process = await ctx.spawn(
    'backend',
    'node',
    ['server.mjs'],
    workingDirectory: directory,
    environment: {'PORT': '$port'},
  );
  var exitCode = -1000;
  unawaited(process.exitCode.then((code) => exitCode = code));
  final endpoint = Uri.parse('http://127.0.0.1:$port/chat');
  final client = HttpClient();
  try {
    final stopwatch = Stopwatch()..start();
    while (true) {
      if (exitCode != -1000) {
        throw CheckFailure(
          'JS backend exited with code $exitCode (see backend.log artifact)',
        );
      }
      try {
        final request = await client.openUrl('OPTIONS', endpoint);
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 204) break;
      } on SocketException {
        // Not listening yet.
      }
      if (stopwatch.elapsed > const Duration(seconds: 15)) {
        throw CheckFailure('JS backend did not answer OPTIONS /chat in 15 s');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    ctx.note(
      'JS backend ready on port $port after ${stopwatch.elapsedMilliseconds} ms',
    );
  } finally {
    client.close(force: true);
  }
  return endpoint;
}

RemoteConversationTransport _transport(
  CheckContext ctx,
  Uri endpoint, {
  FutureOr<Map<String, String>> Function()? authHeaders,
  Map<String, String> headers = const {},
  http.Client? client,
}) {
  final transport = RemoteConversationTransport(
    endpoint: endpoint,
    authHeaders: authHeaders,
    headers: headers,
    client: client,
  );
  ctx.onCleanup(() async => transport.dispose());
  return transport;
}

/// Replaces the pending approval of [pending]'s assistant message with an
/// application decision, the way a UI does after the user taps approve.
Conversation _decide(
  Conversation pending,
  ApprovalStatus status, {
  String? reason,
}) {
  final assistant = pending.messages.last;
  return Conversation(
    id: pending.id,
    messages: [
      ...pending.messages.take(pending.messages.length - 1),
      ConversationMessage(
        id: assistant.id,
        role: assistant.role,
        status: ConversationMessageStatus.streaming,
        parts: [
          for (final part in assistant.parts)
            if (part is ApprovalPart)
              ApprovalPart(
                id: part.id,
                callId: part.callId,
                status: status,
                approvalId: part.approvalId,
                extra: {'reason': ?reason},
              )
            else
              part,
        ],
      ),
    ],
  );
}

/// Posts [body] to the JS backend like a browser would and returns status,
/// headers and the raw response text.
Future<({int status, Map<String, String> headers, String body})> _rawPost(
  Uri endpoint,
  String body,
) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final headers = <String, String>{};
    response.headers.forEach(
      (name, values) => headers[name] = values.join(','),
    );
    return (status: response.statusCode, headers: headers, body: text);
  } finally {
    client.close(force: true);
  }
}

Future<List<Conversation>> _drain(Stream<Conversation> stream) =>
    stream.toList();

FixtureResponse _okStream(List<Object> events) =>
    FixtureResponse.sse(events, done: true, headers: _streamHeader);

const _helloEvents = <Object>[
  {'type': 'start', 'messageId': 'assistant-fixture'},
  {'type': 'text-start', 'id': 't1'},
  {'type': 'text-delta', 'id': 't1', 'delta': 'Hello'},
  {'type': 'text-end', 'id': 't1'},
  {'type': 'finish', 'finishReason': 'stop'},
];

final checks = PackageChecks(_package, [
  Check(
    id: 'js-backend-wire-format',
    feature: 'remote-interop',
    description:
        'The real JS reference backend answers a CORS preflight with 204 and '
        'a UI-message request with 200, text/event-stream, the v1 stream '
        'header, ordered start/text/finish events and a final [DONE].',
    run: (ctx) async {
      final endpoint = await _startJsBackend(ctx);
      final client = HttpClient();
      final preflight = await client.openUrl('OPTIONS', endpoint);
      final preflightResponse = await preflight.close();
      await preflightResponse.drain<void>();
      client.close(force: true);
      ctx.expectEquals(preflightResponse.statusCode, 204, 'preflight status');
      ctx.expect(
        (preflightResponse.headers.value('access-control-expose-headers') ?? '')
            .contains('x-vercel-ai-ui-message-stream'),
        'CORS does not expose the stream header',
      );
      final response = await _rawPost(
        endpoint,
        jsonEncode({
          'messages': [
            {
              'id': 'user-1',
              'role': 'user',
              'parts': [
                {'type': 'text', 'text': 'Hello'},
              ],
            },
          ],
        }),
      );
      ctx.observe('status', response.status);
      ctx.observe('headers', response.headers);
      ctx.observe('body', response.body);
      ctx.expectEquals(response.status, 200, 'status');
      ctx.expect(
        (response.headers['content-type'] ?? '').startsWith(
          'text/event-stream',
        ),
        'content-type: ${response.headers['content-type']}',
      );
      ctx.expectEquals(
        response.headers['x-vercel-ai-ui-message-stream'],
        'v1',
        'stream version header',
      );
      final frames = [
        for (final line in const LineSplitter().convert(response.body))
          if (line.startsWith('data: ')) line.substring(6),
      ];
      final types = [
        for (final frame in frames)
          if (frame != '[DONE]') (jsonDecode(frame) as Map)['type'],
      ];
      ctx.expectEquals(types, [
        'start',
        'text-start',
        'text-delta',
        'text-end',
        'finish',
      ], 'event types');
      ctx.expectEquals(frames.last, '[DONE]', 'terminator');
    },
  ),
  Check(
    id: 'js-text-turn',
    feature: 'remote-text',
    description:
        'RemoteConversationTransport.send against the real JS backend yields '
        'snapshots that end with the user message intact and one completed '
        'assistant message holding the streamed text.',
    run: (ctx) async {
      final endpoint = await _startJsBackend(ctx);
      final transport = _transport(ctx, endpoint);
      final original = _userConversation('Hello there');
      final snapshots = await _drain(transport.send(original));
      ctx.observe('snapshotCount', snapshots.length);
      ctx.expect(snapshots.length >= 3, 'got ${snapshots.length} snapshots');
      final last = snapshots.last;
      ctx.expectEquals(last.id, 'conversation-1', 'conversation id');
      ctx.expectEquals(last.messages.length, 2, 'message count');
      ctx.expect(
        last.messages.first == original.messages.first,
        'user message changed',
      );
      final assistant = last.messages.last;
      ctx.observe('assistantId', assistant.id);
      ctx.expectEquals(assistant.role, ConversationRole.assistant, 'role');
      ctx.expectEquals(
        assistant.status,
        ConversationMessageStatus.complete,
        'status',
      );
      ctx.expectEquals(
        (assistant.parts.single as TextPart).text,
        'Hello from the pinned AI SDK backend.',
        'assistant text',
      );
      ctx.expect(
        RegExp(r'^[0-9a-f-]{36}$').hasMatch(assistant.id),
        'assistant id is not the backend UUID: ${assistant.id}',
      );
      ctx.expectEquals(
        snapshots.first.messages.last.status,
        ConversationMessageStatus.streaming,
        'first snapshot is streaming',
      );
      ctx.expectEquals(original.messages.length, 1, 'input is not mutated');
    },
  ),
  Check(
    id: 'js-approval-request',
    feature: 'remote-approval',
    description:
        'A user message containing "approval" makes the real JS backend '
        'stream a tool call and approval request; the final snapshot is '
        'pendingApproval with the tool call and a pending ApprovalPart and '
        'no tool result.',
    run: (ctx) async {
      final endpoint = await _startJsBackend(ctx);
      final transport = _transport(ctx, endpoint);
      final snapshots = await _drain(
        transport.send(_userConversation('Please ask for approval')),
      );
      final assistant = snapshots.last.messages.last;
      ctx.observe('status', assistant.status.name);
      ctx.observe('parts', [for (final p in assistant.parts) p.toJson()]);
      ctx.expectEquals(
        assistant.status,
        ConversationMessageStatus.pendingApproval,
        'status',
      );
      final call = assistant.parts.whereType<ToolCallPart>().single;
      ctx.expectEquals(call.name, 'delete', 'tool name');
      ctx.expectEquals(call.arguments, {'path': '/tmp/reference'}, 'arguments');
      final approval = assistant.parts.whereType<ApprovalPart>().single;
      ctx.expectEquals(approval.status, ApprovalStatus.pending, 'approval');
      ctx.expectEquals(approval.callId, call.callId, 'approval call id');
      ctx.expect((approval.approvalId ?? '').isNotEmpty, 'approvalId is empty');
      ctx.expectEquals(
        assistant.parts.whereType<ToolResultPart>().length,
        0,
        'no tool result before a decision',
      );
      // The package never runs the tool: the pending snapshot is all there is.
      ctx.expectEquals(
        snapshots
            .where((s) => s.messages.last.parts.any((p) => p is ToolResultPart))
            .length,
        0,
        'snapshots with a result',
      );
    },
  ),
  Check(
    id: 'js-approval-approved-continuation',
    feature: 'remote-approval',
    description:
        'Sending the conversation back with the approval set to approved '
        'continues the same assistant message: the JS backend returns the '
        'tool output and the "approved and resumed" text.',
    run: (ctx) async {
      final endpoint = await _startJsBackend(ctx);
      final transport = _transport(ctx, endpoint);
      final pending = (await _drain(
        transport.send(_userConversation('Please ask for approval')),
      )).last;
      final snapshots = await _drain(
        transport.send(_decide(pending, ApprovalStatus.approved)),
      );
      final assistant = snapshots.last.messages.last;
      ctx.observe('parts', [for (final p in assistant.parts) p.toJson()]);
      ctx.expectEquals(
        snapshots.last.messages.length,
        pending.messages.length,
        'continuation must reuse the assistant message',
      );
      ctx.expectEquals(assistant.id, pending.messages.last.id, 'assistant id');
      ctx.expectEquals(
        assistant.status,
        ConversationMessageStatus.complete,
        'status',
      );
      final approval = assistant.parts.whereType<ApprovalPart>().single;
      ctx.expectEquals(approval.status, ApprovalStatus.approved, 'approval');
      final result = assistant.parts.whereType<ToolResultPart>().single;
      ctx.expectEquals(result.isError, false, 'result is an error');
      ctx.expectEquals(result.output, {
        'ok': true,
        'path': '/tmp/reference',
      }, 'tool output');
      ctx.expectEquals(
        assistant.parts.whereType<TextPart>().single.text,
        'The scripted tool call was approved and resumed.',
        'resumed text',
      );
    },
  ),
  Check(
    id: 'js-approval-denied-continuation',
    feature: 'remote-approval',
    description:
        'Sending the conversation back with the approval rejected and a '
        'reason continues the message with an execution_denied result and '
        'the "denied and resumed safely" text.',
    run: (ctx) async {
      final endpoint = await _startJsBackend(ctx);
      final transport = _transport(ctx, endpoint);
      final pending = (await _drain(
        transport.send(_userConversation('Please ask for approval')),
      )).last;
      final snapshots = await _drain(
        transport.send(
          _decide(pending, ApprovalStatus.rejected, reason: 'Not on prod'),
        ),
      );
      final assistant = snapshots.last.messages.last;
      ctx.observe('parts', [for (final p in assistant.parts) p.toJson()]);
      ctx.expectEquals(
        assistant.status,
        ConversationMessageStatus.complete,
        'status',
      );
      final approval = assistant.parts.whereType<ApprovalPart>().single;
      ctx.expectEquals(approval.status, ApprovalStatus.rejected, 'approval');
      ctx.expectEquals(approval.extra['reason'], 'Not on prod', 'reason');
      final result = assistant.parts.whereType<ToolResultPart>().single;
      ctx.expectEquals(result.outputKind, 'execution_denied', 'outputKind');
      ctx.expectEquals(
        assistant.parts.whereType<TextPart>().single.text,
        'The scripted tool call was denied and resumed safely.',
        'denied text',
      );
    },
  ),
  Check(
    id: 'js-rejects-malformed-request',
    feature: 'remote-errors',
    description:
        'The real JS backend answers 400 to a body that is not valid UI '
        'messages; the transport turns the 400 for an empty conversation '
        'into RemoteProtocolException "Remote request failed (400)".',
    run: (ctx) async {
      final endpoint = await _startJsBackend(ctx);
      final raw = await _rawPost(endpoint, '{"messages":[{"nope":1}]}');
      ctx.observe('rawStatus', raw.status);
      ctx.observe('rawBody', raw.body);
      ctx.expectEquals(raw.status, 400, 'raw status');
      ctx.expect(
        raw.body.startsWith('invalid UI messages'),
        'raw body: ${raw.body}',
      );
      final transport = _transport(ctx, endpoint);
      final error = await ctx.expectThrows<RemoteProtocolException>(
        () => _drain(
          transport.send(Conversation(id: 'empty', messages: const [])),
        ),
        'empty conversation',
      );
      ctx.expect(
        error.message.contains('Remote request failed (400)'),
        'message: ${error.message}',
      );
    },
  ),
  Check(
    id: 'request-headers-and-auth',
    feature: 'remote-request',
    description:
        'send() POSTs to the endpoint with accept, content-type, the v1 '
        'stream header, static headers and the authHeaders result, calling '
        'authHeaders again for every send.',
    run: (ctx) async {
      final server = await ctx.server((_) => _okStream(_helloEvents));
      var calls = 0;
      final transport = _transport(
        ctx,
        Uri.parse(server.url('/api/chat')),
        headers: {'x-app': 'verify'},
        authHeaders: () async => {'Authorization': 'Bearer token-${++calls}'},
      );
      await _drain(transport.send(_userConversation('one')));
      await _drain(transport.send(_userConversation('two')));
      final requests = ctx.requestsTo(server, '/api/chat', method: 'POST');
      ctx.expectEquals(requests.length, 2, 'request count');
      ctx.expectEquals(calls, 2, 'authHeaders calls');
      for (final (index, request) in requests.indexed) {
        ctx.expectEquals(
          request.headers['authorization'],
          'Bearer token-${index + 1}',
          'authorization #$index',
        );
        ctx.expectEquals(request.headers['x-app'], 'verify', 'static header');
        ctx.expectEquals(
          request.headers['accept'],
          'text/event-stream',
          'accept',
        );
        ctx.expect(
          (request.headers['content-type'] ?? '').startsWith(
            'application/json',
          ),
          'content-type: ${request.headers['content-type']}',
        );
        ctx.expectEquals(
          request.headers['x-vercel-ai-ui-message-stream'],
          'v1',
          'stream version request header',
        );
      }
      ctx.expectEquals(
        ((requests[1].jsonObject['messages'] as List).single as Map)['parts'],
        [
          {'type': 'text', 'text': 'two'},
        ],
        'second request text',
      );
    },
  ),
  Check(
    id: 'request-body-mapping',
    feature: 'remote-request',
    description:
        'The request body is {messages: [UIMessage]}: text, reasoning, file '
        'bytes as data URLs, URI files, sources, an approved tool call in '
        'approval-responded state and a finished one in output-available '
        'state; unsupported parts fail before any request is sent.',
    run: (ctx) async {
      final server = await ctx.server((_) => _okStream(_helloEvents));
      final transport = _transport(ctx, Uri.parse(server.url('/chat')));
      final conversation = Conversation(
        id: 'mapping',
        messages: [
          ConversationMessage(
            id: 'u1',
            role: ConversationRole.user,
            metadata: {'locale': 'en'},
            parts: [
              TextPart(id: 'u1-t', text: 'Look at these'),
              FilePart(
                id: 'u1-f1',
                mimeType: 'text/plain',
                name: 'note.txt',
                data: ConversationFileBytes(
                  Uint8List.fromList(utf8.encode('hi')),
                ),
              ),
              FilePart(
                id: 'u1-f2',
                mimeType: 'image/png',
                uri: 'https://example.test/a.png',
              ),
            ],
          ),
          ConversationMessage(
            id: 'a1',
            role: ConversationRole.assistant,
            parts: [
              ReasoningPart(id: 'a1-r', text: 'Thinking'),
              SourcePart(
                id: 'a1-s',
                uri: 'https://example.test/doc',
                sourceId: 'src-1',
                title: 'Doc',
              ),
              ToolCallPart(
                id: 'a1-c1',
                callId: 'call-1',
                name: 'delete',
                arguments: {'path': '/a'},
              ),
              ApprovalPart(
                id: 'a1-ap1',
                callId: 'call-1',
                status: ApprovalStatus.approved,
                approvalId: 'approval-1',
                extra: {'reason': 'ok'},
              ),
              ToolCallPart(
                id: 'a1-c2',
                callId: 'call-2',
                name: 'lookup',
                arguments: {'q': 'x'},
              ),
              ToolResultPart(
                id: 'a1-r2',
                callId: 'call-2',
                output: {'hits': 2},
              ),
            ],
          ),
        ],
      );
      await _drain(transport.send(conversation));
      final body = ctx.singleRequest(server, '/chat').jsonObject;
      final messages = (body['messages'] as List).cast<Map>();
      ctx.expectEquals(body.keys.toList(), ['messages'], 'body keys');
      ctx.expectEquals(messages[0]['id'], 'u1', 'message id');
      ctx.expectEquals(messages[0]['role'], 'user', 'role');
      ctx.expectEquals(messages[0]['metadata'], {'locale': 'en'}, 'metadata');
      final userParts = (messages[0]['parts'] as List).cast<Map>();
      ctx.expectEquals(userParts[0], {
        'type': 'text',
        'text': 'Look at these',
      }, 'text');
      ctx.expectEquals(userParts[1], {
        'type': 'file',
        'url': 'data:text/plain;base64,${base64Encode(utf8.encode('hi'))}',
        'mediaType': 'text/plain',
        'filename': 'note.txt',
      }, 'file bytes become a data URL');
      ctx.expectEquals(userParts[2], {
        'type': 'file',
        'url': 'https://example.test/a.png',
        'mediaType': 'image/png',
      }, 'file URI');
      final assistant = (messages[1]['parts'] as List).cast<Map>();
      ctx.expectEquals(assistant[0], {
        'type': 'reasoning',
        'text': 'Thinking',
      }, 'reasoning');
      ctx.expectEquals(assistant[1], {
        'type': 'source-url',
        'sourceId': 'src-1',
        'url': 'https://example.test/doc',
        'title': 'Doc',
      }, 'source');
      ctx.expectEquals(assistant[2], {
        'type': 'tool-delete',
        'toolCallId': 'call-1',
        'state': 'approval-responded',
        'input': {'path': '/a'},
        'approval': {'id': 'approval-1', 'approved': true, 'reason': 'ok'},
      }, 'approved tool call');
      ctx.expectEquals(assistant[3], {
        'type': 'tool-lookup',
        'toolCallId': 'call-2',
        'state': 'output-available',
        'input': {'q': 'x'},
        'output': {'hits': 2},
      }, 'finished tool call');
      ctx.expectEquals(assistant.length, 4, 'tool result parts are folded in');

      final before = server.requests.length;
      final unsupported = <String, Conversation>{
        'provider file reference': Conversation(
          id: 'u1',
          messages: [
            ConversationMessage(
              id: 'm',
              role: ConversationRole.user,
              parts: [
                FilePart(
                  id: 'p',
                  mimeType: 'application/pdf',
                  data: ConversationFileProviderReference(
                    namespace: 'openai',
                    id: 'file-1',
                  ),
                ),
              ],
            ),
          ],
        ),
        'redacted reasoning': Conversation(
          id: 'u2',
          messages: [
            ConversationMessage(
              id: 'm',
              role: ConversationRole.assistant,
              parts: [
                RedactedReasoningPart(id: 'p', data: Uint8List.fromList([1])),
              ],
            ),
          ],
        ),
      };
      for (final entry in unsupported.entries) {
        await ctx.expectThrows<UnsupportedError>(
          () => _drain(transport.send(entry.value)),
          entry.key,
        );
      }
      ctx.expectEquals(
        server.requests.length,
        before,
        'requests for unsupported parts',
      );
    },
  ),
  Check(
    id: 'stream-reduction',
    feature: 'remote-reduce',
    description:
        'UI-message events reduce into snapshots: text and reasoning deltas '
        'grow in place, tool input streams then resolves, tool output and '
        'tool error become results, sources, files and metadata are kept, '
        'unknown data events are preserved and transient ones dropped.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _okStream([
          {
            'type': 'start',
            'messageId': 'assistant-1',
            'messageMetadata': {'model': 'verify'},
          },
          {'type': 'start-step'},
          {'type': 'reasoning-start', 'id': 'r1'},
          {'type': 'reasoning-delta', 'id': 'r1', 'delta': 'Let me '},
          {'type': 'reasoning-delta', 'id': 'r1', 'delta': 'think.'},
          {'type': 'reasoning-end', 'id': 'r1'},
          {'type': 'text-start', 'id': 't1'},
          {'type': 'text-delta', 'id': 't1', 'delta': 'One, '},
          {'type': 'text-delta', 'id': 't1', 'delta': 'two.'},
          {'type': 'text-end', 'id': 't1'},
          {
            'type': 'source-url',
            'sourceId': 's1',
            'url': 'https://example.test/s1',
            'title': 'S1',
          },
          {
            'type': 'source-document',
            'sourceId': 's2',
            'mediaType': 'application/pdf',
            'title': 'Spec',
            'filename': 'spec.pdf',
          },
          {
            'type': 'file',
            'url': 'data:text/plain;base64,aGk=',
            'mediaType': 'text/plain',
          },
          {
            'type': 'tool-input-start',
            'toolCallId': 'c1',
            'toolName': 'weather',
          },
          {
            'type': 'tool-input-delta',
            'toolCallId': 'c1',
            'inputTextDelta': '{"city":',
          },
          {
            'type': 'tool-input-available',
            'toolCallId': 'c1',
            'toolName': 'weather',
            'input': {'city': 'Paris'},
          },
          {
            'type': 'tool-output-available',
            'toolCallId': 'c1',
            'output': {'tempC': 18},
          },
          {
            'type': 'tool-input-available',
            'toolCallId': 'c2',
            'toolName': 'weather',
            'input': {'city': 'Nowhere'},
          },
          {
            'type': 'tool-output-error',
            'toolCallId': 'c2',
            'errorText': 'City not found',
          },
          {
            'type': 'data-weather',
            'id': 'data-1',
            'data': {'city': 'Paris'},
          },
          {
            'type': 'data-progress',
            'transient': true,
            'data': {'pct': 50},
          },
          {'type': 'future-event', 'payload': 7},
          {
            'type': 'message-metadata',
            'messageMetadata': {
              'usage': {'tokens': 42},
            },
          },
          {'type': 'finish-step'},
          {'type': 'start-step'},
          {'type': 'text-start', 'id': 'discarded'},
          {'type': 'text-delta', 'id': 'discarded', 'delta': 'rolled back'},
          {'type': 'reset-step'},
          {'type': 'finish-step'},
          {
            'type': 'finish',
            'finishReason': 'stop',
            'messageMetadata': {'done': true},
          },
        ]),
      );
      final transport = _transport(ctx, Uri.parse(server.url('/chat')));
      final snapshots = await _drain(transport.send(_userConversation('go')));
      final last = snapshots.last;
      final assistant = last.messages.last;
      ctx.observe('snapshotCount', snapshots.length);
      ctx.observe('parts', [for (final p in assistant.parts) p.toJson()]);
      ctx.observe('metadata', assistant.metadata);
      final textLengths = [
        for (final s in snapshots)
          if (s.messages.last.parts.whereType<TextPart>().isNotEmpty)
            s.messages.last.parts.whereType<TextPart>().first.text,
      ];
      ctx.expect(
        textLengths.contains('One, ') && textLengths.contains('One, two.'),
        'text did not grow incrementally: $textLengths',
      );
      ctx.expectEquals(assistant.id, 'assistant-1', 'message id from start');
      ctx.expectEquals(
        assistant.status,
        ConversationMessageStatus.complete,
        'status',
      );
      ctx.expectEquals(
        assistant.parts.whereType<ReasoningPart>().single.text,
        'Let me think.',
        'reasoning',
      );
      ctx.expectEquals(
        assistant.parts.whereType<TextPart>().single.text,
        'One, two.',
        'text (the reset-step text is rolled back)',
      );
      ctx.expectEquals(
        assistant.parts.whereType<SourcePart>().single.uri,
        'https://example.test/s1',
        'source url',
      );
      ctx.expectEquals(
        assistant.parts.whereType<DocumentSourcePart>().single.name,
        'spec.pdf',
        'source document',
      );
      final file = assistant.parts.whereType<FilePart>().single;
      ctx.expectEquals(
        (file.data as ConversationFileBytes).bytes,
        utf8.encode('hi'),
        'data URL decoded to bytes',
      );
      final calls = assistant.parts.whereType<ToolCallPart>().toList();
      ctx.expectEquals(calls.map((c) => c.callId).toList(), [
        'c1',
        'c2',
      ], 'calls');
      ctx.expectEquals(calls[0].arguments, {'city': 'Paris'}, 'resolved input');
      ctx.expect(
        calls[0].extra['inputPending'] != true,
        'tool input still pending after tool-input-available',
      );
      final results = assistant.parts.whereType<ToolResultPart>().toList();
      ctx.expectEquals(results[0].output, {'tempC': 18}, 'tool output');
      ctx.expectEquals(results[1].isError, true, 'tool error flag');
      ctx.expectEquals(results[1].output, 'City not found', 'tool error text');
      final unknownTypes = assistant.parts
          .whereType<UnknownPart>()
          .map((p) => p.type)
          .toList();
      ctx.expectEquals(unknownTypes, [
        'data-weather',
        'future-event',
      ], 'unknown');
      ctx.expectEquals(assistant.metadata['model'], 'verify', 'start metadata');
      ctx.expectEquals(assistant.metadata['usage'], {
        'tokens': 42,
      }, 'message-metadata');
      ctx.expectEquals(assistant.metadata['done'], true, 'finish metadata');
    },
  ),
  Check(
    id: 'error-and-abort-streams',
    feature: 'remote-reduce',
    description:
        'An error event ends as a failed message carrying the error text; '
        'an abort event ends as an interrupted message; both streams close '
        'without throwing.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return _okStream([
            {'type': 'start', 'messageId': 'a-err'},
            {'type': 'text-start', 'id': 't'},
            {'type': 'text-delta', 'id': 't', 'delta': 'Partial'},
            {'type': 'error', 'errorText': 'Model overloaded'},
            {'type': 'finish'},
          ]);
        }
        return _okStream([
          {'type': 'start', 'messageId': 'a-abort'},
          {'type': 'text-start', 'id': 't'},
          {'type': 'text-delta', 'id': 't', 'delta': 'Cut'},
          {'type': 'abort'},
        ]);
      });
      final transport = _transport(ctx, Uri.parse(server.url('/chat')));
      final failed = (await _drain(
        transport.send(_userConversation('x')),
      )).last;
      final failedMessage = failed.messages.last;
      ctx.observe('failedMetadata', failedMessage.metadata);
      ctx.expectEquals(
        failedMessage.status,
        ConversationMessageStatus.failed,
        'failed',
      );
      ctx.expectEquals(
        failedMessage.metadata['error'],
        'Model overloaded',
        'error text',
      );
      ctx.expectEquals(
        (failedMessage.parts.single as TextPart).text,
        'Partial',
        'partial text kept',
      );
      final aborted = (await _drain(
        transport.send(_userConversation('y')),
      )).last;
      ctx.expectEquals(
        aborted.messages.last.status,
        ConversationMessageStatus.interrupted,
        'interrupted',
      );
      ctx.expectEquals(
        (aborted.messages.last.parts.single as TextPart).text,
        'Cut',
        'text kept on abort',
      );
    },
  ),
  Check(
    id: 'protocol-violations',
    feature: 'remote-errors',
    description:
        'Wrong content type or version header, a missing terminal event or '
        '[DONE], a malformed frame, a delta without start, and HTTP 401 or '
        '500 each fail with RemoteProtocolException and a specific message.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        switch (request.path) {
          case '/wrong-type':
            return FixtureResponse.json({'ok': true}, headers: _streamHeader);
          case '/no-version':
            return FixtureResponse.sse(_helloEvents, done: true);
          case '/no-done':
            return FixtureResponse.sse(_helloEvents, headers: _streamHeader);
          case '/no-finish':
            return FixtureResponse.sse(
              _helloEvents.take(4).toList(),
              done: true,
              headers: _streamHeader,
            );
          case '/bad-json':
            return FixtureResponse.sse(
              ['{not json'],
              done: true,
              headers: _streamHeader,
            );
          case '/delta-no-start':
            return _okStream([
              {'type': 'start'},
              {'type': 'text-delta', 'id': 'x', 'delta': 'orphan'},
              {'type': 'finish'},
            ]);
          case '/http-401':
            return FixtureResponse.json({'error': 'no'}, status: 401);
          default:
            return FixtureResponse.json({'error': 'boom'}, status: 500);
        }
      });
      const expectations = {
        '/wrong-type': 'Invalid UI message stream headers',
        '/no-version': 'Invalid UI message stream headers',
        '/no-done': 'Truncated UI message stream',
        '/no-finish': 'ended without finish or abort',
        '/bad-json': 'Malformed SSE or JSON frame',
        '/delta-no-start': 'Delta without start for x',
        '/http-401': 'Remote request failed (401)',
        '/http-500': 'Remote request failed (500)',
      };
      for (final entry in expectations.entries) {
        final transport = _transport(ctx, Uri.parse(server.url(entry.key)));
        final error = await ctx.expectThrows<RemoteProtocolException>(
          () => _drain(transport.send(_userConversation('x'))),
          entry.key,
        );
        ctx.expect(
          error.message.contains(entry.value),
          '${entry.key}: expected "${entry.value}" in "${error.message}"',
        );
      }
    },
  ),
  Check(
    id: 'unreachable-endpoint',
    feature: 'remote-errors',
    description:
        'Sending to a port nobody listens on fails with a transport error '
        '(not a protocol error), and the transport stays usable for the '
        'next send.',
    run: (ctx) async {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      final transport = _transport(
        ctx,
        Uri.parse('http://127.0.0.1:$deadPort/chat'),
      );
      final error = await ctx.expectThrows<Object>(
        () => _drain(transport.send(_userConversation('x'))),
        'unreachable',
      );
      ctx.observe('errorType', '${error.runtimeType}');
      ctx.expect(
        error is http.ClientException || error is SocketException,
        'expected a socket/client error, got ${error.runtimeType}: $error',
      );
      ctx.expect(error is! RemoteProtocolException, 'wrongly a protocol error');
      // A second send fails the same way instead of hanging or throwing
      // StateError.
      await ctx.expectThrows<Object>(
        () => _drain(transport.send(_userConversation('y'))),
        'second send',
      );
    },
  ),
  Check(
    id: 'cancellation',
    feature: 'remote-cancel',
    description:
        'Cancelling the subscription, cancelling a RemoteCancellationToken or '
        'disposing the transport aborts the in-flight HTTP request: the '
        'server sees the disconnect and no further snapshots arrive; a '
        'pre-cancelled token sends nothing.',
    run: (ctx) async {
      // A raw socket server: dart:io's HttpServer notices a vanished client
      // only on a failed write, so the check watches the socket itself.
      var requests = 0;
      var disconnects = 0;
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      ctx.onCleanup(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await listener.close();
      });
      listener.listen((socket) {
        sockets.add(socket);
        var open = true;
        var sawRequest = false;
        socket.listen(
          (_) async {
            if (sawRequest) return;
            sawRequest = true;
            requests++;
            socket.add(
              utf8.encode(
                'HTTP/1.1 200 OK\r\n'
                'Content-Type: text/event-stream\r\n'
                'X-Vercel-AI-UI-Message-Stream: v1\r\n'
                'Connection: keep-alive\r\n\r\n'
                'data: {"type":"start","messageId":"slow"}\r\n\r\n'
                'data: {"type":"text-start","id":"t"}\r\n\r\n',
              ),
            );
            while (open) {
              try {
                socket.add(
                  utf8.encode(
                    'data: {"type":"text-delta","id":"t","delta":"."}\r\n\r\n',
                  ),
                );
                await socket.flush();
              } catch (_) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 15));
            }
          },
          onDone: () {
            if (open) disconnects++;
            open = false;
          },
          onError: (Object _) {
            if (open) disconnects++;
            open = false;
          },
        );
      });
      final endpoint = Uri.parse('http://127.0.0.1:${listener.port}/chat');
      Future<void> waitForDisconnect(int expected, String what) async {
        final stopwatch = Stopwatch()..start();
        while (disconnects < expected) {
          if (stopwatch.elapsed > const Duration(seconds: 3)) {
            throw CheckFailure('server never saw the disconnect: $what');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      // 1. Cancel the subscription.
      final transport = _transport(ctx, endpoint);
      var snapshots = 0;
      final firstSnapshots = Completer<void>();
      final subscription = transport.send(_userConversation('a')).listen((_) {
        snapshots++;
        if (snapshots >= 2 && !firstSnapshots.isCompleted) {
          firstSnapshots.complete();
        }
      });
      await firstSnapshots.future.timeout(const Duration(seconds: 3));
      await subscription.cancel();
      await waitForDisconnect(1, 'subscription.cancel');
      final afterCancel = snapshots;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      ctx.expectEquals(snapshots, afterCancel, 'snapshots after cancel');

      // 2. Cancel through a token: the stream completes without an error.
      final token = RemoteCancellationToken();
      var tokenSnapshots = 0;
      final tokenDone = Completer<void>();
      Object? tokenError;
      transport
          .send(_userConversation('b'), cancellation: token)
          .listen(
            (_) {
              if (++tokenSnapshots == 2) token.cancel();
            },
            onError: (Object e) => tokenError = e,
            onDone: tokenDone.complete,
          );
      await tokenDone.future.timeout(const Duration(seconds: 3));
      await waitForDisconnect(2, 'token.cancel');
      ctx.expectEquals(tokenError, null, 'token cancellation error');
      ctx.expect(token.isCancelled, 'token not cancelled');

      // 3. A token cancelled before send never opens a request.
      final before = requests;
      final emptyDone = await _drain(
        transport.send(
          _userConversation('c'),
          cancellation: RemoteCancellationToken()..cancel(),
        ),
      );
      ctx.expectEquals(emptyDone.length, 0, 'snapshots from a cancelled token');
      ctx.expectEquals(requests, before, 'requests from a cancelled token');

      // 4. dispose() aborts the active request and refuses new sends.
      final disposable = RemoteConversationTransport(endpoint: endpoint);
      final disposed = Completer<void>();
      Object? disposeError;
      var disposeSnapshots = 0;
      disposable
          .send(_userConversation('d'))
          .listen(
            (_) {
              if (++disposeSnapshots == 2) disposable.dispose();
            },
            onError: (Object e) => disposeError = e,
            onDone: disposed.complete,
          );
      await disposed.future.timeout(const Duration(seconds: 3));
      await waitForDisconnect(3, 'dispose');
      ctx.observe('disposeError', '$disposeError');
      ctx.expect(
        disposeError == null || disposeError is RemoteCancelledException,
        'dispose surfaced $disposeError',
      );
      ctx.expect(
        (() {
          try {
            disposable.send(_userConversation('e'));
            return false;
          } on StateError {
            return true;
          }
        })(),
        'send after dispose must throw StateError',
      );
    },
  ),
  Check(
    id: 'injected-client-ownership',
    feature: 'remote-lifecycle',
    description:
        'An injected http.Client is used for the request and left open by '
        'dispose(), because the caller owns it.',
    run: (ctx) async {
      final server = await ctx.server((_) => _okStream(_helloEvents));
      final client = _CountingClient();
      ctx.onCleanup(() async => client.inner.close());
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse(server.url('/chat')),
        client: client,
      );
      final snapshots = await _drain(transport.send(_userConversation('x')));
      ctx.expectEquals(
        (snapshots.last.messages.last.parts.single as TextPart).text,
        'Hello',
        'text through the injected client',
      );
      ctx.expectEquals(client.sends, 1, 'requests through the client');
      transport.dispose();
      transport.dispose();
      ctx.expectEquals(client.closes, 0, 'injected client closed by dispose');
    },
  ),
]);

class _CountingClient extends http.BaseClient {
  final http.Client inner = http.Client();
  int sends = 0;
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sends++;
    return inner.send(request);
  }

  @override
  void close() => closes++;
}
