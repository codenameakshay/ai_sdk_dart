import 'package:ai_sdk_flutter_ui/src/widgets/streaming_text_view.dart';
import 'package:ai_sdk_flutter_ui/src/widgets/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: child),
  ),
);

double _dotOpacity(WidgetTester tester, int index) {
  return tester
      .widget<Opacity>(
        find.descendant(
          of: find.byKey(ValueKey('typing-dot-$index')),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;
}

double _cursorOpacity(WidgetTester tester) {
  return tester
      .widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey('streaming-cursor')),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;
}

void main() {
  group('TypingIndicator', () {
    testWidgets('renders three animated dots', (tester) async {
      await tester.pumpWidget(_wrap(const TypingIndicator()));

      expect(find.byKey(const ValueKey('typing-indicator')), findsOneWidget);
      expect(find.byKey(const ValueKey('typing-dot-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('typing-dot-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('typing-dot-2')), findsOneWidget);

      // Advance the repeating animation a little; no label by default.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows an optional label', (tester) async {
      final label = 'Assistant is typing'; // runtime value (non-const)
      await tester.pumpWidget(_wrap(TypingIndicator(label: label)));

      expect(find.text('Assistant is typing'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('dots hold steady under reduced motion', (tester) async {
      await tester.pumpWidget(
        _wrap(const TypingIndicator(), disableAnimations: true),
      );

      expect(find.byKey(const ValueKey('typing-dot-0')), findsOneWidget);
      // Under reduced motion each dot is a static, dimmed Opacity (0.55)
      // rather than the animated wave.
      expect(_dotOpacity(tester, 0), 0.55);
      // No repeating ticker is running, so settling completes immediately.
      await tester.pumpAndSettle();
    });

    testWidgets('responds when reduced motion toggles both ways', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const TypingIndicator()));

      final typingAnimatedBuilders = find.descendant(
        of: find.byKey(const ValueKey('typing-indicator')),
        matching: find.byType(AnimatedBuilder),
      );
      expect(typingAnimatedBuilders, findsNWidgets(3));
      final animatedOpacity = _dotOpacity(tester, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_dotOpacity(tester, 0), isNot(animatedOpacity));

      await tester.pumpWidget(
        _wrap(const TypingIndicator(), disableAnimations: true),
      );
      await tester.pump();

      expect(typingAnimatedBuilders, findsNothing);
      expect(_dotOpacity(tester, 0), 0.55);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_dotOpacity(tester, 0), 0.55);

      await tester.pumpWidget(_wrap(const TypingIndicator()));
      await tester.pump();

      expect(typingAnimatedBuilders, findsNWidgets(3));
      final resumedOpacity = _dotOpacity(tester, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(_dotOpacity(tester, 0), isNot(resumedOpacity));
    });

    testWidgets('announces typing as a live region', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(const TypingIndicator()));

      expect(find.bySemanticsLabel('Assistant is typing'), findsOneWidget);
      final node = tester
          .getSemantics(find.bySemanticsLabel('Assistant is typing'))
          .getSemanticsData();
      expect(node.flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });
  });

  group('StreamingCursor', () {
    testWidgets('responds when reduced motion toggles both ways', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const StreamingTextView(
            text: 'Streaming',
            isStreaming: true,
            selectable: false,
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('streaming-cursor')),
          matching: find.byType(AnimatedBuilder),
        ),
        findsOneWidget,
      );
      final animatedOpacity = _cursorOpacity(tester);
      await tester.pump(const Duration(milliseconds: 120));
      expect(_cursorOpacity(tester), isNot(animatedOpacity));

      await tester.pumpWidget(
        _wrap(
          const StreamingTextView(
            text: 'Streaming',
            isStreaming: true,
            selectable: false,
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('streaming-cursor')),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('streaming-cursor')),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      await tester.pumpWidget(
        _wrap(
          const StreamingTextView(
            text: 'Streaming',
            isStreaming: true,
            selectable: false,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('streaming-cursor')),
          matching: find.byType(AnimatedBuilder),
        ),
        findsOneWidget,
      );
      final resumedOpacity = _cursorOpacity(tester);
      await tester.pump(const Duration(milliseconds: 120));
      expect(_cursorOpacity(tester), isNot(resumedOpacity));
    });
  });
}
