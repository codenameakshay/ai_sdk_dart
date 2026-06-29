import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ChatComposer', () {
    testWidgets('calls onSend with trimmed text and clears the field', (
      tester,
    ) async {
      String? sent;
      await tester.pumpWidget(_wrap(ChatComposer(onSend: (t) => sent = t)));

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        '  hi there  ',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();

      expect(sent, 'hi there');
      // Internal controller cleared the field.
      expect(find.text('  hi there  '), findsNothing);
    });

    testWidgets('does not send empty/whitespace text', (tester) async {
      var calls = 0;
      await tester.pumpWidget(_wrap(ChatComposer(onSend: (_) => calls++)));
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        '   ',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      expect(calls, 0);
    });

    testWidgets('send button is disabled while loading', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        _wrap(ChatComposer(onSend: (_) => calls++, isLoading: true)),
      );

      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('chat-composer-send')),
      );
      expect(button.onPressed, isNull);

      // Tapping does nothing.
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'hello',
      );
      await tester.tap(
        find.byKey(const ValueKey('chat-composer-send')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(calls, 0);
    });

    testWidgets('shows a stop button when loading with onStop', (tester) async {
      var stopped = false;
      await tester.pumpWidget(
        _wrap(
          ChatComposer(
            onSend: (_) {},
            isLoading: true,
            onStop: () => stopped = true,
          ),
        ),
      );

      expect(find.byKey(const ValueKey('chat-composer-stop')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-composer-send')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('chat-composer-stop')));
      await tester.pump();
      expect(stopped, isTrue);
    });

    testWidgets('shows an attach button only when onAttach is set', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(ChatComposer(onSend: (_) {})));
      expect(find.byKey(const ValueKey('chat-composer-attach')), findsNothing);

      var attached = false;
      await tester.pumpWidget(
        _wrap(ChatComposer(onSend: (_) {}, onAttach: () => attached = true)),
      );
      expect(
        find.byKey(const ValueKey('chat-composer-attach')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-attach')));
      await tester.pump();
      expect(attached, isTrue);
    });
  });
}
