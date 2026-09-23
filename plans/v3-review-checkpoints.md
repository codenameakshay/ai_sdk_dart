# v3 independent review checkpoints

These are interim reviews of the working tree against `b702929811281ac6be4c5ea2c10004b412b74924`, not final release approval. The spec is [the approved report](v3.0.0-report.md).

## Standards / no-comments checkpoint

A fresh Luna auditor found no documented coding-standard violations in the audited reliability and provider changes. It identified duplicated schema request fragments in streaming and non-streaming provider paths as a maintainability judgement. That finding was sent to the provider owner for consolidation.

The comments audit found no newly added workaround constraints, suppression directives, or protected comments requiring an approval decision. No comment deletions were accepted at this checkpoint. Re-audit the final diff.

Separate lifecycle findings:

- Completed operation scopes retained callbacks on a long-lived caller cancellation future. Core now uses a detachable cancellation event subscription and cancels it when the scope closes. Regression qualification remains necessary.
- Structured-stream cleanup could report a secondary cancellation error outside the original failure path. Cleanup errors are contained so they cannot replace the terminal source/decoder error. Further cleanup tests remain necessary.

## Spec checkpoint

- OpenAI Responses could emit the same function call on both argument completion and output-item completion. Sent to the provider owner for deduplication and single-execution integration tests.
- Core stream aggregation dropped opaque reasoning metadata and signatures. A new public regression reproduced this. Core now merges reasoning metadata across start/delta/end and preserves a generic end signature; provider multi-turn integration still needs qualification.
- Anthropic native schema used the older `output_format` shape. Parent verified current pinned upstream source uses `output_config.format` and sent an exact source reference to the provider owner. Source: `packages/anthropic/src/anthropic-language-model.ts:678–705` at upstream `e9c1d2f54da6bd01a16bb8a5fdfcb4b62f34e7d0`. The older v6 migration text is superseded here.
- Gemini thought signatures must come from the outer Part, and provider tool IDs must survive round trips. First-draft nested signature extraction and invented tool-response payload IDs were rejected; exact provider fixtures are required.

## MCP checkpoint

A separate fresh audit identified modern subscription recovery using a legacy method, modern HTTP cancellation sending legacy notifications, auth retry bypassing the mutating replay policy, and malformed progress totals. These were sent to the MCP owner for regression tests and correction.

The audit also distinguished optional host authentication callbacks from a complete MCP authorization implementation. Discovery, issuer/resource binding, PKCE handoff, and documented platform behavior remain explicit acceptance items, not claims implied by adding a callback.

## Parent follow-up checkpoint

- Conversation snapshot implementation was registered in the workspace, but failed manual contract review: shallow container freezing, inconsistent deep equality/hash behavior, permissive malformed input coercions, empty text rejection, and incomplete ID validation. Returned to its owner with public regression requirements. Four initial tests are not release qualification.
- The Responses executor-once fixture included `call_id` and `name` directly in argument events. Real streams establish those on `response.output_item.added`; the adapter currently ignores that event. The apparent deduplication success does not yet prove real protocol correctness. Identity-map and realistic fixture correction remains required. Text start/end IDs also differ.
- Structured finalization still used a last-object extractor after strict parsing was requested. A complete earlier object can mask malformed trailing output. Returned for strict whole-document/fenced-document parsing and regressions.
- MCP authorization discovery dropped issuer path components and accepted relative/empty/insecure token endpoints. Nine new regressions failed before correction. The parent changed discovery to the three-endpoint tenant order required by the 2026-07-28 specification and rejects malformed metadata URIs, permitting HTTP only for loopback. `fvm dart test packages/ai_sdk_mcp/test/` passed 134 tests; package analysis clean. Logs: `/tmp/ai-sdk-v3-auth-before.log`, `/tmp/ai-sdk-v3-mcp-auth-after.log`.

Source for tenant discovery order: https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization/authorization-server-discovery (retrieved during this review; local copy `/tmp/v3-auth-server-discovery.md`).

## Cleanup, aggregation and remote follow-up

