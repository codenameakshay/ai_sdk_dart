# Core and provider-contract reliability audit

Audit scope: `ai_sdk_dart` and `ai_sdk_provider` at HEAD `b702929811281ac6be4c5ea2c10004b412b74924`. This is a read-only review. The focused verification run used Dart 3.13.3 and passed 48 tests across `stream_object_conformance_test.dart`, `generation_params_test.dart`, and `provider_value_types_test.dart`; the repository contains 643 test invocations under the two packages. No source files were changed and no credentials were encountered.

Pinned verification used `fvm dart` 3.12.2: `fvm dart test packages/ai_sdk_dart/test/conformance/stream_object_conformance_test.dart packages/ai_sdk_dart/test/conformance/generation_params_test.dart packages/ai_sdk_provider/test/provider_value_types_test.dart` completed with `All tests passed!` (`+48`). The supplied benchmark also ran successfully with `fvm dart run packages/ai_sdk_dart/benchmark/structured_stream_benchmark.dart --json`; its output is summarized under PERF-04. A runnable reproduction is in `plans/v3-research/core_reliability_repro.dart`.

## System shape

`ai_sdk_provider` is a deliberately thin V4 contract seam: `LanguageModelV4` exposes `doGenerate`/`doStream` (`packages/ai_sdk_provider/lib/src/language_model/language_model_v4.dart:11-34`), while embedding, image, speech, transcription, and rerank contracts each expose one provider operation. `ai_sdk_dart` normalizes messages and options, owns retries/tool execution/structured parsing, and turns provider stream parts into public result streams. This layering is sound: providers do wire translation and cancellation adapters; core does provider-independent orchestration.

## Findings

### [CORRECTNESS-01] Make `streamObject` settle its result after an exceptional source stream

- **Evidence**: `packages/ai_sdk_dart/lib/src/core/stream_object.dart:109-167` wraps `await for (final part in broadcast)` in `try/finally`, but has no `catch`; if `response.stream` emits a Dart stream error rather than a `StreamPartError`, control jumps to `finally`, closes the two controllers, and never completes or errors `objectCompleter`.
- **Evidence**: `packages/ai_sdk_dart/lib/src/core/stream_object.dart:170-176` exposes `objectCompleter.future` as both `stream` and `object`, so callers can wait forever after a provider transport-level stream failure.
- **Evidence**: `packages/ai_sdk_dart/test/conformance/stream_object_conformance_test.dart:114-145` covers an in-band `StreamPartError`, but not an actual stream error event.
- **Impact**: Provider/network failures represented as stream errors leave the primary object future pending and make retry/error UI hang indefinitely; only the partial and patch streams close.
- **Effort**: S (hours, including a regression test).
- **Risk**: LOW; centralize the same error completion already used for in-band errors.
- **Confidence**: HIGH; this follows directly from Dart `await for` error semantics and the missing catch.
- **Fix sketch**: Catch `(error, stackTrace)`, complete `objectCompleter` with that error if pending, and add errors to the public object/patch streams according to their contract. Add a fake model whose stream calls `controller.addError` and assert `result.object` and `result.stream` terminate.
- **Reproduction**: `timeout 20s fvm dart run plans/v3-research/core_reliability_repro.dart` prints `start`, `streamObject returned`, `unhandled source error: Bad state: transport boom`, and `streamObject object: TIMEOUT (source error did not settle object)`. The repro attaches a zone error handler so the process can continue; without it, the same source error exits the process as an unhandled exception.

### [CORRECTNESS-02] Apply cancellation and timeout during `streamObject` consumption

- **Evidence**: `packages/ai_sdk_dart/lib/src/core/stream_object.dart:69-78` accepts only `timeout`, with no `CancellationToken`/abort argument.
- **Evidence**: `packages/ai_sdk_dart/lib/src/core/stream_object.dart:97-117` applies `withOptionalTimeout` only to the provider's `doStream` startup future; the subsequent `await for` at lines 117 onward has no timeout or cancellation race.
- **Evidence**: `packages/ai_sdk_dart/test/conformance/stream_object_conformance_test.dart:216-228` verifies only a slow startup timeout, not a stream that starts and then goes silent.
- **Impact**: A live provider connection can remain pending forever after the initial response object arrives; callers cannot stop structured-object streaming through the same cancellation contract available to `streamText`.
- **Effort**: M (one day-ish, API addition plus lifecycle tests).
- **Risk**: MED; adding an abort parameter is source-compatible, but stream cancellation must also be propagated to provider adapters and controller cleanup.
- **Confidence**: HIGH for the missing behavior; whether an app needs it depends on provider stream lifecycle.
- **Fix sketch**: Add `CancellationToken? abortSignal` and a total/idle timeout policy, use `raceWithCancellation` while advancing the iterator, and cancel the subscription when terminal. Test pre-cancel, mid-stream cancel, silent stream timeout, and provider `CancelToken` propagation.

