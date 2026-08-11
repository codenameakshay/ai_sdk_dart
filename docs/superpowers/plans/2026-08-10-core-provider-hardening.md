# Core and Provider Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make streaming, retries, cancellation, structured output, and provider HTTP behavior reliable under real network and tool-loop conditions.

**Architecture:** Core owns retry, cancellation, and stream-result semantics. Providers translate the shared contracts to their wire protocols and reusable HTTP clients without duplicating orchestration policy.

**Tech Stack:** Dart 3.12, Flutter 3.44, `dio`, `package:test`, existing fake models and wire fixtures.

---

### Task 1: Google streaming parity

**Files:**
- Modify: `packages/ai_sdk_google/lib/src/google_provider.dart`
- Test: `packages/ai_sdk_google/test/google_provider_test.dart`

- [ ] Add a failing stream test that decodes the existing Gemini `functionCall` fixture and asserts one `LanguageModelV3ToolCallPart` with the fixture's name and JSON arguments.
- [ ] Run `fvm dart test packages/ai_sdk_google/test/google_provider_test.dart -n 'doStream surfaces function calls'` and confirm the missing tool call fails.
- [ ] Route streamed `functionCall` parts through the same tool-call conversion used by `doGenerate`, preserving IDs and JSON arguments.
- [ ] Add a failing request-capture test with `stopSequences: ['END']`, then include `stopSequences` in streaming `generationConfig`.
- [ ] Run the complete Google package test suite and commit the focused change.

### Task 2: Cohere tool-call finalization

**Files:**
- Modify: `packages/ai_sdk_cohere/lib/src/cohere_provider.dart`
- Test: `packages/ai_sdk_cohere/test/cohere_provider_test.dart`

- [ ] Add a failing stream fixture that ends after tool-input deltas without an explicit tool-call-end event.
- [ ] Assert message end emits one finalized tool call rather than losing accumulated input.
- [ ] Implement one finalization helper used by explicit tool end and message end; reject malformed JSON through the existing provider error path.
- [ ] Run `fvm dart test packages/ai_sdk_cohere/test/` and commit.

### Task 3: Shared retry policy

**Files:**
- Create: `packages/ai_sdk_dart/lib/src/core/retry.dart`
- Modify: `packages/ai_sdk_dart/lib/src/core/generate_text.dart`
- Modify: `packages/ai_sdk_dart/lib/src/core/stream_text.dart`
- Test: `packages/ai_sdk_dart/test/conformance/generation_params_test.dart`
- Test: `packages/ai_sdk_dart/test/conformance/timeout_test.dart`

- [ ] Add failing tests proving an `AiApiCallError(isRetryable: false)` makes one attempt, a retryable error eventually succeeds, cancellation is never retried, and delay cannot exceed the remaining timeout.
- [ ] Add deterministic injected delay/random hooks scoped for tests.
- [ ] Implement capped exponential backoff with jitter and `Retry-After` parsing when provider metadata supplies it.
- [ ] Delete the duplicated retry loops from generate and stream paths and use the shared helper.
- [ ] Run all `ai_sdk_dart` tests and commit.

### Task 4: Cancellation and stream error ownership

**Files:**
- Modify: `packages/ai_sdk_dart/lib/src/agent/tool_loop_agent.dart`
- Modify: `packages/ai_sdk_dart/lib/src/core/stream_text.dart`
- Modify: `packages/ai_sdk_dart/lib/src/core/generate_text.dart`
- Test: `packages/ai_sdk_dart/test/conformance/tool_loop_agent_coverage_test.dart`
- Test: `packages/ai_sdk_dart/test/conformance/stream_text_conformance_test.dart`
- Test: `packages/ai_sdk_dart/test/conformance/smooth_stream_onabort_test.dart`

- [ ] Add failing tests for abort before provider dispatch, during a stream, between tool steps, and during tool execution.
- [ ] Add `abortSignal` and timeout inputs to `ToolLoopAgent.generate` and `.stream`, forwarding them to core calls and `ToolExecutionOptions`.
- [ ] Race provider and tool awaits against cancellation so a silent upstream stream cannot keep the public operation alive.
- [ ] Add a zone-guarded failing test that consumes only `textStream` during an upstream error and observes no unhandled error.
- [ ] Make `fullStream` authoritative and internally observe every derived completer while preserving typed failures for explicitly awaited results.
- [ ] Run all core tests and commit.

### Task 5: Structured-stream parsing cost

**Files:**
- Create: `packages/ai_sdk_dart/benchmark/structured_stream_benchmark.dart`
- Create: `packages/ai_sdk_dart/lib/src/core/partial_json.dart`
- Modify: `packages/ai_sdk_dart/lib/src/core/stream_text.dart`
- Modify: `packages/ai_sdk_dart/lib/src/core/stream_object.dart`
- Test: `packages/ai_sdk_dart/test/conformance/stream_text_parsing_coverage_test.dart`
- Test: `packages/ai_sdk_dart/test/conformance/stream_object_conformance_test.dart`

- [ ] Add correctness tests for nested objects, escaped quotes, arrays, split Unicode, incomplete values, and duplicate partial suppression.
- [ ] Add a benchmark that streams 1 KiB, 64 KiB, and 1 MiB JSON documents in small deltas and reports decode count and elapsed time.
- [ ] Implement a boundary tracker that invokes JSON decoding only after a potentially complete structural boundary.
- [ ] Share the tracker between text structured output and `streamObject`.
- [ ] Verify outputs are unchanged and decode count grows linearly with structural emissions; commit.

### Task 6: Reusable provider HTTP clients and credentials

**Files:**
- Modify: `packages/ai_sdk_provider/lib/src/shared/provider_options.dart`
- Modify: provider factory/configuration files under `packages/ai_sdk_{openai,openai_compatible,anthropic,google,cohere,ollama}/lib/src/`
- Test: corresponding provider tests and API-error conformance tests

- [ ] Define an asynchronous `CredentialProvider` contract that resolves authorization immediately before dispatch and can represent static keys without a compatibility wrapper.
- [ ] Add failing tests proving credentials rotate between calls and one injected HTTP client handles multiple requests.
- [ ] Move client ownership to provider instances; accept injection and expose disposal only when the provider owns the client.
- [ ] Replace compile-time-only request authorization with the credential resolver while keeping explicit static keys as the simplest constructor input.
- [ ] Run every affected provider suite and commit by provider group.

### Task 7: Core module boundary cleanup

**Files:**
- Modify: `packages/ai_sdk_dart/lib/src/core/stream_text.dart`
- Create focused files under `packages/ai_sdk_dart/lib/src/core/streaming/`
- Test: existing `stream_text_*` conformance and coverage tests

- [ ] With all behavior tests green, move event/result declarations, orchestration helpers, and structured parsing into responsibility-specific files.
- [ ] Preserve public exports and delete duplicated helpers rather than retaining forwarding copies.
- [ ] Run formatting, analysis, all core tests, and coverage; commit.

