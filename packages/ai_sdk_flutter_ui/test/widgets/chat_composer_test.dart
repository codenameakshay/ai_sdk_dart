import 'dart:ui' as ui;

import 'package:ai_sdk_flutter_ui/src/widgets/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _tabUntilActivated(
  WidgetTester tester,
  bool Function() activated, {
  int maxTabs = 10,
}) async {
  for (var i = 0; i < maxTabs; i++) {
    if (activated()) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (activated()) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }
  fail('Unable to activate target after $maxTabs tabs');
}

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

    testWidgets('submitting the field via the keyboard action sends', (
      tester,
    ) async {
      String? sent;
      await tester.pumpWidget(_wrap(ChatComposer(onSend: (t) => sent = t)));

      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'via keyboard',
      );
      // Triggers TextField.onSubmitted -> _send(), without tapping the button.
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(sent, 'via keyboard');
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

    testWidgets('send and stop controls expose accessible labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(_wrap(ChatComposer(onSend: (_) {})));

      final sendNode = tester
          .getSemantics(
            find.byKey(const ValueKey('chat-composer-send-semantics')),
          )
          .getSemanticsData();
      expect(sendNode.label, 'Send message');
      expect(sendNode.hasAction(ui.SemanticsAction.tap), isTrue);
      final sendSize = tester.getSize(
        find.byKey(const ValueKey('chat-composer-send')),
      );
      expect(sendSize.width, greaterThanOrEqualTo(48));
      expect(sendSize.height, greaterThanOrEqualTo(48));

      await tester.pumpWidget(
        _wrap(ChatComposer(onSend: (_) {}, isLoading: true, onStop: () {})),
      );
      await tester.pumpAndSettle();

      final stopNode = tester
          .getSemantics(
            find.byKey(const ValueKey('chat-composer-stop-semantics')),
          )
          .getSemanticsData();
      expect(stopNode.label, 'Stop response');
      expect(stopNode.hasAction(ui.SemanticsAction.tap), isTrue);
      semantics.dispose();
    });

    testWidgets('attach and send are reachable and activatable by keyboard', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController(text: 'keyboard send');
      addTearDown(controller.dispose);
      var attachCalls = 0;
      String? sent;

      await tester.pumpWidget(
        _wrap(
          ChatComposer(
            controller: controller,
            onSend: (text) => sent = text,
            onAttach: () => attachCalls++,
          ),
        ),
      );

      await _tabUntilActivated(tester, () => attachCalls == 1);
      expect(attachCalls, 1);

      await _tabUntilActivated(tester, () => sent != null);
      expect(sent, 'keyboard send');
      semantics.dispose();
    });

    testWidgets('stop is reachable and activatable by keyboard', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
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

      await _tabUntilActivated(tester, () => stopped);
      expect(stopped, isTrue);
      semantics.dispose();
    });
  });
}
