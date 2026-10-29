---
name: verify-ai-sdk-dart
description: Verify the user-facing features of all 18 AI SDK Dart packages (provider, core, json_schema, conversation, remote, realtime, telemetry, openai_compatible, openai, anthropic, google, azure, cohere, groq, mistral, ollama, mcp, flutter_ui) by driving each package's public API across its real boundary (HTTP, SSE, WebSocket, stdio, pinned JS reference servers) and recording evidence, with optional live OpenAI/Anthropic runs. Use when a change touches anything under packages/ and you need proof that the features still work, not only unit tests; use verify-flutter-chat for the Flutter UI.
---

# Verify AI SDK Dart

This skill checks the packages through their public APIs. A Dart driver records HTTP exchanges from its fixture server or recording Dio client, protocol frames captured by individual checks, and selected caller-visible results. Codecs, validators, custom model contracts, and helpers also run in memory without network traffic. It is separate from the unit-test suite.

| Surface | Packages | How |
| --- | --- | --- |
| Pure-Dart public API | the 17 packages other than `ai_sdk_flutter_ui` | `scripts/verify` → the driver in `driver/` |
| Flutter UI | `ai_sdk_flutter_ui` | `.cursor/skills/verify-flutter-chat` (flutter_chat and advanced_app in headless Chromium). See `features/ai_sdk_flutter_ui.md` |

Run all commands from the repository root:

```sh
V=.cursor/skills/verify-ai-sdk-dart/scripts/verify
$V setup                  # once: driver pub get, plus npm ci for the two JS fixtures if missing
$V doctor                 # must print no FAIL line
$V list [package]         # every check: id, mode, feature, description
$V run all                # every fixture check, about 20 s; evidence path printed
$V run openai --check chat-tool-loop
OPENAI_API_KEY_FILE=<file> ANTHROPIC_API_KEY_FILE=<file> $V run all --live
```

Before you verify a package, read `features/README.md` and the package's feature file.

## Launch

There is no server to keep running. Each `run` is a short-lived process.

- `setup` runs `dart pub get` in `driver/`, and runs `npm ci --ignore-scripts` in `examples/remote_backend/js` and `examples/mcp_reference/js` if `node_modules` is missing or `npm ls --depth=0` fails.
- `driver/pubspec.yaml` pins all 17 workspace packages to this checkout with `dependency_overrides`. Without the overrides, pub resolves the packages' sibling dependencies from pub.dev, and you would verify published code instead of your change. `doctor` checks this.
- Each check starts what it needs and stops it when it ends:
  - an in-process loopback HTTP fixture (`ctx.server`);
  - a WebSocket server (realtime);
  - the pinned Vercel AI SDK 7.0.111 backend (`node server.mjs`, remote);
  - the pinned MCP TypeScript SDK 1.30.0 server over stdio (mcp).
- The wrapper runs the driver in its own process group with `setsid`, and kills that group when the driver exits. A check that crashes cannot leave a Node process behind.

## Doctor

`$V doctor` is read-only. It checks:

- Dart and Node.
- The JS fixture dependencies pass `npm ls --depth=0`. This is not a full comparison of installed transitive packages with the lockfiles.
- The driver resolves all 17 packages from `../../../../packages/<pkg>`.
- The driver pubspec has not changed since `pub get`.
- Which live keys are present. It prints names only, never values.

Run it first, and again whenever a run behaves strangely.

## Drive

`$V run <package|all> [--check <id>] [--live]`. A package name can drop the `ai_sdk_` prefix (`openai`, `dart`, `mcp`).

- **Fixture mode** (default) runs every fixture check. It needs no keys and no external network. The runner blocks non-loopback `dart:io` HTTP requests, not arbitrary sockets or subprocess traffic.
  - The fixtures use each vendor's real wire format, taken from the package's own tests and the public API format.
  - Network checks assert the relevant request fields and caller-visible results. In-memory checks assert values or errors without a wire exchange. Check the module's assertions and recorded evidence for the exact scope.
- **Live mode** (`--live`) also runs the live checks for OpenAI (10) and Anthropic (7).
  - The live checks use the real APIs through a recording Dio client. Live traffic is in the evidence, with headers redacted.
  - Keys come from `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`, or from `*_API_KEY_FILE` (a file that holds only the key).
  - Models are `OPENAI_VERIFY_MODEL` (default `gpt-4.1-mini`) and `ANTHROPIC_VERIFY_MODEL` (default `claude-haiku-5-5`). There are per-modality overrides (`OPENAI_VERIFY_EMBEDDING_MODEL`, `OPENAI_VERIFY_IMAGE_MODEL`, `ANTHROPIC_VERIFY_REASONING_MODEL`) that are listed in the feature files.
  - Calls use small token limits and one low-quality `gpt-image-1-mini` image by default. Get approval for live spend. Cost depends on model overrides and current vendor pricing.
  - A live check without its key reports `SKIP ... missing <KEY>`, not a failure.
- `$V list` is the source of truth for check ids. The `Driving it with verify` section of each feature file names the evidence fields that prove each sub-feature.

## Evidence

