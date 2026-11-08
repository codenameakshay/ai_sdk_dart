import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

Finder get _confetti => find.byWidgetPredicate(
  (w) =>
      w is CustomPaint &&
      w.painter.runtimeType.toString() == '_ConfettiPainter',
);

void main() {
  testWidgets('confetti keeps falling when the app around it is rebuilt', (
    tester,
  ) async {
    final session = OpenUiSession(intelligentUi)
      ..update(
        'root = Col([Celebration(\$won)])\n\$won = false',
        streaming: false,
      );
    addTearDown(session.dispose);

    Widget app(ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: OpenUiView(session: session, builders: intelligentUiBuilders),
      ),
    );

    await tester.pumpWidget(app(ThemeData.light()));
    session.update(
      'root = Col([Celebration(\$won)])\n\$won = true',
      streaming: false,
    );
    await tester.pump();
    await tester.pump();
    expect(_confetti, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(app(ThemeData.dark()));
    expect(_confetti, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_confetti, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(_confetti, findsNothing);
  });
}
