// Reads fixture files with dart:io, which the web platforms lack.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:ai_sdk_openui/intelligent_ui.dart';
import 'package:test/test.dart';

import 'prompt_drift.dart';
import 'support/fixtures.dart';

/// The first line where two texts differ, for a readable failure.
String firstDifference(String actual, String expected) {
  final a = actual.split('\n'), e = expected.split('\n');
  for (var i = 0; i < a.length || i < e.length; i++) {
    final x = i < a.length ? a[i] : '<missing>';
    final y = i < e.length ? e[i] : '<missing>';
    if (x != y) return 'line ${i + 1}\n  actual:   $x\n  expected: $y';
  }
  return 'identical';
}

void main() {
  group('spec.json', () {
    final expected = jsonDecode(fixture('spec.json')) as Map<String, Object?>;
    final actual = intelligentUi.toSpec();

    test('every component signature and description matches', () {
      final want = expected['components'] as Map<String, Object?>;
      final got = actual['components'] as Map<String, Object?>;
      expect(got.keys.toList(), want.keys.toList());
      for (final name in want.keys) {
        expect(jsonEncode(got[name]), jsonEncode(want[name]), reason: name);
      }
    });

    test(r'every $def matches', () {
      final want =
          (expected['schema'] as Map)[r'$defs'] as Map<String, Object?>;
      final got = (actual['schema'] as Map)[r'$defs'] as Map<String, Object?>;
      expect(got.keys.toList(), want.keys.toList());
      for (final name in want.keys) {
        expect(jsonEncode(got[name]), jsonEncode(want[name]), reason: name);
      }
    });

    test('every function and action matches', () {
      for (final key in ['functions', 'actions']) {
        final want = expected[key] as Map<String, Object?>;
        final got = actual[key] as Map<String, Object?>;
        expect(got.keys.toList(), want.keys.toList(), reason: key);
        for (final name in want.keys) {
          expect(
            jsonEncode(got[name]),
            jsonEncode(want[name]),
            reason: '$key.$name',
          );
          final schema = (expected['schema'] as Map)[key] as Map;
          expect(
            jsonEncode(((actual['schema'] as Map)[key] as Map)[name]),
            jsonEncode(schema[name]),
            reason: 'schema.$key.$name',
          );
        }
      }
    });

    test('the whole file is byte-identical', () {
      final text = intelligentUi.toSpecJson();
      expect(
        text,
        fixture('spec.json'),
        reason: firstDifference(text, fixture('spec.json')),
      );
    });
  });

  group('system prompts', () {
    // The reference CLI writes each prompt with a trailing newline. Its
    // checked-in prompts predate its own source; prompt_drift.dart lists every
    // line that differs and why.
    String current(String golden) {
      final out = <String>[];
      for (final line in golden.split('\n')) {
        out.add(promptLineUpdates[line] ?? line);
        for (final (after, lines) in promptLineInserts) {
          if (line == after) out.addAll(lines);
        }
      }
      return out.join('\n');
    }

    test(
      'the chat prompt is system-prompt.txt brought up to date with its source',
      () {
        final text = '${intelligentUi.systemPrompt(chatPrompt)}\n';
        final want = current(fixture('system-prompt.txt'));
        expect(text == want, isTrue, reason: firstDifference(text, want));
      },
    );

    test(
      'the dashboard prompt is dashboard-system-prompt.txt brought up to date with its source',
      () {
        final text = '${intelligentUi.systemPrompt(dashboardPrompt())}\n';
        final want = current(fixture('dashboard-system-prompt.txt'));
        expect(text == want, isTrue, reason: firstDifference(text, want));
      },
    );

    test(
      'the drift only updates and adds lines, never removes golden content',
      () {
        expect(promptLineUpdates, hasLength(4));
        expect(promptLineInserts.single.$2, hasLength(4));
        for (final MapEntry(key: old, value: now)
            in promptLineUpdates.entries) {
          expect(old, isNot(now));
          expect(
            fixture('system-prompt.txt').contains(old) ||
                fixture('dashboard-system-prompt.txt').contains(old),
            isTrue,
          );
        }
      },
    );
  });
}