### [DATA-03] Reject short embedding responses instead of silently returning partial batches

- **Evidence**: the provider contract describes a batch result as `List<EmbeddingModelV2Embedding<VALUE>>` (`packages/ai_sdk_provider/lib/src/embedding_model/embedding_model_v2_generate_result.dart:20-32`), while OpenAI parses only `min(response.length, options.values.length)` (`packages/ai_sdk_openai/lib/src/openai_provider.dart:181-198`) and Google does the same (`packages/ai_sdk_google/lib/src/google_provider.dart:617-633`).
- **Evidence**: `packages/ai_sdk_dart/lib/src/core/embed_many.dart:122-142` appends whatever each provider returns and documents one entry per input (`:15-19`) without checking cardinality.
- **Impact**: A truncated or malformed provider response can silently misalign values and vectors; downstream retrieval/indexing may accept incomplete data without knowing which inputs are missing.
- **Effort**: S (hours, contract tests across providers).
- **Risk**: MED; some providers may legitimately omit values under unusual API behavior, so the desired policy must be explicit.
- **Confidence**: HIGH; the current code intentionally truncates and never validates count.
- **Fix sketch**: Validate `embeddings.length == options.values.length` at the provider/core boundary, raise a typed provider-response error with counts, and add short/empty response tests for single and chunked `embedMany`.
- **Reproduction**: the same pinned repro prints `embedMany values=2 returned=1` from a model that returns one embedding for two requested values. This confirms the core currently returns a successful partial batch.

### [PERF-04] Avoid whole-batch memory spikes in default `embedMany`

- **Evidence**: `packages/ai_sdk_dart/lib/src/core/embed_many.dart:84-101` sends all values in one provider call whenever `maxParallelCalls` is null or at least the input length.
- **Evidence**: the same function only chunks when callers explicitly set `maxParallelCalls` (`:104-122`); no provider-independent request-size or token limit exists in the contract.
- **Impact**: Large document batches can create oversized request bodies, hit provider limits, or retain all input/output vectors in one in-flight operation, despite the API presenting itself as a batch helper.
- **Effort**: M (one day-ish; requires a clear chunk-size API and provider-limit documentation).
- **Risk**: MED; changing default batching changes request count, latency, and usage behavior.
- **Confidence**: MED; the risk is clear, but safe defaults depend on provider/token limits not represented in this seam.
- **Fix sketch**: Add explicit `maxValuesPerCall` (or a provider capability) and preserve input ordering while aggregating usage. Keep current all-at-once behavior only as an explicit opt-in or document it as caller-controlled.

### [PERF-06] Bound cumulative copying for streamed array snapshots

- **Evidence**: `packages/ai_sdk_dart/benchmark/structured_stream_benchmark.dart` deliberately creates an immutable snapshot after every completed array element using `createTrackedImmutableSnapshot(partialValues)` and asserts a triangular copy bound (`:82-111`).
- **Evidence**: pinned benchmark output was array parse attempts `4/244/3874`, snapshot element copies `10/29,890/7,505,875`, and elapsed `10,868/73,067/280,082` microseconds at approximately 1KiB/64KiB/1MiB.
- **Impact**: Consumers of `partialOutputStream`/`elementStream` receive immutable full-array snapshots whose cumulative allocation is O(n²) in emitted element count. Large streamed arrays can create substantial allocation and GC pressure even though parsing itself is bounded.
- **Effort**: M (one day-ish for a changed snapshot representation and compatibility tests).
- **Risk**: HIGH; callers may rely on snapshot immutability and historical values, so a mutable/delta representation would be an API change.
- **Confidence**: HIGH for the measured allocation pattern; MED for production impact because payload and consumer behavior vary.
- **Fix sketch**: Preserve the current immutable API by default, but consider a delta/iterator channel for large arrays or a configurable snapshot cadence. Benchmark allocation and end-to-end UI consumption before changing defaults.

### [PERF-05] Decide whether independent tool calls may execute concurrently

