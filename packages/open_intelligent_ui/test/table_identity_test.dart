import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

void main() {
  testWidgets('table slots keep deterministic ids through streamed rows', (
    tester,
  ) async {
    final pumped = await pumpProgram(
      tester,
      'root = Table(["A", "B"], [[b, b], [Badge("inline"), ""]])\n'
      'b = Badge("shared")',
      semanticsIdentifiers: true,
      streaming: true,
    );
    final first = find.byKey(const ValueKey('openui:b'));
    final second = find.byKey(const ValueKey('openui:b~2'));
    final inline = find.byKey(const ValueKey('openui:root/r1.c0.0'));
    final firstState = tester.state(first);
    final secondState = tester.state(second);
    final inlineState = tester.state(inline);
    expect(tester.getSemantics(first).identifier, 'openui:b');
    expect(tester.getSemantics(second).identifier, 'openui:b~2');
    expect(tester.getSemantics(inline).identifier, 'openui:root/r1.c0.0');

    pumped.session.update(
      'root = Table(["A", "B"], [[b, b], [Badge("inline"), ""], [b, ""]])\n'
      'b = Badge("shared")',
      streaming: false,
    );
    await tester.pump();
    expect(tester.state(first), same(firstState));
    expect(tester.state(second), same(secondState));
    expect(tester.state(inline), same(inlineState));
    final third = find.byKey(const ValueKey('openui:b~3'));
    expect(tester.getSemantics(third).identifier, 'openui:b~3');
    expect(find.text('shared'), findsNWidgets(3));
  });

  testWidgets('table preserves editing focus when a row streams before it', (
    tester,
  ) async {
    final pumped = await pumpProgram(
      tester,
      'root = Table(["Name"], [[b]])\nb = Input("", "Name")',
    );
    await tester.enterText(find.byType(TextField), 'Ana');
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 2,
    );
    await tester.pump();
    expect(editable.widget.focusNode.hasFocus, isTrue);

    pumped.session.update(
      'root = Table(["Name"], [["first"], [b]])\nb = Input("", "Name")',
      streaming: true,
    );
    await tester.pump();

    expect(find.text('first'), findsOneWidget);
    final after = tester.state<EditableTextState>(find.byType(EditableText));
    expect(after.widget.focusNode.hasFocus, isTrue);
    expect(after, same(editable));
    expect(after.widget.controller.text, 'Ana');
    expect(
      after.widget.controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
  });
}
