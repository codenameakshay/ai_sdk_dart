import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ReasoningView', () {
    testWidgets('collapsed by default: reasoning text is not visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const ReasoningView(text: 'step by step thoughts')),
      );

      expect(find.text('Reasoning'), findsOneWidget);
      // Collapsed -> the reasoning text is not on screen (cross-fade shows the
      // empty first child).
      expect(find.text('step by step thoughts'), findsNothing);
    });

    testWidgets('expands then collapses again on tap', (tester) async {
      await tester.pumpWidget(
        _wrap(const ReasoningView(text: 'my private thoughts')),
      );
      expect(find.text('my private thoughts'), findsNothing);

      await tester.tap(find.text('Reasoning'));
      await tester.pumpAndSettle();
      expect(find.text('my private thoughts'), findsOneWidget);

      await tester.tap(find.text('Reasoning'));
      await tester.pumpAndSettle();
      expect(find.text('my private thoughts'), findsNothing);
    });

    testWidgets('respects initiallyExpanded', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ReasoningView(
            text: 'visible immediately',
            initiallyExpanded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('visible immediately'), findsOneWidget);
    });

    testWidgets('uses a custom title', (tester) async {
      await tester.pumpWidget(
        _wrap(const ReasoningView(text: 'x', title: 'Thinking')),
      );
      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('Reasoning'), findsNothing);
    });
  });
}
