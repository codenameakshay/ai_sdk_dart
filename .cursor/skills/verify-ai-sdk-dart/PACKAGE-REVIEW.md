# Package check review

Reviewed the 17 Dart package modules and all 315 registered checks against their assertions, feature docs, and fixture evidence. No package source, example, dependency, or test file changed. The four findings below concern the verification driver, not fixes to the SDK.

## Findings and reproduction

Run these commands from the repository root with dependencies already resolved:

```sh
V=.cursor/skills/verify-ai-sdk-dart/scripts/verify
unset OPENAI_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY_FILE ANTHROPIC_API_KEY_FILE
$V run conversation --check decode-does-not-execute-tools
$V run provider --check shared-value-types
$V run dart --check generate-image-openai
$V run dart --check middleware-embedding-image
```

1. `conversation/decode-does-not-execute-tools` asserted a local execution counter and tool map that were never passed to the codec. Those assertions could not detect a codec regression. Before the fix, the command passed with `observed.executions: 0` and `observed.registeredTools`, regardless of the decoded call. After the fix, it asserts the decoded call id, name, arguments, pending approval, pending message status, and absence of a tool result. Evidence now records `observed.toolCall` and `observed.approvalStatus`. To reproduce the difference, use `apply_patch` to change only the stored `ToolCallPart` constructor's `name: 'delete'` to `name: 'unexpected-delete'` inside this check. Leave its expected-value assertion unchanged. Rerun the first command. The original check passes; the fixed check fails with `preserved tool name: expected "delete", got "unexpected-delete"`. Restore the constructor with `apply_patch` and rerun to pass. Tool execution after approval remains covered separately by `agent-turn-snapshot-and-resume`.

2. `provider/shared-value-types` compared `names.length` with `parts.length`, where `names` is a set produced by mapping the check's own part list through its own exhaustive `nameOf` switch. That checked the local list and mapping, not SDK behavior. Removed that assertion and retained the exhaustive switch over the sealed stream-part type, the recorded part names, and the behavioral helper assertions. The same command passes before and after. It does not prove end-to-end handling of every stream part; the provider and text integration checks cover those paths separately.

3. `anthropic/live-structured-output` checked `'${result.output['capital']}'.isNotEmpty`. Dart turns a missing or null value into the nonempty string `null`, so `{}`, `{"capital":null}`, and `{"capital":42}` all passed. The check now requires a `String` with nonempty trimmed content. The scratch probe below calls the actual check closure against loopback, without a vendor key or request. Before the fix, all four cases print `accepted`. After the fix, the first three print `rejected` and `{"capital":"Paris"}` prints `accepted`.

4. `dart/generate-image-openai` and `dart/middleware-embedding-image` sent `n: 2` with `dall-e-3`, whose documented request limit is one image. Their fixtures accepted an impossible vendor request. Both checks now use `dall-e-2`, which supports multiple images. Both commands pass before and after, but `exchanges[].requestBody.model` changes from `dall-e-3` to `dall-e-2` while `n` remains `2`. The official OpenAPI description says `n` can be between 1 and 10, but only `n=1` is supported for `dall-e-3`. Reproduce that source lookup with the command below. This is fixture mapping proof for the historical model format, not a claim that either retired model is currently available.

```sh
curl -fsSL https://raw.githubusercontent.com/openai/openai-openapi/manual_spec/openapi.yaml | rg -n -C3 'only `n=1`'
```

For finding 3, the command below runs this source directly from the report without creating a test file. Its imports resolve through the existing driver package configuration:

```dart
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:ai_sdk_verify/harness.dart';
import 'package:ai_sdk_verify/packages/ai_sdk_anthropic.dart' as anthropic;

class FixtureContext extends CheckContext {
	FixtureContext(Check check)
		: super(
			package: 'ai_sdk_anthropic', check: check, live: true,
			repoRoot: Directory.current.path,
			artifactDir: Directory('/tmp/ai-sdk-capital-probe-artifacts'),
		);
	late String fixtureBase;
	@override
	String requireEnv(String name) => 'fixture-not-real-key';
	@override
	Dio recordingDio({String? baseUrl}) {
		final client = Dio(BaseOptions(baseUrl: fixtureBase));
		onCleanup(() async => client.close(force: true));
		return client;
	}
}

Future<void> main() async {
	final check = anthropic.checks.checks.singleWhere(
		(c) => c.id == 'live-structured-output',
	);
	for (final output in <Map<String, dynamic>>[
		{}, {'capital': null}, {'capital': 42}, {'capital': 'Paris'},
	]) {
		final ctx = FixtureContext(check);
		try {
			final server = await ctx.server((_) => FixtureResponse.json({
				'id': 'msg_fixture', 'type': 'message', 'role': 'assistant',
				'model': 'claude-fixture', 'stop_reason': 'end_turn',
				'content': [{'type': 'text', 'text': jsonEncode(output)}],
				'usage': {'input_tokens': 1, 'output_tokens': 1},
			}));
			ctx.fixtureBase = server.url('/v1');
			await check.run(ctx);
			stdout.writeln('${jsonEncode(output)} accepted');
		} on CheckFailure {
			stdout.writeln('${jsonEncode(output)} rejected');
		} finally {
			await ctx.dispose();
		}
	}
}
```

```sh
fvm dart --packages=.cursor/skills/verify-ai-sdk-dart/driver/.dart_tool/package_config.json <(sed -n '/^```dart$/,/^```$/p' .cursor/skills/verify-ai-sdk-dart/PACKAGE-REVIEW.md | sed '1d;$d')
```

To compare before and after, use `apply_patch` to replace only the new capital type assertion with the original interpolated-string assertion, run the probe, then restore the type assertion and rerun. Do not run the wrapper with a real key for this reproduction. The command requires Bash process substitution.

## Evidence and gaps

- Baseline: `/tmp/ai-sdk-verify/evidence/codex-r1/summary.json` records 296 passes, two failures, and 17 skips. After the package-check fixes, `/tmp/ai-sdk-verify/evidence/codex-pkg-review/summary.json` records the same totals. All checks remain registered.
- The two fixture failures are unchanged SDK defects in `middleware-extract-reasoning-stream` and `middleware-extract-reasoning-stream-one-delta`. Their assertions were not weakened.
- No live vendor check ran during this review. The 17 live checks skipped. The loopback capital probe exercises a live check's assertion, not Anthropic service behavior.
- Historical vendor results in the feature files, including the Anthropic signed-empty-thinking failure, were not independently rerun. Live compatibility, current prices, and account-specific model access remain unverified.
- The docs now distinguish in-memory assertions from wire assertions, explain bounded response recording and timeout limits, correct the Anthropic skip count and Google redacted URLs, and describe the fixture server's actual streaming behavior. Every registered check's feature id maps to a feature entry. UI verification remains delegated to `verify-flutter-chat`; this Dart run does not verify Flutter rendering.
