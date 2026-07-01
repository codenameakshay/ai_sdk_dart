# AI SDK Dart — Grounded Codebase Audit (2026-06-29)

A ground-truthed analysis of this repo against its own documentation, produced by reading
the actual source of every package. Each claim below cites `file:line`. The goal: separate
what is *real* from what the docs *say*, identify what is genuinely useful in Dart/Flutter
vs. inherently web-only, and scope a v6 → v7 migration.

---

## 1. What it is

A [Melos](https://melos.invertase.dev) monorepo that ports **Vercel AI SDK v6** to Dart/Flutter.
**12 published packages + 3 example apps.** Pure client-side SDK — no backend, no Docker.

| Layer | Package | Size | Role |
|---|---|---|---|
| Core engine | `ai_sdk_dart` | ~7.3k LOC, 32 files | `generateText`, `streamText`, object/embed/tool/middleware/registry/agent |
| Provider spec | `ai_sdk_provider` | ~1.1k LOC, 30 files | Abstract model interfaces (`LanguageModelV3`, `EmbeddingModelV2`, …) |
| Providers (8) | `ai_sdk_openai` (1053), `ai_sdk_anthropic` (751), `ai_sdk_google` (732), `ai_sdk_cohere` (373), `ai_sdk_azure` (348), `ai_sdk_mistral` (302), `ai_sdk_ollama` (274), `ai_sdk_groq` (240) | LOC each | Concrete model clients |
| Flutter UI | `ai_sdk_flutter_ui` | ~449 LOC, 0 tests | `ChatController`, `CompletionController`, `ObjectStreamController` |
| MCP | `ai_sdk_mcp` | ~735 LOC | Model Context Protocol client |
| Examples | `basic` (Dart CLI), `flutter_chat`, `advanced_app` | — | Demos |

Reference doc `AI-SDK.md` (42,801 lines) is a composite export of the **v6** docs.

**Engineering quality is genuinely high:** 562 tests, **all passing** (569 executed across
packages, 0 skipped, 0 solo). No `UnimplementedError` / `TODO` / fake-data stubs anywhere in
`lib`. The core engine and the OpenAI/Anthropic/Google providers are complete, real
implementations. The problems below are almost entirely **documentation overselling the code**,
not broken code.

---

## 2. Doc-grounding: verified discrepancies

This is the heart of the audit — every doc claim that the code contradicts.

### 2a. README provider capability matrix — FALSE cells

| README claim | Reality | Evidence |
|---|---|---|
| **Tool use ✅ for all 8 providers** | **FALSE for 5 of 8.** Azure, Cohere, Groq, Mistral, Ollama never serialize `tools` into the request and never parse tool calls. Passing `tools` to them is **silently ignored**. Genuine tool use: **OpenAI, Anthropic, Google only.** | `_buildBody` omits tools: `groq_provider.dart:96`, `azure_provider.dart:127`, `cohere_provider.dart:112`, `mistral_provider.dart:105`, `ollama_provider.dart:92` |
| **Azure: Native JSON schema output ✅** | **FALSE.** No `response_format`/`outputSchema` anywhere in the Azure package. Only OpenAI does native JSON schema. | Azure: none; OpenAI: `openai_provider.dart:116-124` |
| **Azure: Multimodal image input ✅** | **FALSE.** Azure builds text-only messages; image parts are dropped. | `azure_provider.dart:113` (`whereType<…TextPart>()`) |
| Structured output ✅ all | **True only at the framework level.** Core `generateObject` injects the schema into the system prompt + strips code fences, so all providers "work." Provider-*native* schema = OpenAI only. | `generate_object.dart:72-88` |

**Also (not a README claim, but a correctness hazard):** the 5 small providers flatten every
message with `.whereType<LanguageModelV3TextPart>()`, so any **image / file / prior tool-result
content is silently dropped without error**. Ollama additionally hardcodes usage tokens to 0
(`ollama_provider.dart:132,190-193`) despite the response carrying `prompt_eval_count`/`eval_count`.

**Surprising architecture note:** every provider is a **standalone** `implements LanguageModelV3` —
none subclass/delegate to the OpenAI provider. That's *why* the OpenAI-compatible endpoints
(Groq/Azure/Mistral) don't get tools/multimodal: each reimplements a minimal text-only client
rather than inheriting OpenAI's richer one.

### 2b. README "Features" / "Roadmap" vs. code

| Claim | Reality | Evidence |
|---|---|---|
| streamText "**22** typed event types" | **~20**, not 22. | `stream_text.dart:181-343` (19 concrete + 1 generic finish event) |
| `timeout` "on **all core functions**" | True for the 11 free functions; **`ToolLoopAgent.generate/.stream` accept no `timeout`.** | `tool_loop_agent.dart` (0 occurrences) |
| "5 built-in middlewares" | Actually **6** language-model middlewares (+ undocumented `wrapImageModel`). | `language_model_middleware.dart:65,173,336,381,461,534` |
| Roadmap: `generateVideo` ✅ / `rerank` ✅ "Implemented" — but parity matrix says `[ ]` / `[~]` | **Both are real, working core code** (`generate_video.dart:32-60`, `rerank.dart:50-81`) — but **no shipping provider** implements `VideoModelV1`/`RerankModelV1` except Cohere rerank. README overstates (hides "no provider"); matrix understates (says "not implemented"). | both files + `cohere_provider.dart:310-358` |
| `wrapImageModel` | **Implemented but not exported** from any barrel → dead public API. | `image_model_middleware.dart:47`; absent from `ai_sdk_dart.dart` |

### 2c. `ai_sdk_flutter_ui/README.md` — documents an API that DOES NOT EXIST

This is the single biggest correctness problem. A developer copy-pasting the package README
**will not compile.** The examples, by contrast, are accurate — they are the real source of truth.

| README shows | Actual code |
|---|---|
| `ChatController(model: openai(...))` | Ctor is `{id, initialMessages, onFinish, onError}` — **no `model:`**. Model lives on a `ToolLoopAgent` passed to `sendMessage(agent:, text:)`. `chat_controller.dart:35` |
| `chat.append('a string')` | `append(ModelMessage)` — takes a message, not a String. `:90` |
| `chat.isStreaming` | **Does not exist on ChatController** (only Completion/Object have it). Use `status == ChatStatus.streaming`. |
| `onFinish: (event) => event.text` | Signature is `void Function(ModelMessage)` → `.content`, not `.text`. `:48` |
| `CompletionController(model:)`, `.text` | Ctor needs `agent:`; getter is `.completion`. |
| `ObjectStreamController(model:, schema:).submit(...)` | No `model`/`schema`/`submit`; you call `bind(stream)` with an externally-built stream. `object_stream_controller.dart:44` |

### 2d. MCP — matrix *understates*, README *overstates the transport*

- The parity matrix calls MCP "[~] basic; no live SSE." Reality: **prompts, resources, and
  reconnection are genuinely implemented** (`mcp_client.dart:505,541,589,613`; reconnect
  `:281,301,398-423`) and tested. Matrix is too modest.
- But the README/name **"SSE transport" does no SSE streaming** — `SseClientTransport.send`
  (`:184-203`) is a plain HTTP POST request/response. Server-initiated notifications can never
  arrive, so `notifyResourceUpdated` (`:710`) must be called manually and nothing does.

### 2e. Stale references

- Parity matrix and Makefile cite `packages/ai/…` and `packages/ai_sdk_flutter/…` — **those
  paths don't exist** (actual: `packages/ai_sdk_dart/`, `packages/ai_sdk_flutter_ui/`).
  Confirmed in `AGENTS.md:41`, `docs/v6-parity-matrix.md:143-179`.
- **Test count conflict resolved:** README's "562+ tests" is **accurate** (562 static `test(`
  literals; 569 executed, all pass). **AGENTS.md's "178+" is the wrong/stale number.**

