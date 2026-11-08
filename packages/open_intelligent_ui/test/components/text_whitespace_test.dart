import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump.dart';

String _plain(WidgetTester tester, String contains) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((t) => t.text.toPlainText())
    .firstWhere((t) => t.contains(contains));

void main() {
  testWidgets('text collapses spaces like white-space: pre-line', (
    tester,
  ) async {
    await pumpProgram(
      tester,
      'root = Col([a, b, c])\n'
      'a = Text(["", " About 6 years"])\n'
      'b = Text(["two ", " parts   here"])\n'
      'c = Text("first line   \\n   second")',
    );
    expect(_plain(tester, 'About'), 'About 6 years');
    expect(_plain(tester, 'parts'), 'two parts here');
    expect(_plain(tester, 'first'), 'first line\nsecond');
  });

  testWidgets('a space after an inline component stays', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Text([Icon("check", "sm"), " 7 years"])])',
    );
    expect(_plain(tester, '7 years'), contains(' 7 years'));
  });
}
