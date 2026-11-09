import 'dart:io';

import 'package:test/test.dart';

import 'hosted_deps.dart';

/// The pubspec of every package under packages/, by directory name.
final _packages = {
  for (final dir in Directory('packages').listSync().whereType<Directory>())
    if (File('${dir.path}/pubspec.yaml').existsSync())
      dir.uri.pathSegments[1]: File(
        '${dir.path}/pubspec.yaml',
      ).readAsStringSync(),
};

String _version(String pubspec) =>
    RegExp(r'^version: (\S+)', multiLine: true).firstMatch(pubspec)?[1] ?? '';

/// A sibling whose CHANGELOG heads its current version with "(unreleased)"
/// is not on pub.dev at that version, so a hosted `^<that version>` cannot
/// resolve for a git consumer.
bool _unreleased(String name) {
  final changelog = File('packages/$name/CHANGELOG.md');
  return changelog.existsSync() &&
      changelog.readAsStringSync().contains(
        '## ${_version(_packages[name]!)} (unreleased)',
      );
}

String _dependencies(String pubspec) => pubspec
    .split('\ndependencies:\n')
    .skip(1)
    .join()
    .split('\ndev_dependencies:')
    .first;

void main() {
  test('published packages depend on unreleased siblings by path', () {
    final hosted = <String>[];
    _packages.forEach((name, pubspec) {
      if (pubspec.contains('publish_to: none')) return;
      for (final m in RegExp(
        r'^  (\w+): (\S+)$',
        multiLine: true,
      ).allMatches(_dependencies(pubspec))) {
        final sibling = _packages[m[1]];
        if (sibling != null &&
            _unreleased(m[1]!) &&
            m[2] == '^${_version(sibling)}') {
          hosted.add('$name -> ${m[0]!.trim()}');
        }
      }
    });
    expect(hosted, isEmpty);
  });

  test(
    'hostedPubspec turns sibling path dependencies into caret constraints',
    () {
      final versions = {
        for (final e in _packages.entries) e.key: _version(e.value),
      };
      final core = hostedPubspec(
        _packages['open_intelligent_ui_core']!,
        versions,
      );
      expect(
        core,
        contains('  ai_sdk_openui: ^${versions['ai_sdk_openui']}\n'),
      );
      for (final pubspec in _packages.values) {
        expect(hostedPubspec(pubspec, versions), isNot(contains('path: ../')));
      }
    },
  );

  test(
    'the publish rewrite restores every pubspec and clears skip-worktree',
    () async {
      final scratch = await Directory.systemTemp.createTemp('hosted-deps-');
      addTearDown(() => scratch.delete(recursive: true));
      Future<String> run(String command, List<String> args) async {
        final result = await Process.run(
          command,
          args,
          workingDirectory: scratch.path,
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        return '${result.stdout}';
      }

      for (final MapEntry(key: name, value: pubspec) in _packages.entries) {
        final file = File('${scratch.path}/packages/$name/pubspec.yaml');
        await file.parent.create(recursive: true);
        await file.writeAsString(pubspec);
      }
      final script = File('tool/hosted_deps.dart').absolute.path;
      await run('git', ['init', '-q']);
      await run('git', ['add', '.']);
      await run(Platform.resolvedExecutable, [script]);
      expect(await run('git', ['ls-files', '-v']), contains('S packages/'));
      expect(
        File(
          '${scratch.path}/packages/open_intelligent_ui_core/pubspec.yaml',
        ).readAsStringSync(),
        isNot(contains('path: ../')),
      );

      await run(Platform.resolvedExecutable, [script, '--restore']);
      for (final MapEntry(key: name, value: pubspec) in _packages.entries) {
        expect(
          File(
            '${scratch.path}/packages/$name/pubspec.yaml',
          ).readAsStringSync(),
          pubspec,
          reason: name,
        );
      }
      expect(
        await run('git', ['ls-files', '-v']),
        isNot(contains('S packages/')),
      );
    },
  );

  test('hostedPubspec rejects a path dependency that is not a sibling', () {
    expect(
      () => hostedPubspec('dependencies:\n  a:\n    path: ../b\n', {
        'b': '1.0.0',
      }),
      throwsStateError,
    );
  });
}
