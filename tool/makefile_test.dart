import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('publish covers every published package after its siblings', () async {
    final result = await Process.run('make', [
      '-n',
      'publish',
      'DART=dart',
      'FLUTTER=flutter',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final order = [
      for (final m in RegExp(
        r'pub publish -C packages/(\w+)',
      ).allMatches('${result.stdout}'))
        m[1]!,
    ];
    final pubspecs = {
      for (final dir in Directory('packages').listSync().whereType<Directory>())
        if (File('${dir.path}/pubspec.yaml').existsSync())
          dir.uri.pathSegments[1]: File(
            '${dir.path}/pubspec.yaml',
          ).readAsStringSync(),
    };
    final published = [
      for (final MapEntry(key: name, value: pubspec) in pubspecs.entries)
        if (!pubspec.contains('publish_to: none')) name,
    ];
    expect(order, unorderedEquals(published));
    for (final name in order) {
      final dependencies = pubspecs[name]!
          .split('\ndependencies:\n')
          .skip(1)
          .join()
          .split('\ndev_dependencies:')
          .first;
      for (final m in RegExp(
        r'^  (\w+):',
        multiLine: true,
      ).allMatches(dependencies)) {
        if (!pubspecs.containsKey(m[1])) continue;
        expect(
          order.indexOf(m[1]!),
          inInclusiveRange(0, order.indexOf(name) - 1),
          reason: '$name depends on ${m[1]}',
        );
      }
    }
  });

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
