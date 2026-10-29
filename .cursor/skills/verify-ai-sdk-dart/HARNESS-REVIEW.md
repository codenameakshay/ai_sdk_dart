# Harness review

All probes used Flutter 3.44.3 / Dart 3.12.2 through `fvm dart`. No dependencies changed. No real keys or live provider calls were used. Synthetic key probes run fixture checks only.

## Reproduce

Save the Dart appendix as `driver/bin/harness_probe.dart`, then run these commands from `.cursor/skills/verify-ai-sdk-dart/driver`:

```bash
fvm dart run bin/harness_probe.dart security
fvm dart run bin/harness_probe.dart lifecycle
fvm dart run bin/harness_probe.dart stream
fvm dart run bin/harness_probe.dart request-abort
fvm dart run bin/harness_probe.dart reporting
fvm dart run bin/harness_probe.dart lock
fvm dart run bin/harness_probe.dart network
fvm dart run bin/harness_probe.dart wrapper-signal
fvm dart run bin/harness_probe.dart truncation
fvm dart run bin/harness_probe.dart artifact-rerun
fvm dart run bin/harness_probe.dart binary
fvm dart run bin/harness_probe.dart wrapper-crash
fvm dart run bin/harness_probe.dart concurrency
fvm dart run bin/harness_probe.dart pacing
```

Remove the temporary Dart file after reproducing. The source stays here as review evidence, not a permanent test suite. Probes remove only their own temporary directories and processes.

## Findings and recorded results

Each row names the probe argument from the commands above. The parent reviewer independently reproduced the failing mechanisms and passing results.

| Finding | Probe | Before | After |
| --- | --- | --- | --- |
| Escaped JSON secrets and short keys leaked through evidence, summaries, artifacts and console output. Raw subprocess logs were unsanitized. | `security` | `leaks=[ai_sdk_probe/secret.json, ai_sdk_probe/secret.artifacts/output.log, ai_sdk_probe/secret.artifacts/custom.json, summary.json, summary.md, stdout/stderr]` | `security exit=0 leaks=[]` |
| Timeout cleanup accepted resources that finished opening after disposal, ignored late cleanup registration and allowed late artifact writes. | `lifecycle` | `pendingRejected=false lateCleanup=0 lateArtifactRejected=false` | `pendingRejected=true lateCleanup=1 lateArtifactRejected=true` |
| Live Dio streamed bodies had only a placeholder, not response evidence. | `stream` | `stream captured=false` | `stream captured=true` |
| Aborted fixture request bodies escaped the async server handler as uncaught errors, with no error exchange. | `request-abort` | `uncaught=1 recorded=false` | `uncaught=0 recorded=true` |
| Provider-thrown TimeoutException was falsely described as the runner's 60-second deadline. Cleanup errors could still produce a passing check. | `reporting` | `earlyReason=timed out after 60s cleanup=pass nextCheckExists=true` | `earlyReason=unexpected TimeoutException: TimeoutException: provider read timeout cleanup=fail nextCheckExists=true` |
| Summary updates and same-check artifacts had no interprocess serialization. An initial directory-lock attempt was also ineffective because Directory.createSync succeeds for an existing directory. | `lock` | `lock wroteWhileLocked=true exit=0` | `lock wroteWhileLocked=false exit=0` |
| Fixture checks had no general non-loopback HTTP guard. | `network` | `factoryCalled=true result=fail` | `factoryCalled=false result=pass` |
| A second termination signal interrupted the wrapper's cleanup sleep under set -e, skipping KILL and leaving a TERM-ignoring driver alive. | `wrapper-signal` | `exit=143 driverRunning=true` | `exit=143 driverRunning=false` |
| Truncation before redaction retained a prefix of a known secret at the 16KiB boundary. | `truncation` | `partialSecretLeaked=true` | `partialSecretLeaked=false` |
| Rerunning a check as skipped left artifacts from its previous result. | `artifact-rerun` | `result=skip staleArtifact=true` | `result=skip staleArtifact=false` |

The lock and network before results were also reproduced by temporarily disabling only the newly added lock acquisition and fixture HttpOverrides selection. Restore both immediately after comparison. The network probe installs a throwing connectionFactory sentinel, so even its failing baseline opens no external socket.

