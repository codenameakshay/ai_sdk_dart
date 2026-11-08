import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_gallery/main.dart';

const _example = 'packages/open_intelligent_ui/example';

/// [path] from the example's directory, or from the repo root.
File _file(String path) =>
    [File(path), File('$_example/$path')].firstWhere((f) => f.existsSync());

String _asset() => _file('assets/gallery_programs.json').readAsStringSync();

void main() {
  test('the bundled programs match the engine fixture', () {
    expect(
      _asset(),
      _file(
        '../../ai_sdk_openui/test/fixtures/gallery_programs.json',
      ).readAsStringSync(),
    );
  });

  test('the gallery has every program in its three sections', () {
    final sections = gallerySections(_asset());
    expect(
      [for (final s in sections) s.title],
      ['Composition', 'Working tools', 'Components'],
    );
    expect(sections.fold(0, (n, s) => n + s.programs.length), 45);
  });

  testWidgets('a program opens, renders and sends @ToAssistant as a notice', (
    tester,
  ) async {
    await tester.pumpWidget(GalleryApp(programs: _asset()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Buttons'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Buttons'));
    await tester.pumpAndSettle();
    expect(find.byType(OpenUiView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the theme toggle switches to dark', (tester) async {
    await tester.pumpWidget(GalleryApp(programs: _asset()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dark theme'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Component gallery'))).brightness,
      Brightness.dark,
    );
  });
}
