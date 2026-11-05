# Reasoning interleaving: release readiness

## Scope and release proposals

These are release candidates, not published versions. No tag, merge, deployment,
or publication is part of this change.

| Package | Candidate | Evidence for a release |
| --- | --- | --- |
| `ai_sdk_dart` | 3.1.0 | Adds the unreleased `ModelMessage.text` API and fixes reasoning parsing and interleaved text assembly. |
| `ai_sdk_flutter_ui` | 3.1.0 | Includes unreleased `ChatMessage` APIs and controller fixes. Its parts-based bubble requires the new core getter. |

Only these two package versions change. Provider, conversation, remote, schema,
MCP, telemetry, and realtime package versions remain unchanged. Their existing
`^3.0.0` core constraints accept 3.1.0 without a mechanical dependency update.
PR #30's Anthropic fix remains intact. That package's existing unreleased
changelog is a separate patch-release candidate, not a reason to change its
version in this middleware PR.

The Flutter UI core dependency changes from `^3.0.0` to `^3.1.0`. Comparison with
tag `3.0.0` shows that `ModelMessage.text` is absent there. The current
`ChatMessageBubble` calls that getter. The same comparison shows no other new
core public API consumed by UI: approval replay, agent streaming, lifecycle
callbacks, and ID generation already exist in 3.0.0. Workspace resolution alone
cannot detect a published dependency floor that is too low.

The development toolchain remains Flutter 3.44.3 / Dart 3.12.2 from `.fvmrc`.
The package SDK constraints remain Dart `^3.11.1`, with Flutter `>=3.41.3` for UI.
This run does not qualify those minimum versions independently.

## Stream contract

- Each active text ID owns its pending characters, parsing mode, and extracted
  reasoning ID. A different text ID cannot finish its tag or close its reasoning.
  A random per-stream namespace separates extracted IDs from native reasoning
  and nested middleware. The IDs are opaque, not fixed `mw-reasoning` constants.
- Raw chunks, sources, and other unrelated events pass through unchanged and in
  their original relative order. They do not resolve a partial tag.
- A matching text-end resolves that ID's pending characters and closes its
  reasoning first. Finish, terminal error, and EOF resolve all open parsers.
  They close all extracted reasoning, then all remaining text IDs in opening order.
- A delta-only text ID gets a synthesized text-start. Explicitly ended IDs do not
  get a second text-end at finish or EOF.
- Buffered characters can appear after an intervening source or raw event. The
  middleware cannot classify a partial tag until more text or a boundary arrives.
- Core content follows emitted text-delta order, not text-end order. Interleaved
  text IDs can occupy multiple contiguous text parts. Every run retains its
  source ID's merged start/delta/end metadata.
  Structured output previews use the same delta-order text buffer as final output.
- For one generation step, `text`, joined `textStream`, and joined text parts of
  `content` agree. Existing multi-step semantics remain unchanged: `text` and
  `content` describe the final step, while `textStream` includes every step.

## Regression evidence

The new conformance file failed 30 cases before the product changes. Failures
included cross-ID tag completion, combined reasoning, split open/close tags
around raw/source parts, and reversed final text. The tests now cover every
split position of `<think>plan</think>answer`, independent simultaneous blocks,
finish/EOF recovery, reused IDs, per-ID metadata, and agreement of result surfaces.

PR #29's text-ID and terminal closure assertions remain. Its overlapping-ID
snapshot now expects `b:B` before `a:A` because starting B no longer flushes A.
PR #31's single-delta and multi-block assertions remain. Delta-only snapshots
include a synthesized start, and source snapshots no longer force a flush.
PR #30's adaptive/signed/redacted replay tests run unchanged.
Terminal error parts flush pending text before the error reaches consumers,
preserving partial replies in downstream error handling.

The PR #28 fixture check `middleware-extract-reasoning-stream` now runs with raw
chunks disabled and enabled through the real OpenAI-compatible SSE adapter.
It asserts reasoning, final text, streamed text, content text, and raw opt-in.
The Flutter regression checks the streamed reply, completed transcript, one
finish callback, model finish reason, and submitted/streaming/ready ordering.

## Verification record

