import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChatMessageBubble', () {
    testWidgets('renders user message text (selectable)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatMessageBubble(
            message: ModelMessage(
              role: ModelMessageRole.user,
              content: 'hello there',
            ),
          ),
        ),
      );
      expect(find.text('hello there'), findsOneWidget);
      // Text is selectable.
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('renders assistant message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ChatMessageBubble(
            message: ModelMessage(
              role: ModelMessageRole.assistant,
              content: 'I am the assistant',
            ),
          ),
        ),
      );
      expect(find.text('I am the assistant'), findsOneWidget);
    });

    testWidgets('shows a typing indicator while streaming', (tester) async {
      await tester.pumpWidget(
        _wrap(ChatMessageBubble.text(text: 'partial', isStreaming: true)),
      );
      expect(find.text('partial'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('empty content renders a placeholder ellipsis', (tester) async {
      await tester.pumpWidget(_wrap(ChatMessageBubble.text(text: '')));
      expect(find.text('…'), findsOneWidget);
    });
  });
}
