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

    testWidgets('streamed text keeps its own direction', (tester) async {
      Widget view({required bool isStreaming}) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: StreamingTextView(
              text: 'Delete the file.',
              isStreaming: isStreaming,
            ),
          ),
        ),
      );

      await tester.pumpWidget(view(isStreaming: false));
      expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textDirection,
        TextDirection.ltr,
      );

      await tester.pumpWidget(view(isStreaming: true));
      expect(
        tester
            .widget<RichText>(
              find.descendant(
                of: find.byType(StreamingTextView),
                matching: find.byType(RichText),
              ),
            )
            .textDirection,
        TextDirection.ltr,
      );
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

    testWidgets('renders a plain Text when not selectable', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const StreamingTextView(
            text: 'static',
            isStreaming: false,
            selectable: false,
          ),
        ),
      );
      expect(find.text('static'), findsOneWidget);
      // The non-selectable branch uses a plain Text, not SelectableText.
      expect(find.byType(SelectableText), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StreamingTextView),
          matching: find.byType(Text),
        ),
        findsOneWidget,
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