The product change is commit `b70c731` in draft
[PR #32](https://github.com/codenameakshay/ai_sdk_dart/pull/32).
All Dart and Flutter commands use FVM with Flutter 3.44.3 / Dart 3.12.2.
The local protocol fixtures pin Vercel AI SDK 7.0.111 and MCP TypeScript SDK
1.30.0. Node is 24.21.0 on this host, while CI uses Node 22.

| Check | Result |
| --- | --- |
| Focused core middleware and Anthropic replay tests | 136 passed |
| Downstream Flutter controller regression | Passed |
| Full Flutter UI tests with coverage | 364 passed, 99.04% line coverage (3,212/3,243) |
| `make analyze` | Passed, no issues |
| `make format-check` | Passed, 468 files, zero changes |
| Standalone verification-driver analyzer | Passed |
| PR #28 fixture verification | 298 passed, zero failed, 17 live-only skipped |
| Final-source core fixture rerun | 81 passed, zero failed |
| `make test-examples` | Passed, including fixture-key media lifecycle tests and five remote-backend tests |
| `npm test --prefix examples/remote_backend/js` | Three passed |
| Tool tests | 22 passed |
| Catalog check | Passed, 16 records across nine providers |
| Core and Flutter UI publish dry-runs | Passed, zero warnings each. No publication |
| Flutter chat release web build and scenarios | All eight keyless scenarios passed |
| Advanced app release web build | Passed, source and artifact fingerprints matched |
| Advanced app keyless scenarios | Five passed. Full `widget-gallery` failed at snackbar assertions |
| Prescribed 99% coverage gate | Not clear: complete run failed one test. Retry terminated before a result |

The focused command includes `extract_reasoning_interleaving_test.dart`,
`extract_reasoning_text_id_test.dart`, `middleware_conformance_test.dart`, and
Anthropic's unchanged `adaptive_thinking_replay_test.dart`. It uses
`--concurrency=1 --reporter failures-only`.

Fixture evidence is in
`/tmp/ai-sdk-verify/evidence/reasoning-interleaving-20261105/summary.md`.
The core rerun records HEAD `b70c731`. The raw-interleaving SSE evidence is
`ai_sdk_dart/middleware-extract-reasoning-stream.json` below that directory.
With raw chunks off and on, all three text surfaces equal `Done.` and reasoning
equals `plan it carefully`. The raw counts are zero and six respectively.

The coverage command is:

```sh
AI_SDK_REMOTE_REFERENCE_URL=http://127.0.0.1:19129/chat \
AI_SDK_MCP_REFERENCE=1 make coverage-check
```

The first complete attempt finished with 2,053 passes and one failure in
`openai_files_test.dart`: `timeout while consuming a download body is typed and closes the peer`.
Its 50 ms budget expired during `download()` instead of during body consumption.
The same assertion failed in isolation. No OpenAI file implementation or test changed.
This shared four-CPU host had a load average around 29 during verification.
Both attempts used a temporary `concurrency: 1` Dart runner setting, without changed
assertions, timeouts, package scope, or coverage threshold.
The retry ended with SIGTERM (exit 143), without a coverage result.
The cause of that termination is not established.
The complete failed run stopped before the Flutter suite and coverage summary.
This report does not claim that the 99% threshold passed.

The first full fixture run missed one request in `media-timeouts`.
The complete unchanged rerun passed, as did the final-source core rerun.

Web evidence is in `/tmp/verify-flutter-chat/evidence/`, under
`reasoning-interleaving-ui-20261105` and `reasoning-interleaving-advanced-20261105`.
Both builds record product commit `b70c731` and contain no provider keys.
The chat scenarios cover local approval and denial, remote text and approval
continuations, unreachable-backend handling, RTL, and shell navigation.
Representative desktop, mobile-width, reasoning/source, and dark-theme PNGs
received visual inspection.

The advanced `widget-gallery` scenario failed twice at short-lived snackbar assertions.
The first failure missed the suggestion snackbar. The retry passed that step,
then missed the source-link snackbar. This scenario is not green, and its
later interactive sections are not qualified by this run.
The initial failure record is retained at
`/tmp/ai-sdk-reasoning-widget-gallery-first-failure.json`.
No assertions or scenario timeouts changed.

The other five advanced-app scenarios passed: `widget-gallery-dark`,
`tools-chat-fixtures`, `conversation-ui`, `keyless-guards`, and `drawer-nav`.
The scenario batch ended with SIGTERM after the conversation check.
A fresh doctor check passed, then the remaining guard and drawer checks passed.
Both app runs stopped through `vfc down`. Their scratch builds and browser
profiles were removed, and their evidence remains available.

Logs for the coverage attempts are
`/tmp/ai-sdk-reasoning-coverage-final.log` and
`/tmp/ai-sdk-reasoning-coverage-retry.log`.
The isolated timeout failure is in
`/tmp/ai-sdk-reasoning-download-timeout-isolated.log`.
The release remains a draft until the full gate and interactive gallery pass.

The separate full Flutter UI suite passed all 364 tests with coverage enabled.
It used the same command as the coverage script's Flutter stage:
`fvm flutter test --no-pub --reporter=failures-only --coverage`, from the UI package.
Its line coverage is 99.04% (3,212/3,243), not a monorepo coverage result.
The log is `/tmp/ai-sdk-reasoning-flutter-coverage-final.log`.
The temporary root runner configuration was removed after verification.

## Limitations and other repositories

Fixture results prove local SDK behavior and protocol mapping, not current live
vendor behavior. No live keys, billed requests, native-device checks, or minimum
SDK matrix are part of this run. The verification feature files retain their
explicit exclusions, including device audio, screen readers, live model paths,
and unexposed provider capabilities.

The web checks do not qualify frame throttling, live auto-scroll, custom message
builders, reasoning-file attachments, loaded/failed images, or unsafe retry states.
They also do not qualify untranslated labels, per-message direction, reduced
motion, or haptics. The feature maps document these exclusions in full.

No cross-repository age report or list of other repositories accompanied this
request. The repository's historical release reports describe this monorepo,
not an aged-repository inventory. No other repository change or release is
proposed. An age-based release proposal needs evidence from that repository's
supported SDK constraints, current examples, and current test/coverage results.