- Parent reproduced a secondary cancellation error escaping from Dart `StreamIterator` after a source error. Guarding a later `iterator.cancel()` is insufficient because the iterator auto-cancels on the initial error. New `stream_object_cleanup_test.dart` failed for the source-error case and passed after materializing source errors as `StreamOutcome` data, then cancelling explicitly. This preserves the original error/stack while containing cleanup failure. Cleanup+settlement suite: 9 passed. Logs: `/tmp/ai-sdk-v3-cleanup-before.log`, `/tmp/ai-sdk-v3-cleanup-after.log`.
- The first aggregate implementation left `StreamTextFinishEvent.usage` as final-step usage even though `result.usage` was aggregate. Parent added an assertion that failed, corrected the final event and added per-step response messages/request/response metadata. Two aggregate tests now pass.
- Remote cancellation was not fully qualified by its initial tests. Waiting-header cancellation raced only the result, leaving HTTP work alive; active cancellation was polled only after another frame. A server closing itself after a delay made the test pass without proving interruption of a silent stream. Injected client ownership, cancellation of rejected response bodies, and real socket closure need correction.
- Remote outgoing messages were persistence-codec objects, not an audited Vercel UIMessage conversion. The first pinned reference server ignored request bodies, so its successful text response proves only receiving a simple stream. Request validation and tool/approval round trips remain required.
# 2026-09-23 continuation review

- Fresh `gpt-5.6-luna` launch completed a real code review; model service availability verified.
- Text lifecycle first patch rejected: parent `text_operation_scope_test.dart` run failed step-token cancellation, first-chunk acquisition deadline, and total-token cancellation race. Core lifecycle worker owns correction; W04 remains incomplete.
- Google continuation first qualification rejected: a manually constructed assistant input sent once is not a two-turn provider/core replay test. Real generated-history replay and provider call-ID association are assigned.
- Remote lifecycle tests were strengthened to observe peer EOF, wait for the first reduced SSE state before subscription cancellation, and verify detached observers across 100 completed requests using the same token. Parent reference-server-enabled suite passes all 15 tests.
- Remote `http` lower bound corrected from 1.2 to 1.6: abort support appeared in 1.5 and browser silent-response cancellation was fixed in 1.6. Root dependency resolution passed.
- MCP duplicate `resource_metadata` parameters within one challenge previously overwrote each other. Parent regression failed before correction; full MCP suite now passes 139 tests and analysis is clean.
- Parent public structured-array tests pass: element-only consumers allocate zero snapshots; late subscribers receive full prefixes and retained lists remain unmodifiable. This does not establish zero structural-node allocations or a timing improvement.
- Parent unfiltered Responses test run failed the embedding socket fixture at its 2-second peer-close wait. Its arbitrary 30ms pre-cancellation sleep can run before request acquisition. Worker owns deterministic handshake/EOF correction; filtered Responses-only passes do not qualify the full file.

## Parent approval, framework and file-lifecycle review (2026-09-23)

- Fresh explicitly selected `gpt-5.6-luna` worker executed workspace/branch verification successfully. Catalog tooling analysis passed and the check validated 16 records across 9 providers.
- Parent reran `fvm dart test packages/ai_sdk_dart/test/conformance/streamed_tool_cleanup_test.dart`: one regression passed. This verifies preservation of the original stream failure without an unhandled cleanup failure.
- W05 remains incomplete: `ToolLoopAgent.generate` lacked approval/context forwarding; optional binding fields accepted unbound approvals; `resume` discarded a renewed approval request and could contact the provider with unresolved calls; errors before its final try block leaked the operation scope. Separate typed tool context and generation callback context still need implementation. Returned to core owner with positive and negative replay cases.
- W14 remains incomplete: the Riverpod recipe watched a plain provider containing a ChangeNotifier and did not subscribe to conversation changes; Bloc replacement lacked concurrent close/replacement protection. Compiling examples and composer tests do not prove framework lifecycle behavior. Actual framework rebuild/ownership/interleaving tests assigned.
- W17 remains incomplete: download consumer cancellation did not explicitly cancel the Dio token, disposed scopes still responded to caller signals, timeouts reported cancellation, multipart construction could throw outside scope cleanup, and metadata accepted fractional integers/coerced status strings. Returned for lifecycle corrections and socket evidence.
- Parent benchmark command completed successfully. Current three-sample medians: 64 KiB copy 11.479 ms versus structural 12.870 ms; 1 MiB copy 189.001 ms versus structural 125.432 ms. At 1 MiB the counters change from 7,505,875 copied elements to zero full-list copies, with 7,742 structural nodes and 22,753 root references. These are exploratory results only: fixed ordering, three samples and concurrent worker load do not satisfy the approved 30-run distribution contract or Flutter frame qualification. Raw output: `/tmp/v3-structured-benchmark-review.json`.