### 2f. Real code defects (not doc issues)

1. **`onAbort` / `abortSignal` does not actually interrupt the stream.** The `await for` read
   loop (`stream_text.dart:738`) never checks `abortSignal.isCancelled`; cancel only fires the
   user callback (`:569-575`). The in-flight provider read keeps going.
2. **`stopWhen` cannot extend past `maxSteps`** in `generateText`: `totalSteps` always derives
   from `maxSteps` (`generate_text.dart:425-429`), so `stopWhen: never` with the default
   `maxSteps:1` runs only one step — unlike the JS semantics.

---

## 3. Useful parts for Dart/Flutter

These are real, idiomatic, and worth keeping/investing in:

- **Core engine** (`generateText`, `streamText`, `generateObject`/`streamObject`, `Output.*`,
  `embed`/`embedMany`, `cosineSimilarity`, tools, multi-step loop, middleware, provider
  registry, `ToolLoopAgent`). Complete and well-tested. This is the crown jewel.
- **OpenAI / Anthropic / Google providers** — full implementations (real SSE streaming, tools,
  multimodal, structured output, reasoning/thinking). Match their README claims exactly.
- **`ChatController` + `CompletionController`** — idiomatic Flutter (`ChangeNotifier` +
  `ListenableBuilder`). The "agent passed per call" design fits Flutter better than a
  mechanical port of React's `useChat` would. Exercised by 5 example pages.
