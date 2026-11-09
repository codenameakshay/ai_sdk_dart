import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_programs.dart';

void main() {
  test('every golden program parses cleanly', () {
    for (final entry in goldenPrograms.entries) {
      final report = intelligentUi.parse(entry.value);
      expect(report.errors, isEmpty, reason: entry.key);
      expect(report.hasRoot, isTrue, reason: entry.key);
    }
  });

  test('there is one golden program per component', () {
    expect(goldenPrograms.keys.toSet(), {
      for (final c in IuiComponent.values) c.typeName,
    });
  });
}