### Verified follow-up checkpoints

- Parent Files run: `fvm dart test packages/ai_sdk_openai/test/openai_files_test.dart` passed **20** tests, including actual downstream-cancellation socket EOF, typed silent-body timeout, auth cancellation/no dispatch and strict metadata. This is the count in the parent log (`/tmp/v3-files-parent-review.log`); worker reported 21. Unlistened cancellation and cleanup-failure containment still need explicit coverage. Batch implementation is now assigned separately within W17.
- Parent added `approval_replay_prevalidation_test.dart`. It proves a tampered second call cannot execute the first call. Its first load had a fixture async-signature error; after correction the worker's fingerprint recomputation fix was already present and the regression passed. Do not claim a reproduced red-to-green production failure from this run. W05 comprehensive binding/context tests remain assigned.
- `fvm dart pub publish --dry-run -C packages/ai_sdk_conversation` and the corresponding remote command both exited zero with zero package warnings. These dry-runs do not publish anything.
- Added a real Dart remote example and ran it against the already-running pinned JavaScript reference backend: output `Hello from the pinned AI SDK backend.` Analysis and formatting passed. The example keeps the transport in a try/finally and prints changed assistant text.
- New realtime implementation handoff is based on current fetched official sources and distinguishes Realtime from GPT-Live. No realtime implementation or device support is claimed.

### Remaining provider lifecycle audit

`ai_sdk_openai_compatible/lib/src/dio_cancellation.dart` still adapts an `AbortSignal` by attaching to its non-detachable `onCancelled` future. Google and Cohere contain parallel helpers. Core's detachable `CancellationToken.cancellationEvents` does not automatically make these provider observers detachable; raw provider calls using a long-lived uncancelled token can retain completed request callbacks. Audit an additive observable-signal seam and a disposable provider request scope rather than claiming the core fix covers this path. Auth acquisition and late startup disposal also need consistent provider-level qualification. These are W04/W08 pending items, separate from the verified Responses and core fixtures.

### Batch and framework review before implementation acceptance

- Parent `openai_batch_wire_regression_test.dart` reproduced two protocol failures: a valid error-file row with `response: null` threw malformed-result, and a complete final JSON row without a newline threw truncated-JSONL. Source for the error row is the official Batch guide expiry example. The batch request type also lacked a way to supply any prompt/input. Returned for useful request bodies, strict/limited decoding, pagination, total-deadline ownership, submission-failure file ownership and real loopback lifecycle fixtures.
- Flutter Bloc recipe still disposed a caller-owned replacement in a close race, did not await subscription cleanup and did not guard the initial listener. Riverpod ownership and reactive usage documentation remained inconsistent. Returned with deterministic lifecycle tests. The full UI run had one approval-resume failure; it is a required UI migration, not excluded as unrelated core work.

### Current parent regression review

- Batch wire regressions now pass independently: per-line limits apply to rows rather than whole network chunks, error-only results accept a null response, and complete final rows need no trailing LF. Command: `fvm dart test packages/ai_sdk_openai/test/openai_batch_wire_regression_test.dart`; 3 passed, `/tmp/v3-batch-wire-parent-current.log`.
- Responses pre-cancelled generation and streaming each invoke auth once before rejecting. Two added tests reproduced this behavior; expected auth calls are zero. Command: `fvm dart test packages/ai_sdk_openai/test/responses_cancellation_test.dart --name pre-cancelled`; 2 failed, `/tmp/v3-responses-precancel-before.log`. Assigned lazy auth acquisition to the OpenAI worker. See `v3-research/provider-lifecycle-followup.md`.
- The first Batch total-deadline test used a real 10 ms budget and 30 ms delay. This does not establish deterministic serialization-budget coverage and can fail before upload on a loaded host. Returned for controllable timing and separate pre-upload expiry proof.
- Bloc deferred cancellation initially read a mutable subscription field from the later cleanup callback. The worker changed it to capture the subscription and await cleanup. The parent's concurrent replacement regression passed after that correction was already present: `fvm flutter test packages/ai_sdk_flutter_ui/test/bloc_replacement_review_test.dart`, 1 passed. The log is named `/tmp/v3-bloc-replacement-before.log`, but no production red state was observed in this run. Framework-wide verification remains pending.
- Open PR state refreshed with `gh pr list`: draft #4 remains the only open PR. No new implementation PR has been raised at this checkpoint.
