import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChatErrorView', () {
    testWidgets('renders the error message', (tester) async {
      await tester.pumpWidget(
        _wrap(ChatErrorView(error: Exception('network down'))),
      );

      expect(find.textContaining('network down'), findsOneWidget);
    });

    testWidgets('prefers an explicit message over the error toString', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          ChatErrorView(
            error: Exception('raw'),
            message: 'Something went wrong',
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.textContaining('raw'), findsNothing);
    });

    testWidgets('shows a retry button only when onRetry is provided', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(
        _wrap(
          ChatErrorView(error: 'boom', onRetry: () => retried = true),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-error-retry')));
      expect(retried, isTrue);
    });

    testWidgets('shows a dismiss button only when onDismiss is provided', (
      tester,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        _wrap(
          ChatErrorView(error: 'boom', onDismiss: () => dismissed = true),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-error-dismiss')));
      expect(dismissed, isTrue);
    });

    testWidgets('omits both actions when no callbacks are given', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const ChatErrorView(error: 'boom')));

      expect(find.byKey(const ValueKey('chat-error-retry')), findsNothing);
      expect(find.byKey(const ValueKey('chat-error-dismiss')), findsNothing);
    });
  });
}