Two intermediate implementation regressions were caught and removed during peer review, not present in the original reviewed source:

| Rejected implementation | Probe | Rejected result | Final result |
| --- | --- | --- | --- |
| Decoding all artifact files as UTF-8 corrupted binary media. | `binary` | `binary preserved=false` | `binary preserved=true` |
| Starting each spawned fixture with setsid detached it from the wrapper's crash cleanup group. | `wrapper-crash` | `exit=9 descendantRunning=true` | `exit=9 descendantRunning=false` |

The final artifact scrub replaces matching UTF-8 secret byte sequences and preserves every other byte. Spawned processes retain the wrapper's process group. Per-check cleanup terminates the observed process tree.

Secret-file loading also ignored command-substitution read failures because export masked their status. From repository root:

```bash
OPENAI_API_KEY_FILE=/tmp ANTHROPIC_API_KEY= VERIFY_RUN_ID=harness-file-probe .cursor/skills/verify-ai-sdk-dart/scripts/verify run provider --check file-probe-not-a-check
```

Before, stderr printed `tr: read error: Is a directory`, then launched the driver and failed with `no check file-probe-not-a-check in provider`, exit 2. After, it immediately reports `verify: OPENAI_API_KEY_FILE must point at a readable regular file`, exit 1. Read failures and empty files also fail before launch.

The same invalid file was incorrectly accepted by doctor. `OPENAI_API_KEY_FILE=/tmp ANTHROPIC_API_KEY= .cursor/skills/verify-ai-sdk-dart/scripts/verify doctor` previously exited 0 with `INFO OPENAI_API_KEY from OPENAI_API_KEY_FILE`. It now exits 1 with `FAIL OPENAI_API_KEY_FILE must be a readable regular file containing a nonempty key`.

Response headers were absent despite the retry evidence documentation claiming them. From repository root:

```bash
VERIFY_RUN_ID=codex-harness-headers .cursor/skills/verify-ai-sdk-dart/scripts/verify run provider --check http-helpers
node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync("/tmp/ai-sdk-verify/evidence/codex-harness-headers/ai_sdk_provider/http-helpers.json"));console.log(JSON.stringify(r.exchanges.map(e=>({status:e.status,responseHeaders:e.responseHeaders}))));'
```

Before, responseHeaders was undefined. After, the 429 exchange includes `{"content-type":"application/json","retry-after":"2"}`. Sensitive response headers use the same redaction as request headers.

The doctor readiness message claimed that npm ls --depth=0 proved the entire lockfile. It only validates installed direct dependencies against package.json. The diagnostic now says that explicitly.

## Verification and limits

- Whole-run OS file locking serializes shared run ids. Locks release when the process exits, including crashes. Check JSON and summary JSON/Markdown use atomic replacement.
- `concurrency` produced `exits=[0, 0] results=2`. The old directory lock was not accepted as proof of serialization merely because a two-process run happened to pass.
- `pacing` measured first bytes at 289ms and completion at 655ms, with `firstBeforeEnd=true`. This refuted the documentation's claim that fixture SSE delays buffer until completion. Timing varies; the assertion checks separation, not performance.
- Live response evidence captures the consumed stream prefix, up to 16KiB bytes. Non-JSON fixture text is capped at 16KiB characters after redaction; valid JSON remains fully decoded. Stream evidence preserves consumer cancellation, data and errors.
- Logs are buffered until subprocess cleanup and written after redaction. Per-check cleanup is bounded, and cleanup failure becomes a failed check without aborting subsequent checks.
- Rerunning the same package/check id replaces that check's old artifacts, including when the new result is skipped. Other checks and run directories remain untouched.
- Closing CheckContext rejects new server, client, process, artifact and observation operations. It immediately executes late cleanup registration. Future.timeout cannot cancel arbitrary Dart futures, timers, retained file handles or direct IO. This is not a sandbox. The wrapper's process group is the final subprocess cleanup backstop.
- The fixture HTTP guard covers normal dart:io HttpClient traffic in the check's zone. Custom overrides or direct sockets are not a security sandbox.
- `fvm dart analyze --fatal-infos` and `bash -n ../scripts/verify` passed.
- The parent reran all checks, both ordinary mode and --live with no keys. Both retained 296 pass, 2 known fail, 17 skip. The final full run after the same-check artifact correction also retained those counts. The two extract-reasoning defects and live Anthropic reasoning defect were not weakened or changed.

