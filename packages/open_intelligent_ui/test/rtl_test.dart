import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_intelligent_ui/open_intelligent_ui.dart';

import 'support/pump.dart';

/// The reference's gallery programs, read from the engine package's fixtures
/// (the same file gallery_test.dart reads).
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
  testWidgets('Button aligns to the start', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Button("Go")])',
      textDirection: TextDirection.rtl,
    );
    final viewRect = tester.getRect(find.byType(OpenUiView));
    final buttonRect = tester.getRect(find.bySemanticsLabel('Go'));
    expect(buttonRect.right, closeTo(viewRect.right, 0.5));
  });

  testWidgets('Row and wrap mirror', (tester) async {
    await pumpProgram(
      tester,
      'root = Row([Text("A"), Text("B")], 2, null, null, true)',
      textDirection: TextDirection.rtl,
    );
    final a = tester.getCenter(find.text('A'));
    final b = tester.getCenter(find.text('B'));
    expect(a.dx, greaterThan(b.dx));
  });

  testWidgets('Table mirrors columns', (tester) async {
    await pumpProgram(
      tester,
      'root = Col([Table(["A", "B"], [["x", "y"]])])',
      textDirection: TextDirection.rtl,
    );
    final first = tester.getCenter(find.text('A'));
    final second = tester.getCenter(find.text('B'));
    expect(first.dx, greaterThan(second.dx));
  });

  testWidgets('Badge padding mirrors', (tester) async {
    await pumpProgram(
      tester,
      'root = Badge("Live", null, "check")',
      textDirection: TextDirection.rtl,
    );
    final viewRect = tester.getRect(find.byType(OpenUiView));
    final icon = tester.getRect(find.byType(Glyph));
    final text = tester.getRect(find.text('Live'));
    expect(icon.left, greaterThan(text.right));
    expect(viewRect.right - icon.right, closeTo(8, 0.5));
  });

  for (final p in galleryPrograms()) {
    testWidgets('gallery ${p.id} renders RTL', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final pumped = await pumpProgram(
        tester,
        p.code,
        textDirection: TextDirection.rtl,
        tools: demoTools(now: () => DateTime.utc(2026, 11, 8, 12)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(pumped.session.issues, isEmpty);
      pumped.session.dispose();
    });
  }
}
