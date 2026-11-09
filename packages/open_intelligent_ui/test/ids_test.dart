import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

void main() {
  testWidgets('statement elements are keyed by statement id', (tester) async {
    await pumpProgram(tester, 'root = Col([a])\na = Card([Text("x")])');
    expect(find.byKey(const ValueKey('openui:a')), findsOneWidget);
  });

  testWidgets('inline elements get parent id and position', (tester) async {
    await pumpProgram(tester, 'root = Row([Badge("a"), Badge("b")])');
    expect(
      find.byKey(const ValueKey('openui:root/children.0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('openui:root/children.1')),
      findsOneWidget,
    );
  });

  testWidgets('a statement repeated in one list is deduplicated', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Row([a, a])\na = Badge("x")');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('openui:a')), findsOneWidget);
    expect(find.byKey(const ValueKey('openui:a~2')), findsOneWidget);
  });

  testWidgets('keys survive streaming an earlier sibling', (tester) async {
    final pumped = await pumpProgram(
      tester,
      'root = Col([b])\nb = Input("", "Name")',
    );
    await tester.enterText(find.byType(TextField), 'Ana');
    await tester.pump();

    pumped.session.update(
      'root = Col([a, b])\na = Text("first")\nb = Input("", "Name")',
      streaming: false,
    );
    await tester.pump();

    expect(find.text('first'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Ana',
    );
  });

  testWidgets('semanticsIdentifiers sets identifiers', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([a])\na = Badge("x")',
      semanticsIdentifiers: true,
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('openui:a'))).identifier,
      'openui:a',
    );
  });

  testWidgets('without semanticsIdentifiers no identifier is set', (
    tester,
  ) async {
    await pumpProgram(tester, 'root = Col([a])\na = Badge("x")');
    expect(
      tester.getSemantics(find.byKey(const ValueKey('openui:a'))).identifier,
      isEmpty,
    );
  });
}
