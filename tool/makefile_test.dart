import 'dart:io';

import 'package:test/test.dart';

void main() {
  for (final target in ['format', 'format-check']) {
    test('$target includes repository Dart tooling', () async {
      final result = await Process.run('make', ['-n', target, 'DART=fvm dart']);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(result.stdout, contains('packages/ examples/ tool/'));
    });
  }

  test('ordinary test matrix runs the basic CLI lifecycle assertions', () async {
    final result = await Process.run('make', ['-n', 'test', 'DART=fvm dart']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(
      result.stdout,
      contains(
        'fvm dart --enable-asserts run examples/basic/test/client_lifetime_test.dart',
      ),
    );
  });

  test('ordinary test matrix fails when basic CLI assertions fail', () async {
    final result = await Process.run('make', [
      '-s',
      'test',
      r'''DART=sh -c 'case "$$*" in *examples/basic/test/client_lifetime_test.dart*) exit 23;; esac' stub''',
      'FLUTTER=true',
    ]);
    expect(result.exitCode, isNonZero);
    expect(result.stderr, contains('Error 23'));
  });

  test(
    'ordinary test matrix runs provider lifecycle fixtures with dummy keys',
    () async {
      final result = await Process.run('make', [
        '-n',
        'test',
        'FLUTTER=fvm flutter',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout,
        contains(
          'fvm flutter test --dart-define=OPENAI_API_KEY=fixture --dart-define=ANTHROPIC_API_KEY=fixture --dart-define=GOOGLE_API_KEY=fixture examples/advanced_app/test/provider_lifecycle_test.dart',
        ),
      );
      expect(
        result.stdout,
        contains(
          'examples/advanced_app/test/provider_lifecycle_test.dart examples/advanced_app/test/media_page_lifetime_test.dart examples/advanced_app/test/media_picker_lifetime_test.dart',
        ),
      );
    },
  );
}
