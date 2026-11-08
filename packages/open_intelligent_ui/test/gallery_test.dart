import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

/// The reference's 45 gallery programs, shared with the engine's tests.
List<({String id, String code})> galleryPrograms() {
  const path = 'ai_sdk_openui/test/fixtures/gallery_programs.json';
  final file = [
    File('../$path'),
    File('packages/$path'),
  ].firstWhere((f) => f.existsSync());
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return [
    for (final group in json.values)
      for (final p in (group as List).cast<Map<String, Object?>>())
        (id: p['id'] as String, code: p['code'] as String),
  ];
}

void main() {
  final programs = galleryPrograms();

  test('there are 45 gallery programs', () => expect(programs, hasLength(45)));

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      for (final p in programs) {
        testWidgets('${p.id} renders every component without an error', (
          tester,
        ) async {
          tester.view.physicalSize = const Size(1170, 2532);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          final pumped = await pumpProgram(
            tester,
            p.code,
            brightness: brightness,
            tools: demoTools(now: () => DateTime.utc(2026, 11, 8, 12)),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          expect(pumped.session.issues, isEmpty);
          expect(find.byType(OpenUiElementView), findsWidgets);
          final root = pumped.session.root!;
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w is OpenUiElementView && w.element.typeName == root.typeName,
            ),
            findsWidgets,
          );
          pumped.session.dispose();
        });
      }
    });
  }
}
