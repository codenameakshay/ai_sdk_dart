import 'dart:ui' as ui;

import 'package:ai_sdk_flutter_ui/src/widgets/chat_composer.dart';
import 'package:ai_sdk_flutter_ui/src/widgets/ui_strings.dart';
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

    testWidgets('does not submit while IME composition is active', (
      tester,
    ) async {
      var calls = 0;
      final controller = TextEditingController.fromValue(
        const TextEditingValue(
          text: 'かな',
          composing: TextRange(start: 0, end: 2),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _wrap(ChatComposer(controller: controller, onSend: (_) => calls++)),
      );

      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      expect(calls, 0);

      controller.value = const TextEditingValue(text: 'かな');
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('uses localized labels from the inherited scope', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiSdkUiStringsScope(
              strings: const AiSdkUiStrings(
                messageHint: 'Nachricht',
                sendMessage: 'Senden',
                attachFile: 'Datei anhängen',
              ),
              child: ChatComposer(onSend: (_) {}, onAttach: () {}),
            ),
          ),
        ),
      );

      expect(find.text('Nachricht'), findsOneWidget);
      expect(find.byTooltip('Senden'), findsOneWidget);
      expect(find.byTooltip('Datei anhängen'), findsOneWidget);
    });

    testWidgets('remains usable at large text scale in a narrow width', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Scaffold(
              body: SizedBox(width: 240, child: ChatComposer(onSend: (_) {})),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('chat-composer-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-composer-send')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('replaces the editor session when disabled', (tester) async {
      final controller = TextEditingController(text: 'draft');
      addTearDown(controller.dispose);
      var sent = 0;
      var attached = 0;

      Widget buildComposer({required bool enabled}) => _wrap(
        ChatComposer(
          controller: controller,
          enabled: enabled,
          onSend: (_) => sent++,
          onAttach: () => attached++,
        ),
      );

      await tester.pumpWidget(buildComposer(enabled: true));
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'draft text',
      );
      expect(controller.text, 'draft text');

      await tester.pumpWidget(buildComposer(enabled: false));
      await tester.pump();

      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('chat-composer-field')),
            )
            .enabled,
        isFalse,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'blocked',
      );
      expect(controller.text, 'draft text');
      await tester.tap(
        find.byKey(const ValueKey('chat-composer-send')),
        warnIfMissed: false,
      );
      await tester.tap(
        find.byKey(const ValueKey('chat-composer-attach')),
        warnIfMissed: false,
      );
      expect(sent, 0);
      expect(attached, 0);

      await tester.pumpWidget(buildComposer(enabled: true));
      await tester.pump();
      expect(controller.text, 'draft text');
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'ready again',
      );
      await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
      await tester.pump();
      expect(sent, 1);
      expect(controller.text, 'ready again');
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

    testWidgets('disabled composer disables stop physically and semantically', (
      tester,
    ) async {
      var stopped = false;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          ChatComposer(
            onSend: (_) {},
            isLoading: true,
            enabled: false,
            onStop: () => stopped = true,
          ),
        ),
      );
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('chat-composer-stop')),
      );
      expect(button.onPressed, isNull);
      final node = tester
          .getSemantics(
            find.byKey(const ValueKey('chat-composer-stop-semantics')),
          )
          .getSemanticsData();
      expect(node.hasAction(ui.SemanticsAction.tap), isFalse);
      await tester.tap(
        find.byKey(const ValueKey('chat-composer-stop')),
        warnIfMissed: false,
      );
      expect(stopped, isFalse);
      semantics.dispose();
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

    testWidgets('tracks controller ownership through widget updates', (
      tester,
    ) async {
      final external = TextEditingController(text: 'external');
      addTearDown(external.dispose);

      await tester.pumpWidget(_wrap(ChatComposer(onSend: (_) {})));
      await tester.enterText(
        find.byKey(const ValueKey('chat-composer-field')),
        'internal',
      );

      await tester.pumpWidget(
        _wrap(ChatComposer(controller: external, onSend: (_) {})),
      );
      expect(find.text('external'), findsOneWidget);

      external.text = 'updated';
      await tester.pump();
      expect(find.text('updated'), findsOneWidget);

      await tester.pumpWidget(_wrap(ChatComposer(onSend: (_) {})));
      expect(find.text('updated'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      external.text = 'still usable';
      expect(external.text, 'still usable');
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
