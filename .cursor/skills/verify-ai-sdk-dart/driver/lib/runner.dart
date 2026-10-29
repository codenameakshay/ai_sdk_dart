/// Command-line runner: selects checks, runs them, writes evidence.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'harness.dart';

const _usage = '''
Usage:
  verify.dart list [package]
  verify.dart run <package|all> [--check <id>] [--live] --evidence <dir> [--repo <dir>]
''';

/// Entry point shared by bin/verify.dart and per-developer entry points.
Future<void> runCli(List<String> args, List<PackageChecks> registry) async {
  if (args.isEmpty) {
    stderr.write(_usage);
    exit(2);
  }
  final ids = <String>{};
  final safeSegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  for (final pkg in registry) {
    if (!safeSegment.hasMatch(pkg.package)) {
      stderr.writeln('invalid package identifier');
      exit(2);
    }
    for (final c in pkg.checks) {
      if (!safeSegment.hasMatch(c.id)) {
        stderr.writeln('invalid check identifier');
        exit(2);
      }
      if (!ids.add('${pkg.package}/${c.id}')) {
        stderr.writeln('duplicate check id ${pkg.package}/${c.id}');
        exit(2);
      }
    }
  }
  switch (args.first) {
    case 'list':
      _list(registry, args.length > 1 ? args[1] : null);
    case 'run':
      exit(await _run(registry, args.skip(1).toList()));
    default:
      stderr.write(_usage);
      exit(2);
  }
}

List<PackageChecks> _select(List<PackageChecks> registry, String? package) {
  if (package == null || package == 'all') return registry;
  final short = package.startsWith('ai_sdk_') ? package : 'ai_sdk_$package';
  final match = registry.where((p) => p.package == short).toList();
  if (match.isEmpty) {
    stderr.writeln(
      'unknown package $package; known: ${registry.map((p) => p.package).join(', ')}',
    );
    exit(2);
  }
  return match;
}

void _list(List<PackageChecks> registry, String? package) {
  for (final pkg in _select(registry, package)) {
    final live = pkg.checks.where((c) => c.mode == CheckMode.live).length;
    stdout.writeln(
      '${pkg.package}  (${pkg.checks.length - live} fixture, $live live)',
    );
    for (final c in pkg.checks) {
      final env = c.requiresEnv.isEmpty
          ? ''
          : '  needs ${c.requiresEnv.join(', ')}';
      stdout.writeln(
        '  ${c.id.padRight(34)} ${c.mode.name.padRight(7)} [${c.feature}] ${c.description}$env',
      );
    }
  }
}

Future<int> _run(List<PackageChecks> registry, List<String> args) async {
  String? target;
  String? only;
  String? evidence;
  var repo = Directory.current.path;
  var live = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--check':
        only = args[++i];
      case '--evidence':
        evidence = args[++i];
      case '--repo':
        repo = args[++i];
      case '--live':
        live = true;
      default:
        if (target != null) {
          stderr.write(_usage);
          return 2;
        }
        target = args[i];
    }
  }
  if (target == null || evidence == null) {
    stderr.write(_usage);
    return 2;
  }
  final selected = _select(registry, target);
  if (only != null && !selected.any((p) => p.checks.any((c) => c.id == only))) {
    stderr.writeln('no check $only in $target');
    return 2;
  }
  final root = Directory(evidence)..createSync(recursive: true);
  final secrets = environmentSecrets;
  final lock = await File('${root.path}/.run.lock').open(mode: FileMode.append);
  await lock.lock(FileLock.blockingExclusive);
  try {
    final results = <Map<String, Object?>>[];
    for (final pkg in selected) {
      for (final check in pkg.checks) {
        if (only != null && check.id != only) continue;
        results.add(
          await _runOne(pkg.package, check, live, repo, root, secrets),
        );
      }
    }
    await _writeSummary(root, results, live, target, secrets);
    final failed = results.where((r) => r['result'] == 'fail').length;
    final passed = results.where((r) => r['result'] == 'pass').length;
    final skipped = results.length - failed - passed;
    stdout.writeln('\n$passed passed, $failed failed, $skipped skipped');
    stdout.writeln(scrubSecrets('summary: ${root.path}/summary.md', secrets));
    return failed == 0 ? 0 : 1;
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<Map<String, Object?>> _runOne(
  String package,
  Check check,
  bool live,
  String repo,
  Directory root,
  List<String> secrets,
) async {
  final pkgDir = Directory('${root.path}/$package')
    ..createSync(recursive: true);
  final artifactDir = Directory('${pkgDir.path}/${check.id}.artifacts');
  if (FileSystemEntity.isLinkSync(artifactDir.path)) {
    Link(artifactDir.path).deleteSync();
  } else if (artifactDir.existsSync()) {
    artifactDir.deleteSync(recursive: true);
  }
  final ctx = CheckContext(
    package: package,
    check: check,
    live: live,
    repoRoot: repo,
    artifactDir: artifactDir,
  );
  final watch = Stopwatch()..start();
  String result;
  String? reason;
  String? stack;
  final missing = [
    for (final name in check.requiresEnv)
      if ((Platform.environment[name] ?? '').isEmpty) name,
  ];
  if (check.mode == CheckMode.live && !live) {
    result = 'skip';
    reason = 'live check; rerun with --live';
  } else if (missing.isNotEmpty) {
    result = 'skip';
    reason = 'missing ${missing.join(', ')}';
  } else {
    final timeout =
        check.timeout ??
        (check.mode == CheckMode.live
            ? const Duration(seconds: 120)
            : const Duration(seconds: 60));
    try {
      await runZoned(
        () => check.mode == CheckMode.fixture
            ? HttpOverrides.runWithHttpOverrides(
                () => check.run(ctx),
                _FixtureHttpOverrides(),
              )
            : check.run(ctx),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            parent.print(zone, scrubSecrets(line, secrets));
          },
        ),
      ).timeout(
        timeout,
        onTimeout: () =>
            throw CheckFailure('timed out after ${timeout.inSeconds}s'),
      );
      result = 'pass';
    } on CheckSkipped catch (e) {
      result = 'skip';
      reason = e.reason;
    } on CheckFailure catch (e) {
      result = 'fail';
      reason = e.message;
    } catch (e, s) {
      result = 'fail';
      reason = 'unexpected ${e.runtimeType}: $e';
      stack = '$s';
    } finally {
      try {
        await ctx.dispose();
      } catch (error, trace) {
        result = 'fail';
        reason = '${reason == null ? '' : '$reason; '}cleanup failed: $error';
        stack ??= '$trace';
      }
    }
  }
  watch.stop();
  final record = <String, Object?>{
    'package': package,
    'check': check.id,
    'feature': check.feature,
    'mode': check.mode.name,
    'description': check.description,
    'result': result,
    'reason': ?reason,
    'durationMs': watch.elapsedMilliseconds,
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'observed': ctx.observed,
    'exchanges': [for (final e in ctx.exchanges) e.toJson()],
    if (ctx.notes.isNotEmpty) 'notes': ctx.notes,
    'stack': ?stack,
  };
  _writeAtomic(
    File('${pkgDir.path}/${check.id}.json'),
    const JsonEncoder.withIndent('  ').convert(scrubEvidence(record, secrets)),
  );
  final label = result.toUpperCase().padRight(4);
  stdout.writeln(
    scrubSecrets(
      '$label $package/${check.id} (${check.mode.name}) ${watch.elapsedMilliseconds}ms'
      '${reason == null ? '' : ': $reason'}',
      secrets,
    ),
  );
  return {
    'package': package,
    'check': check.id,
    'feature': check.feature,
    'mode': check.mode.name,
    'result': result,
    'reason': reason,
    'durationMs': watch.elapsedMilliseconds,
    'evidence': '$package/${check.id}.json',
  };
}

