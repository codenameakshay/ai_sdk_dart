import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChatMessageList', () {
    testWidgets('renders existing messages', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'first user'),
          ModelMessage(
            role: ModelMessageRole.assistant,
            content: 'first assistant',
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ChatMessageList(controller: controller)));

      expect(find.text('first user'), findsOneWidget);
      expect(find.text('first assistant'), findsOneWidget);
    });

    testWidgets('shows the optimistic streaming bubble', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'ask'),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_wrap(ChatMessageList(controller: controller)));
      expect(find.text('ask'), findsOneWidget);

      // Use a model that holds the stream open after emitting text, so the
      // optimistic in-flight bubble is observable while streaming.
      final model = HoldingTextModel('streamed reply');
      controller.sendMessage(
        agent: ToolLoopAgent(model: model),
        text: 'ask again',
      );

      // Pump frames until the streaming content appears.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (controller.streamingContent.isNotEmpty) break;
      }

      expect(controller.streamingContent.isNotEmpty, isTrue);
      // The optimistic assistant turn renders flush via StreamingTextView
      // (no bubble), carrying the live buffer.
      expect(find.byType(StreamingTextView), findsOneWidget);
      expect(
        tester.widget<StreamingTextView>(find.byType(StreamingTextView)).text,
        'streamed reply',
      );

      // Release the stream and let it settle so no timers dangle.
      model.finish();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (controller.status == ChatStatus.ready) break;
      }
    });

    testWidgets('renders the empty state when provided and empty', (
      tester,
    ) async {
      final controller = ChatController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            controller: controller,
            emptyState: const Text('Start chatting'),
          ),
        ),
      );
      expect(find.text('Start chatting'), findsOneWidget);
    });

    testWidgets('uses a custom messageBuilder when provided', (tester) async {
      final controller = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'raw'),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _wrap(
          ChatMessageList(
            controller: controller,
            messageBuilder: (context, message, isStreaming) =>
                Text('custom:${message.content}'),
          ),
        ),
      );
      expect(find.text('custom:raw'), findsOneWidget);
    });

    testWidgets('swapping the controller re-subscribes to the new one', (
      tester,
    ) async {
      final first = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'from first'),
        ],
      );
      addTearDown(first.dispose);
      final second = ChatController(
        initialMessages: const [
          ModelMessage(role: ModelMessageRole.user, content: 'from second'),
        ],
      );
      addTearDown(second.dispose);

      await tester.pumpWidget(_wrap(ChatMessageList(controller: first)));
      expect(find.text('from first'), findsOneWidget);

      // Rebuild with a different controller -> didUpdateWidget swaps listeners.
      await tester.pumpWidget(_wrap(ChatMessageList(controller: second)));
      expect(find.text('from second'), findsOneWidget);
      expect(find.text('from first'), findsNothing);

      // The new controller is the live one: its changes drive rebuilds.
      second.append(
        const ModelMessage(role: ModelMessageRole.user, content: 'later'),
      );
      await tester.pump();
      expect(find.text('later'), findsOneWidget);
    });
  });
}
