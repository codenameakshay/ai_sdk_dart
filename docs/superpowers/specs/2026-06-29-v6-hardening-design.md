# Spec: v6 Hardening → a complete, honest, fully-tested Dart/Flutter AI hub

Date: 2026-06-29 · Branch: `improve/v6-hardening` · Grounded by: `docs/codebase-audit-2026-06.md`

## Goal

Turn the existing AI SDK v6 Dart port into a **one-stop, fully-tested, honest** package hub
for AI in Dart/Flutter. Three north-star outcomes:

1. **Pragmatic 100% line coverage** of every package's `lib/` (meaningful tests, not line-chasing).
2. **Only relevant, working code** — everything ported from v6 is real and useful for Dart/Flutter;
   nothing half-baked or silently broken.
3. **A great Flutter UI layer** — hardened controllers + a prebuilt widget library so a Flutter dev
   can build an AI feature end-to-end from this repo alone.

## Locked scope decisions

- **v6 only.** No v7 migration this round (v7 is days-old GA and still churning; v6 still maintained).
  v7 is a separate future effort — see `docs/codebase-audit-2026-06.md` §5.
- **Complete the existing 8 providers** (implement tools + multimodal in the 5 thin ones).
  **No new providers** and **no higher-level RAG/vector helpers** this round.
- **Flutter UI: controllers + prebuilt widget library + tests for every controller and widget.**
- **Coverage: pragmatic 100% on `lib/`** for all packages; justified `// coverage:ignore` only for
  unreachable defensive branches; exclude examples, generated code, mock test helpers.
- **Breaking API changes allowed** (drop `experimental_` prefixes where sensible, rename, remove dead
  exports) with per-package version bumps. Nothing is off-limits.

## Half-baked feature fates (approved)

| Feature | Fate |
|---|---|
| `generateVideo` + `VideoModelV1` + mock + registry video category | **Remove** (zero providers, not stable v6) |
| `telemetry` (no-op default) | **Keep** as bring-your-own hook; add tests |
| `wrapImageModel` (built, unexported) | **Export + test** |
| MCP `dart:io`/stdio | **Isolate `dart:io` behind conditional imports** (HTTP transport works on web); keep stdio for desktop |
| `SseClientTransport` (does no SSE) | **Implement real SSE streaming** |
| `simulateStreamingMiddleware` | **Keep** |

## Workstreams

### WS0 — Correctness + doc truth (first; permanent-truth fixes only)
- [ ] Rewrite `packages/ai_sdk_flutter_ui/README.md` to match the real API (no `model:` ctor, `bind()`, etc.)
- [ ] Fix `onAbort`/`abortSignal` to actually break the `streamText` read loop (+ test)
- [ ] Fix `stopWhen` vs `maxSteps` so `stopWhen` can drive the loop past the default (+ test)
- [ ] Purge stale `packages/ai/` / `packages/ai_sdk_flutter/` paths from `docs/v6-parity-matrix.md` + `Makefile`
- [ ] `AGENTS.md`: "178+" → 562 tests; fix outdated Makefile notes
- [ ] README: "22 event types" → actual (~20); "5 middlewares" → 6; `timeout` claim (exclude agent or add it); reconcile generateVideo/rerank roadmap vs matrix
- [ ] Note: provider-capability matrix cells (tool use / native JSON / multimodal) are revisited **after WS2**, which makes them true rather than downgrading them.

### WS1 — Architecture pass + relevance pruning
- [ ] Generate lightweight `CONTEXT.md` + seed `docs/adr/`
- [ ] Run architecture review; apply structural fixes (file/boundary issues, duplicated completer logic, `Object?` union params → typed)
- [ ] Execute the feature fates table (remove generateVideo; export wrapImageModel; MCP `dart:io` isolation; real SSE; etc.)

### WS2 — Provider completeness
- [ ] Azure, Cohere, Groq, Mistral, Ollama: serialize `tools` + `toolChoice`; parse tool calls from responses
- [ ] Same 5: serialize multimodal image parts; stop `whereType<TextPart>` content-dropping (error/warn on truly unsupported)
- [ ] Azure: native JSON-schema `response_format` (OpenAI-compatible)
- [ ] Ollama: real usage tokens from `prompt_eval_count`/`eval_count`
- [ ] Update README provider matrix to the now-true state

### WS3 — Flutter UI hub
- [ ] Controllers: consistent `isStreaming`; rework `ObjectStreamController` to own model+schema; lifecycle correctness
- [ ] Widgets: message list, composer/input bar, streaming markdown text, tool-call card, reasoning/citation display, file/image picker
- [ ] Tests for every controller + widget

### WS4 — Pragmatic 100% coverage sweep
- [ ] Coverage tooling: `dart test --coverage` → `format_coverage` → lcov per package
- [ ] Fill gaps to 100% `lib/` across all packages (providers included)
- [ ] CI gate for coverage

### WS5 — Examples
- [ ] Upgrade `basic`, `flutter_chat`, `advanced_app` to exercise complete providers + new widgets + MCP

## Process
- Incremental commits on `improve/v6-hardening`; **one PR** (this branch) tracks all of it.
- Parallel agents for mechanical per-package work; design decisions single-threaded.
- Checkpoint with the user after WS1 (architecture pass) before the large WS2/WS3 builds.
