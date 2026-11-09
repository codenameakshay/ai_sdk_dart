// Packages depend on unreleased siblings by path, so a git consumer resolves
// them from the same commit (see docs/git-dependencies.md). pub.dev rejects
// path dependencies, so `make dry-run` and `make publish` run this first to
// turn each one into `^<sibling version>`, then run it with `--restore`.
//
//   dart run tool/hosted_deps.dart            rewrite, keeping the originals
//   dart run tool/hosted_deps.dart --restore  put the originals back
//
// While rewritten, git is told to skip the pubspecs, so pub publishes from a
// clean state.
import 'dart:io';

final _pathDep = RegExp(
  r'^  (\w+):\n(?:    # ignore: invalid_dependency\n)?    path: \.\./(\w+)\n',
  multiLine: true,
);

/// [pubspec] with each `path: ../<sibling>` dependency (and the analyzer
/// ignore comment that allows it) replaced by a caret constraint on the
/// sibling's version from [versions].
String hostedPubspec(String pubspec, Map<String, String> versions) =>
    pubspec.replaceAllMapped(_pathDep, (m) {
      final version = versions[m[2]];
      if (m[1] != m[2] || version == null) {
        throw StateError('No sibling package for ${m[0]!.trim()}');
      }
      return '  ${m[1]}: ^$version\n';
    });

void main(List<String> args) {
  final backups = Directory('.dart_tool/hosted_deps');
  final pubspecs = Directory('packages')
      .listSync()
      .whereType<Directory>()
      .map((d) => File('${d.path}/pubspec.yaml'))
      .where((f) => f.existsSync())
      .toList();
  if (args.contains('--restore')) {
    for (final f in pubspecs) {
      final backup = File('${backups.path}/${f.parent.uri.pathSegments[1]}');
      if (backup.existsSync()) {
        backup.copySync(f.path);
        backup.deleteSync();
        _git(['update-index', '--no-skip-worktree', f.path]);
      }
    }
    return;
  }
  String field(String text, String key) =>
      RegExp('^$key: (\\S+)', multiLine: true).firstMatch(text)?[1] ?? '';
  final versions = {
    for (final text in pubspecs.map((f) => f.readAsStringSync()))
      field(text, 'name'): field(text, 'version'),
  };
  backups.createSync(recursive: true);
  for (final f in pubspecs) {
    final text = f.readAsStringSync();
    final hosted = hostedPubspec(text, versions);
    if (hosted == text) continue;
    f.copySync('${backups.path}/${f.parent.uri.pathSegments[1]}');
    f.writeAsStringSync(hosted);
    // pub warns about a checked-in file that differs from git; this one
    // differs only for the publish.
    _git(['update-index', '--skip-worktree', f.path]);
  }
}

void _git(List<String> args) {
  final result = Process.runSync('git', args);
  if (result.exitCode != 0) {
    throw ProcessException('git', args, '${result.stderr}');
  }
}
