import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AiChatScaffold', () {
    testWidgets('composes a message list and a composer', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'seed message'),
        ],
      );
      addTearDown(controller.dispose);
      final agent = ToolLoopAgent(
        model: MockLanguageModelV3(response: [mockText('reply')]),
      );

      await tester.pumpWidget(
        _wrap(AiChatScaffold(controller: controller, agent: agent)),
      );

      expect(find.byType(ChatMessageList), findsOneWidget);
      expect(find.byType(ChatComposer), findsOneWidget);
      expect(find.text('seed message'), findsOneWidget);
    });

    testWidgets('sending via the composer drives the controller', (
      tester,
    ) async {
      final controller = ChatController();
      addTearDown(controller.dispose);
      final agent = ToolLoopAgent(
        model: MockLanguageModelV3(response: [mockText('Hi back')]),
      );

      await tester.pumpWidget(
        _wrap(AiChatScaffold(controller: controller, agent: agent)),
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'Hello',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));

      // Pump frames until the conversation settles.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (controller.status == ChatStatus.ready &&
            controller.messages.length >= 2) {
          break;
        }
      }

      // user message + assistant reply rendered.
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Hi back'), findsOneWidget);
      expect(controller.messages, hasLength(2));
    });

    testWidgets('shows an empty state when there are no messages', (
      tester,
    ) async {
      final controller = ChatController();
      addTearDown(controller.dispose);
      final agent = ToolLoopAgent(model: MockLanguageModelV3());

      await tester.pumpWidget(
        _wrap(
          AiChatScaffold(
            controller: controller,
            agent: agent,
            emptyState: const Center(child: Text('No messages yet')),
          ),
        ),
      );
      expect(find.text('No messages yet'), findsOneWidget);
    });
  });
}