class _FixtureHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (uri) {
          if (!{'localhost', '127.0.0.1', '::1'}.contains(uri.host)) {
            throw CheckFailure(
              'fixture check blocked non-loopback HTTP request to ${uri.host}',
            );
          }
          return 'DIRECT';
        };
}

void _writeAtomic(File target, String text) {
  final pending = File('${target.path}.$pid.tmp');
  pending.writeAsStringSync(text, flush: true);
  pending.renameSync(target.path);
}

Future<void> _writeSummary(
  Directory root,
  List<Map<String, Object?>> results,
  bool live,
  String target,
  List<String> secrets,
) async {
  String git(List<String> a) {
    try {
      return (Process.runSync('git', a).stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  final head = git(['rev-parse', '--short', 'HEAD']);
  final dirty = git(['status', '--porcelain', '--', 'packages']).isNotEmpty;
  // Several invocations can share one run id; keep earlier results unless
  // this invocation re-ran the same check.
  final summaryFile = File('${root.path}/summary.json');
  final previous = <Map<String, Object?>>[];
  if (summaryFile.existsSync()) {
    final old =
        jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
    final rerun = {for (final r in results) '${r['package']}/${r['check']}'};
    for (final r in (old['results'] as List).cast<Map<String, dynamic>>()) {
      if (!rerun.contains('${r['package']}/${r['check']}')) previous.add(r);
    }
  }
  results = [...previous, ...results];
  final summary = {
    'lastTarget': target,
    'live': live,
    'head': head,
    'packagesDirty': dirty,
    'capturedAt': DateTime.now().toUtc().toIso8601String(),
    'results': results,
  };
  _writeAtomic(
    File('${root.path}/summary.json'),
    const JsonEncoder.withIndent('  ').convert(scrubEvidence(summary, secrets)),
  );
  final md = StringBuffer()
    ..writeln('# AI SDK Dart verification')
    ..writeln()
    ..writeln(
      'Last invocation: `$target`, live mode ${live ? 'on' : 'off'}, HEAD `$head`'
      '${dirty ? ' with uncommitted package changes' : ''}. '
      '${results.where((r) => r['result'] == 'pass').length} pass, '
      '${results.where((r) => r['result'] == 'fail').length} fail, '
      '${results.where((r) => r['result'] == 'skip').length} skip.',
    )
    ..writeln()
    ..writeln('| Package | Check | Feature | Mode | Result | Reason |')
    ..writeln('| --- | --- | --- | --- | --- | --- |');
  for (final r in results) {
    final reason = '${r['reason'] ?? ''}'
        .replaceAll('|', '\\|')
        .replaceAll('\n', ' ');
    md.writeln(
      '| ${r['package']} | [${r['check']}](${r['evidence']}) | ${r['feature']} | '
      '${r['mode']} | ${r['result']} | $reason |',
    );
  }
  _writeAtomic(File('${root.path}/summary.md'), scrubSecrets('$md', secrets));
}