- **Evidence**: both generation paths execute each model-emitted tool call in source order with `await`: `packages/ai_sdk_dart/lib/src/core/generate_text.dart:542-570` and `packages/ai_sdk_dart/lib/src/core/stream_text.dart:572-642`.
- **Impact**: A response containing several independent slow tools takes the sum of their durations before the next model step; users cannot opt into bounded parallelism. Parallel execution could reduce latency, but ordering and side-effect semantics are currently implicit.
- **Effort**: M for a design/API spike; L for a safe implementation with ordering and approval semantics.
- **Risk**: HIGH; concurrent tools can race, duplicate side effects, alter callback order, and change tool-result message ordering.
- **Confidence**: MED; the serial behavior is certain, but whether it is a defect depends on the intended tool contract.
- **Fix sketch**: First characterize whether tool calls are promised to execute in model order. If independent execution is allowed, add an explicit per-call concurrency policy and preserve deterministic result ordering; otherwise document serial execution and add a latency/ordering test so it remains intentional.

### [ARCH-05] Consolidate provider response validation and embedding cardinality rules at the seam

- **Evidence**: OpenAI (`packages/ai_sdk_openai/lib/src/openai_provider.dart:168-210`), Google (`packages/ai_sdk_google/lib/src/google_provider.dart:602-633`), and other providers independently parse embedding arrays, numeric vectors, usage, and malformed response errors.
- **Evidence**: the provider package exposes shared JSON/error helpers (`packages/ai_sdk_provider/lib/src/shared/json_helpers.dart`, `api_error.dart`), but no shared result validator for batch cardinality or vector shape.
- **Impact**: Each provider can drift in malformed-response handling and silently return different partial-result semantics; every new embedding provider repeats the same boundary logic.
- **Effort**: M (one day-ish to define helper contract and migrate providers/tests).
- **Risk**: MED; stricter shared validation may expose provider behavior that callers currently tolerate.
- **Confidence**: HIGH for duplication; MED for the exact desired common policy.
- **Fix sketch**: Add internal/shared helpers for typed list parsing, numeric-vector validation, cardinality checks, and usage extraction. Keep wire-specific field lookup in providers, but make post-parse result invariants uniform.

### [API-08] Restrict `responseMessages` to generated response messages

- **Evidence**: `packages/ai_sdk_dart/lib/src/core/generate_text.dart:634-640` derives `responseMessages` by filtering the entire mutable `normalizedMessages` history for assistant/tool roles. `streamText` repeats the same filter at `packages/ai_sdk_dart/lib/src/core/stream_text.dart:739-745`.
- **Evidence**: `plans/v3-research/core_reliability_repro.dart` runs `generateText` with one prior assistant message and one new model response; pinned output is `responseMessages after assistant history: 2`.
- **Impact**: Callers persisting or replaying `responseMessages` receive prior assistant/tool history again, so a multi-turn app can duplicate old model messages or mistake the result envelope for the newly generated response.
- **Effort**: M (clarify contract, capture per-step generated messages, update tests/docs).
- **Risk**: HIGH; existing consumers may have adapted to the current broad-history behavior.
- **Confidence**: MED; the implementation is certain, while the intended contract must be checked against the SDK result semantics before changing it.
- **Fix sketch**: Preserve a separate generated-response list as each model step completes and use that for `responseMessages`; retain full conversation history in `requestMessages` or an explicitly named field. Add a multi-turn regression test with prior assistant and tool messages.

### [API-09] Make schema validation semantics explicit for typed tools

- **Evidence**: `Schema<T>` stores a JSON schema map and a decoder (`packages/ai_sdk_dart/lib/src/tools/tool.dart:94-103`), while `parseToolInput` only checks that raw input is a map and then calls `fromJson` (`packages/ai_sdk_dart/lib/src/core/shared/common_helpers.dart:31-47`). No general JSON-schema validator is invoked by core.
- **Evidence**: `plans/v3-research/core_reliability_repro.dart` declares a schema requiring a string `city`, supplies `{unexpected: 1}`, and uses identity `fromJson`; pinned output is `schema-invalid input step tool results: [accepted: {unexpected: 1}], text=done`.
- **Impact**: A schema map controls provider declarations/native strict mode but does not itself validate tool input locally. Users expecting required/type enforcement can execute invalid data unless their `fromJson` decoder performs validation.
- **Effort**: S for documentation and examples; L for adding a complete JSON-schema validator/dependency.
- **Risk**: MED; changing to automatic validation may reject inputs currently accepted and add dependency/size cost to a client SDK.
- **Confidence**: HIGH for current semantics; this is an API contract gap, not necessarily a bug if documented.
- **Fix sketch**: Document that `fromJson` is the runtime validation boundary and provide a small strict decoder/code-generation recommendation. Consider an opt-in validator only after measuring dependency size and supported JSON Schema dialect requirements.

