import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

void main() {
  testWidgets('Table foreground and padding restyle every cell', (
    tester,
  ) async {
    const cellPadding = EdgeInsets.all(30);
    final theme = OpenUiTheme.light.copyWith(
      components: const {
        'Table': OpenUiComponentStyle(
          foreground: Colors.purple,
          padding: cellPadding,
        ),
      },
    );

    await pumpProgram(
      tester,
      'root = Col([Table(["Header"], [["body"]])])',
      theme: theme,
    );

    for (final text in ['Header', 'body']) {
      expect(
        tester.renderObject<RenderParagraph>(find.text(text)).text.style!.color,
        Colors.purple,
      );
      expect(
        find.ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate(
            (widget) => widget is Padding && widget.padding == cellPadding,
          ),
        ),
        findsOneWidget,
      );
    }
  });
}
