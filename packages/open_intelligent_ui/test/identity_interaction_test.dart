import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

void main() {
  for (final (layout, initialRoot, updatedRoot) in [
    ('Col', 'Col([b])', 'Col([a, b])'),
    ('Row', 'Row([b])', 'Row([a, b])'),
    ('Grid', 'Grid([b])', 'Grid([a, b])'),
    ('Grid cross-row', 'Grid([b])', 'Grid([x, a, b])'),
    ('Box column', 'Box([b])', 'Box([a, b])'),
    ('Box row', 'Box([b], "row")', 'Box([a, b], "row")'),
    ('Card', 'Card([b])', 'Card([a, b])'),
    ('Form', 'Form([b])', 'Form([a, b])'),
  ]) {
    testWidgets('$layout preserves editing focus across streamed insertion', (
      tester,
    ) async {
      final pumped = await pumpProgram(
        tester,
        'root = $initialRoot\nb = Input("", "Name")',
      );
      await tester.enterText(find.byType(TextField), 'Ana');
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.widget.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      await tester.pump();
      expect(editable.widget.focusNode.hasFocus, isTrue);

      pumped.session.update(
        'root = $updatedRoot\nx = Text("before")\na = Text("first")\nb = Input("", "Name")',
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
}
