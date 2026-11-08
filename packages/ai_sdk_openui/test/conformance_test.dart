import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_openui/ai_sdk_openui.dart';
import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The reference's 45 gallery programs (16 Intelligent UI examples, 2
/// dashboards, the 4 prompt examples, one per component, 4 compositions),
/// extracted by tool/extract_fixtures.mjs.
List<({String id, String code})> galleryPrograms() {
  final json =
      jsonDecode(fixture('gallery_programs.json')) as Map<String, Object?>;
  return [
    for (final group in json.values)
      for (final p in (group as List).cast<Map<String, Object?>>())
        (id: p['id'] as String, code: p['code'] as String),
  ];
}

void main() {
  final programs = galleryPrograms();
  final today = DateTime.utc(2026, 11, 8, 12);

  test('the fixture has all 45 programs', () {
    expect(programs, hasLength(45));
  });

  for (final p in programs) {
    group(p.id, () {
      test('parses with no errors, unresolved or orphaned names', () {
        final report = intelligentUi.parse(p.code);
        expect(report.hasRoot, isTrue);
        expect(report.errors, isEmpty);
        expect(report.warnings, isEmpty);
        expect(report.unresolved, isEmpty);
        expect(report.orphaned, isEmpty);
      });

      test('streams in 7-character chunks to the same tree', () async {
        final whole = OpenUiSession(intelligentUi)
          ..update(p.code, streaming: false);
        final streamed = OpenUiSession(intelligentUi);
        for (var i = 7; i < p.code.length; i += 7) {
          streamed.update(p.code.substring(0, i), streaming: true);
          expect(() => streamed.root, returnsNormally);
        }
        streamed.update(p.code, streaming: false);
        expect(_shape(streamed.root), _shape(whole.root));
        whole.dispose();
        streamed.dispose();
      });

      test('evaluates with the demo tools and no runtime issues', () async {
        final session = OpenUiSession(
          intelligentUi,
          tools: demoTools(now: () => today),
        )..update(p.code, streaming: false);
        expect(session.root, isNotNull);
        await _settle(session);
        expect(session.issues, isEmpty);
        expect(session.isQueryLoading, isFalse);
        session.dispose();
      });
    });
  }
}

/// Lets queries resolve.
Future<void> _settle(OpenUiSession session) async {
  for (var i = 0; i < 20 && (i == 0 || session.isQueryLoading); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A comparable outline of an evaluated tree: type names and leaf values.
Object? _shape(Object? v) => switch (v) {
  OpenUiElement() => {
    'type': v.typeName,
    'id': v.statementId,
    'props': _props(v),
  },
  List() => [for (final x in v) _shape(x)],
  Map() => {for (final e in v.entries) '${e.key}': _shape(e.value)},
  OpenUiAction() => 'action',
  OpenUiBinding() => 'binding:${v.variable}',
  _ => v,
};

Object? _props(OpenUiElement e) {
  final out = <String, Object?>{};
  for (final name in intelligentUi.components[e.typeName]!.props.keys) {
    if (e.props.has(name)) out[name] = _shape(e.props[name]);
  }
  return out;
}
