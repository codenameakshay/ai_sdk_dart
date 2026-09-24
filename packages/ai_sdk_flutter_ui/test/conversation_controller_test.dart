import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_remote/ai_sdk_remote.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _ApprovalSequenceModel extends LanguageModelV4 {
  _ApprovalSequenceModel(this.responses);

  final List<List<LanguageModelV4ContentPart>> responses;
  final seenMessages = <List<LanguageModelV4Message>>[];
  int streamCalls = 0;

  @override
  String get provider => 'test';

  @override
  String get modelId => 'approval-sequence';

  @override
  String get specificationVersion => 'v4';

  List<LanguageModelV4ContentPart> _nextResponse() {
    final index = streamCalls < responses.length
        ? streamCalls
        : responses.length - 1;
    streamCalls++;
    return responses[index];
  }

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    seenMessages.add(List.unmodifiable(options.prompt.messages));
    final parts = <LanguageModelV4StreamPart>[];
    var index = 0;
    for (final part in _nextResponse()) {
      final id = 'part-$streamCalls-$index';
      switch (part) {
        case LanguageModelV4TextPart(:final text):
          parts
            ..add(StreamPartTextStart(id: id))
            ..add(StreamPartTextDelta(id: id, delta: text))
            ..add(StreamPartTextEnd(id: id));
        case LanguageModelV4ToolCallPart(
          :final toolCallId,
          :final toolName,
          :final input,
        ):
          parts
            ..add(StreamPartToolInputStart(id: toolCallId, toolName: toolName))
            ..add(
              StreamPartToolInputDelta(
                id: toolCallId,
                delta: jsonEncode(input),
              ),
            )
            ..add(StreamPartToolInputEnd(id: toolCallId))
            ..add(StreamPartToolCall(toolCall: part));
        default:
          throw StateError('Unsupported test response part $part');
      }
      index++;
    }
    parts.add(
      const StreamPartFinish(
        finishReason: LanguageModelV4FinishReason.stop,
        rawFinishReason: 'stop',
      ),
    );
    return LanguageModelV4StreamResult(stream: Stream.fromIterable(parts));
  }
}

Tool<Map<String, dynamic>, String> _countedApprovalTool(
  void Function() onExecute,
) => Tool<Map<String, dynamic>, String>(
  inputSchema: Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  ),
  approvalPolicy: ToolApprovalPolicy.always,
  executeDynamic: (input, options) async {
    onExecute();
    return 'done';
  },
);

class _ControllableModel extends LanguageModelV4 {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  String get provider => 'test';
  @override
  String get modelId => 'controllable';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    final stream = StreamController<LanguageModelV4StreamPart>();
    scheduleMicrotask(() {
      stream
        ..add(const StreamPartTextStart(id: 'live-text'))
        ..add(const StreamPartTextDelta(id: 'live-text', delta: 'partial'));
      if (!started.isCompleted) started.complete();
      release.future.then((_) {
        stream
          ..add(const StreamPartTextEnd(id: 'live-text'))
          ..add(
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.stop,
            ),
          )
          ..close();
      });
    });
    return LanguageModelV4StreamResult(stream: stream.stream);
  }
}

class _MetadataReasoningModel extends LanguageModelV4 {
  @override
  String get provider => 'test';

  @override
  String get modelId => 'metadata-reasoning';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(
    stream: Stream.fromIterable([
      const StreamPartReasoningStart(
        id: 'reasoning-1',
        providerMetadata: {
          'vendor': {'start': true, 'shared': 'start'},
        },
      ),
      const StreamPartReasoningDelta(
        id: 'reasoning-1',
        delta: 'trace',
        providerMetadata: {
          'vendor': {'delta': true, 'shared': 'delta'},
        },
      ),
      const StreamPartReasoningEnd(
        id: 'reasoning-1',
        signature: 'signature-1',
        providerMetadata: {
          'vendor': {'end': true, 'shared': 'end'},
        },
      ),
      const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
    ]),
  );
}

class _MetadataTextSequenceModel extends LanguageModelV4 {
  final seenMessages = <List<LanguageModelV4Message>>[];
  int calls = 0;

  @override
  String get provider => 'test';

  @override
  String get modelId => 'metadata-text';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    seenMessages.add(List.unmodifiable(options.prompt.messages));
    final first = calls++ == 0;
    final parts = first
        ? <LanguageModelV4StreamPart>[
            const StreamPartTextStart(
              id: 'text-1',
              providerMetadata: {
                'vendor': {'start': true, 'shared': 'start'},
              },
            ),
            const StreamPartTextDelta(
              id: 'text-1',
              delta: 'first',
              providerMetadata: {
                'vendor': {'delta': true, 'shared': 'delta'},
              },
            ),
            const StreamPartTextEnd(
              id: 'text-1',
              providerMetadata: {
                'vendor': {'end': true, 'shared': 'end'},
              },
            ),
          ]
        : <LanguageModelV4StreamPart>[
            const StreamPartTextStart(id: 'text-2'),
            const StreamPartTextDelta(id: 'text-2', delta: 'second'),
            const StreamPartTextEnd(id: 'text-2'),
          ];
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        ...parts,
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _UnsupportedConversationPart extends ConversationPart {
  _UnsupportedConversationPart()
    : super(id: 'unsupported-part', type: 'custom');

  @override
  Map<String, dynamic> toJson() => {'id': id, 'type': type};
}

ToolLoopAgent _textAgent(String text) =>
    ToolLoopAgent(model: MockLanguageModelV4(response: [mockText(text)]));

Conversation _empty() => Conversation(id: 'chat-1', messages: const []);

class _NoRetryBackend implements ConversationBackend {
  _NoRetryBackend(this.conversation, {this.failApproval = false});
  @override
  Conversation conversation;
  final bool failApproval;
  final _changes = StreamController<Conversation>.broadcast();

  @override
  Stream<Conversation> get changes => _changes.stream;

  @override
  Future<void> send(String text) async => throw StateError('send failed');

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> restore(Map<String, dynamic> encoded) async {}

  @override
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) async {
    if (failApproval) throw StateError('approval failed');
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
  }
}

class _StreamPartsModel extends LanguageModelV4 {
  _StreamPartsModel(this.parts);
  final List<LanguageModelV4StreamPart> parts;

  @override
  String get provider => 'test';
  @override
  String get modelId => 'stream-parts';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async => LanguageModelV4StreamResult(stream: Stream.fromIterable(parts));
}

