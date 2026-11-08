import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

void main() {
  testWidgets('Card foreground combines with its variant style', (
    tester,
  ) async {
    final theme = OpenUiTheme.light.copyWith(
      components: const {
        'Card': OpenUiComponentStyle(foreground: Colors.purple),
        'Card.soft': OpenUiComponentStyle(background: Colors.amber),
      },
    );

    await pumpProgram(
      tester,
      'root = Card([Text("card body")], "soft")',
      theme: theme,
    );

    expect(
      tester
          .renderObject<RenderParagraph>(find.text('card body'))
          .text
          .style!
          .color,
      Colors.purple,
    );
    final card = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('card body'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((card.decoration! as BoxDecoration).color, Colors.amber);
  });
}
