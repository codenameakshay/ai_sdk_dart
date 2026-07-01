import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

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
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(body: TypingIndicator()),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('typing-dot-0')), findsOneWidget);
      // Under reduced motion each dot is a static, dimmed Opacity (0.55)
      // rather than the animated wave.
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey('typing-dot-0')),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.55);
      // No repeating ticker is running, so settling completes immediately.
      await tester.pumpAndSettle();
    });
  });
}
