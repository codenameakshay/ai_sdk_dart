import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_chat/pages/conversation_page.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('local conversation approval completes once', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LocalConversationPage()));
    await tester.pump();

    await _send(tester, 'Please delete the example file.');
    await _waitFor(tester, find.byKey(const ValueKey('tool-approval-approve')));
    expect(find.text('Approve tool call?'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Tool approval required for deleteFile'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-composer-field')))
          .enabled,
      isFalse,
    );
    await _waitForSingle(
      tester,
      find.byKey(const ValueKey('chat-composer-send')),
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-composer-send')))
          .onPressed,
      isNull,
    );
    await binding.takeScreenshot('conversation-local-approval');

    await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
    await _waitFor(tester, find.text('Tool result: deleted /tmp/example'));
    await _waitForFinishedTurn(tester);
    expect(find.text('Tool result: deleted /tmp/example'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-approval-approve')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-composer-field')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-composer-send')))
          .onPressed,
      isNotNull,
    );
    await _waitFor(tester, find.bySemanticsLabel(RegExp('Assistant message')));
    await binding.takeScreenshot('conversation-local-approved');
  });

  testWidgets('local conversation denial does not execute the tool', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LocalConversationPage()));
    await tester.pump();

    await _send(tester, 'Please delete the example file.');
    await _waitFor(tester, find.byKey(const ValueKey('tool-approval-deny')));
    await tester.tap(find.byKey(const ValueKey('tool-approval-deny')));
    await _waitFor(tester, find.text('Tool denied; no local action ran.'));
    await _waitForFinishedTurn(tester);

    expect(find.text('Tool denied; no local action ran.'), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-approval-deny')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-composer-field')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-composer-send')))
          .onPressed,
      isNotNull,
    );
    await _waitFor(tester, find.bySemanticsLabel(RegExp('Assistant message')));
    await binding.takeScreenshot('conversation-local-denied');
  });

  testWidgets('remote conversation returns one ordinary assistant answer', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RemoteConversationPage()));
    await tester.pump();

    await _send(tester, 'Say hello.');
    await _waitFor(tester, find.text('Hello from the pinned AI SDK backend.'));
    await _waitForFinishedTurn(tester);

    expect(find.text('Hello from the pinned AI SDK backend.'), findsOneWidget);
    await _waitFor(tester, find.bySemanticsLabel(RegExp('Assistant message')));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-composer-field')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-composer-send')))
          .onPressed,
      isNotNull,
    );
    await binding.takeScreenshot('conversation-remote-text');
  });

  testWidgets('remote conversation approval resumes after approval', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RemoteConversationPage()));
    await tester.pump();

    await _send(tester, 'I need an approval before deleting anything.');
    await _waitFor(tester, find.byKey(const ValueKey('tool-approval-approve')));
    expect(
      find.descendant(
        of: find.byType(ToolApprovalCard),
        matching: find.text('delete'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
    await _waitFor(
      tester,
      find.text('The scripted tool call was approved and resumed.'),
    );

    expect(
      find.text('The scripted tool call was approved and resumed.'),
      findsOneWidget,
    );
    await _waitForFinishedTurn(tester);
    await _waitFor(tester, find.bySemanticsLabel(RegExp('Assistant message')));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-composer-field')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-composer-send')))
          .onPressed,
      isNotNull,
    );
    await binding.takeScreenshot('conversation-remote-approved');
  });

  testWidgets('remote conversation denial resumes safely', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RemoteConversationPage()));
    await tester.pump();

    await _send(tester, 'Approval is required for this request.');
    await _waitFor(tester, find.byKey(const ValueKey('tool-approval-deny')));
    await tester.tap(find.byKey(const ValueKey('tool-approval-deny')));
    await _waitFor(
      tester,
      find.text('The scripted tool call was denied and resumed safely.'),
    );
    await _waitForFinishedTurn(tester);

    expect(
      find.text('The scripted tool call was denied and resumed safely.'),
      findsOneWidget,
    );
    await _waitFor(tester, find.bySemanticsLabel(RegExp('Assistant message')));
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-composer-field')))
          .enabled,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-composer-send')))
          .onPressed,
      isNotNull,
    );
    await binding.takeScreenshot('conversation-remote-denied');
  });

  testWidgets('conversation scaffold exposes dismissible app errors', (
    tester,
  ) async {
    final backend = _ErrorBackend();
    final conversation = ConversationController(backend);
    addTearDown(conversation.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiChatScaffold.conversation(
            conversationController: conversation,
          ),
        ),
      ),
    );
    await tester.pump();

    await _send(tester, 'Trigger an app error.');
    await _waitFor(tester, find.byKey(const ValueKey('chat-error-dismiss')));
    expect(find.text('Bad state: fixture backend failure'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await binding.takeScreenshot('conversation-error');

    await tester.tap(find.byKey(const ValueKey('chat-error-dismiss')));
    await tester.pump();
    expect(find.text('Bad state: fixture backend failure'), findsNothing);
  });

  testWidgets('local approval survives a process restart without tool replay', (
    tester,
  ) async {
    final snapshotFile = File(
      '${Directory.systemTemp.path}/ai-sdk-v3-pending-approval.json',
    );
    final model = _RestartApprovalModel();
    var executions = 0;
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(
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
              return 'deleted ${(input as Map)['path']}';
            },
          ),
        },
      ),
      initial: Conversation(id: 'restart-proof', messages: const []),
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

    if (!await snapshotFile.exists()) {
      await controller.send('Delete the example file.');
      await _waitFor(
        tester,
        find.byKey(const ValueKey('tool-approval-approve')),
      );
      expect(executions, 0);
      await snapshotFile.writeAsString(
        jsonEncode({
          'phase': 'written',
          'snapshot': ConversationCodec.encode(controller.conversation),
        }),
      );
      await IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .takeScreenshot('conversation-persisted-write');
    } else {
      final stored = jsonDecode(await snapshotFile.readAsString()) as Map;
      expect(stored['phase'], 'written');
      final encoded = (stored['snapshot'] as Map).cast<String, dynamic>();
      final original = ConversationCodec.decode(encoded);
      await controller.restore(encoded);
      await tester.pump();
      expect(model.calls, 0);
      expect(executions, 0);
      expect(
        backend.conversation.messages.map((m) => m.id),
        original.messages.map((m) => m.id),
      );
      await _waitFor(
        tester,
        find.byKey(const ValueKey('tool-approval-approve')),
      );
      await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
      await _waitFor(tester, find.text('Tool result: deleted /tmp/example'));
      await _waitForFinishedTurn(tester);
      expect(executions, 1);
      expect(model.calls, 1);
      expect(
        controller.conversation.messages.where(
          (m) => m.role == ConversationRole.user,
        ),
        hasLength(1),
      );
      await IntegrationTestWidgetsFlutterBinding.ensureInitialized()
          .takeScreenshot('conversation-persisted-restore');
      await snapshotFile.delete();
    }
  });

  testWidgets('failed text turn retries with stable message IDs', (
    tester,
  ) async {
    final model = _FailThenSucceedModel();
    final backend = LocalConversationBackend(
      agent: ToolLoopAgent(model: model),
      initial: Conversation(id: 'retry-proof', messages: const []),
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
    await _send(tester, 'Try a safe text request.');
    await _waitFor(tester, find.text('Retry'));
    final failedIds = backend.conversation.messages.map((m) => m.id).toList();
    expect(backend.retryInfo.isAvailable, isTrue);
    await tester.tap(find.text('Retry'));
    await _waitFor(tester, find.text('Retried answer.'));
    await _waitForFinishedTurn(tester);
    expect(model.calls, 2);
    expect(backend.conversation.messages.map((m) => m.id), failedIds);
    expect(
      backend.conversation.messages.where(
        (m) => m.role == ConversationRole.user,
      ),
      hasLength(1),
    );
    await IntegrationTestWidgetsFlutterBinding.ensureInitialized()
        .takeScreenshot('conversation-local-retry');
  });
}

