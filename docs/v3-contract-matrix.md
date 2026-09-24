# v3 contract comparison and qualification

Target: Vercel AI SDK 7.0.111 / provider 4.0.17 at `e9c1d2f54da6bd01a16bb8a5fdfcb4b62f34e7d0`. Decisions: [ADR 0005](adr/0005-v3-public-contract.md). This is an implementation audit, not a full-parity claim. Package version 3.0.0 and provider interface suffixes are independent.

## Language provider call options

Compared with `packages/provider/src/language-model/v4/language-model-v4-call-options.ts` at the pinned revision.

| Upstream field | Dart field | Status / difference |
|---|---|---|
| prompt | `LanguageModelV4Prompt` | Dart adaptation: instruction plus message wrapper; not the JS prompt array |
| maxOutputTokens | maxOutputTokens | Present; adapter mapping must be verified per provider |
| temperature | temperature | Present; provider/model may reject unsupported settings |
| stopSequences | stopSequences | Present, empty-list default |
| topP | topP | Present |
| topK | topK | Present; provider-specific support |
| presencePenalty | presencePenalty | Present; provider-specific support |
| frequencyPenalty | frequencyPenalty | Present; provider-specific support |
| responseFormat | `LanguageModelV4ResponseFormat` | Text/JSON variants, schema/name/description; native mappings under qualification |
| seed | seed | Present; not a universal determinism guarantee |
| tools | Function/provider-defined subclasses | Present; hosted lifecycle semantics incomplete |
| toolChoice | `LanguageModelV4ToolChoice` | Present |
| includeRawChunks | includeRawChunks | Present at provider seam; high-level `BodyInclusionPolicy` gates raw events, default off |
| abortSignal | shared `AbortSignal` | Dart adaptation: token interface; no DOM dependency |
| headers | `Map<String, String>?` | Dart adaptation: omit keys instead of JS undefined values |
| reasoning | `LanguageModelV4Reasoning` enum | providerDefault/none/minimal/low/medium/high/xhigh; enum existence does not prove every adapter honors it |
| providerOptions | `ProviderOptions` | Present; provider-specific data remains open |

`LanguageModelV4` identifies provider/model, exposes `supportedUrls`, and separates `doGenerate` and `doStream`. Default `supportedUrls` is empty. URL advertisement must be qualified independently from accepting a URL field.

## Content and streaming

| Upstream concept | Current Dart mapping | Work remaining |
|---|---|---|
| Text | `LanguageModelV4TextPart`, start/delta/end events | Retain matching segment IDs across all adapters |
| Reasoning | Reasoning part and start/delta/end | Signature and metadata aggregation added; actual two-turn provider fixtures remain |
| Custom content | `LanguageModelV4OpaquePart(provider, raw)` | Direct canonical variant implemented; provider namespace rejection is tested in Responses. Persisted replay qualification remains open |
| Reasoning file | `LanguageModelV4ReasoningFilePart` and typed stream event | Direct variant implemented; metadata preservation across persisted conversation replay remains under repair |
| Generated file | `LanguageModelV4FilePart` | Preserve generated media and provider references; distinguish reference from arbitrary URL |
| Tool call | Parsed `input`, call ID/name | Dart adaptation from wire JSON; hosted/executed identity incomplete |
| Tool result | Text, content, JSON, error-text, error-JSON and execution-denied variants; preliminary/dynamic flags | Canonical variants implemented; each provider still needs protocol-specific continuation qualification |
| Approval request | Approval ID plus complete call | Exact call ID/name/input fingerprint/policy binding and replay prevalidation implemented; local persistence tests pass |
| Source | URL source plus direct `LanguageModelV4DocumentSourcePart` | Both variants implemented. Responses citation-plus-tool continuation regression added; full persisted metadata fidelity remains open |
| Redacted reasoning | Explicit Dart byte-content part | Deliberate adaptation; lossless provider replay needs fixtures |
| Response metadata | ID/model/timestamp/headers/body | Present; high-level body inclusion defaults off, preserving IDs/headers/timing; provider-direct results remain explicit low-level access |
| Finish | Enum plus separate raw string and nested usage | Dart representation differs from upstream unified/raw finish object |
| Stream error/raw/start | Typed provider stream variants | Canonical high-level `stream`, raw `providerStream`, deprecated `fullStream` getter alias; focused settlement/privacy tests pass, full adapter qualification remains |

A `LanguageModelV4` suffix is not a promise of structural TypeScript interoperability. Dart tests must establish each mapped behavior. Unknown future models remain constructible even when their specific capabilities are not yet qualified.

## Other model contracts

| Interface | Current Dart contract | v3 qualification |
|---|---|---|
| Embeddings | Generic `EmbeddingModelV2<VALUE>` with count limit, parallel flag and shared abort signal | Upstream V4 is text-specific and permits asynchronous capability values. Keep the Dart suffix and document this adaptation; qualify real provider count limits, vector integrity and transport cancellation |
| Images | `ImageModelV3` with shared abort option | Audit provider size/count/format/mask/reference semantics and usage separately |
| Speech | `SpeechModelV1` with shared abort option | Audit voice/format/language and streaming limitations |
| Transcription | `TranscriptionModelV1` with shared abort option | Audit word/segment timestamps, language and file handling |
| Reranking | `RerankModelV1` with shared abort option | Audit index association, return-document policy and relevance scores |

`maxEmbeddingsPerCall == null` means the adapter supplies no count limit; it is not proof that the remote service is unlimited. Core honors the caller's explicit batch size and any smaller known provider limit. Parallelism defaults to one and is further constrained by `supportsParallelCalls`.

## Release evidence required

- All adapter implementations receive a shared cancellation signal and close actual HTTP work on cancellation.
- Pinned real event fixtures, including multi-item/multi-tool streams, replace simplified invented events.
- A custom-provider migration example compiles with the new shared `AbortSignal` and embedding capabilities.
- Final-step and aggregate views agree across streaming and non-streaming generation.
- Per-provider capability tables distinguish implemented, fixture-tested, live-tested and unsupported behavior.
- Update this matrix as missing variants land; do not change a gap to complete based solely on an API declaration.

Parent verification checkpoint (2026-09-23): core suite 720 passed after canonical stream alias and body/metric changes. Flutter approval/persistence and duplicate/Bloc race suites 12 passed. These results support the updated rows only; unresolved content variants, hosted tools, provider lifecycle and live qualification above remain open.
