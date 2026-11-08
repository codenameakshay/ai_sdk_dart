import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/src/components/play.dart' show Flashcard;

import '../support/pump.dart';

void main() {
  testWidgets('a flashcard keeps the taller face height on both sides', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answer = List.filled(12, 'a long answer').join(' ');
    await pumpProgram(tester, 'root = Col([Flashcard("Hi", "$answer")])');
    final front = tester.getSize(find.byType(Flashcard)).height;
    expect(front, greaterThan(168));

    await tester.tap(find.byType(Flashcard));
    await tester.pumpAndSettle();
    expect(find.text('Hi'), findsNothing);
    expect(tester.getSize(find.byType(Flashcard)).height, front);
  });
}