class _FailThenSucceedModel extends LanguageModelV4 {
  int calls = 0;

  @override
  String get provider => 'retry-fixture';
  @override
  String get modelId => 'text-retry';
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
    if (++calls == 1) throw StateError('scripted text failure');
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        const StreamPartTextStart(id: 'retry-answer'),
        const StreamPartTextDelta(id: 'retry-answer', delta: 'Retried answer.'),
        const StreamPartTextEnd(id: 'retry-answer'),
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

class _RestartApprovalModel extends LanguageModelV4 {
  int calls = 0;

  @override
  String get provider => 'restart-fixture';
  @override
  String get modelId => 'restart-approval';
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
    final results = options.prompt.messages
        .expand((message) => message.content)
        .whereType<LanguageModelV4ToolResultPart>()
        .toList();
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable([
        if (results.isEmpty) ...[
          const StreamPartToolCall(
            toolCall: LanguageModelV4ToolCallPart(
              toolCallId: 'restart-call-1',
              toolName: 'deleteFile',
              input: {'path': '/tmp/example'},
            ),
          ),
        ] else ...[
          const StreamPartTextStart(id: 'restart-answer'),
          StreamPartTextDelta(
            id: 'restart-answer',
            delta:
                'Tool result: ${(results.single.output as ToolResultOutputText).text}',
          ),
          const StreamPartTextEnd(id: 'restart-answer'),
        ],
        const StreamPartFinish(finishReason: LanguageModelV4FinishReason.stop),
      ]),
    );
  }
}

Future<void> _send(WidgetTester tester, String text) async {
  final field = find.byKey(const ValueKey('chat-composer-field'));
  await tester.enterText(field, text);
  await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
  await tester.pump();
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<void> _waitForSingle(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().length != 1 && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<void> _waitForFinishedTurn(WidgetTester tester) async {
  final send = find.byKey(const ValueKey('chat-composer-send'));
  final stop = find.byKey(const ValueKey('chat-composer-stop'));
  final field = find.byKey(const ValueKey('chat-composer-field'));
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (send.evaluate().length == 1 &&
        stop.evaluate().isEmpty &&
        field.evaluate().length == 1 &&
        tester.widget<IconButton>(send).onPressed != null &&
        tester.widget<TextField>(field).enabled == true) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(stop, findsNothing);
  expect(send, findsOneWidget);
  expect(tester.widget<IconButton>(send).onPressed, isNotNull);
  expect(tester.widget<TextField>(field).enabled, isTrue);
}

class _ErrorBackend implements ConversationBackend {
  final Conversation _conversation = Conversation(
    id: 'error-fixture',
    messages: [],
  );

  @override
  Conversation get conversation => _conversation;

  @override
  Stream<Conversation> get changes => const Stream<Conversation>.empty();

  @override
  Future<void> send(String text) async {
    throw StateError('fixture backend failure');
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
  Future<void> dispose() async {}
}
