import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('StreamingTextView', () {
    testWidgets('renders text when not streaming (selectable)', (tester) async {
      await tester.pumpWidget(
        _wrap(const StreamingTextView(text: 'final answer')),
      );
      expect(find.text('final answer'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      // No cursor when idle.
      expect(find.byKey(const ValueKey('streaming-cursor')), findsNothing);
    });

    testWidgets('shows a blinking cursor while streaming', (tester) async {
      await tester.pumpWidget(
        _wrap(const StreamingTextView(text: 'typing', isStreaming: true)),
      );
      // RichText contains the text + cursor widget span.
      expect(find.byKey(const ValueKey('streaming-cursor')), findsOneWidget);
      // Pump to advance the blink animation without leaving timers dangling.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(
        _wrap(const StreamingTextView(text: 'typing', isStreaming: false)),
      );
      expect(find.byKey(const ValueKey('streaming-cursor')), findsNothing);
    });

    testWidgets('starts blinking when it transitions into streaming', (
      tester,
    ) async {
      // Non-const so the constructor body runs at runtime, and starts idle so
      // the didUpdateWidget false->true branch (re-)starts the blink.
      await tester.pumpWidget(
        _wrap(StreamingTextView(text: 'typing', isStreaming: false)),
      );
      expect(find.byKey(const ValueKey('streaming-cursor')), findsNothing);

      await tester.pumpWidget(
        _wrap(StreamingTextView(text: 'typing', isStreaming: true)),
      );
      expect(find.byKey(const ValueKey('streaming-cursor')), findsOneWidget);

      // Advance the blink, then settle by leaving streaming so no timer dangles.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(
        _wrap(StreamingTextView(text: 'typing', isStreaming: false)),
      );
    });

    testWidgets('updates as text grows', (tester) async {
      await tester.pumpWidget(
        _wrap(const StreamingTextView(text: 'Hel', isStreaming: false)),
      );
      expect(find.text('Hel'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(const StreamingTextView(text: 'Hello', isStreaming: false)),
      );
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('Hel'), findsNothing);
    });
  });
}