- **Real streaming everywhere** — all 8 providers parse live SSE/NDJSON; no fake
  generate-then-chunk fallback.
- **MCP over HTTP** — functional (initialize + tools + prompts + resources + reconnection)
  for **server-side / desktop Dart**.
- **Middleware system, provider registry, mock testing models** — genuinely reusable Dart APIs.

---

## 4. Useless / irrelevant parts for Dart/Flutter

Measured directly against `AI-SDK.md` (the v6 docs). These Vercel concepts are inherently
web/JS-bound; the port correctly omits most of them:

- **The entire `AI SDK UI` hook layer** — `useChat` (×195 in the v6 docs), `useObject` (×36),
  `useCompletion` (×34), `@ai-sdk/react` (×71), `@ai-sdk/svelte`, `@ai-sdk/vue`, SolidStart.
  Framework-bound React/Svelte/Vue/Solid hooks. The Flutter controllers are the correct
  Dart replacement; do **not** port the hooks.
- **The UI Message Stream / Data Stream HTTP protocol + Transport abstraction** —
  `createUIMessageStream` / `toUIMessageStream` (×70+), Route Handlers, custom transports.
  This is the server↔client wire format for the JS hooks. A Flutter app calling providers
  directly doesn't need it. (It *would* matter only if you build a Dart backend that must
  speak the AI-SDK wire protocol to a JS frontend — niche.)
- **`AI SDK RSC`** — `streamUI` (×4), `createStreamableUI`/`createAI`/`useAIState` (×0).
  React Server Components generative UI. Already near-dead in v6; zero reason to port.
- **Next.js / Node / Edge runtime glue** — `use client`/`use server` directives, `NextRequest`,
  Node HTTP server helpers, ESM/CommonJS concerns. Runtime-specific; irrelevant to Dart.
- **`StdioMCPTransport`** (a port exists at `mcp_client.dart:225`) — spawns `npx`/`node`
  subprocesses via `dart:io Process.start`. **Desktop/CLI-only**; unusable on Flutter
  mobile/web. Worse: the top-level `import 'dart:io'` (`mcp_client.dart:3`) makes the **whole
  `ai_sdk_mcp` package non-web-compatible**, even for the HTTP transport.

---

## 5. v6 → v7 migration complications

**v7 status (web-sourced, 2026-06-29):** AI SDK **7.0.x is GA** (`ai@7.0.0` published
2026-06-25, now 7.0.4). v6 is still patched in parallel (`ai-v6: 6.0.214`), so the port is
**not stranded** on v6. Sources: npm registry dist-tags for `ai` and `@ai-sdk/provider`;
`vercel.com/changelog/ai-sdk-7`; `ai-sdk.dev/docs/migration-guides/migration-guide-7-0`.

**The dominant cost is the provider spec bump V3 → V4** (`@ai-sdk/provider` 4.0.0 →
`LanguageModelV4` etc., `specificationVersion: 'v4'`). This is **NOT in Vercel's app-developer
migration guide** — it must be reverse-engineered from the `@ai-sdk/provider@4.0.0` types — yet
it's the most expensive part for a *port*, because the port lives at the provider-interface layer.

