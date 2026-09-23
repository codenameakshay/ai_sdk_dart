import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri endpoint;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://${server.address.host}:${server.port}/chat');
  });

  tearDown(() => server.close(force: true));

  test('reduces split UTF-8 SSE frames and invokes auth per request', () async {
    var authCalls = 0;
    server.listen((request) async {
      expect(request.headers.value('authorization'), 'Bearer token');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
      final events = [
        {'type': 'start', 'messageId': 'assistant-1'},
        {'type': 'text-start', 'id': 'text-1'},
        {'type': 'text-delta', 'id': 'text-1', 'delta': 'Hi '},
        {'type': 'text-delta', 'id': 'text-1', 'delta': '🌍'},
        {'type': 'text-end', 'id': 'text-1'},
        {'type': 'finish'},
      ];
      for (final event in events) {
        final encoded = utf8.encode('data: ${jsonEncode(event)}\r\n\r\n');
        for (final byte in encoded) {
          request.response.add([byte]);
          await Future<void>.delayed(Duration.zero);
        }
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final transport = RemoteConversationTransport(
      endpoint: endpoint,
      authHeaders: () {
        authCalls++;
        return {'authorization': 'Bearer token'};
      },
    );
    final snapshots = await transport
        .send(Conversation(id: 'c1', messages: const []))
        .toList();
    transport.dispose();

    expect(authCalls, 1);
    expect(snapshots.last.messages.single.id, 'assistant-1');
    expect(
      (snapshots.last.messages.single.parts.single as TextPart).text,
      'Hi 🌍',
    );
    expect(
      snapshots.last.messages.single.status,
      ConversationMessageStatus.complete,
    );
  });

  test('maps tool approval and output without executing anything', () async {
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
      final events = [
        {'type': 'start', 'messageId': 'assistant-1'},
        {
          'type': 'tool-input-available',
          'toolCallId': 'call-1',
          'toolName': 'delete',
          'input': {'path': '/tmp/a'},
        },
        {
          'type': 'tool-approval-request',
          'approvalId': 'approval-1',
          'toolCallId': 'call-1',
        },
        {
          'type': 'tool-approval-response',
          'approvalId': 'approval-1',
          'approved': true,
        },
        {
          'type': 'tool-output-available',
          'toolCallId': 'call-1',
          'output': {'ok': true},
        },
        {
          'type': 'tool-output-available',
          'toolCallId': 'call-1',
          'output': {'ok': true},
        },
        {
          'type': 'source-url',
          'sourceId': 'source-1',
          'url': 'https://example.test/a',
        },
        {
          'type': 'source-url',
          'sourceId': 'source-1',
          'url': 'https://example.test/a',
        },
        {
          'type': 'data-weather',
          'data': {'temperature': 20},
        },
        {'type': 'finish'},
      ];
      for (final event in events) {
        request.response.write('data: ${jsonEncode(event)}\n\n');
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final snapshots = await RemoteConversationTransport(
      endpoint: endpoint,
    ).send(Conversation(id: 'c1', messages: const [])).toList();
    final parts = snapshots.last.messages.single.parts;
    expect(parts.whereType<ToolCallPart>().single.arguments, {
      'path': '/tmp/a',
    });
    expect(
      parts.whereType<ApprovalPart>().single.status,
      ApprovalStatus.approved,
    );
    expect(parts.whereType<ToolResultPart>().single.output, {'ok': true});
    expect(parts.whereType<SourcePart>(), hasLength(1));
    final unknown = parts.whereType<UnknownPart>().single;
    expect(unknown.raw['data'], {'temperature': 20});
  });

  test('retains typed files, document sources, opaque frames, and result flags', () async {
    server.listen((request) async {
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
      final events = [
        {'type': 'start', 'messageId': 'assistant-lossless'},
        {
          'type': 'tool-input-available',
          'toolCallId': 'call-json',
          'toolName': 'search',
          'input': {'q': 'dart'},
          'providerExecuted': true,
          'providerOptions': {'vendor': {'trace': 't-1'}},
        },
        {
          'type': 'tool-output-available',
          'toolCallId': 'call-json',
          'toolName': 'search',
          'output': {'ok': true},
          'outputKind': 'json',
          'preliminary': true,
          'isDynamic': true,
          'providerOptions': {'vendor': {'requestId': 'r-1'}},
        },
        {
          'type': 'tool-input-available',
          'toolCallId': 'call-denied',
          'toolName': 'delete',
          'input': {'path': '/tmp/a'},
        },
        {
          'type': 'tool-output-denied',
          'toolCallId': 'call-denied',
          'toolName': 'delete',
          'reason': 'Needs approval',
          'approvalId': 'approval-9',
        },
        {
          'type': 'source-document',
          'sourceId': 'doc-1',
          'mediaType': 'application/pdf',
          'title': 'Research paper',
          'filename': 'paper.pdf',
          'providerMetadata': {'vendor': {'documentId': 'doc-7'}},
        },
        {
          'type': 'reasoning-file',
          'url': 'data:application/octet-stream;base64,AAH/',
          'mediaType': 'application/octet-stream',
          'providerOptions': {'vendor': {'encrypted': true}},
        },
        {
          'type': 'opaque',
          'provider': 'vendor-x',
          'raw': ['scalar', 7, true],
          'id': 'opaque-1',
        },
        {'type': 'finish'},
      ];
      for (final event in events) {
        request.response.write('data: ${jsonEncode(event)}\n\n');
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final conversation = (await RemoteConversationTransport(endpoint: endpoint)
            .send(Conversation(id: 'c1', messages: const []))
            .toList())
        .last;
    final parts = conversation.messages.single.parts;
    final call = parts.whereType<ToolCallPart>().first;
    expect(call.providerExecuted, isTrue);
    expect(call.providerOptions['vendor'], {'trace': 't-1'});
    final result = parts
        .whereType<ToolResultPart>()
        .firstWhere((part) => part.callId == 'call-json');
    expect(result.output, {'ok': true});
    expect(result.preliminary, isTrue);
    expect(result.isDynamic, isTrue);
    expect(result.providerOptions['vendor'], {'requestId': 'r-1'});
    final denied = parts
        .whereType<ToolResultPart>()
        .firstWhere((part) => part.callId == 'call-denied');
    expect(denied.outputKind, 'execution_denied');
    expect(denied.executionDeniedReason, 'Needs approval');
    expect(denied.executionDeniedApprovalId, 'approval-9');
    final doc = parts.whereType<DocumentSourcePart>().single;
    expect(doc.providerMetadata['vendor'], {'documentId': 'doc-7'});
    final reasoning = parts.whereType<ReasoningFilePart>().single;
    expect((reasoning.data! as ConversationFileBytes).bytes, [0, 1, 255]);
    expect(reasoning.providerOptions['vendor'], {'encrypted': true});
    final opaque = parts.whereType<UnknownPart>().single;
    expect(opaque.raw['provider'], 'vendor-x');
    expect(opaque.raw['raw'], ['scalar', 7, true]);
  });

  test('rejects bad headers and truncated streams', () async {
    server.listen((request) async {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      await request.response.close();
    });
    expect(
      () => RemoteConversationTransport(
        endpoint: endpoint,
      ).send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(isA<RemoteProtocolException>()),
    );
  });

  test(
    'consumes frames emitted by the pinned ai 7.0.111 reference server',
    () async {
      final value = Platform.environment['AI_SDK_REMOTE_REFERENCE_URL'];
      if (value == null) {
        markTestSkipped(
          'Set AI_SDK_REMOTE_REFERENCE_URL to run the JS reference server',
        );
        return;
      }
      final snapshots =
          await RemoteConversationTransport(endpoint: Uri.parse(value))
              .send(
                Conversation(
                  id: 'c1',
                  messages: [
                    ConversationMessage(
                      id: 'user-1',
                      role: ConversationRole.user,
                      parts: [TextPart(id: 'text-1', text: 'Hello')],
                    ),
                  ],
                ),
              )
              .toList();
      final message = snapshots.last.messages
          .where((item) => item.id == 'js-example-assistant')
          .single;
      expect(message.id, 'js-example-assistant');
      expect(message.status, ConversationMessageStatus.complete);
      expect(
        (message.parts.single as TextPart).text,
        'Hello from the pinned AI SDK backend.',
      );
    },
  );

  test(
    'sends validated UI tool and approval history to the reference server',
    () async {
      final value = Platform.environment['AI_SDK_REMOTE_REFERENCE_URL'];
      if (value == null) {
        markTestSkipped(
          'Set AI_SDK_REMOTE_REFERENCE_URL to run the JS reference server',
        );
        return;
      }
      final snapshots =
          await RemoteConversationTransport(endpoint: Uri.parse(value))
              .send(
                Conversation(
                  id: 'c1',
                  messages: [
                    ConversationMessage(
                      id: 'assistant-history',
                      role: ConversationRole.assistant,
                      parts: [
                        ToolCallPart(
                          id: 'call-part',
                          callId: 'call-1',
                          name: 'delete',
                          arguments: {'path': '/tmp/history'},
                        ),
                        ApprovalPart(
                          id: 'approval-part',
                          callId: 'call-1',
                          status: ApprovalStatus.pending,
                        ),
                      ],
                    ),
                  ],
                ),
              )
              .toList();
      final message = snapshots.last.messages
          .where((item) => item.id == 'js-example-assistant')
          .single;
      expect(message.status, ConversationMessageStatus.pendingApproval);
      expect(message.parts.whereType<ToolCallPart>(), hasLength(1));
      expect(
        message.parts.whereType<ApprovalPart>().single.status,
        ApprovalStatus.pending,
      );
    },
  );

  test('cancellation interrupts waiting headers and active streams', () async {
    final keepAlive = List.filled(65536, 'x').join();
    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      request.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1')
        ..headers.set('connection', 'close');
      try {
        for (var i = 0; i < 100; i++) {
          request.response.write(
            i == 0 ? 'data: {"type":"start"}\n\n' : ': $keepAlive\n\n',
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      } catch (_) {}
    });
    final token = RemoteCancellationToken();
    final pending = RemoteConversationTransport(endpoint: endpoint)
        .send(
          Conversation(id: 'c1', messages: const []),
          cancellation: token,
        )
        .toList();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    token.cancel();
    await expectLater(pending, throwsA(isA<RemoteCancelledException>()));
    await token.dispose();

    final activeToken = RemoteCancellationToken();
    final snapshots = <Conversation>[];
    final stopwatch = Stopwatch()..start();
    final active = RemoteConversationTransport(endpoint: endpoint)
        .send(
          Conversation(id: 'c1', messages: const []),
          cancellation: activeToken,
        )
        .listen(snapshots.add);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    activeToken.cancel();
    await active.asFuture<void>();
    stopwatch.stop();
    expect(snapshots.length, lessThanOrEqualTo(1));
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    await activeToken.dispose();
  });

  test('retains in-band errors and rejects malformed JSON', () async {
    server.listen((request) async {
      request.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
      if (request.uri.query == 'error') {
        request.response
          ..write('data: {"type":"start","messageId":"a"}\n\n')
          ..write('data: {"type":"error","errorText":"backend failed"}\n\n')
          ..write('data: {"type":"finish"}\n\n')
          ..write('data: [DONE]\n\n');
      } else {
        request.response.write('data: {not-json}\n\n');
      }
      await request.response.close();
    });
    final errorSnapshots = await RemoteConversationTransport(
      endpoint: endpoint.replace(query: 'error'),
    ).send(Conversation(id: 'c1', messages: const [])).toList();
    expect(
      errorSnapshots.last.messages.single.status,
      ConversationMessageStatus.failed,
    );
    expect(
      () => RemoteConversationTransport(
        endpoint: endpoint,
      ).send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(isA<RemoteProtocolException>()),
    );
  });

  test('surfaces HTTP authorization failures', () async {
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write('unauthorized');
      await request.response.close();
    });
    expect(
      () => RemoteConversationTransport(
        endpoint: endpoint,
      ).send(Conversation(id: 'c1', messages: const [])).toList(),
      throwsA(
        isA<RemoteProtocolException>().having(
          (error) => error.message,
          'message',
          contains('401'),
        ),
      ),
    );
  });

  test('does not close a client injected and owned by the caller', () async {
    final client = MockClient((request) async => http.Response('ok', 200));
    final transport = RemoteConversationTransport(
      endpoint: Uri.parse('https://example.test/chat'),
      client: client,
    );
    transport.dispose();
    expect(
      (await client.get(Uri.parse('https://example.test/ping'))).statusCode,
      200,
    );
    client.close();
  });
}
