import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

class _ComposerProbeController extends ChatController {
  @override
  Future<void> sendMessage({
    required ToolLoopAgent agent,
    required String text,
  }) async {
    append(ModelMessage(role: ModelMessageRole.user, content: text));
  }
}

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
      final controller = _ComposerProbeController();
      addTearDown(controller.dispose);
      final agent = ToolLoopAgent(
        model: MockLanguageModelV3(doStreamError: StateError('ignored')),
      );

      await tester.pumpWidget(
        _wrap(AiChatScaffold(controller: controller, agent: agent)),
      );

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'Hello',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();

      // The composer routes through the controller.
      expect(find.text('Hello'), findsOneWidget);
      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.content, 'Hello');
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
