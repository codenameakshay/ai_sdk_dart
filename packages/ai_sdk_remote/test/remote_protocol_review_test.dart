import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'merges static and async authentication headers before dispatch',
    () async {
      late http.BaseRequest sent;
      final client = MockClient((request) async {
        sent = request;
        return _response(
          'data: {"type":"start"}\n\n'
          'data: {"type":"finish"}\n\n'
          'data: [DONE]\n\n',
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
        headers: const {'x-client': 'fixture', 'authorization': 'static-token'},
        authHeaders: () => const {
          'authorization': 'Bearer dynamic-token',
          'x-auth': 'auth-fixture',
        },
      );
      addTearDown(transport.dispose);
      addTearDown(client.close);

      await transport.send(Conversation(id: 'c1', messages: const [])).toList();

      expect(sent.headers['x-client'], 'fixture');
      expect(sent.headers['authorization'], 'Bearer dynamic-token');
      expect(sent.headers['x-auth'], 'auth-fixture');
      expect(sent.headers['accept'], 'text/event-stream');
      expect(sent.headers['x-vercel-ai-ui-message-stream'], 'v1');
    },
  );

  test('auth failure prevents HTTP dispatch', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
      authHeaders: () => throw StateError('auth fixture failed'),
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await expectLater(
      transport.send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(isA<StateError>()),
    );
    expect(requests, 0);
  });

  test('rejects an SSE object without an event type', () async {
    final client = MockClient((request) async {
      return _response(
        'data: {"message":"missing type"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await expectLater(
      transport.send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(isA<RemoteProtocolException>()),
    );
  });

  test('rejects tool output errors without error text', () async {
    final client = MockClient((request) async {
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"tool-input-available","toolCallId":"call-1",'
        '"toolName":"search","input":{"q":"dart"}}\n\n'
        'data: {"type":"tool-output-error","toolCallId":"call-1"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await expectLater(
      transport.send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(isA<RemoteProtocolException>()),
    );
  });

  test('serializes tool metadata using UI message history fields', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await transport.send(_toolHistory()).toList();

    final message = (body!['messages'] as List).single as Map;
    final part = (message['parts'] as List).single as Map;
    expect(part['input'], {'path': '/tmp/review'});
    expect(part['callProviderMetadata'], {
      'vendor': {'trace': 'call-1'},
    });
    expect(part['resultProviderMetadata'], {
      'vendor': {'trace': 'result-1'},
    });
    expect(part.containsKey('providerOptions'), isFalse);
  });

  test('serializes denied tool output with the UI denied state', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await transport.send(_deniedToolHistory()).toList();

    final message = (body!['messages'] as List).single as Map;
    final part = (message['parts'] as List).single as Map;
    expect(part['state'], 'output-denied');
    expect(part['input'], {'path': '/tmp/review'});
    expect(part['approval'], {
      'id': 'approval-1',
      'approved': false,
      'reason': 'user denied',
    });
    expect(part.containsKey('output'), isFalse);
    expect(part.containsKey('errorText'), isFalse);
    expect(part.containsKey('outputKind'), isFalse);
  });

  test('rejects non-text tool errors before dispatch', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await expectLater(
      transport.send(_errorToolHistory()).toList(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(requests, 0);
  });

  test(
    'maps stream provider metadata into conversation provider options',
    () async {
      final client = MockClient((request) async {
        return _response(
          'data: {"type":"start","messageId":"assistant-1"}\n\n'
          'data: {"type":"text-start","id":"text-1",'
          '"providerMetadata":{"vendor":{"segment":"answer"}}}\n\n'
          'data: {"type":"text-delta","id":"text-1","delta":"Hi"}\n\n'
          'data: {"type":"text-end","id":"text-1"}\n\n'
          'data: {"type":"tool-input-available","toolCallId":"call-1",'
          '"toolName":"search","input":{"q":"dart"},'
          '"providerMetadata":{"vendor":{"trace":"call-1"}}}\n\n'
          'data: {"type":"tool-output-available","toolCallId":"call-1",'
          '"output":{"ok":true},'
          '"providerMetadata":{"vendor":{"trace":"result-1"}}}\n\n'
          'data: {"type":"finish"}\n\n'
          'data: [DONE]\n\n',
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      addTearDown(transport.dispose);
      addTearDown(client.close);

      final snapshots = await transport
          .send(Conversation(id: 'c1', messages: const []))
          .toList();
      final parts = snapshots.last.messages.single.parts;
      expect((parts.whereType<TextPart>().single).providerOptions, {
        'vendor': {'segment': 'answer'},
      });
      expect((parts.whereType<ToolCallPart>().single).providerOptions, {
        'vendor': {'trace': 'call-1'},
      });
      expect((parts.whereType<ToolResultPart>().single).providerOptions, {
        'vendor': {'trace': 'result-1'},
      });
    },
  );

  test('retains approval response provider metadata', () async {
    final client = MockClient((request) async {
      return _response(
        'data: {"type":"start","messageId":"assistant-1"}\n\n'
        'data: {"type":"tool-input-available","toolCallId":"call-1",'
        '"toolName":"delete","input":{"path":"/tmp/a"}}\n\n'
        'data: {"type":"tool-approval-request","approvalId":"approval-1",'
        '"toolCallId":"call-1"}\n\n'
        'data: {"type":"tool-approval-response","approvalId":"approval-1",'
        '"approved":true,"providerMetadata":{"vendor":{"id":"m-1"}}}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    final snapshots = await transport
        .send(Conversation(id: 'c1', messages: const []))
        .toList();
    final approval = snapshots.last.messages.single.parts
        .whereType<ApprovalPart>()
        .single;
    expect(approval.metadata, {
      'vendor': {'id': 'm-1'},
    });
  });

  test('rejects denied output that has no preceding tool input', () async {
    final client = MockClient((request) async {
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"tool-output-denied","toolCallId":"missing"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await expectLater(
      transport.send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(isA<RemoteProtocolException>()),
    );
  });

  test('serializes an image part as a UI file part', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await transport
        .send(
          Conversation(
            id: 'c1',
            messages: [
              ConversationMessage(
                id: 'user-1',
                role: ConversationRole.user,
                parts: [
                  ImagePart(
                    id: 'image-1',
                    data: ConversationFileBytes(
                      Uint8List.fromList([0, 255, 128]),
                    ),
                    mimeType: 'image/png',
                  ),
                ],
              ),
            ],
          ),
        )
        .toList();

    final part = ((body!['messages'] as List).single as Map)['parts'] as List;
    expect(part.single, {
      'type': 'file',
      'url': 'data:image/png;base64,AP+A',
      'mediaType': 'image/png',
    });
  });

  test('rejects redacted reasoning before dispatch', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await expectLater(
      transport
          .send(
            Conversation(
              id: 'c1',
              messages: [
                ConversationMessage(
                  id: 'assistant-1',
                  role: ConversationRole.assistant,
                  parts: [
                    RedactedReasoningPart(
                      id: 'reasoning-1',
                      data: Uint8List.fromList([1, 2, 3]),
                    ),
                  ],
                ),
              ],
            ),
          )
          .toList(),
      throwsA(isA<UnsupportedError>()),
    );
    expect(requests, 0);
  });

  test(
    'preserves lifecycle metadata and dynamic tools across replay',
    () async {
      final requestBodies = <Map<String, dynamic>>[];
      var requestCount = 0;
      final client = MockClient((request) async {
        requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        requestCount++;
        if (requestCount == 1) {
          return _response(
            'data: {"type":"start","messageId":"assistant-1"}\n\n'
            'data: {"type":"text-start","id":"text-1",'
            '"providerMetadata":{"vendor":{"start":true,"keep":true,'
            '"nested":{"start":true}}}}\n\n'
            'data: {"type":"text-delta","id":"text-1","delta":"Hi",'
            '"providerMetadata":{"vendor":{"delta":true,'
            '"nested":{"delta":true}}}}\n\n'
            'data: {"type":"text-end","id":"text-1",'
            '"providerMetadata":{"vendor":{"end":true,'
            '"nested":{"end":true}}}}\n\n'
            'data: {"type":"reasoning-start","id":"reasoning-1",'
            '"providerMetadata":{"vendor":{"start":true}}}\n\n'
            'data: {"type":"reasoning-delta","id":"reasoning-1",'
            '"delta":"Think",'
            '"providerMetadata":{"vendor":{"delta":true}}}\n\n'
            'data: {"type":"reasoning-end","id":"reasoning-1",'
            '"providerMetadata":{"vendor":{"end":true}}}\n\n'
            'data: {"type":"tool-input-start","toolCallId":"call-1",'
            '"toolName":"lookup","dynamic":true,"providerExecuted":true,'
            '"providerMetadata":{"vendor":{"start":true}}}\n\n'
            'data: {"type":"tool-input-available","toolCallId":"call-1",'
            '"toolName":"lookup","dynamic":true,"input":{"q":"dart"},'
            '"providerMetadata":{"vendor":{"available":true}}}\n\n'
            'data: {"type":"tool-output-available","toolCallId":"call-1",'
            '"toolName":"lookup","dynamic":true,"output":{"ok":true},'
            '"providerMetadata":{"vendor":{"result":true}}}\n\n'
            'data: {"type":"finish"}\n\n'
            'data: [DONE]\n\n',
          );
        }
        return _response(
          'data: {"type":"start"}\n\n'
          'data: {"type":"finish"}\n\n'
          'data: [DONE]\n\n',
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      addTearDown(transport.dispose);
      addTearDown(client.close);

      final snapshots = await transport
          .send(Conversation(id: 'c1', messages: const []))
          .toList();
      final finalConversation = snapshots.last;
      final text = finalConversation.messages.single.parts
          .whereType<TextPart>()
          .single;
      final reasoning = finalConversation.messages.single.parts
          .whereType<ReasoningPart>()
          .single;
      final call = finalConversation.messages.single.parts
          .whereType<ToolCallPart>()
          .single;
      final result = finalConversation.messages.single.parts
          .whereType<ToolResultPart>()
          .single;
      expect(text.providerOptions, {
        'vendor': {
          'start': true,
          'keep': true,
          'delta': true,
          'end': true,
          'nested': {'start': true, 'delta': true, 'end': true},
        },
      });
      expect(reasoning.providerOptions, {
        'vendor': {'start': true, 'delta': true, 'end': true},
      });
      expect(call.providerExecuted, isTrue);
      expect(call.extra['dynamic'], isTrue);
      expect(call.providerOptions, {
        'vendor': {'start': true, 'available': true},
      });
      expect(result.isDynamic, isTrue);

      await transport.send(finalConversation).toList();
      final assistant = (requestBodies[1]['messages'] as List).single as Map;
      final parts = assistant['parts'] as List;
      expect(parts[0]['providerMetadata']['vendor'], {
        'start': true,
        'keep': true,
        'delta': true,
        'end': true,
        'nested': {'start': true, 'delta': true, 'end': true},
      });
      expect(parts[1]['providerMetadata']['vendor'], {
        'start': true,
        'delta': true,
        'end': true,
      });
      expect(parts[2], {
        'type': 'dynamic-tool',
        'toolCallId': 'call-1',
        'toolName': 'lookup',
        'state': 'output-available',
        'input': {'q': 'dart'},
        'providerExecuted': true,
        'callProviderMetadata': {
          'vendor': {'start': true, 'available': true},
        },
        'resultProviderMetadata': {
          'vendor': {'result': true},
        },
        'output': {'ok': true},
      });
    },
  );

  test(
    'reduces control, source, file, and tool input protocol events',
    () async {
      final client = MockClient((request) async {
        return _response(
          'data: {"type":"start","messageId":"assistant-1",'
          '"messageMetadata":{"phase":"one"}}\n\n'
          'data: {"type":"tool-input-start","toolCallId":"call-1",'
          '"toolName":"search"}\n\n'
          'data: {"type":"tool-input-delta","toolCallId":"call-1",'
          '"inputTextDelta":"{\\"q\\":\\"dart\\"}"}\n\n'
          'data: {"type":"tool-input-error","toolCallId":"call-1",'
          '"toolName":"search","input":{},"errorText":"bad input"}\n\n'
          'data: {"type":"tool-approval-request","approvalId":"approval-1",'
          '"toolCallId":"call-1"}\n\n'
          'data: {"type":"tool-approval-response","approvalId":"approval-1",'
          '"approved":false,"reason":"policy"}\n\n'
          'data: {"type":"source-url","sourceId":"source-1",'
          '"url":"https://example.test/source","title":"Source"}\n\n'
          'data: {"type":"source-document","sourceId":"document-1",'
          '"mediaType":"text/plain","title":"Document",'
          '"filename":"document.txt"}\n\n'
          'data: {"type":"file","mediaType":"image/png",'
          '"data":{"kind":"bytes","base64":"AQI="},"filename":"a.png"}\n\n'
          'data: {"type":"file","mediaType":"text/plain",'
          '"data":{"kind":"provider_reference","namespace":"vendor",'
          '"id":"file-1"}}\n\n'
          'data: {"type":"reasoning-file","mediaType":"text/plain",'
          '"url":"data:text/plain,hello","filename":"trace.txt"}\n\n'
          'data: {"type":"message-metadata","messageMetadata":'
          '{"phase":"two"}}\n\n'
          'data: {"type":"vendor-event","value":3}\n\n'
          'data: {"type":"start-step"}\n\n'
          'data: {"type":"finish-step"}\n\n'
          'data: {"type":"reset-step"}\n\n'
          'data: {"type":"text-start","id":"text-1"}\n\n'
          'data: {"type":"text-delta","id":"text-1","delta":"done"}\n\n'
          'data: {"type":"text-end","id":"text-1"}\n\n'
          'data: {"type":"abort"}\n\n'
          'data: [DONE]\n\n',
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      addTearDown(transport.dispose);
      addTearDown(client.close);

      final snapshots = await transport
          .send(Conversation(id: 'c1', messages: const []))
          .toList();
      final message = snapshots.last.messages.single;
      expect(message.status, ConversationMessageStatus.interrupted);
      expect(message.metadata, {'phase': 'two'});
      expect(message.parts.whereType<TextPart>().single.text, 'done');
    },
  );

  test('serializes source and reasoning file history fields', () async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return _response(
        'data: {"type":"start"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    await transport
        .send(
          Conversation(
            id: 'history',
            messages: [
              ConversationMessage(
                id: 'assistant-1',
                role: ConversationRole.assistant,
                parts: [
                  FilePart(
                    id: 'file-1',
                    data: ConversationFileBytes(Uint8List.fromList([1, 2])),
                    mimeType: 'application/octet-stream',
                    name: 'bytes.bin',
                    providerOptions: {
                      'vendor': {'file': true},
                    },
                  ),
                  ReasoningFilePart(
                    id: 'reasoning-file-1',
                    data: ConversationFileBytes(Uint8List.fromList([3, 4])),
                    mimeType: 'application/octet-stream',
                    name: 'trace.bin',
                    providerOptions: {
                      'vendor': {'reasoning': true},
                    },
                  ),
                  SourcePart(
                    id: 'source-1',
                    uri: 'https://example.test/source',
                    title: 'Source',
                    providerMetadata: {
                      'vendor': {'source': true},
                    },
                  ),
                  DocumentSourcePart(
                    id: 'document-1',
                    mediaType: 'text/plain',
                    title: 'Document',
                    name: 'document.txt',
                    providerMetadata: {
                      'vendor': {'document': true},
                    },
                  ),
                  UnknownPart(
                    id: 'unknown-1',
                    type: 'future-part',
                    raw: {'id': 'unknown-1', 'type': 'future-part', 'value': 1},
                  ),
                ],
              ),
            ],
          ),
        )
        .toList();

    final parts = ((body!['messages'] as List).single as Map)['parts'] as List;
    expect(parts[0]['providerMetadata'], {
      'vendor': {'file': true},
    });
    expect(parts[0]['filename'], 'bytes.bin');
    expect(parts[1]['type'], 'reasoning-file');
    expect(parts[1]['filename'], 'trace.bin');
    expect(parts[1]['providerMetadata'], {
      'vendor': {'reasoning': true},
    });
    expect(parts[2]['providerMetadata'], {
      'vendor': {'source': true},
    });
    expect(parts[3]['providerMetadata'], {
      'vendor': {'document': true},
    });
    expect(parts[4], {'id': 'unknown-1', 'type': 'future-part', 'value': 1});
  });

  test('replays a pending dynamic tool as dynamic-tool', () async {
    Map<String, dynamic>? body;
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      if (requestCount == 2) {
        body = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return _response(
        requestCount == 1
            ? 'data: {"type":"start","messageId":"assistant-1"}\n\n'
                  'data: {"type":"tool-input-start",'
                  '"toolCallId":"call-1","toolName":"mcp_lookup",'
                  '"dynamic":true}\n\n'
                  'data: {"type":"tool-input-available",'
                  '"toolCallId":"call-1","toolName":"mcp_lookup",'
                  '"dynamic":true,"input":{"q":"dart"}}\n\n'
                  'data: {"type":"tool-approval-request",'
                  '"approvalId":"approval-1","toolCallId":"call-1"}\n\n'
                  'data: {"type":"finish"}\n\n'
                  'data: [DONE]\n\n'
            : 'data: {"type":"start"}\n\n'
                  'data: {"type":"finish"}\n\n'
                  'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    final snapshots = await transport
        .send(Conversation(id: 'c1', messages: const []))
        .toList();
    await transport.send(snapshots.last).toList();

    final part =
        (((body!['messages'] as List).single as Map)['parts'] as List).single
            as Map;
    expect(part['type'], 'dynamic-tool');
    expect(part['toolName'], 'mcp_lookup');
    expect(part['state'], 'approval-requested');
  });

  test(
    'reset-step removes only the current step after pending approval',
    () async {
      final client = MockClient((request) async {
        return _response(
          'data: {"type":"start","messageId":"assistant-1"}\n\n'
          'data: {"type":"text-start","id":"prior-text"}\n\n'
          'data: {"type":"text-delta","id":"prior-text",'
          '"delta":"prior"}\n\n'
          'data: {"type":"text-end","id":"prior-text"}\n\n'
          'data: {"type":"start-step"}\n\n'
          'data: {"type":"tool-input-available","toolCallId":"call-1",'
          '"toolName":"delete","input":{"path":"/tmp/a"}}\n\n'
          'data: {"type":"tool-approval-request",'
          '"approvalId":"approval-1","toolCallId":"call-1"}\n\n'
          'data: {"type":"reset-step"}\n\n'
          'data: {"type":"text-start","id":"next-text"}\n\n'
          'data: {"type":"text-delta","id":"next-text",'
          '"delta":"next"}\n\n'
          'data: {"type":"text-end","id":"next-text"}\n\n'
          'data: {"type":"finish"}\n\n'
          'data: [DONE]\n\n',
        );
      });
      final transport = RemoteConversationTransport(
        endpoint: Uri.parse('https://backend.test/chat'),
        client: client,
      );
      addTearDown(transport.dispose);
      addTearDown(client.close);

      final conversation =
          (await transport
                  .send(Conversation(id: 'c1', messages: const []))
                  .toList())
              .last;
      final message = conversation.messages.single;
      expect(message.status, ConversationMessageStatus.complete);
      expect(message.parts.whereType<ToolCallPart>(), isEmpty);
      expect(message.parts.whereType<ApprovalPart>(), isEmpty);
      expect(message.parts.whereType<TextPart>().map((part) => part.text), [
        'prior',
        'next',
      ]);
    },
  );

  test('reset-step rejects a stale text update from a retained step', () async {
    await _expectSendError(
      'data: {"type":"start","messageId":"assistant-1"}\n\n'
      'data: {"type":"text-start","id":"prior-text"}\n\n'
      'data: {"type":"text-delta","id":"prior-text",'
      '"delta":"prior"}\n\n'
      'data: {"type":"text-end","id":"prior-text"}\n\n'
      'data: {"type":"start-step"}\n\n'
      'data: {"type":"text-start","id":"current-text"}\n\n'
      'data: {"type":"text-delta","id":"current-text",'
      '"delta":"current"}\n\n'
      'data: {"type":"reset-step"}\n\n'
      'data: {"type":"text-delta","id":"prior-text",'
      '"delta":"late"}\n\n'
      'data: {"type":"finish"}\n\n'
      'data: [DONE]\n\n',
      isA<RemoteProtocolException>(),
    );
  });

  test('reset-step resumes a failed step before the next finish', () async {
    final client = MockClient((request) async {
      return _response(
        'data: {"type":"start","messageId":"assistant-1"}\n\n'
        'data: {"type":"error","errorText":"retryable"}\n\n'
        'data: {"type":"reset-step"}\n\n'
        'data: {"type":"text-start","id":"retry-text"}\n\n'
        'data: {"type":"text-delta","id":"retry-text",'
        '"delta":"retried"}\n\n'
        'data: {"type":"text-end","id":"retry-text"}\n\n'
        'data: {"type":"finish"}\n\n'
        'data: [DONE]\n\n',
      );
    });
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://backend.test/chat'),
      client: client,
    );
    addTearDown(transport.dispose);
    addTearDown(client.close);

    final conversation =
        (await transport
                .send(Conversation(id: 'c1', messages: const []))
                .toList())
            .last;
    final message = conversation.messages.single;
    expect(message.status, ConversationMessageStatus.complete);
    expect(message.parts.whereType<TextPart>().single.text, 'retried');
  });

  test('pinned server resumes an approved tool continuation', () async {
    final endpoint = _pinnedEndpoint();
    if (endpoint == null) {
      markTestSkipped('Set AI_SDK_REMOTE_REFERENCE_URL for the pinned server');
      return;
    }
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse(endpoint),
    );
    addTearDown(transport.dispose);

    final snapshots = await transport.send(_approvedToolHistory()).toList();
    final message = snapshots.last.messages
        .where((item) => item.id == 'js-example-assistant')
        .single;
    expect(message.status, ConversationMessageStatus.complete);
    expect(
      (message.parts.whereType<TextPart>().single).text,
      'The scripted tool call was approved and resumed.',
    );
    expect(message.parts.whereType<ToolResultPart>(), hasLength(1));
  });

  test('pinned server accepts a denied tool history', () async {
    final endpoint = _pinnedEndpoint();
    if (endpoint == null) {
      markTestSkipped('Set AI_SDK_REMOTE_REFERENCE_URL for the pinned server');
      return;
    }
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse(endpoint),
    );
    addTearDown(transport.dispose);

    final snapshots = await transport.send(_deniedToolHistory()).toList();
    final message = snapshots.last.messages
        .where((item) => item.id == 'js-example-assistant')
        .single;
    expect(message.status, ConversationMessageStatus.complete);
    expect(
      (message.parts.whereType<TextPart>().single).text,
      'The scripted tool call was denied and resumed safely.',
    );
  });

  test('pinned server accepts a text tool error history', () async {
    final endpoint = _pinnedEndpoint();
    if (endpoint == null) {
      markTestSkipped('Set AI_SDK_REMOTE_REFERENCE_URL for the pinned server');
      return;
    }
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse(endpoint),
    );
    addTearDown(transport.dispose);

    final snapshots = await transport.send(_errorTextToolHistory()).toList();
    final message = snapshots.last.messages
        .where((item) => item.id == 'js-example-assistant')
        .single;
    expect(message.status, ConversationMessageStatus.pendingApproval);
    expect(message.parts.whereType<ToolCallPart>(), hasLength(1));
    expect(message.parts.whereType<ApprovalPart>(), hasLength(1));
  });

  test('rejects invalid lifecycle and approval ordering', () async {
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"text-delta","id":"missing","delta":"x"}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"text-start","id":"text-1"}\n\n'
      'data: {"type":"reasoning-delta","id":"text-1","delta":"x"}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"text-start","id":"text-1"}\n\n'
      'data: {"type":"text-end","id":"text-1"}\n\n'
      'data: {"type":"text-delta","id":"text-1","delta":"late"}\n\n'
      'data: {"type":"finish"}\n\n'
      'data: [DONE]\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"text-start","id":"text-1"}\n\n'
      'data: {"type":"text-end","id":"text-1"}\n\n'
      'data: {"type":"text-end","id":"text-1"}\n\n'
      'data: {"type":"finish"}\n\n'
      'data: [DONE]\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"text-end","id":"missing"}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"tool-approval-request",'
      '"approvalId":"approval-1","toolCallId":"missing"}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"tool-input-available","toolCallId":"call-1",'
      '"toolName":"search","input":{}}\n\n'
      'data: {"type":"tool-approval-response",'
      '"approvalId":"unknown","approved":true}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"tool-input-available","toolCallId":"call-1",'
      '"toolName":"search","input":{}}\n\n'
      'data: {"type":"tool-approval-request",'
      '"approvalId":"approval-1","toolCallId":"call-1"}\n\n'
      'data: {"type":"tool-approval-response",'
      '"approvalId":"approval-1","approved":true}\n\n'
      'data: {"type":"reset-step"}\n\n'
      'data: {"type":"tool-approval-response",'
      '"approvalId":"approval-1","approved":true}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"tool-output-available",'
      '"toolCallId":"missing","output":{}}\n\n',
      isA<RemoteProtocolException>(),
    );
  });

  test('rejects unsupported file representations before dispatch', () async {
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"file","mediaType":"text/plain",'
      '"data":{"kind":"provider_reference"}}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"file","mediaType":"text/plain",'
      '"data":{"kind":"bytes","base64":"%%%"}}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"file","mediaType":"text/plain",'
      '"data":{"kind":"other"}}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"file","mediaType":"text/plain",'
      '"url":"data:text/plain"}\n\n',
      isA<RemoteProtocolException>(),
    );
  });

  test('rejects unsupported outgoing history states', () async {
    await _expectHistoryError(
      Conversation(
        id: 'c1',
        messages: [
          ConversationMessage(
            id: 'user-1',
            role: ConversationRole.user,
            parts: [
              FilePart(
                id: 'file-1',
                data: ConversationFileProviderReference(
                  namespace: 'vendor',
                  id: 'opaque',
                ),
                mimeType: 'text/plain',
              ),
            ],
          ),
        ],
      ),
      isA<UnsupportedError>(),
    );
    await _expectHistoryError(
      Conversation(
        id: 'c1',
        messages: [
          ConversationMessage(
            id: 'user-1',
            role: ConversationRole.user,
            parts: [
              ImagePart(
                id: 'image-1',
                data: ConversationFileProviderReference(
                  namespace: 'vendor',
                  id: 'opaque',
                ),
                mimeType: 'image/png',
              ),
            ],
          ),
        ],
      ),
      isA<UnsupportedError>(),
    );
    await _expectHistoryError(
      Conversation(
        id: 'c1',
        messages: [
          ConversationMessage(
            id: 'assistant-1',
            role: ConversationRole.assistant,
            parts: [
              ImagePart(
                id: 'image-1',
                data: ConversationFileBytes(Uint8List.fromList([1])),
                mimeType: null,
              ),
            ],
          ),
        ],
      ),
      isA<UnsupportedError>(),
    );
    await _expectHistoryError(
      Conversation(
        id: 'c1',
        messages: [
          ConversationMessage(
            id: 'assistant-1',
            role: ConversationRole.assistant,
            parts: [
              ToolCallPart(
                id: 'call-1',
                callId: 'call-1',
                name: 'delete',
                arguments: {'path': '/tmp/a'},
              ),
              ToolResultPart(
                id: 'result-1',
                callId: 'call-1',
                output: null,
                isError: true,
                outputKind: 'execution_denied',
              ),
            ],
          ),
        ],
      ),
      isA<UnsupportedError>(),
    );
  });

  test('rejects truncated and mismatched text streams', () async {
    await _expectSendError(
      'data: {"type":"start"}\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"reasoning-start","id":"reasoning-1"}\n\n'
      'data: {"type":"text-end","id":"reasoning-1"}\n\n',
      isA<RemoteProtocolException>(),
    );
    await _expectSendError(
      'data: {"type":"start"}\n\n'
      'data: {"type":"file","mediaType":"text/plain",'
      '"url":"data:text/plain;base64,%%%"}\n\n',
      isA<RemoteProtocolException>(),
    );
  });

  test('exposes cancellation and protocol exception descriptions', () async {
    final token = RemoteCancellationToken();
    expect(token.isCancelled, isFalse);
    final cancelled = token.whenCancelled;
    token.cancel();
    await cancelled;
    expect(token.isCancelled, isTrue);
    expect(const RemoteProtocolException('bad').toString(), contains('bad'));
    expect(
      const RemoteCancelledException().toString(),
      'RemoteCancelledException',
    );
    await token.dispose();
  });
}

String? _pinnedEndpoint() =>
    Platform.environment['AI_SDK_REMOTE_REFERENCE_URL'];

http.Response _response(String body) => http.Response(
  body,
  200,
  headers: const {
    'x-vercel-ai-ui-message-stream': 'v1',
    'content-type': 'text/event-stream',
  },
);

Future<void> _expectSendError(String body, Matcher matcher) async {
  final client = MockClient((request) async => _response(body));
  final transport = RemoteConversationTransport(
    endpoint: Uri.parse('https://backend.test/chat'),
    client: client,
  );
  try {
    await expectLater(
      transport.send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(matcher),
    );
  } finally {
    transport.dispose();
    client.close();
  }
}

Future<void> _expectHistoryError(
  Conversation conversation,
  Matcher matcher,
) async {
  final client = MockClient(
    (request) async => _response(
      'data: {"type":"start"}\n\n'
      'data: {"type":"finish"}\n\n'
      'data: [DONE]\n\n',
    ),
  );
  final transport = RemoteConversationTransport(
    endpoint: Uri.parse('https://backend.test/chat'),
    client: client,
  );
  try {
    await expectLater(transport.send(conversation).toList(), throwsA(matcher));
  } finally {
    transport.dispose();
    client.close();
  }
}

Conversation _toolHistory() => Conversation(
  id: 'history',
  messages: [
    ConversationMessage(
      id: 'assistant-history',
      role: ConversationRole.assistant,
      parts: [
        ToolCallPart(
          id: 'call-part',
          callId: 'call-1',
          name: 'search',
          arguments: {'path': '/tmp/review'},
          providerOptions: {
            'vendor': {'trace': 'call-1'},
          },
        ),
        ToolResultPart(
          id: 'result-part',
          callId: 'call-1',
          output: {'ok': true},
          providerOptions: {
            'vendor': {'trace': 'result-1'},
          },
        ),
      ],
    ),
  ],
);

Conversation _approvedToolHistory() => Conversation(
  id: 'continuation',
  messages: [
    ConversationMessage(
      id: 'assistant-history',
      role: ConversationRole.assistant,
      parts: [
        ToolCallPart(
          id: 'call-part',
          callId: 'call-1',
          name: 'delete',
          arguments: {'path': '/tmp/reference'},
        ),
        ApprovalPart(
          id: 'approval-part',
          callId: 'call-1',
          approvalId: 'js-approval-1',
          status: ApprovalStatus.approved,
        ),
        ToolResultPart(
          id: 'result-part',
          callId: 'call-1',
          output: {'ok': true, 'path': '/tmp/reference'},
        ),
      ],
    ),
  ],
);

Conversation _deniedToolHistory() => Conversation(
  id: 'denied',
  messages: [
    ConversationMessage(
      id: 'assistant-history',
      role: ConversationRole.assistant,
      parts: [
        ToolCallPart(
          id: 'call-part',
          callId: 'call-1',
          name: 'delete',
          arguments: {'path': '/tmp/review'},
        ),
        ApprovalPart(
          id: 'approval-part',
          callId: 'call-1',
          approvalId: 'approval-1',
          status: ApprovalStatus.rejected,
          extra: {'reason': 'user denied'},
        ),
        ToolResultPart(
          id: 'result-part',
          callId: 'call-1',
          output: null,
          isError: true,
          outputKind: 'execution_denied',
        ),
      ],
    ),
  ],
);

Conversation _errorToolHistory() => Conversation(
  id: 'error',
  messages: [
    ConversationMessage(
      id: 'assistant-history',
      role: ConversationRole.assistant,
      parts: [
        ToolCallPart(
          id: 'call-part',
          callId: 'call-1',
          name: 'search',
          arguments: {'q': 'dart'},
        ),
        ToolResultPart(
          id: 'result-part',
          callId: 'call-1',
          output: {'message': 'bad'},
          isError: true,
          outputKind: 'error_json',
        ),
      ],
    ),
  ],
);

Conversation _errorTextToolHistory() => Conversation(
  id: 'error-text',
  messages: [
    ConversationMessage(
      id: 'assistant-history',
      role: ConversationRole.assistant,
      parts: [
        ToolCallPart(
          id: 'call-part',
          callId: 'call-1',
          name: 'search',
          arguments: {'q': 'dart'},
        ),
        ToolResultPart(
          id: 'result-part',
          callId: 'call-1',
          output: 'search failed',
          isError: true,
          outputKind: 'error_text',
        ),
      ],
    ),
  ],
);