| v7 change | Affected Dart files | Difficulty |
|---|---|---|
| Provider spec **V3→V4** rename + ripple | all of `ai_sdk_provider` + **all 8 providers** + core (`LanguageModelV3` appears ~1777×) | **HIGH** — big-bang, can't be incremental |
| `FilePart.data` → discriminated union `{type:'data'\|'url'\|'reference'\|'text'}` | `ai_sdk_provider` content/prompt types + every provider's request mapping | **HIGH** — real semantic change, not a rename |
| UI content-part collapse (`image-*`/`file-*` → `{type:'file'}`, `media`→`file-data`, new `reasoning-file`) | the 3 Flutter controllers | **MED** — consumer-facing |
| `system` → `instructions`; `onFinish`→`onEnd`, `onStepFinish`→`onStepEnd`, `experimental_onStart`→`onStart` | core + Flutter controllers (public API) | **LOW–MED** — renames, but public surface |
| `fullStream` → `stream` | `stream_text.dart` — **collides** with the port's existing `stream` getter | **MED** — needs a naming decision |
| Tool approval `needsApproval` → call-level `toolApproval` | `tools/tool.dart` (23 sites), `tool_loop_agent.dart`, `model_message.dart` | **MED** |
| `stepCountIs`→`isStepCount`; multi-step result reshape (`finalStep`); usage reshape (`inputTokenDetails`/`outputTokenDetails`) | `stop_conditions`, `generate_text` result, usage type | **LOW–MED** |
| Drop `experimental_` prefixes (output/generateImage/transcribe/generateSpeech/customProvider/telemetry) | scattered | **LOW** (port is partly ahead — already no `Output` prefix) |
| Re-export `AI-SDK.md` from v7 docs | repo root | **LOW (tedious)** — currently anchors team to v6 |
| New additive features (WorkflowAgent, HarnessAgent, TUI, reasoning effort, `generateVideo`) | new files | **MED, deferrable** |

**Key complications, ranked:**
1. V3→V4 + `FilePart` union touch all 8 providers **simultaneously** (shared `ai_sdk_provider`
   version) — no incremental path, no Dart codemod equivalent to `@ai-sdk/codemod`.
2. The most expensive layer (provider spec) is **undocumented** in the official guide.
3. `FilePart` is a genuine structural change → highest per-provider bug risk.
4. Public-API renames cascade to every downstream Dart app, by hand.
5. `fullStream`→`stream` naming collision with the port's existing API.

**Recommendation:** *Plan now, migrate after 7.0.x settles.* v7 is 4 days old and at 7.0.4 already;
v6 is still maintained. Sequence: (1) re-export `AI-SDK.md` from v7; (2) do the `ai_sdk_provider`
V3→V4 + `FilePart` change on a branch, prove it end-to-end on **one** provider as a template;
(3) propagate to the other 7; (4) apply app-level renames + result reshape; (5) update Flutter
controllers for content-part collapse; (6) defer additive features.

---

## 6. Recommended doc/code fixes (quick wins, independent of v7)

1. **Fix `ai_sdk_flutter_ui/README.md`** to match the real API (highest priority — it doesn't compile).
2. **Correct the README provider matrix:** Tool use ✅ only for OpenAI/Anthropic/Google; remove
   Azure's Native-JSON-schema and Multimodal ✅. Or — better — actually implement tool/multimodal
   serialization in the 5 small providers (the interfaces already support it).
3. Make the 5 small providers **error (or warn)** instead of silently dropping image/tool content.
4. Fix "22 event types" → 20; "timeout on all core functions" (exclude agent or add it);
   "5 middlewares" → 6; reconcile README roadmap vs. parity matrix on video/rerank.
5. Update parity-matrix + Makefile stale `packages/ai/` paths; fix AGENTS.md "178+" → 562.
6. Make `onAbort` actually cancel the read loop; reconsider `stopWhen` vs `maxSteps`.
7. Either implement real SSE streaming in `SseClientTransport` or rename it; isolate `dart:io`
   behind conditional imports so `ai_sdk_mcp`'s HTTP transport works on web.
8. Add tests for `ai_sdk_flutter_ui` (currently 0) and exercise `addToolApprovalResponse` + MCP
   (currently never demonstrated in any example).
