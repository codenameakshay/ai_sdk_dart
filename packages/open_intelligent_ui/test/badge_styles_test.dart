import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

void main() {
  testWidgets('Badge border combines with its tone style', (tester) async {
    final theme = OpenUiTheme.light.copyWith(
      components: const {
        'Badge': OpenUiComponentStyle(border: Colors.purple),
        'Badge.danger': OpenUiComponentStyle(foreground: Colors.amber),
      },
    );

    await pumpProgram(
      tester,
      'root = Col([Badge("New", "danger")])',
      theme: theme,
    );

    expect(
      tester.renderObject<RenderParagraph>(find.text('New')).text.style!.color,
      Colors.amber,
    );
    final badge = tester.widget<Container>(
      find
          .ancestor(of: find.text('New'), matching: find.byType(Container))
          .first,
    );
    expect((badge.decoration! as BoxDecoration).border, isA<Border>());
    expect(
      ((badge.decoration! as BoxDecoration).border! as Border).top.color,
      Colors.purple,
    );
  });
}
