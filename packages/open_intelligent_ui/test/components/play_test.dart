import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/play.dart'
    show Celebration, Flashcard;

import '../support/pump.dart';

Finder get _confetti => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_ConfettiPainter',
);

const _win =
    'root = Col([Button("Win", @Set(\$won, true)), Button("Lose", @Set(\$won, false)), Celebration(\$won)])\n\$won = false';

void main() {
  group('Flashcard', () {
    testWidgets(
      'shows the front and the default hint, and flips to the back on tap',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([Flashcard("Capital of France?", "**Paris**")])',
        );
        expect(find.text('Capital of France?'), findsOneWidget);
        expect(find.text('Tap to flip'), findsOneWidget);
        expect(find.text('Paris'), findsNothing);

        await tester.tap(find.text('Capital of France?'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Paris'), findsOneWidget);
        expect(find.text('Capital of France?'), findsNothing);
        expect(find.text('Tap to flip'), findsNothing);
      },
    );

    testWidgets('the back renders inline Markdown', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Flashcard("Front", "Back **bold**")])',
      );
      await tester.tap(find.text('Front'));
      await tester.pump();
      expect(
        find.text('Front'),
        findsOneWidget,
        reason: 'the turn has not started',
      );
      await tester.pump(const Duration(milliseconds: 500));
      final back = tester.widget<RichText>(
        find
            .descendant(
              of: find.byType(Flashcard),
              matching: find.byType(RichText),
            )
            .first,
      );
      final plain = back.text.toPlainText();
      expect(plain, contains('Back'));
      expect(plain, contains('bold'));
      expect(plain, isNot(contains('**')));
    });

    testWidgets('tapping again flips back to the front', (tester) async {
      await pumpProgram(tester, 'root = Col([Flashcard("Front", "Back")])');
      await tester.tap(find.text('Front'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Front'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets(
      'a custom hint replaces the default and an empty one falls back',
      (tester) async {
        await pumpProgram(
          tester,
          'root = Col([Flashcard("A", "B", "Click me"), Flashcard("C", "D", "")])',
        );
        expect(find.text('Click me'), findsOneWidget);
        expect(find.text('Tap to flip'), findsOneWidget);
      },
    );

    testWidgets('faces may be components', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Flashcard(Title("Front title"), Col([Text("Back one"), Text("Back two")]))])',
      );
      expect(find.text('Front title'), findsOneWidget);
      await tester.tap(find.text('Front title'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Back one'), findsOneWidget);
      expect(find.text('Back two'), findsOneWidget);
    });

    testWidgets('reports itself as a toggle button', (tester) async {
      await pumpProgram(tester, 'root = Col([Flashcard("Front", "Back")])');
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.byType(Flashcard)),
        isSemantics(isButton: true, hasToggledState: true, isToggled: false),
      );
      await tester.tap(find.text('Front'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.getSemantics(find.byType(Flashcard)),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true),
      );
      handle.dispose();
    });

    testWidgets('works in dark mode', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Flashcard("Front", "Back")])',
        brightness: Brightness.dark,
      );
      await tester.tap(find.text('Front'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Back'), findsOneWidget);
    });
  });

  group('Celebration', () {
    testWidgets(
      'bursts confetti into the Overlay when when turns true, then removes it',
      (tester) async {
        await pumpProgram(tester, _win);
        expect(_confetti, findsNothing);

        await tester.tap(find.text('Win'));
        await tester.pump();
        await tester.pump();
        expect(_confetti, findsOneWidget);
        expect(
          find.ancestor(of: _confetti, matching: find.byType(IgnorePointer)),
          findsWidgets,
        );

        await tester.pump(const Duration(milliseconds: 1000));
        expect(_confetti, findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1000));
        expect(_confetti, findsOneWidget, reason: 'about 2.2s in total');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(_confetti, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the confetti paints something while it falls', (tester) async {
      await pumpProgram(tester, _win);
      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final box = tester.renderObject<RenderBox>(_confetti);
      expect(box, paints..rrect());
    });

    testWidgets('already true on first build does not burst', (tester) async {
      await pumpProgram(tester, _win.replaceFirst('false', 'true'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsNothing);
    });

    testWidgets('a program that is still streaming does not burst', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        _win.replaceFirst('\$won = false', '\$won = true'),
        streaming: true,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsNothing);
      p.session.update(
        _win.replaceFirst('\$won = false', '\$won = true'),
        streaming: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        _confetti,
        findsNothing,
        reason: 'it never saw false after streaming',
      );
    });

    testWidgets('only a change from false to true bursts, again each time', (
      tester,
    ) async {
      await pumpProgram(tester, _win);
      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(_confetti, findsNothing);

      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsNothing, reason: 'true to true is not a change');

      await tester.tap(find.text('Lose'));
      await tester.pump();
      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a second burst while one is falling replaces it', (
      tester,
    ) async {
      await pumpProgram(tester, _win);
      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Lose'));
      await tester.pump();
      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(_confetti, findsNothing);
    });

    testWidgets('removing the component while confetti falls cleans up', (
      tester,
    ) async {
      final p = await pumpProgram(tester, _win);
      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_confetti, findsOneWidget);
      p.session.update('root = Col([Text("gone")])', streaming: false);
      await tester.pump();
      await tester.pump();
      expect(_confetti, findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('gone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a non-boolean when never bursts', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Button("Set", @Set(\$won, 1)), Celebration(\$won)])\n\$won = 0',
      );
      await tester.tap(find.text('Set'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsNothing);
    });

    testWidgets('reduced motion skips the confetti', (tester) async {
      final session = OpenUiSession(intelligentUi)
        ..update(_win, streaming: false);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: OpenUiView(
              session: session,
              builders: intelligentUiBuilders,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Win'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_confetti, findsNothing);
    });

    testWidgets('Celebration alone renders no visible box', (tester) async {
      await pumpProgram(tester, 'root = Col([Celebration(false)])');
      expect(tester.getSize(find.byType(Celebration)).height, 0);
    });
  });
}