Each run writes to `/tmp/ai-sdk-verify/evidence/<run-id>/` (override the root with `VERIFY_EVIDENCE_ROOT`). The run id is printed. Set `VERIFY_RUN_ID` to reuse one id across several `run` calls. An OS file lock on `.run.lock` serializes invocations that share an evidence directory. The summary merges the results, and a rerun replaces only the checks it ran, including clearing those checks' old artifact directories even when the new result is a skip. Evidence and summary files are replaced atomically, but the two summary files are not a single transaction.

- `summary.md` and `summary.json`: every check with its result, mode, feature id, reason and evidence link, plus HEAD and whether `packages/` had uncommitted changes.
- `<package>/<check>.json`: the description, result, reason, duration, `observed` (selected caller-visible values), `exchanges` (method, URL, `requestHeaders`, `requestBody`, status, `responseHeaders`, `responseContentType`, `responseBody`, and any error), and optional `notes`. In-memory checks and some separately recorded transports have no `exchanges`.
- `<package>/<check>.artifacts/`: extra files such as subprocess logs, recorded stdio frames and audio.

Live streamed response bodies retain at most the first 16 KiB consumed by the caller, followed by a truncation marker when necessary. Non-streamed binary responses record a byte count. Non-JSON fixture bodies above 16 KiB retain a text prefix. Do not treat this evidence as a complete packet capture.

The runner scrubs known nonempty environment secrets (`OPENAI_API_KEY` and the others in `harness.dart`) in raw, JSON-escaped, and URL-encoded forms from evidence and artifacts. Recorded sensitive headers are `<redacted>`, and sensitive URL query values are percent-encoded redaction placeholders. Unknown secrets or other encodings are not guaranteed to be removed. Treat evidence as potentially sensitive.

Proof standards:

- A pass means that the check's assertions succeeded. For network checks, inspect the asserted request fields and caller-visible result. For in-memory checks, inspect the asserted values or errors. Do not trust the PASS line alone or infer coverage of unasserted fields.
- Fixtures prove the adapter's mapping against the documented wire format. Only `--live` proves current vendor behavior, and it exists for OpenAI and Anthropic only. Say which one you ran.
- A failing check is a finding. Fix the package or report the failure. Do not weaken the check. On 2026-10-29 three checks fail on real package defects. Two are `extractReasoningMiddleware` streaming bugs (see `features/ai_sdk_dart-platform.md`). One is live `ai_sdk_anthropic/live-reasoning`: the adapter drops signed thinking blocks that have empty text (see `features/ai_sdk_anthropic.md`).
- Report the "Not covered" lines of the feature file for any area that you claim to have verified.
- For UI changes, `ai_sdk_flutter_ui` needs the verify-flutter-chat runs listed in its feature file. The driver does not touch Flutter.

## Cleanup

Each check disposes its registered servers, clients, and subprocesses, and the wrapper kills the driver's process group as a backstop. A timeout closes the check context and rejects new context operations. Dart cannot cancel arbitrary futures, so timeout does not guarantee that all check code has stopped. Cleanup failures make the check fail, appear in `notes`, and do not stop later checks. Run evidence directories are retained; rerunning a check replaces its JSON and artifacts. Remove only a confirmed old run directory when you no longer need it. For UI runs, use `vfc down` (see verify-flutter-chat).

## Helpers

- `scripts/verify`: `setup`, `doctor`, `list`, `run`, `new`. Run `$V help` for usage.
- `driver/lib/harness.dart`:
  - `Check`, `PackageChecks`, and `CheckContext`;
  - `ctx.server` (a fixture with recording), `ctx.recordingDio` (live recording) and `ctx.spawn` (a cleaned-up subprocess);
  - assertions, `observe` and `note`;
  - `FixtureResponse.json/.sse/.ndjson/.text/.bytes` and `SseEvent`.
- `driver/lib/packages/<package>.dart`: the checks for one package. `ai_sdk_dart` is split into `ai_sdk_dart_text.dart` and `ai_sdk_dart_platform.dart`. `ai_sdk_openai_compatible.dart` is the reference style.
- `driver/lib/runner.dart`: the CLI behind `bin/verify.dart`. When you work on one module while others do not compile, make a temporary `bin/dev_<x>.dart` that calls `runCli(args, [module.checks])`, then delete it.

To add a check: add a `Check` to the package's module, add or extend the sub-feature in its feature file with a `Driving it with verify` bullet, then run `cd driver && fvm dart analyze --fatal-infos` and `$V run <package>`.

## Gotchas

- `generateText` wraps retryable errors (429, 5xx, 529) in `AiRetryError` even with `maxRetries: 0`. The typed `AiApiCallError` is in `lastError`.
- With an injected Dio `client`, some providers take the endpoint from the provider's `baseUrl` (Groq, Mistral, the OpenAI chat models), and others from the Dio's `baseUrl` (OpenAI media endpoints, Cohere, Ollama). Pass both when you point a provider at a fixture. Otherwise the request goes to the real vendor.
- The global convenience instances (`openai`, `anthropic`, ...) read keys through `String.fromEnvironment`. A runtime check cannot set them, so they are not driven.
- The driver has its own `pubspec.lock`. Transitive versions (dio, http) can differ slightly from the workspace lock. Package source always comes from this checkout.
- Analyze the driver from `driver/` with `fvm dart analyze --fatal-infos`. The repository's `make analyze` stays clean with the skill present.