### [TEST-06] Add transport-error and backpressure characterization tests before reliability changes

- **Evidence**: the current focused suite has strong coverage for in-band stream errors, cancellation, retries, and structured parsing (`packages/ai_sdk_dart/test/conformance/stream_object_conformance_test.dart`, `generation_params_test.dart`), and all 48 focused tests passed.
- **Evidence**: no test in the stream-object suite creates a source `StreamController` that emits `addError` and then checks `object`; the existing error tests inject `StreamPartError` values (`stream_object_conformance_test.dart:114-145`).
- **Evidence**: `streamText` uses terminal-aware broadcast wrapping (`packages/ai_sdk_dart/lib/src/core/streaming/terminal_streams.dart:17-46`), while `streamObject` directly exposes a broadcast stream (`stream_object.dart:100-107,170-175`), with no matching late-subscriber/error-terminal characterization tests.
- **Impact**: Reliability changes can regress stream terminal semantics or expose different behavior between text and object APIs without a shared test oracle.
- **Effort**: S (hours).
- **Risk**: LOW; tests only.
- **Confidence**: HIGH; the missing scenarios are directly visible in the test/source asymmetry.
- **Fix sketch**: Add tests for source errors, silent streams, cancellation, late subscribers, listener cancellation, and provider stream cleanup. Add a small fake model that records subscription cancellation and backpressure behavior.

### [DX-07] Document the cancellation/timeout boundary of every core API

- **Evidence**: `streamText` accepts `abortSignal` and applies cancellation while advancing stream iterators (`packages/ai_sdk_dart/lib/src/core/stream_text.dart:953-967`), while `streamObject` accepts only startup `timeout` (`stream_object.dart:69-117`). Other helpers such as `embed`, `embedMany`, image, speech, transcription, and rerank expose timeout but no cancellation token (`packages/ai_sdk_dart/lib/src/core/embed.dart:30-45`, `generate_image.dart:35-59`, `generate_speech.dart:28-43`).
- **Impact**: Users cannot infer from the otherwise uniform API which operations can be actively cancelled versus merely abandoned after a future timeout; long-running client applications risk leaked work and inconsistent UX.
- **Effort**: S for docs and tests; M if API parity is selected.
- **Risk**: LOW for documentation, MED for adding cancellation to all model contracts.
- **Confidence**: HIGH.
- **Fix sketch**: Publish a table of startup timeout, consumption timeout, and cancellation semantics per function. Then decide whether provider contracts should gain a shared abort signal for non-language model operations.

## Confirmed strengths

- Retry behavior is unusually well characterized: `retry_helper.dart:55-142` honors retryability, retry budgets, `Retry-After`, cancellation during backoff, and typed exhausted retries; the focused generation tests passed all related cases.
- Provider cancellation is wired through Dio adapters in the OpenAI-compatible, Anthropic, and Google implementations (for example `packages/ai_sdk_openai_compatible/lib/src/openai_compatible_chat_language_model.dart:753-771`), and core stream cancellation races iterator advancement (`stream_text.dart:953-967`).
- Structured-stream parsing has an explicit cadence benchmark at `packages/ai_sdk_dart/benchmark/structured_stream_benchmark.dart`; it asserts bounded parse attempts and snapshot-copy growth rather than merely timing a happy path.
- The benchmark result is useful even though it exposes cumulative snapshot-copy cost: it prevents parse-attempt regressions and gives a reproducible baseline for any future immutable-snapshot optimization.
- The provider seam uses typed sealed content/stream part classes and typed errors instead of exposing raw provider JSON to core callers (`packages/ai_sdk_provider/lib/src/language_model/language_model_v4_content.dart`, `language_model_v4_stream_part.dart`, `errors/ai_errors.dart`).

## Suggested execution order

1. Add the source-stream-error regression test and fix `streamObject` settlement (`CORRECTNESS-01`).
2. Add stream-object cancellation/consumption-timeout semantics with characterization tests (`CORRECTNESS-02`, `TEST-06`).
3. Decide and enforce embedding cardinality invariants (`DATA-03`).
4. Document or redesign batch sizing and operation cancellation (`PERF-04`, `DX-07`).
5. Clarify response-message and schema-validation contracts before changing behavior (`API-08`, `API-09`).
6. Consolidate post-parse provider validation only after the invariants are covered by provider conformance tests (`ARCH-05`).
