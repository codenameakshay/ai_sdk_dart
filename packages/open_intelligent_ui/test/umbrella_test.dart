// ignore_for_file: implementation_imports
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_core/components.dart';
import 'package:open_intelligent_ui_core/src/components/builtin_glyphs.dart';
import 'package:open_intelligent_ui_core/src/components/lucide_icons.dart';

void main() {
  test('the umbrella builds the whole library', () {
    expect(
      identical(intelligentUiFor(intelligentUiBuilders), intelligentUi),
      isTrue,
    );
  });

  testWidgets(
    'the umbrella view draws lucide icons and opens links by default',
    (tester) async {
      final session = OpenUiSession(intelligentUi)
        ..update('root = Col([Icon("map-pin")])', streaming: false);
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpenUiView(session: session, builders: intelligentUiBuilders),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(OutlineGlyph), findsOneWidget);
      final view = tester.widget<OpenUiView>(find.byType(OpenUiView));
      expect(view.fallbackServices.icons, equals(lucideIconResolver));
    },
  );

  test('built-in glyphs match lucide', () {
    expect(builtinGlyphs, isNotEmpty);
    for (final entry in builtinGlyphs.entries) {
      expect(lucideIcons[entry.key], entry.value, reason: entry.key);
    }
  });
}
