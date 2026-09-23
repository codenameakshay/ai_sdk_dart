import 'dart:async';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _RetryModel extends LanguageModelV4 {
  _RetryModel({this.failFirst = false});

  final bool failFirst;
  int calls = 0;

  @override
  String get provider => 'test';
  @override
  String get modelId => 'retry';
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
    calls++;
    if (failFirst && calls == 1) throw StateError('first request failed');
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        const StreamPartTextStart(id: 'retry-text'),
        StreamPartTextDelta(id: 'retry-text', delta: 'retried'),
        const StreamPartTextEnd(id: 'retry-text'),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _ReplayCaptureModel extends LanguageModelV4 {
  final seenPrompts = <List<LanguageModelV4Message>>[];

  @override
  String get provider => 'test';
  @override
  String get modelId => 'replay-capture';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    seenPrompts.add(List.unmodifiable(options.prompt.messages));
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: 'done')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    seenPrompts.add(List.unmodifiable(options.prompt.messages));
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        const StreamPartTextStart(id: 'done'),
        const StreamPartTextDelta(id: 'done', delta: 'done'),
        const StreamPartTextEnd(id: 'done'),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _DelayedSendBackend implements ConversationBackend {
  _DelayedSendBackend(this._conversation);

  Conversation _conversation;
  final changesController = StreamController<Conversation>.broadcast();
  final release = Completer<void>();

  @override
  Conversation get conversation => _conversation;
  @override
  Stream<Conversation> get changes => changesController.stream;

  @override
  Future<void> send(String text) async {
    _conversation = Conversation(
      id: _conversation.id,
      messages: [
        ..._conversation.messages,
        ConversationMessage(
          id: 'user-new',
          role: ConversationRole.user,
          parts: [TextPart(id: 'user-new-part', text: text)],
        ),
      ],
    );
    changesController.add(_conversation);
    await release.future;
    _conversation = Conversation(
      id: _conversation.id,
      messages: [
        ..._conversation.messages,
        ConversationMessage(
          id: 'assistant-new',
          role: ConversationRole.assistant,
          status: ConversationMessageStatus.streaming,
          parts: [TextPart(id: 'assistant-new-part', text: 'streaming')],
        ),
      ],
    );
    changesController.add(_conversation);
  }

  @override
  Future<void> interrupt() async {}
  @override
  Future<void> restore(Map<String, dynamic> encoded) async {}
  @override
  Future<void> respondToApproval({
    required String approvalId,
    required bool approved,
    String? reason,
  }) async {}
  @override
  Future<void> dispose() => changesController.close();
}

Conversation _empty() => Conversation(id: 'retry-chat', messages: const []);

void main() {
  test(
    'local retry replaces a failed assistant without duplicating the user',
    () async {
      final model = _RetryModel(failFirst: true);
      final backend = LocalConversationBackend(
        agent: ToolLoopAgent(model: model),
        initial: _empty(),
      );
      await backend.send('hello');
      final failed = backend.conversation.messages;
      final userId = failed
          .singleWhere((m) => m.role == ConversationRole.user)
          .id;
      final assistantId = failed
          .singleWhere((m) => m.role == ConversationRole.assistant)
          .id;

      await backend.retryLastTurn();

      expect(model.calls, 2);
      expect(
        backend.conversation.messages.where(
          (m) => m.role == ConversationRole.user,
        ),
        hasLength(1),
      );
      expect(backend.conversation.messages.map((m) => m.id), [
        userId,
        assistantId,
      ]);
      expect(
        backend.conversation.messages.last.status,
        ConversationMessageStatus.complete,
      );
      await backend.dispose();
    },
  );

  test('retry refuses a tool turn before any executor can run', () async {
    var executions = 0;
    final initial = Conversation(
      id: 'unsafe',
      messages: [
        ConversationMessage(
          id: 'user-1',
          role: ConversationRole.user,
          parts: [TextPart(id: 'user-part', text: 'run it')],
        ),
        ConversationMessage(
          id: 'assistant-1',
          role: ConversationRole.assistant,
          status: ConversationMessageStatus.failed,
          parts: [
            ToolCallPart(
              id: 'call-part',
              callId: 'call-1',
              name: 'danger',
              arguments: {},
            ),
          ],
        ),
      ],
    );
    final tool = Tool<Map<String, dynamic>, String>(
      inputSchema: Schema<Map<String, dynamic>>(
        jsonSchema: const {'type': 'object'},
        fromJson: (json) => json,
      ),
      executeDynamic: (input, options) async {
        executions++;
        return 'done';
      },
    );
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(
        model: MockLanguageModelV4(response: [mockText('ok')]),
        tools: {'danger': tool},
      ),
      initial: initial,
    );

    await expectLater(
      backend.retryLastTurn(),
      throwsA(isA<RetryUnsafeError>()),
    );
    expect(executions, 0);
    expect(backend.conversation.messages.map((m) => m.id), [
      'user-1',
      'assistant-1',
    ]);
    await backend.dispose();
  });

  testWidgets('conversation scaffold retry runs a failed pure-text turn', (
    tester,
  ) async {
    final model = _RetryModel();
    final initial = Conversation(
      id: 'retry-ui',
      messages: [
        ConversationMessage(
          id: 'user-1',
          role: ConversationRole.user,
          parts: [TextPart(id: 'user-part', text: 'hello')],
        ),
        ConversationMessage(
          id: 'assistant-1',
          role: ConversationRole.assistant,
          status: ConversationMessageStatus.failed,
          parts: [TextPart(id: 'partial', text: 'partial')],
        ),
      ],
    );
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(model: model),
      initial: initial,
    );
    final controller = ConversationController(backend);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiChatScaffold.conversation(conversationController: controller),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('chat-error-retry')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-error-retry')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(model.calls, 1);
    expect(find.text('retried'), findsOneWidget);
  });

  test(
    'restored multi-step approval replay preserves assistant/tool chronology',
    () async {
      final model = _ReplayCaptureModel();
      var executions = 0;
      final agent = ToolLoopAgent(
        model: model,
        tools: {
          'deleteFile': Tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            approvalPolicy: ToolApprovalPolicy.always,
            executeDynamic: (input, options) async {
              executions++;
              return 'deleted';
            },
          ),
        },
      );
      final snapshot = Conversation(
        id: 'chronology',
        messages: [
          ConversationMessage(
            id: 'user-1',
            role: ConversationRole.user,
            parts: [TextPart(id: 'user-part', text: 'continue')],
          ),
          ConversationMessage(
            id: 'assistant-1',
            role: ConversationRole.assistant,
            status: ConversationMessageStatus.pendingApproval,
            parts: [
              ToolCallPart(
                id: 'call-a',
                callId: 'call-a',
                name: 'lookup',
                arguments: const {'id': 'a'},
              ),
              ToolResultPart(
                id: 'result-a',
                callId: 'call-a',
                toolName: 'lookup',
                output: 'found',
                outputKind: 'text',
              ),
              ReasoningPart(id: 'reasoning-b', text: 'checking'),
              ToolCallPart(
                id: 'call-b',
                callId: 'call-b',
                name: 'deleteFile',
                arguments: const {'path': '/tmp/a'},
              ),
              ApprovalPart(
                id: 'approval-b',
                callId: 'call-b',
                approvalId: 'approval-b',
                toolName: 'deleteFile',
                argumentsFingerprint: '{"path":"/tmp/a"}',
                policyVersion: 'default',
                status: ApprovalStatus.pending,
              ),
            ],
          ),
        ],
      );
      final backend = LocalConversationBackend(agent: agent, initial: _empty());
      await backend.restore(ConversationCodec.encode(snapshot));
      await backend.respondToApproval(approvalId: 'approval-b', approved: true);
      await pumpUntil(
        () =>
            backend.conversation.messages.last.status ==
            ConversationMessageStatus.complete,
      );

      expect(executions, 1);
      final prompt = model.seenPrompts.single;
      expect(prompt.map((message) => message.role), [
        LanguageModelV4Role.user,
        LanguageModelV4Role.assistant,
        LanguageModelV4Role.tool,
        LanguageModelV4Role.assistant,
        LanguageModelV4Role.tool,
      ]);
      expect(
        prompt[1].content
            .whereType<LanguageModelV4ToolCallPart>()
            .single
            .toolCallId,
        'call-a',
      );
      expect(
        prompt[2].content
            .whereType<LanguageModelV4ToolResultPart>()
            .single
            .toolCallId,
        'call-a',
      );
      expect(
        prompt[3].content.whereType<LanguageModelV4ReasoningPart>().single.text,
        'checking',
      );
      expect(
        prompt[3].content
            .whereType<LanguageModelV4ToolCallPart>()
            .single
            .toolCallId,
        'call-b',
      );
      expect(
        prompt[4].content
            .whereType<LanguageModelV4ToolResultPart>()
            .single
            .toolCallId,
        'call-b',
      );
      await backend.dispose();
    },
  );

  test(
    'new send stays submitted while only the previous assistant exists',
    () async {
      final backend = _DelayedSendBackend(
        Conversation(
          id: 'status',
          messages: [
            ConversationMessage(
              id: 'user-old',
              role: ConversationRole.user,
              parts: [TextPart(id: 'user-old-part', text: 'old')],
            ),
            ConversationMessage(
              id: 'assistant-old',
              role: ConversationRole.assistant,
              status: ConversationMessageStatus.complete,
              parts: [TextPart(id: 'assistant-old-part', text: 'old answer')],
            ),
          ],
        ),
      );
      final conversation = ConversationController(backend);
      final adapter = ConversationChatController(
        conversation,
        disposeConversationController: false,
      );
      final sending = adapter.sendText('new');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.status, ChatStatus.submitted);

    backend.release.complete();
    await sending;
    await Future<void>.delayed(Duration.zero);
    expect(adapter.status, ChatStatus.streaming);
      adapter.dispose();
      await conversation.dispose();
    },
  );
}
