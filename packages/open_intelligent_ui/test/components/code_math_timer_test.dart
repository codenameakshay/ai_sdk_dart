import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui/src/components/timer.dart' show clock;

import '../support/pump.dart';

Finder get _horizontalScroll => find.byWidgetPredicate(
  (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
);

Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell));

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<InkWell>(_button(label)).onTap != null;

void main() {
  group('Code', () {
    testWidgets('shows the language, or "code" without one, and the source', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        r'root = Col([Code("print(1)\nprint(2)", "python"), Code("echo hi")])',
      );
      expect(find.text('python'), findsOneWidget);
      expect(find.text('code'), findsOneWidget);
      expect(find.text('print(1)\nprint(2)'), findsOneWidget);
      expect(find.text('echo hi'), findsOneWidget);
    });

    testWidgets('the code is selectable monospace text in the ink color', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Code("x = 1", "dart")])');
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.style!.fontFamily, OpenUiTheme.light.monoFontFamily);
      expect(text.style!.color, OpenUiTheme.light.ink);
    });

    testWidgets(
      'copy sends the code through services.copyText and says Copied for 1.5s',
      (tester) async {
        final p = await pumpProgram(
          tester,
          r'root = Col([Code("a = 1\nb = 2", "dart")])',
        );
        expect(find.text('Copy'), findsOneWidget);
        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(p.copied, ['a = 1\nb = 2']);
        expect(find.text('Copied'), findsOneWidget);
        expect(find.text('Copy'), findsNothing);

        await tester.pump(const Duration(milliseconds: 1499));
        expect(find.text('Copied'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 1));
        expect(find.text('Copy'), findsOneWidget);
      },
    );

    testWidgets('a second copy restarts the 1.5s countdown', (tester) async {
      final p = await pumpProgram(tester, 'root = Col([Code("x", "dart")])');
      await tester.tap(find.text('Copy'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Copied'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Copied'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Copy'), findsOneWidget);
      expect(p.copied, ['x', 'x']);
    });

    testWidgets('the copy button is announced as a button', (tester) async {
      await pumpProgram(tester, 'root = Col([Code("x", "dart")])');
      expect(find.bySemanticsLabel('Copy code'), findsOneWidget);
    });

    testWidgets('removing the block before the reset timer fires is safe', (
      tester,
    ) async {
      final p = await pumpProgram(tester, 'root = Col([Code("x", "dart")])');
      await tester.tap(find.text('Copy'));
      await tester.pump();
      p.session.update('root = Col([Text("gone")])', streaming: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('gone'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark mode uses the dark tokens', (tester) async {
      await pumpProgram(
        tester,
        'root = Col([Code("x", "dart")])',
        brightness: Brightness.dark,
      );
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.style!.color, OpenUiTheme.dark.ink);
    });
  });

  group('Math', () {
    testWidgets('renders a formula as typeset math, not as its source', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Math("E = mc^2")])');
      expect(find.byType(fm.Math), findsOneWidget);
      expect(find.text('E = mc^2'), findsNothing);
      expect(_horizontalScroll, findsOneWidget);
      expect(
        tester.widget<fm.Math>(find.byType(fm.Math)).mathStyle,
        fm.MathStyle.display,
      );
    });

    testWidgets('inline math is text style and does not scroll', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Math("x^2", true)])');
      final math = tester.widget<fm.Math>(find.byType(fm.Math));
      expect(math.mathStyle, fm.MathStyle.text);
      expect(_horizontalScroll, findsNothing);
    });

    testWidgets('a bad formula shows its TeX source in the danger color', (
      tester,
    ) async {
      await pumpProgram(tester, r'root = Col([Math("\\frac{1}{")])');
      final source = find.text(r'\frac{1}{');
      expect(source, findsOneWidget);
      final style = tester.widget<Text>(source).style!;
      expect(style.color, OpenUiTheme.light.status['danger']);
      expect(style.fontFamily, OpenUiTheme.light.monoFontFamily);
    });

    testWidgets('an unknown command is shown as written', (tester) async {
      await pumpProgram(
        tester,
        r'root = Col([Math("\\nosuchcommand{x}", true)])',
      );
      expect(find.text(r'\nosuchcommand{x}'), findsOneWidget);
    });
  });

  group('clock', () {
    test('formats minutes and seconds, and hours when there are any', () {
      expect(clock(0), '0:00');
      expect(clock(5), '0:05');
      expect(clock(59), '0:59');
      expect(clock(60), '1:00');
      expect(clock(125), '2:05');
      expect(clock(600), '10:00');
      expect(clock(3599), '59:59');
      expect(clock(3600), '1:00:00');
      expect(clock(3725), '1:02:05');
      expect(clock(36000), '10:00:00');
    });
  });

  group('Timer', () {
    const program = 'root = Col([Timer(\$left, "Tea")])\n\$left = 3';

    testWidgets('shows the label and the bound seconds as a clock', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Timer(\$left, "Tea")])\n\$left = 125',
      );
      expect(find.text('Tea'), findsOneWidget);
      expect(find.text('2:05'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('Tea')), findsWidgets);
      handle.dispose();
    });

    testWidgets('shows hours', (tester) async {
      await pumpProgram(tester, 'root = Col([Timer(\$left)])\n\$left = 3725');
      expect(find.text('1:02:05'), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('Timer')), findsWidgets);
      handle.dispose();
    });

    testWidgets('Start counts the bound variable down each second', (
      tester,
    ) async {
      final p = await pumpProgram(tester, program);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('Pause'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(p.session.state[r'$left'], 2);
      expect(find.text('0:02'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(p.session.state[r'$left'], 1);
      expect(find.text('0:01'), findsOneWidget);
    });

    testWidgets('Pause stops the count and Resume goes on from there', (
      tester,
    ) async {
      final p = await pumpProgram(tester, program);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Resume'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(p.session.state[r'$left'], 2);
      await tester.tap(find.text('Resume'));
      await tester.pump(const Duration(seconds: 1));
      expect(p.session.state[r'$left'], 1);
    });

    testWidgets('Reset restores the value the timer started from', (
      tester,
    ) async {
      final p = await pumpProgram(tester, program);
      expect(
        _enabled(tester, 'Reset'),
        isFalse,
        reason: 'nothing to reset yet',
      );
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(p.session.state[r'$left'], 1);
      expect(_enabled(tester, 'Reset'), isTrue);
      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(p.session.state[r'$left'], 3);
      expect(find.text('0:03'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(_enabled(tester, 'Reset'), isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(p.session.state[r'$left'], 3, reason: 'reset stopped the ticker');
    });

    testWidgets('reaching 0 shows the done state and disables Start', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Timer(\$left, "Tea")])\n\$left = 2',
      );
      expect(
        tester.widget<Text>(find.text('0:02')).style!.color,
        OpenUiTheme.light.ink,
      );
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(p.session.state[r'$left'], 0);
      final done = tester.widget<Text>(find.text('0:00'));
      expect(done.style!.color, OpenUiTheme.light.status['success']);
      expect(
        find.text('Start'),
        findsOneWidget,
        reason: 'stopped, so Start again',
      );
      expect(_enabled(tester, 'Start'), isFalse);
      expect(_enabled(tester, 'Reset'), isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(p.session.state[r'$left'], 0, reason: 'never below zero');

      await tester.tap(find.text('Reset'));
      await tester.pump();
      expect(p.session.state[r'$left'], 2);
      expect(
        tester.widget<Text>(find.text('0:02')).style!.color,
        OpenUiTheme.light.ink,
      );
    });

    testWidgets('a timer at 0 from the start is disabled and not done', (
      tester,
    ) async {
      await pumpProgram(tester, 'root = Col([Timer(\$left)])\n\$left = 0');
      expect(_enabled(tester, 'Start'), isFalse);
      expect(
        tester.widget<Text>(find.text('0:00')).style!.color,
        OpenUiTheme.light.ink,
      );
    });

    testWidgets('a value the model changed is picked up when it starts', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Button("Ten", @Set(\$left, 10)), Timer(\$left)])\n\$left = 3',
      );
      await tester.tap(find.text('Ten'));
      await tester.pump();
      expect(find.text('0:10'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      expect(p.session.state[r'$left'], 9);
    });

    testWidgets('text and invalid values read as numbers or zero', (
      tester,
    ) async {
      await pumpProgram(
        tester,
        'root = Col([Timer(\$a), Timer(\$b), Timer(\$c)])\n\$a = "90"\n\$b = "abc"\n\$c = -5',
      );
      expect(find.text('1:30'), findsOneWidget);
      expect(find.text('0:00'), findsNWidgets(2));
    });

    testWidgets('both buttons are disabled while the program streams', (
      tester,
    ) async {
      await pumpProgram(tester, program, streaming: true);
      expect(_enabled(tester, 'Start'), isFalse);
      expect(_enabled(tester, 'Reset'), isFalse);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:03'), findsOneWidget);
    });

    testWidgets('removing a running timer cancels its ticker', (tester) async {
      final p = await pumpProgram(tester, program);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      p.session.update('root = Col([Text("gone")])', streaming: false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('gone'), findsOneWidget);
      expect(p.session.state[r'$left'], 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the example timer program ticks in dark mode too', (
      tester,
    ) async {
      final p = await pumpProgram(
        tester,
        'root = Col([Timer(\$left, "Time left")])\n\$left = 180',
        brightness: Brightness.dark,
      );
      expect(find.text('3:00'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2:59'), findsOneWidget);
      expect(p.session.state[r'$left'], 179);
    });
  });
}
