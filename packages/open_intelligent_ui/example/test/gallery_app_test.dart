import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/components.dart' show OutlineGlyph;
import 'package:open_intelligent_ui/open_intelligent_ui.dart';
import 'package:open_intelligent_ui_gallery/main.dart';

const _example = 'packages/open_intelligent_ui/example';

/// [path] from the example's directory, or from the repo root.
File _file(String path) =>
    [File(path), File('$_example/$path')].firstWhere((f) => f.existsSync());

String _asset() => _file('assets/gallery_programs.json').readAsStringSync();

void main() {
  final programs = gallerySections(_asset()).expand((s) => s.programs).toList();

  for (final brightness in Brightness.values) {
    for (final program in programs) {
      testWidgets('${program.id} renders its content in ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: ProgramPage(program: program),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          final view = find.byType(OpenUiView);
          final session = tester.widget<OpenUiView>(view).session;
          expect(session.errors, isEmpty);
          expect(session.root, isNotNull);
          expect(
            find.descendant(of: view, matching: find.byType(ErrorWidget)),
            findsNothing,
          );
          expect(tester.getSize(view).height, greaterThan(0));
          expect(Theme.of(tester.element(view)).brightness, brightness);
          final heading = RegExp(
            r'Title\("([^"\\]*)"',
          ).firstMatch(program.code);
          if (heading != null) {
            expect(
              find.descendant(
                of: view,
                matching: find.textContaining(heading.group(1)!),
              ),
              findsWidgets,
            );
          } else if (program.id == 'buttons') {
            expect(find.text('Customize my capsule'), findsOneWidget);
          } else {
            expect(program.id, 'icons');
            expect(
              find.descendant(of: view, matching: find.byType(OutlineGlyph)),
              findsNWidgets(8),
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

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
    await tester.tap(find.text('Customize my capsule'));
    await tester.pump();
    expect(
      find.textContaining('Sent to the assistant: “Customize my capsule”'),
      findsOneWidget,
    );
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

  testWidgets('an empty gallery keeps navigation and settings usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const GalleryApp(
        programs:
            '{"compositionPrograms":[],"toolPrograms":[],"examples":[],"programs":[]}',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OpenUiView), findsNothing);
    expect(find.text('Chat demo'), findsOneWidget);
    await tester.tap(find.byTooltip('Dark theme'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Light theme'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reopening a program starts fresh rather than keeping old fields',
    (tester) async {
      await tester.pumpWidget(GalleryApp(programs: _asset()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Checkbox list'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Checkbox list'));
      await tester.pumpAndSettle();
      expect(find.text('2/6 packed'), findsOneWidget);
      await tester.tap(find.text('Relaxed Oxford shirt'));
      await tester.pumpAndSettle();
      expect(find.text('3/6 packed'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checkbox list'));
      await tester.pumpAndSettle();
      expect(find.text('2/6 packed'), findsOneWidget);
      expect(find.text('3/6 packed'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