void main() {
  test(
    'local and remote adapters normalize a scripted text turn equally',
    () async {
      final local = LocalConversationBackend(
        agent: _textAgent('hello'),
        initial: _empty(),
      );
      await local.send('hi');

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
        request.response.write(
          'data: ${jsonEncode({'type': 'start', 'messageId': 'message-2'})}\n\n'
          'data: ${jsonEncode({'type': 'text-start', 'id': 'text-0'})}\n\n'
          'data: ${jsonEncode({'type': 'text-delta', 'id': 'text-0', 'delta': 'hello'})}\n\n'
          'data: ${jsonEncode({'type': 'text-end', 'id': 'text-0'})}\n\n'
          'data: ${jsonEncode({'type': 'finish'})}\n\n'
          'data: [DONE]\n\n',
        );
        await request.response.close();
      });
      final remote = RemoteConversationBackend(
        transport: RemoteConversationTransport(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
        initial: _empty(),
      );
      await remote.send('hi');

      expect(remote.conversation, local.conversation);
      expect(remote.conversation.messages.map((m) => m.id), [
        'message-1',
        'message-2',
      ]);
      await local.dispose();
      await remote.dispose();
    },
  );

  test(
    'local backend carries lossless typed history into the next turn',
    () async {
      final model = _ApprovalSequenceModel([
        [const LanguageModelV4TextPart(text: 'next answer')],
      ]);
      final initial = Conversation(
        id: 'lossless-local',
        messages: [
          ConversationMessage(
            id: 'assistant-1',
            role: ConversationRole.assistant,
            parts: [
              ToolCallPart(
                id: 'call-part',
                callId: 'call-1',
                name: 'search',
                arguments: {'q': 'dart'},
                providerExecuted: true,
                providerOptions: {
                  'vendor': {'trace': 't-1'},
                },
              ),
              ToolResultPart(
                id: 'result-part',
                callId: 'call-1',
                toolName: 'search',
                output: {'ok': true},
                outputKind: 'json',
                preliminary: true,
                isDynamic: true,
                providerOptions: {
                  'vendor': {'requestId': 'r-1'},
                },
              ),
              ReasoningFilePart(
                id: 'reasoning-file',
                data: ConversationFileBytes(Uint8List.fromList([1, 2, 255])),
                mimeType: 'application/octet-stream',
                name: 'trace.bin',
              ),
              DocumentSourcePart(
                id: 'doc-source',
                mediaType: 'application/pdf',
                title: 'Paper',
                providerMetadata: {
                  'vendor': {'documentId': 'doc-1'},
                },
              ),
              UnknownPart(
                id: 'opaque-part',
                type: 'opaque',
                raw: {
                  'id': 'opaque-part',
                  'type': 'opaque',
                  'provider': 'vendor-x',
                  'raw': ['opaque', 3],
                },
              ),
            ],
          ),
        ],
      );
      final backend = LocalConversationBackend(
        agent: ToolLoopAgent(model: model),
        initial: initial,
      );

      await backend.send('continue');

      final assistant = model.seenMessages.single.singleWhere(
        (message) => message.role == LanguageModelV4Role.assistant,
      );
      final parts = assistant.content;
      final call = parts.whereType<LanguageModelV4ToolCallPart>().single;
      expect(call.toolCallId, 'call-1');
      expect(call.providerExecuted, isTrue);
      expect(call.providerOptions?['vendor'], {'trace': 't-1'});
      final result = parts.whereType<LanguageModelV4ToolResultPart>().single;
      expect(result.output, isA<ToolResultOutputJson>());
      expect(result.preliminary, isTrue);
      expect(result.isDynamic, isTrue);
      expect(result.providerOptions?['vendor'], {'requestId': 'r-1'});
      final file = parts.whereType<LanguageModelV4ReasoningFilePart>().single;
      expect((file.data as DataContentBytes).bytes, [1, 2, 255]);
      expect(file.filename, 'trace.bin');
      final document = parts
          .whereType<LanguageModelV4DocumentSourcePart>()
          .single;
      expect(document.id, 'doc-source');
      expect(document.providerMetadata?['vendor'], {'documentId': 'doc-1'});
      final opaque = parts.whereType<LanguageModelV4OpaquePart>().single;
      expect(opaque.provider, 'vendor-x');
      expect(opaque.raw, ['opaque', 3]);
      await backend.dispose();
    },
  );

  test(
    'accumulates reasoning provider metadata across stream events',
    () async {
      final backend = LocalConversationBackend(
        agent: ToolLoopAgent(model: _MetadataReasoningModel()),
        initial: _empty(),
      );

      await backend.send('trace');

      final reasoning = backend.conversation.messages
          .expand((message) => message.parts)
          .whereType<ReasoningPart>()
          .single;
      expect(reasoning.text, 'trace');
      expect(reasoning.signature, 'signature-1');
      expect(reasoning.metadata, {
        'vendor': {'start': true, 'delta': true, 'end': true, 'shared': 'end'},
      });
      expect(reasoning.providerOptions, reasoning.metadata);
      await backend.dispose();
    },
  );

  test('persists text provider metadata into the next local request', () async {
    final model = _MetadataTextSequenceModel();
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(model: model),
      initial: _empty(),
    );

    await backend.send('first');
    final firstText = backend.conversation.messages
        .where((message) => message.role == ConversationRole.assistant)
        .expand((message) => message.parts)
        .whereType<TextPart>()
        .singleWhere((part) => part.text == 'first');
    expect(firstText.providerOptions, {
      'vendor': {'start': true, 'delta': true, 'end': true, 'shared': 'end'},
    });

    await backend.send('second');
    final replayedAssistant = model.seenMessages[1].singleWhere(
      (message) => message.role == LanguageModelV4Role.assistant,
    );
    final replayedText = replayedAssistant.content
        .whereType<LanguageModelV4TextPart>()
        .single;
    expect(replayedText.providerOptions, firstText.providerOptions);
    await backend.dispose();
  });

  test(
    'unsupported conversation parts fail before provider dispatch',
    () async {
      final model = _ApprovalSequenceModel([
        [const LanguageModelV4TextPart(text: 'unexpected')],
      ]);
      final backend = LocalConversationBackend(
        agent: ToolLoopAgent(model: model),
        initial: Conversation(
          id: 'unsupported-history',
          messages: [
            ConversationMessage(
              id: 'assistant-1',
              role: ConversationRole.assistant,
              parts: [_UnsupportedConversationPart()],
            ),
          ],
        ),
      );

      await backend.send('continue');

      expect(model.streamCalls, 0);
      expect(
        backend.conversation.messages.last.status,
        ConversationMessageStatus.failed,
      );
      await backend.dispose();
    },
  );

  test(
    'remote approval resumes once and preserves the conversation history',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var requests = 0;
      final requestBodies = <Map<String, dynamic>>[];
      server.listen((request) async {
        requests++;
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        requestBodies.add(body);
        final messages = (body['messages'] as List)
            .cast<Map<String, dynamic>>();
        final parts = messages
            .expand(
              (message) =>
                  (message['parts'] as List).cast<Map<String, dynamic>>(),
            )
            .toList();
        final approved = parts
            .where((part) => (part['type'] as String).startsWith('tool-'))
            .map((part) => part['approval'])
            .whereType<Map<String, dynamic>>()
            .any((approval) => approval['approved'] == true);
        final events = requests == 1
            ? [
                {'type': 'start', 'messageId': 'assistant-1'},
                {
                  'type': 'tool-input-available',
                  'toolCallId': 'call-1',
                  'toolName': 'delete',
                  'input': {'path': '/tmp/example'},
                },
                {
                  'type': 'tool-approval-request',
                  'approvalId': 'remote-approval-1',
                  'toolCallId': 'call-1',
                },
                {'type': 'finish'},
              ]
            : [
                {'type': 'start', 'messageId': 'assistant-1'},
                {
                  'type': 'tool-input-available',
                  'toolCallId': 'call-1',
                  'toolName': 'delete',
                  'input': {'path': '/tmp/example'},
                },
                {
                  'type': approved
                      ? 'tool-output-available'
                      : 'tool-output-denied',
                  'toolCallId': 'call-1',
                  if (approved) 'output': {'ok': true},
                },
                {'type': 'text-start', 'id': 'answer-1'},
                {
                  'type': 'text-delta',
                  'id': 'answer-1',
                  'delta': approved ? 'approved answer' : 'denied answer',
                },
                {'type': 'text-end', 'id': 'answer-1'},
                {'type': 'finish'},
              ];
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType('text', 'event-stream')
          ..headers.set('x-vercel-ai-ui-message-stream', 'v1');
        for (final event in events) {
          request.response.write('data: ${jsonEncode(event)}\n\n');
        }
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });

      final backend = RemoteConversationBackend(
        transport: RemoteConversationTransport(
          endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        ),
        initial: _empty(),
      );
      await backend.send('delete it');
      final pending = backend.conversation.messages.last.parts
          .whereType<ApprovalPart>()
          .single;
      expect(pending.approvalId, 'remote-approval-1');
      await backend.respondToApproval(
        approvalId: 'remote-approval-other',
        approved: true,
      );
      expect(
        backend.conversation.messages.last.parts
            .whereType<ApprovalPart>()
            .single
            .status,
        ApprovalStatus.pending,
      );

      final first = backend.respondToApproval(
        approvalId: pending.approvalId!,
        approved: true,
        reason: 'approved by test',
      );
      final duplicate = backend.respondToApproval(
        approvalId: pending.approvalId!,
        approved: true,
      );
      await Future.wait([first, duplicate]);

      expect(requests, 2);
      final resumedMessages = requestBodies[1]['messages'] as List;
      expect(resumedMessages, hasLength(2));
      expect(
        (resumedMessages.first as Map<String, dynamic>)['id'],
        'message-1',
      );
      final resumedTool =
          (resumedMessages.last as Map<String, dynamic>)['parts'] as List;
      final wireTool = resumedTool.cast<Map<String, dynamic>>().singleWhere(
        (part) => (part['type'] as String).startsWith('tool-'),
      );
      expect((wireTool['approval'] as Map)['id'], 'remote-approval-1');
      expect((wireTool['approval'] as Map)['approved'], isTrue);
      expect((wireTool['approval'] as Map)['reason'], 'approved by test');
      expect(backend.conversation.messages.map((message) => message.id), [
        'message-1',
        'assistant-1',
      ]);
      expect(
        backend.conversation.messages.last.parts
            .whereType<TextPart>()
            .single
            .text,
        'approved answer',
      );
      expect(
        backend.conversation.messages.last.parts
            .whereType<ToolResultPart>()
            .single
            .output,
        {'ok': true},
      );
      await backend.dispose();
    },
  );

  test(
    'restore is pure, preserves unknown parts, and keeps IDs stable',
    () async {
      final backend = LocalConversationBackend(
        agent: _textAgent('unused'),
        initial: _empty(),
      );
      final snapshot = Conversation(
        id: 'chat-1',
        messages: [
          ConversationMessage(
            id: 'message-1',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.pendingApproval,
            parts: [
              ToolCallPart(
                id: 'part-call',
                callId: 'call-1',
                name: 'secure',
                arguments: const {'x': 1},
              ),
              ApprovalPart(
                id: 'part-approval',
                callId: 'call-1',
                status: ApprovalStatus.pending,
              ),
              UnknownPart(
                id: 'part-provider',
                type: 'provider-file',
                raw: const {
                  'id': 'part-provider',
                  'type': 'provider-file',
                  'payload': {'opaque': true},
                },
              ),
            ],
          ),
        ],
      );
      await backend.restore(ConversationCodec.encode(snapshot));
      expect(backend.conversation, snapshot);
      expect(
        backend.conversation.messages.single.parts,
        snapshot.messages.single.parts,
      );
      await backend.dispose();
    },
  );

  test('interrupt preserves partial snapshot and blocks late output', () async {
    final model = _ControllableModel();
    final initial = Conversation(
      id: 'chat-1',
      messages: [
        ConversationMessage(
          id: 'message-2',
          role: ConversationRole.user,
          parts: [TextPart(id: 'system-part', text: 'system')],
        ),
      ],
    );
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(model: model),
      initial: initial,
    );
    final snapshots = <Conversation>[];
    final subscription = backend.changes.listen(snapshots.add);
    final send = backend.send('hi');
    await model.started.future;
    await Future<void>.delayed(Duration.zero);
    expect(snapshots.last.messages.last.parts.single, isA<TextPart>());
    expect(
      (snapshots.last.messages.last.parts.single as TextPart).id,
      'text-0',
    );
    await backend.interrupt();
    await send;
    final interrupted = backend.conversation.messages.last;
    expect(interrupted.status, ConversationMessageStatus.interrupted);
    expect((interrupted.parts.single as TextPart).text, 'partial');
    expect(
      ConversationCodec.decode(ConversationCodec.encode(backend.conversation)),
      backend.conversation,
    );
    final count = snapshots.length;
    if (!model.release.isCompleted) model.release.complete();
    await Future<void>.delayed(Duration.zero);
    expect(snapshots.length, count);
    await subscription.cancel();
    await backend.dispose();
  });

  test('restored remote approval resumes with the restored IDs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    var requests = 0;
    server.listen((request) async {
      requests++;
      await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('text', 'event-stream')
        ..headers.set('x-vercel-ai-ui-message-stream', 'v1')
        ..write(
          'data: ${jsonEncode({'type': 'start', 'messageId': 'assistant-restored'})}\n\n',
        )
        ..write(
          'data: ${jsonEncode({'type': 'text-start', 'id': 'answer-restored'})}\n\n',
        )
        ..write(
          'data: ${jsonEncode({'type': 'text-delta', 'id': 'answer-restored', 'delta': 'resumed'})}\n\n',
        )
        ..write(
          'data: ${jsonEncode({'type': 'text-end', 'id': 'answer-restored'})}\n\n',
        )
        ..write('data: ${jsonEncode({'type': 'finish'})}\n\n')
        ..write('data: [DONE]\n\n');
      await request.response.close();
    });
    final backend = RemoteConversationBackend(
      transport: RemoteConversationTransport(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      ),
      initial: _empty(),
    );
    final restored = Conversation(
      id: 'chat-1',
      messages: [
        ConversationMessage(
          id: 'assistant-restored',
          role: ConversationRole.assistant,
          status: ConversationMessageStatus.pendingApproval,
          parts: [
            ToolCallPart(
              id: 'call-part-restored',
              callId: 'call-restored',
              name: 'delete',
              arguments: const {'path': '/tmp/restored'},
            ),
            ApprovalPart(
              id: 'approval-part-restored',
              approvalId: 'approval-restored',
              callId: 'call-restored',
              status: ApprovalStatus.pending,
            ),
          ],
        ),
      ],
    );
    await backend.restore(ConversationCodec.encode(restored));
    await backend.respondToApproval(
      approvalId: 'approval-restored',
      approved: false,
      reason: 'restored denial',
    );
    expect(requests, 1);
    expect(backend.conversation.messages.first.id, 'assistant-restored');
    expect(
      backend.conversation.messages.last.parts
          .whereType<TextPart>()
          .single
          .text,
      'resumed',
    );
    await backend.dispose();
  });

  test(
    'persists a pending approval and resumes it exactly once after restore',
    () async {
      final first = LocalConversationBackend(
        agent: approvalAgent(repeatCallAfterApproval: false),
        initial: _empty(),
      );
      await first.send('delete it');
      final encoded = ConversationCodec.encode(first.conversation);
      final second = LocalConversationBackend(
        agent: approvalAgent(
          repeatCallAfterApproval: false,
          continuationOnly: true,
        ),
        initial: _empty(),
      );
      await second.restore(encoded);
      final pending = second.conversation.messages.singleWhere(
        (message) =>
            message.status == ConversationMessageStatus.pendingApproval,
      );
      final approval = pending.parts.whereType<ApprovalPart>().single;
      await second.respondToApproval(
        approvalId: approval.approvalId!,
        approved: true,
      );
      await pumpUntil(
        () => second.conversation.messages.any(
          (message) =>
              message.status == ConversationMessageStatus.complete &&
              message.parts.whereType<TextPart>().any(
                (part) => part.text == 'final answer',
              ),
        ),
      );
      expect(
        second.conversation.messages
            .expand((message) => message.parts)
            .whereType<TextPart>()
            .any((part) => part.text == 'final answer'),
        isTrue,
      );
      await first.dispose();
      await second.dispose();
    },
  );

  test(
    'restored approval replays the complete provider content tree',
    () async {
      final continuation = _ApprovalSequenceModel([
        [const LanguageModelV4TextPart(text: 'resumed')],
      ]);
      var executions = 0;
      final backend = LocalConversationBackend(
        agent: ToolLoopAgent(
          model: continuation,
          maxSteps: 2,
          approvalPolicyRevision: 'v1',
          tools: {'delete': _countedApprovalTool(() => executions++)},
        ),
        initial: _empty(),
      );
      final snapshot = Conversation(
        id: 'rich-replay',
        messages: [
          ConversationMessage(
            id: 'user-1',
            role: ConversationRole.user,
            parts: [TextPart(id: 'user-text', text: 'delete it')],
          ),
          ConversationMessage(
            id: 'assistant-1',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.pendingApproval,
            parts: [
              TextPart(
                id: 'assistant-text',
                text: 'I will delete it',
                providerOptions: {
                  'vendor': {'segment': 'answer'},
                },
              ),
              ReasoningPart(
                id: 'assistant-reasoning',
                text: 'checking permissions',
                signature: 'sig-replay',
                providerOptions: {
                  'vendor': {'trace': 'trace-1'},
                },
              ),
              ImagePart(
                id: 'assistant-image',
                data: ConversationFileBytes(Uint8List.fromList([1, 2, 3])),
                mimeType: 'image/png',
                providerOptions: {
                  'vendor': {'image': 'img-1'},
                },
              ),
              RedactedReasoningPart(
                id: 'assistant-redacted',
                data: Uint8List.fromList([4, 5, 6]),
                providerOptions: {
                  'vendor': {'redacted': true},
                },
              ),
              FilePart(
                id: 'assistant-file',
                data: ConversationFileProviderReference(
                  namespace: 'vendor',
                  id: 'file-1',
                ),
                mimeType: 'application/pdf',
                name: 'report.pdf',
                providerOptions: {
                  'vendor': {'file': 'file-1'},
                },
              ),
              SourcePart(
                id: 'assistant-source',
                uri: 'https://example.com/source',
                title: 'Source',
                providerMetadata: {
                  'vendor': {'citation': 'cite-1'},
                },
              ),
              UnknownPart(
                id: 'assistant-opaque',
                type: 'opaque',
                raw: {
                  'id': 'assistant-opaque',
                  'type': 'opaque',
                  'provider': 'vendor',
                  'raw': {'token': 'opaque-1'},
                },
              ),
              ToolCallPart(
                id: 'old-call-part',
                callId: 'old-call',
                name: 'lookup',
                arguments: {'id': 'old'},
                providerOptions: {
                  'vendor': {'call': 'old'},
                },
                providerExecuted: true,
              ),
              ToolResultPart(
                id: 'old-result-part',
                callId: 'old-call',
                toolName: 'lookup',
                output: [
                  {
                    'type': 'text',
                    'text': 'lookup result',
                    'providerOptions': {
                      'vendor': {'result': 'old'},
                    },
                  },
                  {'type': 'reasoning', 'text': 'verified', 'signature': 'sig'},
                  {
                    'type': 'redacted_reasoning',
                    'data': {'kind': 'bytes', 'base64': 'AQI='},
                  },
                  {
                    'type': 'image',
                    'data': {'kind': 'base64', 'base64': 'AQI='},
                    'mediaType': 'image/png',
                  },
                  {
                    'type': 'file',
                    'data': {'kind': 'url', 'url': 'https://example.com/a.pdf'},
                    'mediaType': 'application/pdf',
                  },
                  {
                    'type': 'reasoning_file',
                    'data': {
                      'kind': 'provider_reference',
                      'namespace': 'vendor',
                      'id': 'reasoning-1',
                    },
                    'mediaType': 'application/octet-stream',
                  },
                  {
                    'type': 'source',
                    'id': 'source-1',
                    'url': 'https://example.com/source',
                  },
                  {
                    'type': 'source-document',
                    'id': 'document-1',
                    'mediaType': 'application/pdf',
                    'title': 'Document',
                  },
                  {
                    'type': 'opaque',
                    'provider': 'vendor',
                    'raw': {'id': 'opaque-1'},
                  },
                ],
                outputKind: 'content',
                providerOptions: {
                  'vendor': {'result': 'old'},
                },
              ),
              ToolCallPart(
                id: 'pending-call-part',
                callId: 'pending-call',
                name: 'delete',
                arguments: const {},
                providerOptions: {
                  'vendor': {'call': 'pending'},
                },
              ),
              ApprovalPart(
                id: 'approval-delete',
                callId: 'pending-call',
                approvalId: 'approval-delete',
                toolName: 'delete',
                argumentsFingerprint: '{}',
                policyVersion: 'v1',
                status: ApprovalStatus.pending,
              ),
            ],
          ),
        ],
      );

      await backend.restore(ConversationCodec.encode(snapshot));
      await backend.respondToApproval(
        approvalId: 'approval-delete',
        approved: true,
      );
      await pumpUntil(
        () => backend.conversation.messages.any(
          (message) =>
              message.status == ConversationMessageStatus.complete &&
              message.parts.whereType<TextPart>().any(
                (part) => part.text == 'resumed',
              ),
        ),
      );

      final prompt = continuation.seenMessages.single;
      final assistantParts = prompt
          .where((message) => message.role == LanguageModelV4Role.assistant)
          .expand((message) => message.content)
          .toList();
      expect(
        assistantParts
            .whereType<LanguageModelV4TextPart>()
            .single
            .providerOptions,
        {
          'vendor': {'segment': 'answer'},
        },
      );
      final reasoning = assistantParts
          .whereType<LanguageModelV4ReasoningPart>()
          .single;
      expect(reasoning.signature, 'sig-replay');
      expect(reasoning.providerOptions, {
        'vendor': {'trace': 'trace-1'},
      });
      final image = assistantParts.whereType<LanguageModelV4ImagePart>().single;
      expect(image.mediaType, 'image/png');
      expect(image.providerOptions, {
        'vendor': {'image': 'img-1'},
      });
      expect((image.image as DataContentBytes).bytes, [1, 2, 3]);
      final redacted = assistantParts
          .whereType<LanguageModelV4RedactedReasoningPart>()
          .single;
      expect(redacted.providerOptions, {
        'vendor': {'redacted': true},
      });
      expect(redacted.data, [4, 5, 6]);
      final file = assistantParts.whereType<LanguageModelV4FilePart>().single;
      expect(file.filename, 'report.pdf');
      expect(file.providerOptions, {
        'vendor': {'file': 'file-1'},
      });
      expect(file.data, isA<DataContentProviderReference>());
      final source = assistantParts
          .whereType<LanguageModelV4SourcePart>()
          .single;
      expect(source.providerMetadata, {
        'vendor': {'citation': 'cite-1'},
      });
      final opaque = assistantParts
          .whereType<LanguageModelV4OpaquePart>()
          .single;
      expect(opaque.provider, 'vendor');
      expect(opaque.raw, {'token': 'opaque-1'});
      final oldCall = assistantParts
          .whereType<LanguageModelV4ToolCallPart>()
          .singleWhere((part) => part.toolCallId == 'old-call');
      expect(oldCall.providerOptions, {
        'vendor': {'call': 'old'},
      });
      expect(oldCall.providerExecuted, isTrue);
      final pendingCall = assistantParts
          .whereType<LanguageModelV4ToolCallPart>()
          .singleWhere((part) => part.toolCallId == 'pending-call');
      expect(pendingCall.providerOptions, {
        'vendor': {'call': 'pending'},
      });
      expect(pendingCall.providerExecuted, isFalse);

      final oldResult = prompt
          .where((message) => message.role == LanguageModelV4Role.tool)
          .expand((message) => message.content)
          .whereType<LanguageModelV4ToolResultPart>()
          .singleWhere((part) => part.toolCallId == 'old-call');
      expect(oldResult.providerOptions, {
        'vendor': {'result': 'old'},
      });
      final content = oldResult.output as ToolResultOutputContent;
      final contentText = content.parts.first as LanguageModelV4TextPart;
      expect(contentText.providerOptions, {
        'vendor': {'result': 'old'},
      });
      expect(
        (content.parts[1] as LanguageModelV4ReasoningPart).signature,
        'sig',
      );
      expect((content.parts[2] as LanguageModelV4RedactedReasoningPart).data, [
        1,
        2,
      ]);
      expect(
        (content.parts[3] as LanguageModelV4ImagePart).image,
        isA<DataContentBase64>(),
      );
      expect(
        (content.parts[4] as LanguageModelV4FilePart).data,
        isA<DataContentUrl>(),
      );
      expect(
        (content.parts[5] as LanguageModelV4ReasoningFilePart).data,
        isA<DataContentProviderReference>(),
      );
      expect(content.parts[6], isA<LanguageModelV4SourcePart>());
      expect(content.parts[7], isA<LanguageModelV4DocumentSourcePart>());
      expect((content.parts[8] as LanguageModelV4OpaquePart).raw, {
        'id': 'opaque-1',
      });
      expect(executions, 1);
      await backend.dispose();
    },
  );

  test(
    'restored binding changes retain pending approval without dispatch',
    () async {
      final source = LocalConversationBackend(
        agent: approvalAgent(repeatCallAfterApproval: false),
        initial: _empty(),
      );
      await source.send('delete it');
      final encoded = ConversationCodec.encode(source.conversation);
      final message =
          (encoded['messages'] as List).last as Map<String, dynamic>;
      final parts = message['parts'] as List;
      final approval = parts.whereType<Map<String, dynamic>>().firstWhere(
        (part) => part['type'] == 'approval',
      );
      approval['toolName'] = 'changedTool';
      final restored = LocalConversationBackend(
        agent: approvalAgent(repeatCallAfterApproval: false),
        initial: _empty(),
      );
      await restored.restore(encoded);
      await restored.respondToApproval(
        approvalId: approval['approvalId'] as String,
        approved: true,
      );
      await pumpUntil(
        () =>
            restored.conversation.messages.last.status ==
            ConversationMessageStatus.pendingApproval,
      );
      expect(
        restored.conversation.messages.last.parts
            .whereType<ApprovalPart>()
            .single
            .status,
        ApprovalStatus.pending,
      );
      await source.dispose();
      await restored.dispose();
    },
  );

  test(
    'persists two independent approvals and resumes each tool exactly once',
    () async {
      final firstModel = _ApprovalSequenceModel([
        [
          mockToolCall(
            toolName: 'first',
            input: const {'value': 1},
            toolCallId: 'call-first',
          ),
          mockToolCall(
            toolName: 'second',
            input: const {'value': 2},
            toolCallId: 'call-second',
          ),
        ],
      ]);
      final continuationModel = _ApprovalSequenceModel([
        [mockText('both approved')],
      ]);
      var firstExecutions = 0;
      var secondExecutions = 0;
      ToolLoopAgent buildAgent(LanguageModelV4 model) => ToolLoopAgent(
        model: model,
        maxSteps: 3,
        tools: {
          'first': _countedApprovalTool(() => firstExecutions++),
          'second': _countedApprovalTool(() => secondExecutions++),
        },
        approvalPolicyRevision: 'v1',
      );

      final source = LocalConversationBackend(
        agent: buildAgent(firstModel),
        initial: _empty(),
      );
      await source.send('approve both');
      final pending = source.conversation.messages.singleWhere(
        (message) =>
            message.status == ConversationMessageStatus.pendingApproval,
      );
      final approvals = pending.parts.whereType<ApprovalPart>().toList();
      expect(approvals, hasLength(2));
      final firstApproval = approvals.singleWhere(
        (approval) => approval.callId == 'call-first',
      );
      final secondApproval = approvals.singleWhere(
        (approval) => approval.callId == 'call-second',
      );

      await source.respondToApproval(
        approvalId: firstApproval.approvalId!,
        approved: true,
      );
      final encoded = ConversationCodec.encode(source.conversation);
      final restored = LocalConversationBackend(
        agent: buildAgent(continuationModel),
        initial: _empty(),
      );
      await restored.restore(encoded);
      final restoredApprovals = restored.conversation.messages.last.parts
          .whereType<ApprovalPart>()
          .toList();
      expect(
        restoredApprovals
            .singleWhere((part) => part.callId == 'call-first')
            .status,
        ApprovalStatus.approved,
      );
      expect(
        restoredApprovals
            .singleWhere((part) => part.callId == 'call-second')
            .status,
        ApprovalStatus.pending,
      );

      await restored.respondToApproval(
        approvalId: secondApproval.approvalId!,
        approved: true,
      );
      await pumpUntil(
        () => restored.conversation.messages.any(
          (message) =>
              message.status == ConversationMessageStatus.complete &&
              message.parts.whereType<TextPart>().any(
                (part) => part.text == 'both approved',
              ),
        ),
      );

      expect(firstExecutions, 1);
      expect(secondExecutions, 1);
      expect(firstModel.streamCalls, 1);
      expect(continuationModel.streamCalls, 1);
      final replayedToolResults = continuationModel.seenMessages.single
          .expand((message) => message.content)
          .whereType<LanguageModelV4ToolResultPart>()
          .toList();
      expect(
        replayedToolResults.map((part) => part.toolCallId),
        containsAll(<String>['call-first', 'call-second']),
      );
      expect(
        replayedToolResults.map(
          (part) =>
              (part.toolCallId, (part.output as ToolResultOutputText).text),
        ),
        containsAll(<(String, String)>[
          ('call-first', 'done'),
          ('call-second', 'done'),
        ]),
      );
      expect(
        continuationModel.seenMessages.single.map((message) => message.role),
        containsAll(<LanguageModelV4Role>[
          LanguageModelV4Role.user,
          LanguageModelV4Role.assistant,
          LanguageModelV4Role.tool,
        ]),
      );
      final finalApprovals = restored.conversation.messages.last.parts
          .whereType<ApprovalPart>()
          .toList();
      expect(finalApprovals, hasLength(2));
      expect(
        finalApprovals,
        everyElement(
          predicate<ApprovalPart>(
            (part) => part.status == ApprovalStatus.approved,
          ),
        ),
      );
      await source.dispose();
      await restored.dispose();
    },
  );

  test('denial persists across restore and skips both executors', () async {
    final model = _ApprovalSequenceModel([
      [
        mockToolCall(
          toolName: 'first',
          input: const {'value': 1},
          toolCallId: 'call-first',
        ),
        mockToolCall(
          toolName: 'second',
          input: const {'value': 2},
          toolCallId: 'call-second',
        ),
      ],
      [mockText('both denied')],
    ]);
    var executions = 0;
    ToolLoopAgent buildAgent() => ToolLoopAgent(
      model: model,
      maxSteps: 3,
      tools: {
        'first': _countedApprovalTool(() => executions++),
        'second': _countedApprovalTool(() => executions++),
      },
    );
    final source = LocalConversationBackend(
      agent: buildAgent(),
      initial: _empty(),
    );
    await source.send('deny both');
    final approvals = source.conversation.messages.last.parts
        .whereType<ApprovalPart>()
        .toList();
    expect(approvals, hasLength(2));
    await source.respondToApproval(
      approvalId: approvals.first.approvalId!,
      approved: false,
      reason: 'first denied',
    );
    final restored = LocalConversationBackend(
      agent: buildAgent(),
      initial: _empty(),
    );
    await restored.restore(ConversationCodec.encode(source.conversation));
    final second = restored.conversation.messages.last.parts
        .whereType<ApprovalPart>()
        .singleWhere((part) => part.callId == 'call-second');
    await restored.respondToApproval(
      approvalId: second.approvalId!,
      approved: false,
      reason: 'second denied',
    );
    await pumpUntil(
      () =>
          restored.conversation.messages.last.status ==
          ConversationMessageStatus.complete,
    );
    expect(executions, 0);
    expect(model.streamCalls, 2);
    expect(
      restored.conversation.messages.last.parts.whereType<ApprovalPart>().map(
        (part) => part.status,
      ),
      everyElement(ApprovalStatus.rejected),
    );
    expect(
      restored.conversation.messages.last.parts.whereType<ToolResultPart>().map(
        (part) => part.executionDeniedReason,
      ),
      everyElement(isNotNull),
    );
    expect(
      restored.conversation.messages.last.parts.whereType<TextPart>().map(
        (part) => part.text,
      ),
      contains('both denied'),
    );
    await source.dispose();
    await restored.dispose();
  });

  test('live tool execution errors are persisted as error results', () async {
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(
        model: _ApprovalSequenceModel([
          [
            mockToolCall(
              toolName: 'fail',
              input: const {},
              toolCallId: 'call-fail',
            ),
          ],
        ]),
        tools: {
          'fail': Tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            executeDynamic: (input, options) async =>
                throw StateError('tool failed'),
          ),
        },
      ),
      initial: _empty(),
    );

    await backend.send('run failing tool');

    final result = backend.conversation.messages.last.parts
        .whereType<ToolResultPart>()
        .single;
    expect(result.isError, isTrue);
    expect(result.outputKind, 'text');
    expect(result.output, contains('tool failed'));
    await backend.dispose();
  });

  test(
    'live tool error and execution-denied events retain their details',
    () async {
      final agent = RecordingStreamAgent();
      final backend = LocalConversationBackend(agent: agent, initial: _empty());
      final sending = backend.send('run tools');
      await pumpUntil(() => agent.invocations.isNotEmpty);
      await pumpUntil(
        () =>
            backend.conversation.messages.last.status ==
            ConversationMessageStatus.streaming,
      );
      final invocation = agent.invocations.single;
      invocation
        ..emitToolInputEnd(
          toolCallId: 'error-call',
          toolName: 'lookup',
          input: const {},
        )
        ..emitToolInputEnd(
          toolCallId: 'denied-call',
          toolName: 'delete',
          input: const {},
        )
        ..emitToolError(
          toolCallId: 'error-call',
          toolName: 'lookup',
          error: {'message': 'lookup failed'},
        )
        ..emitToolResult(
          const LanguageModelV4ToolResultPart(
            toolCallId: 'denied-call',
            toolName: 'delete',
            output: ToolResultOutputExecutionDenied(
              'policy denied',
              'approval-1',
            ),
          ),
        );
      final finishing = invocation.finish(
        finalText: 'done',
        closeTextStream: false,
      );
      await sending;
      await finishing;

      final results = backend.conversation.messages.last.parts
          .whereType<ToolResultPart>()
          .toList();
      final error = results.singleWhere((part) => part.callId == 'error-call');
      expect(error.output, {'message': 'lookup failed'});
      expect(error.outputKind, 'error_json');
      expect(error.isError, isTrue);
      final denied = results.singleWhere(
        (part) => part.callId == 'denied-call',
      );
      expect(denied.executionDeniedReason, 'policy denied');
      expect(denied.executionDeniedApprovalId, 'approval-1');
      await backend.dispose();
    },
  );

  test('provider failure settles a failed assistant snapshot', () async {
    final backend = LocalConversationBackend(
      agent: syncThrowingAgent(StateError('provider failed')),
      initial: _empty(),
    );
    await backend.send('fail safely');
    expect(backend.conversation.messages, hasLength(2));
    expect(
      backend.conversation.messages.last.status,
      ConversationMessageStatus.failed,
    );
    await backend.dispose();
  });

  test('renews a changed approval policy and persists the renewal', () async {
    final model = _ApprovalSequenceModel([
      [
        mockToolCall(
          toolName: 'secure',
          input: const {'value': 1},
          toolCallId: 'call-secure',
        ),
      ],
      [mockText('renewed answer')],
    ]);
    var executions = 0;
    ToolLoopAgent buildAgent(String revision) => ToolLoopAgent(
      model: model,
      maxSteps: 2,
      approvalPolicyRevision: revision,
      tools: {'secure': _countedApprovalTool(() => executions++)},
    );
    final source = LocalConversationBackend(
      agent: buildAgent('v1'),
      initial: _empty(),
    );
    await source.send('secure it');
    final encoded = ConversationCodec.encode(source.conversation);

    final changedPolicy = LocalConversationBackend(
      agent: buildAgent('v2'),
      initial: _empty(),
    );
    await changedPolicy.restore(encoded);
    final staleApproval = changedPolicy.conversation.messages.last.parts
        .whereType<ApprovalPart>()
        .single;
    await changedPolicy.respondToApproval(
      approvalId: staleApproval.approvalId!,
      approved: true,
    );
    await pumpUntil(
      () =>
          changedPolicy.conversation.messages.last.parts
              .whereType<ApprovalPart>()
              .single
              .policyVersion ==
          'v2',
    );
    final renewedWire = ConversationCodec.encode(changedPolicy.conversation);
    final resumed = LocalConversationBackend(
      agent: buildAgent('v2'),
      initial: _empty(),
    );
    await resumed.restore(renewedWire);
    final renewedApproval = resumed.conversation.messages.last.parts
        .whereType<ApprovalPart>()
        .single;
    expect(renewedApproval.status, ApprovalStatus.pending);
    expect(renewedApproval.policyVersion, 'v2');
    await resumed.respondToApproval(
      approvalId: renewedApproval.approvalId!,
      approved: true,
    );
    await pumpUntil(
      () =>
          resumed.conversation.messages.last.status ==
          ConversationMessageStatus.complete,
    );
    expect(executions, 1);
    expect(model.streamCalls, 2);
    expect(
      resumed.conversation.messages.last.parts.whereType<TextPart>().map(
        (part) => part.text,
      ),
      contains('renewed answer'),
    );
    await source.dispose();
    await changedPolicy.dispose();
    await resumed.dispose();
  });

  test('accepts a new approval round after the first continuation', () async {
    final model = _ApprovalSequenceModel([
      [
        mockToolCall(
          toolName: 'first',
          input: const {'value': 1},
          toolCallId: 'call-first',
        ),
      ],
      [
        mockToolCall(
          toolName: 'second',
          input: const {'value': 2},
          toolCallId: 'call-second',
        ),
      ],
      [mockText('two rounds complete')],
    ]);
    var firstExecutions = 0;
    var secondExecutions = 0;
    final agent = ToolLoopAgent(
      model: model,
      maxSteps: 3,
      tools: {
        'first': _countedApprovalTool(() => firstExecutions++),
        'second': _countedApprovalTool(() => secondExecutions++),
      },
    );
    final backend = LocalConversationBackend(agent: agent, initial: _empty());
    await backend.send('run in rounds');
    var approval = backend.conversation.messages.last.parts
        .whereType<ApprovalPart>()
        .single;
    expect(approval.callId, 'call-first');
    await backend.respondToApproval(
      approvalId: approval.approvalId!,
      approved: true,
    );
    await pumpUntil(
      () => backend.conversation.messages.last.parts
          .whereType<ApprovalPart>()
          .any((part) => part.callId == 'call-second'),
    );
    approval = backend.conversation.messages.last.parts
        .whereType<ApprovalPart>()
        .singleWhere((part) => part.callId == 'call-second');
    await backend.respondToApproval(
      approvalId: approval.approvalId!,
      approved: true,
    );
    await pumpUntil(
      () =>
          backend.conversation.messages.last.status ==
          ConversationMessageStatus.complete,
    );
    expect(firstExecutions, 1);
    expect(secondExecutions, 1);
    expect(model.streamCalls, 3);
    expect(
      backend.conversation.messages.last.parts.whereType<TextPart>().map(
        (part) => part.text,
      ),
      contains('two rounds complete'),
    );
    expect(
      backend.conversation.messages.last.parts.whereType<ApprovalPart>().map(
        (part) => part.status,
      ),
      everyElement(ApprovalStatus.approved),
    );
    await backend.dispose();
  });

  test('retry can pause for and resume a tool approval', () async {
    final model = _ApprovalSequenceModel([
      [
        mockToolCall(
          toolName: 'delete',
          input: const {'path': '/tmp/retry'},
          toolCallId: 'retry-call',
        ),
      ],
      [mockText('retry complete')],
    ]);
    var executions = 0;
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(
        model: model,
        maxSteps: 2,
        tools: {'delete': _countedApprovalTool(() => executions++)},
      ),
      initial: Conversation(
        id: 'retry-approval',
        messages: [
          ConversationMessage(
            id: 'user-1',
            role: ConversationRole.user,
            parts: [TextPart(id: 'user-text', text: 'delete it')],
          ),
          ConversationMessage(
            id: 'assistant-1',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.failed,
            parts: [TextPart(id: 'failed-text', text: 'failed')],
          ),
        ],
      ),
    );

    await backend.retryLastTurn();
    final approval = backend.conversation.messages.last.parts
        .whereType<ApprovalPart>()
        .single;
    expect(
      backend.conversation.messages.last.status,
      ConversationMessageStatus.pendingApproval,
    );
    expect(executions, 0);

    await backend.respondToApproval(
      approvalId: approval.approvalId!,
      approved: true,
    );
    await pumpUntil(
      () =>
          backend.conversation.messages.last.status ==
          ConversationMessageStatus.complete,
    );
    expect(executions, 1);
    expect(model.streamCalls, 2);
    await backend.dispose();
  });

  test('controller retry is unsupported unless the backend opts in', () async {
    final backend = _NoRetryBackend(_empty());
    final controller = ConversationController(backend, disposeBackend: false);
    expect(controller.retryInfo.isAvailable, isFalse);
    expect(
      controller.retryInfo.availability,
      ConversationRetryAvailability.unsupported,
    );
    expect(ConversationRetryError('retry failed').toString(), 'retry failed');
    await expectLater(
      controller.retryLastTurn(),
      throwsA(isA<RetryUnsupportedError>()),
    );
    await controller.interrupt();
    await controller.restore({
      'schemaVersion': 1,
      'id': 'chat-1',
      'messages': [],
    });
    await controller.dispose();
    await backend.dispose();
  });

  test('chat adapter reports backend failures and stop interrupts', () async {
    final backend = _NoRetryBackend(_empty(), failApproval: true);
    final controller = ConversationController(backend);
    final chat = ConversationChatController(controller);
    expect(chat.retryInfo.isAvailable, isFalse);
    await chat.sendMessage(agent: _textAgent('ignored'), text: 'hi');
    expect(chat.error, isA<StateError>());
    expect(chat.status, ChatStatus.error);
    expect(chat.isStreaming, isFalse);
    chat.clearError();
    expect(chat.error, isNull);
    chat.addToolApprovalResponse(approvalId: 'approval', approved: true);
    await pumpUntil(() => chat.status == ChatStatus.error);
    expect(chat.error, isA<StateError>());
    await chat.stop();
    chat.dispose();
  });

  test('local backend records live media, sources, and tool output', () async {
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(
        model: _StreamPartsModel([
          StreamPartFile(
            file: LanguageModelV4FilePart(
              data: DataContentBytes(Uint8List.fromList([1, 2])),
              mediaType: 'application/pdf',
              filename: 'a.pdf',
            ),
          ),
          StreamPartFile(
            file: LanguageModelV4FilePart(
              data: const DataContentBase64('AQI='),
              mediaType: 'image/png',
            ),
          ),
          StreamPartFile(
            file: LanguageModelV4FilePart(
              data: DataContentUrl(Uri.parse('https://example.com/b.bin')),
              mediaType: 'application/octet-stream',
            ),
          ),
          const StreamPartReasoningFile(
            file: LanguageModelV4ReasoningFilePart(
              data: DataContentProviderReference(
                namespace: 'vendor',
                id: 'trace-1',
              ),
              mediaType: 'application/octet-stream',
            ),
          ),
          const StreamPartSource(
            source: LanguageModelV4SourcePart(
              id: 'source-1',
              url: 'https://example.com/source',
              title: 'Source',
            ),
          ),
          const StreamPartDocumentSource(
            source: LanguageModelV4DocumentSourcePart(
              id: 'doc-1',
              mediaType: 'application/pdf',
              title: 'Document',
            ),
          ),
          const StreamPartOpaque(
            opaque: LanguageModelV4OpaquePart(
              provider: 'vendor',
              raw: {'id': 'opaque-1'},
            ),
          ),
          const StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ]),
      ),
      initial: _empty(),
    );
    await backend.send('media');
    final parts = backend.conversation.messages.last.parts;
    expect(parts.whereType<FilePart>(), hasLength(3));
    expect(parts.whereType<ReasoningFilePart>(), hasLength(1));
    expect(parts.whereType<SourcePart>(), hasLength(1));
    expect(parts.whereType<DocumentSourcePart>(), hasLength(1));
    expect(parts.whereType<UnknownPart>(), hasLength(1));
    await backend.dispose();
  });

  test('local backend persists rich tool results and tool errors', () async {
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(
        model: _StreamPartsModel([
          const StreamPartToolInputStart(id: 'call-rich', toolName: 'lookup'),
          const StreamPartToolInputEnd(id: 'call-rich'),
          StreamPartToolCall(
            toolCall: mockToolCall(
              toolName: 'lookup',
              input: const {},
              toolCallId: 'call-rich',
            ),
          ),
          StreamPartToolResult(
            toolResult: LanguageModelV4ToolResultPart(
              toolCallId: 'call-rich',
              toolName: 'lookup',
              output: ToolResultOutputContent([
                const LanguageModelV4TextPart(text: 'ok'),
                const LanguageModelV4ReasoningPart(
                  text: 'why',
                  signature: 'sig',
                  providerOptions: {
                    'vendor': {'reasoning': true},
                  },
                ),
                const LanguageModelV4ImagePart(
                  image: DataContentBase64('AQI='),
                  mediaType: 'image/png',
                  providerOptions: {
                    'vendor': {'image': true},
                  },
                ),
                LanguageModelV4FilePart(
                  data: DataContentUrl(Uri.parse('https://example.com/a.pdf')),
                  mediaType: 'application/pdf',
                  filename: 'a.pdf',
                  providerOptions: {
                    'vendor': {'file': true},
                  },
                ),
                const LanguageModelV4SourcePart(
                  id: 'source-1',
                  url: 'https://example.com/source',
                  title: 'Source',
                  providerMetadata: {
                    'vendor': {'source': true},
                  },
                ),
                const LanguageModelV4DocumentSourcePart(
                  id: 'doc-1',
                  mediaType: 'application/pdf',
                  title: 'Document',
                  filename: 'document.pdf',
                  providerMetadata: {
                    'vendor': {'document': true},
                  },
                ),
                const LanguageModelV4OpaquePart(
                  provider: 'vendor',
                  raw: {'id': 'opaque-1'},
                ),
              ]),
            ),
          ),
          const StreamPartFinish(
            finishReason: LanguageModelV4FinishReason.stop,
          ),
        ]),
      ),
      initial: _empty(),
    );
    await backend.send('lookup');
    final result = backend.conversation.messages
        .expand((message) => message.parts)
        .whereType<ToolResultPart>()
        .single;
    expect(result.outputKind, 'content');
    expect(result.output, isA<List>());
    expect((result.output as List), hasLength(7));
    await backend.dispose();
  });
}
