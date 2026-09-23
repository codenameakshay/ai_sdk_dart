import 'package:ai_sdk_conversation/ai_sdk_conversation.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
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
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('chat-composer-send')))
          .onPressed,
      isNull,
    );
    await binding.takeScreenshot('conversation-local-approval');

    await tester.tap(find.byKey(const ValueKey('tool-approval-approve')));
    await _waitFor(tester, find.text('Tool result: deleted /tmp/example'));
    await _waitForSingle(
      tester,
      find.byKey(const ValueKey('chat-composer-send')),
    );
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
    expect(find.bySemanticsLabel(RegExp('Assistant message')), findsOneWidget);
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
    await _waitForSingle(
      tester,
      find.byKey(const ValueKey('chat-composer-send')),
    );

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
    expect(find.bySemanticsLabel(RegExp('Assistant message')), findsOneWidget);
    await binding.takeScreenshot('conversation-local-denied');
  });

  testWidgets('remote conversation returns one ordinary assistant answer', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RemoteConversationPage()));
    await tester.pump();

    await _send(tester, 'Say hello.');
    await _waitFor(tester, find.text('Hello from the pinned AI SDK backend.'));
    await _waitForSingle(
      tester,
      find.byKey(const ValueKey('chat-composer-send')),
    );

    expect(find.text('Hello from the pinned AI SDK backend.'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Assistant message')), findsOneWidget);
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
    await _waitForSingle(
      tester,
      find.byKey(const ValueKey('chat-composer-send')),
    );
    expect(find.bySemanticsLabel(RegExp('Assistant message')), findsOneWidget);
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
    await _waitForSingle(
      tester,
      find.byKey(const ValueKey('chat-composer-send')),
    );

    expect(
      find.text('The scripted tool call was denied and resumed safely.'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Assistant message')), findsOneWidget);
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