## Transient probe source

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:ai_sdk_verify/harness.dart';
import 'package:ai_sdk_verify/runner.dart';

CheckContext context() => CheckContext(package: 'ai_sdk_probe', check: Check(id: 'probe', feature: 'probe', description: 'probe', run: (_) async {}), live: false, repoRoot: Directory.current.path, artifactDir: Directory.systemTemp.createTempSync('harness-probe-artifacts-'));

Future<void> main(List<String> args) async {
  if (args.first == 'truncation') {
    final result = await Process.run(Platform.resolvedExecutable, ['run', 'bin/harness_probe.dart', 'truncation-worker'], environment: {'OPENAI_API_KEY': 'dummy-secret-for-truncation-41'});
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
    return;
  }
  if (args.first == 'truncation-worker') {
    final ctx = context();
    final secret = Platform.environment['OPENAI_API_KEY']!;
    final server = await ctx.server((_) => FixtureResponse.text('${'x' * (16 * 1024 - 8)}$secret'));
    final dio = ctx.recordingDio();
    final response = await dio.get<ResponseBody>(server.origin, options: Options(responseType: ResponseType.stream));
    await response.data!.stream.drain<void>();
    final leak = ctx.exchanges.any((e) => '${e.responseBody}'.contains(secret.substring(0, 8)));
    print('truncation partialSecretLeaked=$leak');
    await ctx.dispose();
    ctx.artifactDir.deleteSync(recursive: true);
    exitCode = leak ? 1 : 0;
    return;
  }
  if (args.first == 'signal-worker') {
    ProcessSignal.sigterm.watch().listen((_) {});
    File(Platform.environment['PROBE_PID_FILE']!).writeAsStringSync('$pid');
    await Completer<void>().future;
  }
  if (args.first == 'crash-worker') {
    final ctx = context();
    final process = await ctx.spawn('orphan', 'bash', ['-c', 'trap "" TERM; while true; do sleep 1; done']);
    File(Platform.environment['PROBE_PID_FILE']!).writeAsStringSync('${process.pid}');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    exit(9);
  }
  if (args.first == 'runner') {
    await runCli(args.skip(1).toList(), [PackageChecks('ai_sdk_probe', [
      Check(id: 'secret', feature: 'probe', description: 'probe', run: (ctx) async {
        final first = Platform.environment['OPENAI_API_KEY']!;
        final second = Platform.environment['ANTHROPIC_API_KEY']!;
        ctx.observe(first, {'value': first, 'short': second});
        ctx.artifact('custom.json').writeAsStringSync(jsonEncode({'value': first, 'short': second}));
        await ctx.spawn('output', 'bash', ['-c', 'printf "%s" "\$OPENAI_API_KEY"; printf "%s" "\$ANTHROPIC_API_KEY" >&2']);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        ctx.skip('$first $second');
      }),
      for (final id in ['one', 'two', for (var i = 0; i < 12; i++) 'parallel-$i']) Check(id: id, feature: 'probe', description: 'probe', run: (_) async { await Future<void>.delayed(const Duration(milliseconds: 100)); }),
      Check(id: 'network', feature: 'probe', description: 'probe', run: (ctx) async {
        var factoryCalled = false;
        final client = HttpClient()..connectionFactory = (uri, proxy, port) {
          factoryCalled = true;
          throw StateError('sentinel connection factory reached, no socket opened');
        };
        try {
          await client.getUrl(Uri.parse('https://example.invalid'));
        } catch (error) {
          ctx.observe('error', '$error');
        } finally { client.close(force: true); }
        ctx.observe('factoryCalled', factoryCalled);
        ctx.expect(!factoryCalled, 'non-loopback request reached connection factory');
      }),
      Check(id: 'early-timeout', feature: 'probe', description: 'probe', run: (_) async { throw TimeoutException('provider read timeout'); }),
      Check(id: 'cleanup-failure', feature: 'probe', description: 'probe', run: (ctx) async { ctx.onCleanup(() async { throw StateError('synthetic cleanup failure'); }); }),
      Check(id: 'after-cleanup', feature: 'probe', description: 'probe', run: (_) async {}),
      Check(id: 'artifacts', feature: 'probe', description: 'probe', mode: Platform.environment['PROBE_WRITE'] == '1' ? CheckMode.fixture : CheckMode.live, run: (ctx) async { ctx.artifact('marker.txt').writeAsStringSync('old result marker'); }),
    ])]);
    return;
  }
  if (args.first == 'artifact-rerun') {
    final root = Directory.systemTemp.createTempSync('harness-rerun-');
    for (final flag in ['1', '0']) {
      await Process.run(Platform.resolvedExecutable, ['run', 'bin/harness_probe.dart', 'runner', 'run', 'probe', '--check', 'artifacts', '--evidence', root.path], environment: {'PROBE_WRITE': flag});
    }
    final old = File('${root.path}/ai_sdk_probe/artifacts.artifacts/marker.txt').existsSync();
    final record = jsonDecode(File('${root.path}/ai_sdk_probe/artifacts.json').readAsStringSync());
    print('artifact-rerun result=${record['result']} staleArtifact=$old');
    root.deleteSync(recursive: true);
    exitCode = !old && record['result'] == 'skip' ? 0 : 1;
  } else if (args.first == 'reporting') {
    final root = Directory.systemTemp.createTempSync('harness-reporting-');
    await Process.run(Platform.resolvedExecutable, ['run', 'bin/harness_probe.dart', 'runner', 'run', 'probe', '--evidence', root.path], environment: {'OPENAI_API_KEY': '', 'ANTHROPIC_API_KEY': ''});
    final timeout = jsonDecode(File('${root.path}/ai_sdk_probe/early-timeout.json').readAsStringSync());
    final cleanup = jsonDecode(File('${root.path}/ai_sdk_probe/cleanup-failure.json').readAsStringSync());
    print('reporting earlyReason=${timeout['reason']} cleanup=${cleanup['result']} nextCheckExists=${File('${root.path}/ai_sdk_probe/after-cleanup.json').existsSync()}');
    root.deleteSync(recursive: true);
    exitCode = '${timeout['reason']}'.contains('provider read timeout') && cleanup['result'] == 'fail' ? 0 : 1;
  } else if (args.first == 'binary') {
    final ctx = context();
    final bytes = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0xff, 0];
    final file = ctx.artifact('image.png')..writeAsBytesSync(bytes);
    await ctx.dispose();
    final preserved = jsonEncode(bytes) == jsonEncode(file.readAsBytesSync());
    print('binary preserved=$preserved');
    ctx.artifactDir.deleteSync(recursive: true);
    exitCode = preserved ? 0 : 1;
  } else if (args.first == 'wrapper-signal') {
    final root = Directory.systemTemp.createTempSync('harness-wrapper-signal-');
    final marker = File('${root.path}/child.pid');
    final script = File('../scripts/verify').absolute.path;
    final self = File('bin/harness_probe.dart').absolute.path;
    final wrapper = await Process.start('setsid', ['bash', script, 'run', 'provider'], environment: {'DART': '${Platform.resolvedExecutable} $self signal-worker', 'PROBE_PID_FILE': marker.path, 'VERIFY_EVIDENCE_ROOT': root.path, 'VERIFY_RUN_ID': 'signal'});
    final out = wrapper.stdout.drain<void>();
    final err = wrapper.stderr.drain<void>();
    while (!marker.existsSync()) { await Future<void>.delayed(const Duration(milliseconds: 50)); }
    final driverPid = int.parse(marker.readAsStringSync());
    wrapper.kill(ProcessSignal.sigterm);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    Process.killPid(-wrapper.pid, ProcessSignal.sigterm);
    final code = await wrapper.exitCode;
    final stat = await Process.run('ps', ['-o', 'stat=', '-p', '$driverPid']);
    final running = '${stat.stdout}'.trim().isNotEmpty && !'${stat.stdout}'.trim().startsWith('Z');
    print('wrapper-signal exit=$code driverRunning=$running');
    Process.killPid(-driverPid, ProcessSignal.sigkill);
    Process.killPid(driverPid, ProcessSignal.sigkill);
    await Future.wait([out, err]);
    root.deleteSync(recursive: true);
    exitCode = !running && code == 143 ? 0 : 1;
  } else if (args.first == 'wrapper-crash') {
    final root = Directory.systemTemp.createTempSync('harness-wrapper-crash-');
    final marker = File('${root.path}/child.pid');
    final script = File('../scripts/verify').absolute.path;
    final self = File('bin/harness_probe.dart').absolute.path;
    final result = await Process.run('bash', [script, 'run', 'provider'], environment: {'DART': '${Platform.resolvedExecutable} $self crash-worker', 'PROBE_PID_FILE': marker.path, 'VERIFY_EVIDENCE_ROOT': root.path, 'VERIFY_RUN_ID': 'crash'});
    final childPid = int.parse(marker.readAsStringSync());
    final stat = await Process.run('ps', ['-o', 'stat=', '-p', '$childPid']);
    final running = '${stat.stdout}'.trim().isNotEmpty && !'${stat.stdout}'.trim().startsWith('Z');
    print('wrapper-crash exit=${result.exitCode} descendantRunning=$running');
    Process.killPid(-childPid, ProcessSignal.sigkill);
    Process.killPid(childPid, ProcessSignal.sigkill);
    root.deleteSync(recursive: true);
    exitCode = !running && result.exitCode == 9 ? 0 : 1;
  } else if (args.first == 'security') {
    final root = Directory.systemTemp.createTempSync('harness-security-');
    const first = 'dummy-"quoted\\secret\nvalue';
    const second = 'q7!';
    final result = await Process.run(Platform.resolvedExecutable, ['run', 'bin/harness_probe.dart', 'runner', 'run', 'probe', '--check', 'secret', '--evidence', root.path], environment: {'OPENAI_API_KEY': first, 'ANTHROPIC_API_KEY': second});
    final leaks = <String>[];
    for (final entity in root.listSync(recursive: true).whereType<File>()) {
      final raw = entity.readAsStringSync();
      final encoded = jsonEncode(first).substring(1, jsonEncode(first).length - 1);
      if (raw.contains(first) || raw.contains(second) || raw.contains(encoded)) leaks.add(entity.path.substring(root.path.length + 1));
    }
    if ('${result.stdout}${result.stderr}'.contains(first) || '${result.stdout}${result.stderr}'.contains(second)) leaks.add('stdout/stderr');
    print('security exit=${result.exitCode} leaks=$leaks');
    root.deleteSync(recursive: true);
    exitCode = leaks.isEmpty ? 0 : 1;
  } else if (args.first == 'lifecycle') {
    final ctx = context();
    var cleanupCount = 0;
    final pending = ctx.server((_) => FixtureResponse.text('ok'));
    await ctx.dispose();
    var rejected = false;
    try { final server = await pending; await server.close(); } catch (_) { rejected = true; }
    ctx.onCleanup(() async { cleanupCount++; });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    var artifactRejected = false;
    try { ctx.artifact('late').writeAsStringSync('late'); } catch (_) { artifactRejected = true; }
    print('lifecycle pendingRejected=$rejected lateCleanup=$cleanupCount lateArtifactRejected=$artifactRejected');
    ctx.artifactDir.deleteSync(recursive: true);
    exitCode = rejected && cleanupCount == 1 && artifactRejected ? 0 : 1;
  } else if (args.first == 'stream') {
    final ctx = context();
    final server = await ctx.server((_) => FixtureResponse.sse([{'text': 'stream evidence'}], done: true));
    final dio = ctx.recordingDio();
    final response = await dio.get<ResponseBody>(server.origin, options: Options(responseType: ResponseType.stream));
    await response.data!.stream.drain<void>();
    final body = ctx.exchanges.firstWhere((e) => e.source == 'live').responseBody;
    print('stream captured=${'$body'.contains('stream evidence')}');
    await ctx.dispose();
    ctx.artifactDir.deleteSync(recursive: true);
    exitCode = '$body'.contains('stream evidence') ? 0 : 1;
  } else if (args.first == 'pacing') {
    final ctx = context();
    final server = await ctx.server((_) => FixtureResponse.sse(['first', 'second', 'third'], delay: const Duration(milliseconds: 180)));
    final client = HttpClient();
    final watch = Stopwatch()..start();
    final response = await (await client.getUrl(Uri.parse(server.origin))).close();
    var first = -1;
    await for (final chunk in response) { if (first < 0 && chunk.isNotEmpty) first = watch.elapsedMilliseconds; }
    final last = watch.elapsedMilliseconds;
    print('pacing firstMs=$first endMs=$last firstBeforeEnd=${first + 200 < last}');
    client.close(force: true);
    await ctx.dispose();
    ctx.artifactDir.deleteSync(recursive: true);
    exitCode = first + 200 < last ? 0 : 1;
  } else if (args.first == 'lock') {
    final root = Directory.systemTemp.createTempSync('harness-lock-');
    final lock = await File('${root.path}/.run.lock').open(mode: FileMode.append);
    await lock.lock(FileLock.blockingExclusive);
    final child = await Process.start(Platform.resolvedExecutable, ['run', 'bin/harness_probe.dart', 'runner', 'run', 'probe', '--check', 'one', '--evidence', root.path]);
    final output = child.stdout.drain<void>();
    final errors = child.stderr.drain<void>();
    await Future<void>.delayed(const Duration(seconds: 3));
    final premature = File('${root.path}/summary.json').existsSync();
    await lock.unlock();
    await lock.close();
    final code = await child.exitCode;
    await Future.wait([output, errors]);
    print('lock wroteWhileLocked=$premature exit=$code');
    root.deleteSync(recursive: true);
    exitCode = !premature && code == 0 ? 0 : 1;
  } else if (args.first == 'network') {
    final root = Directory.systemTemp.createTempSync('harness-network-');
    final result = await Process.run(Platform.resolvedExecutable, ['run', 'bin/harness_probe.dart', 'runner', 'run', 'probe', '--check', 'network', '--evidence', root.path]);
    final record = jsonDecode(File('${root.path}/ai_sdk_probe/network.json').readAsStringSync());
    print('network exit=${result.exitCode} factoryCalled=${record['observed']['factoryCalled']} result=${record['result']}');
    root.deleteSync(recursive: true);
    exitCode = result.exitCode;
  } else if (args.first == 'concurrency' || args.first == 'stale') {
    final root = Directory.systemTemp.createTempSync('harness-summary-');
    if (args.first == 'stale') Directory('${root.path}/.summary.lock').createSync();
    final results = await Future.wait([for (final id in args.first == 'stale' ? ['one'] : ['one', 'two']) Process.run(Platform.resolvedExecutable, ['run', 'bin/harness_probe.dart', 'runner', 'run', 'probe', '--check', id, '--evidence', root.path])]);
    final file = File('${root.path}/summary.json');
    final count = file.existsSync() ? (jsonDecode(file.readAsStringSync())['results'] as List).length : 0;
    print('${args.first} exits=${results.map((r) => r.exitCode).toList()} results=$count');
    root.deleteSync(recursive: true);
    exitCode = results.every((r) => r.exitCode == 0) && count == results.length ? 0 : 1;
  } else if (args.first == 'request-abort') {
    final errors = <Object>[];
    await runZonedGuarded(() async {
      final ctx = context();
      final server = await ctx.server((_) => FixtureResponse.text('ok'));
      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.write('POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1000\r\n\r\nx');
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      socket.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      print('request-abort uncaught=${errors.length} recorded=${ctx.exchanges.any((e) => e.error != null)}');
      await ctx.dispose();
      ctx.artifactDir.deleteSync(recursive: true);
    }, (e, _) { errors.add(e); });
    exitCode = errors.isEmpty ? 0 : 1;
  }
}
```
