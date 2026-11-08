import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/pump.dart';

void main() {
  testWidgets('Carousel preserves editing focus across streamed insertion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pumped = await pumpProgram(
      tester,
      'root = Carousel([b])\nb = Input("", "Name")',
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
      'root = Carousel([a, b])\na = Text("first")\nb = Input("", "Name")',
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
