import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
