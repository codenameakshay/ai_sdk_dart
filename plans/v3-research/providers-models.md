# v3 provider and model readiness research

Research snapshot: 2026-09-23T05:21Z UTC. Official model pages were fetched on this date. Provider model catalogs are live and account/region dependent; model names below are evidence from the linked page as rendered at retrieval time, not a promise that every account can invoke them. This report does not treat an arbitrary model string accepted by this repository as proof that the model is supported.

## Executive assessment

The repository is a V4 language-model SDK with several native adapters and an OpenAI Chat Completions compatibility layer. It has no OpenAI Responses API, Realtime API, Batch API, hosted-tool lifecycle abstraction, or provider model registry/validation. OpenAI is the largest protocol gap: the adapter targets `/chat/completions`, while current OpenAI documentation separates Responses, Chat Completions, Images, Audio, and Realtime surfaces. Google, Anthropic, and Cohere have native protocol implementations, including provider-defined tool wire mappings, but each exposes only the operations implemented in this repo. Azure, Groq, and Mistral inherit the compatibility layer, so capability parity claims must be scoped to the shared wire format and checked against each model's official support matrix.

The code accepts any model ID string. The “newest model” question therefore requires documentation/API catalog checks and capability metadata; it cannot be solved by changing a default string alone.

## Protocol and capability matrix

| Package | Current source shape | Implemented protocol capabilities | Material gap for v3 | Official model source checked |
|---|---|---|---|---|
| `ai_sdk_openai` | Shared OpenAI-compatible chat plus native media (`packages/ai_sdk_openai/lib/src/openai_provider.dart:53-90`) | Chat Completions V4, embeddings V2, images V3, speech V1, transcription V1; reasoning fields via `extraBody` (`:98-118`) | No Responses, Realtime, Batch, or hosted-tool lifecycle; provider-defined fields are mostly pass-through | [OpenAI models](https://developers.openai.com/api/docs/models), [Responses](https://developers.openai.com/api/docs/guides/migrate-to-responses), [Realtime](https://developers.openai.com/api/docs/guides/realtime) |
| `ai_sdk_anthropic` | Native Messages implementation (`packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:83-115`) | Messages generate/stream, tools, images/documents, citations, extended thinking, prompt-cache controls (`:537-585`; `anthropic_options.dart:1-100`) | No batch endpoint, Files API lifecycle, computer-use/server-tool orchestration, or model catalog; thinking/citations need model-version tests | [Claude models](https://docs.anthropic.com/en/docs/about-claude/models/overview), [Messages](https://docs.anthropic.com/en/api/messages), [Extended thinking](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking) |
| `ai_sdk_google` | Native Gemini `generateContent` + `batchEmbedContents` (`packages/ai_sdk_google/lib/src/google_provider.dart:83-124,545-615`) | Gemini text/multimodal content, function calling, streaming, embeddings, inline/file data; cached-token usage is parsed (`:815-827`) | No Live/Realtime session API, Files/upload lifecycle, batch generation, grounding/search tools, or model capability registry | [Gemini models](https://ai.google.dev/gemini-api/docs/models), [Gemini API](https://ai.google.dev/gemini-api/docs), [Function calling](https://ai.google.dev/gemini-api/docs/function-calling) |
| `ai_sdk_azure` | Azure deployment URLs over shared base (`packages/ai_sdk_azure/lib/src/azure_provider.dart:61-103`) | Chat Completions V4, tools/multimodal/structured output inherited from base, embeddings V2; Azure key and API-version query | No Azure Responses/Assistants/Realtime/Batch-specific APIs; deployment/model capability is opaque and must be validated per Azure region/version | [Azure OpenAI models](https://learn.microsoft.com/azure/ai-services/openai/concepts/models), [Azure API versions](https://learn.microsoft.com/azure/ai-services/openai/api-version-deprecation) |
| `ai_sdk_groq` | Thin shared-base factory (`packages/ai_sdk_groq/lib/src/groq_provider.dart:20-67`) | OpenAI-shaped chat/streaming/tools/multimodal/JSON schema by default; `max_tokens` override | No Groq-native audio, batch, hosted-tool lifecycle, or model catalog; shared `supportsMultimodal: true` does not mean every Groq model accepts vision/audio | [Groq models](https://console.groq.com/docs/models), [Groq tool use](https://console.groq.com/docs/tool-use) |
| `ai_sdk_mistral` | Shared chat plus native embeddings (`packages/ai_sdk_mistral/lib/src/mistral_provider.dart:55-157`) | OpenAI-shaped chat/streaming/tools/multimodal/JSON schema; embeddings; Mistral `random_seed` and `max_tokens` overrides | No native OCR, moderation, audio, batch, agents/connectors, or document APIs despite Mistral's broader platform; compatibility base cannot represent those | [Mistral models](https://docs.mistral.ai/getting-started/models/models_overview/), [Mistral API](https://docs.mistral.ai/api/) |
| `ai_sdk_cohere` | Native Cohere V2 (`packages/ai_sdk_cohere/lib/src/cohere_provider.dart:26-79`) | Chat/streaming, tools, image URL content, embeddings, rerank; tool choice maps `specific` to `REQUIRED` (`:260-291`) | No Cohere model catalog/feature metadata, batch, fine-tuning, or native connectors; tool-choice mapping loses specificity | [Cohere models](https://docs.cohere.com/docs/models), [Chat API](https://docs.cohere.com/reference/chat), [Rerank](https://docs.cohere.com/reference/rerank) |
| `ai_sdk_ollama` | Native local `/api/chat` and `/api/embed` (`packages/ai_sdk_ollama/lib/src/ollama_provider.dart:17-49,191-230`) | Local chat/streaming, tools, base64 images, embeddings; nested Ollama generation options | No model lifecycle/pull/list API, vision capability discovery, structured-output contract, or local model catalog; model support depends on installed Ollama model | [Ollama model library](https://ollama.com/library), [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md) |
| `ai_sdk_openai_compatible` | Shared deep module (`packages/ai_sdk_openai_compatible/lib/src/openai_compatible_config.dart:4-114`) | Chat Completions request/response, SSE tool deltas, multimodal serialization, JSON-schema response format, reasoning-field extraction | It cannot provide provider-native capabilities; defaults may overstate support (`supportsTools`, `supportsMultimodal`, and schema all default true, `:31-37`) | [OpenAI Chat Completions](https://platform.openai.com/docs/api-reference/chat) |

## Exact current catalog evidence

These are concise excerpts from the raw official responses saved under `/tmp/provider_research/` for rechecking. The raw responses are outside the repository and contain no credentials. Retrieval clock: `2026-09-23T05:21Z` (the catalog pages are live-generated and may change after this report).

| Provider | Exact ID(s) visible in official catalog | Status / quoted evidence | Capability implication |
|---|---|---|---|
| OpenAI | `gpt-6-astra`, `gpt-6-sol`, `gpt-6-luna`; `gpt-realtime-2.1`, `gpt-realtime-2.1-mini`; `gpt-image-2.5-sunburst`; `gpt-transcribe`; `gpt-4o-mini-tts` | `/tmp/provider_research/openai-clean.txt`: “GPT-6 Astra … Model ID gpt-6-astra … Reasoning low medium high xhigh max … Tools Functions, Web search, File search, Computer use”; Sol and Luna have the same exact Model ID fields and published max output/context. The page separately lists “GPT-Realtime-2.1 Reasoning model with tool use”, “GPT-Image-2.5 Sunburst”, “GPT-Transcribe”, and “GPT-4o Mini TTS”. | The repository's image/speech/transcription adapters are separate and useful, but its main model is Chat Completions only (`packages/ai_sdk_openai_compatible/lib/src/openai_compatible_chat_language_model.dart:91-119`). Realtime/built-in-tool IDs cannot be assumed to work through that model. |
| Anthropic | API IDs `claude-opus-5-5`, `claude-fable-5-1`, `claude-sonnet-5`, `claude-haiku-4-5-20251001` | `/tmp/provider_research/anthropic-clean.txt`: “If you're unsure … start with Claude Opus 5.5”; “Use Claude Fable 5.1 for demanding reasoning and long-horizon agentic work”; and the API-ID entries list `claude-fable-5-1`, `claude-opus-5-5`, `claude-sonnet-5`, and dated `claude-haiku-4-5-20251001`. The same page says all current models support text/image input, vision, and tool use. | The native Messages adapter can send these IDs as strings and already handles thinking blocks/signatures, but no catalog validation exists. |
| Google | Stable `gemini-3.8-flash`, `gemini-3.8-live`, `gemini-3.8-live-extended-thinking`; `gemini-embedding-2-preview`, `gemini-embedding-001`, `gemini-3.5-transcribe` | `/tmp/provider_research/google-clean.txt`: “Gemini 3.8 Flash … New Stable”; “Gemini 3.8 Live … Default Live API model … New Stable”; “Gemini 3.8 Live Extended Thinking … New Stable”; also exact embedding/transcribe IDs above. | `generateContent` and `batchEmbedContents` are implemented, but the repository has no Live, transcription, multimodal embedding, or Files API model surface (`packages/ai_sdk_google/lib/src/google_provider.dart:52-58,545-615`). |
| Groq | `llama-3.1-8b-instant`, `llama-3.3-70b-versatile`, `openai/gpt-oss-120b`, `openai/gpt-oss-20b` | `/tmp/provider_research/groq-clean.txt`: production table shows Llama 3.1 8B, Llama 3.3 70B, GPT OSS 120B, and GPT OSS 20B. The page separately marks preview models as evaluation-only and may discontinue them; raw schema/navigation strings are not used as catalog evidence. | Shared chat/tool serialization is plausible for these IDs, but the repository does not model Groq's per-model context/rate/vision matrix. |
| Mistral | `mistral-medium-3-5` (API ID on current card; card URL/model slug `mistral-medium-3-5-26-04`) | The fetched official card at [Mistral Medium 3.5](https://docs.mistral.ai/models/mistral-medium-3-5-26-04), preserved as `/tmp/provider_research/mistral-medium-3-5-clean.txt`, says “April 28, 2026 … GA”, prints `mistral-medium-3-5`, and lists Structured Outputs, Function Calling, Batching, Agents & Conversations, and Built-In Tools. Do not treat retired `mistral-medium-2508`/`2505` as current. | Chat and OpenAI-shaped embedding are implemented, but the current card's structured outputs, batching, agents, and built-in tools are not exposed by this package. |
| Cohere | `command-a-plus-05-2026`, `command-a-03-2025`, `embed-v4.0` | `/tmp/provider_research/cohere-clean.txt`: “command-a-plus-05-2026 Live … vision input support, agentic, reasoning, and world-class translation”; Command A is Live and `embed-v4.0` supports “Text, Images, Mixed texts/images (i.e. PDFs)”. | The repository's embed adapter sends only text values and defaults `embedding_types` to float (`packages/ai_sdk_cohere/lib/src/cohere_provider.dart:639-667`), so Embed v4 multimodal inputs are not represented. |

The exact IDs above are verified page content, not recommendations to replace all examples immediately. A release should first run one authenticated smoke test per provider/model and record deprecation/access results. The raw files preserve the snapshot for parent recheck: `/tmp/provider_research/{openai,anthropic,google,groq,mistral,cohere}.{html,txt}` and the parent-cleaned excerpts `/tmp/provider_research/{openai,anthropic,google,groq,mistral,cohere}-clean.txt`. The cleaned excerpts are the authority for the current recommendation/status wording in this section; script/navigation-only strings in raw HTML are intentionally ignored.

Two protocol facts matter for model readiness. The OpenAI catalog cards expose reasoning levels and hosted tools on GPT-6 Astra/Sol/Luna, but the repository's generic reasoning hook only emits `reasoning_effort`/`reasoning_summary`; it does not represent hosted-tool lifecycle events (`packages/ai_sdk_openai/lib/src/openai_provider.dart:98-118`). Anthropic's current overview explicitly says all current models support image input and tool use, and this adapter preserves `thinking` signatures (`packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:184-194`), so that path is stronger than the generic compatibility layer. Google’s current stable Live models are catalog evidence for a session protocol that the current one-shot `generateContent` adapter cannot invoke.

The current package examples still use older IDs: OpenAI `gpt-4o` (`packages/ai_sdk_openai/lib/src/openai_provider.dart:17`), Anthropic `claude-3-5-sonnet-20241022` (`packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:14`), Google `gemini-1.5-flash` (`packages/ai_sdk_google/lib/src/google_provider.dart:13`), Groq `llama3-8b-8192` (`packages/ai_sdk_groq/lib/src/groq_provider.dart:16`), and Mistral `mistral-large-latest` (`packages/ai_sdk_mistral/lib/src/mistral_provider.dart:15`). These are examples rather than defaults, but they are useful migration/doc freshness signals. The Cohere example uses `command-r-plus`, and Ollama uses `llama3` (`packages/ai_sdk_cohere/lib/src/cohere_provider.dart:18-20`; `packages/ai_sdk_ollama/lib/src/ollama_provider.dart:11-15`).

## Findings and prioritized plans

### [DIRECTION-01] Add OpenAI Responses support to the existing language-model interface

- **Evidence**: `packages/ai_sdk_openai/lib/src/openai_provider.dart:53-67` always returns `OpenAICompatibleChatLanguageModel`; its shared implementation posts `/chat/completions` (`packages/ai_sdk_openai_compatible/lib/src/openai_compatible_chat_language_model.dart:91-119`). Official OpenAI documentation now documents Responses separately at [Responses API](https://developers.openai.com/api/docs/guides/migrate-to-responses).
- **Impact**: Users cannot access current OpenAI built-in tools, response items, background work, or Responses-native reasoning/content semantics through the main provider.
- **Effort**: L (multi-day; new request/stream/event model and tests).
- **Risk**: HIGH; mapping Responses events and tool calls into V4 content without losing semantics is a public API design change.
- **Confidence**: HIGH.
- **Fix sketch**: Extend or implement `LanguageModelV4` for Responses while retaining the current `OpenAICompatibleChatLanguageModel` path for callers that need Chat Completions. Map Responses items/events into existing V4 content and stream parts first; add capability-gated built-in tools and fixtures only where the V4 types can preserve their metadata.

### [DIRECTION-02] Introduce capability metadata and model catalog validation

- **Evidence**: Every factory accepts arbitrary `String modelId` (`openai_provider.dart:53`, `anthropic_provider.dart:53`, `google_provider.dart:52`, etc.). `OpenAICompatibleConfig` defaults tools, multimodal, and JSON schema support to true (`packages/ai_sdk_openai_compatible/lib/src/openai_compatible_config.dart:31-37`), while official catalogs expose provider/model-specific support matrices (OpenAI, Anthropic, Google links above).
- **Impact**: A caller can select a retired or modality-incompatible ID and only discover failure after a request; shared defaults can advertise unsupported features for a specific model.
- **Effort**: M (one day-ish for metadata shape and docs; L if live catalog sync is required).
- **Risk**: MED; catalog data changes frequently and stale metadata can reject valid newly released IDs.
- **Confidence**: HIGH.
- **Fix sketch**: Add optional model descriptors/capability overrides and a non-networked registry hook. Keep arbitrary IDs accepted, but expose `validateModel()` and warnings; add dated provider fixture snapshots rather than embedding a permanently authoritative list.

### [DIRECTION-03] Preserve provider-native reasoning/thought metadata

- **Evidence**: OpenAI maps generic reasoning to `reasoning_effort` and optional summary but does not parse a thought signature (`packages/ai_sdk_openai/lib/src/openai_provider.dart:98-118`); Anthropic does preserve the returned thinking signature (`packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:184-194`) and streams thinking deltas (`:390-421`); the compatibility base only guesses among `reasoning_content`, `reasoning`, and `thinking` (`packages/ai_sdk_openai_compatible/lib/src/openai_compatible_config.dart:93-103`). Google maps function calls/content but has no thought-signature handling (`packages/ai_sdk_google/lib/src/google_provider.dart:172-220`).
- **Impact**: Anthropic's signature path is already present, but OpenAI-compatible and Google reasoning models can lose signatures, encrypted thought parts, attribution, or provider-specific metadata needed for follow-up tool calls.
- **Effort**: M (schema review and provider fixtures).
- **Risk**: HIGH; exposing raw reasoning/signatures has privacy and compatibility implications.
- **Confidence**: MED-HIGH; exact current provider contracts must be checked per model release.
- **Fix sketch**: Preserve unknown provider metadata and add explicit signature fields where the provider requires them; do not duplicate Anthropic's existing signature support. Test round-trip tool-call continuation for OpenAI, Anthropic, and Gemini reasoning models.

### [CORRECTNESS-01] Do not claim Ollama structured-output support without a format field

- **Evidence**: `packages/ai_sdk_ollama/lib/src/ollama_provider.dart:191-210` builds only `model`, `messages`, optional tools, nested generation `options`, and `stream`; `rg` finds no `response_format`, JSON schema, or `format` handling in the adapter. Ollama's official API documents a model-specific `format` option, but this adapter does not expose it.
- **Impact**: Callers cannot request Ollama JSON/schema output through the typed provider; passing an SDK output schema is silently not translated.
- **Effort**: S (hours, including fixtures).
- **Risk**: MED; models differ in JSON/schema behavior.
- **Confidence**: HIGH.
- **Fix sketch**: Add a typed Ollama provider option for `format` (string or schema map according to the official API), serialize it in the request, and add JSON/schema fixture tests. Keep this separate from OpenAI `response_format` naming.

### [CORRECTNESS-02] Distinguish hosted tools from provider-defined pass-through tools

- **Evidence**: OpenAI sends caller-supplied tools through Chat Completions (`packages/ai_sdk_openai_compatible/lib/src/openai_compatible_chat_language_model.dart:61-82`); Google serializes function declarations and provider-defined entries such as Google Search (`packages/ai_sdk_google/lib/src/google_provider.dart:655-680`); Anthropic serializes provider-defined tool type/args (`packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:757-771`). None of these paths implements a full provider-hosted tool lifecycle; provider-defined wire pass-through is present and must not be described as absent.
- **Impact**: A provider-defined tool may reach the provider wire format, but hosted web/file/computer/code execution results and approval/event lifecycles are not generally modeled; users cannot infer orchestration from the model ID.
- **Effort**: M per native hosted-tool family; L for a common abstraction.
- **Risk**: HIGH; hosted tools have provider-specific approval, billing, and event semantics.
- **Confidence**: HIGH.
- **Fix sketch**: Keep ordinary function tools distinct from provider-defined and hosted tools. Add explicit hosted-tool event/result metadata only after provider-specific design spikes; preserve existing provider-defined pass-through behavior and add fixtures for it.

### [DIRECTION-04] Fill first-party media and batch gaps by provider, not through compatibility defaults

- **Evidence**: Only OpenAI exposes image/speech/transcription factories (`packages/ai_sdk_openai/lib/src/openai_provider.dart:76-90`); Google has embeddings but no media factories (`packages/ai_sdk_google/lib/src/google_provider.dart:52-58`); Mistral's adapter exposes only chat and embeddings (`packages/ai_sdk_mistral/lib/src/mistral_provider.dart:55-77`); the compatibility base handles only chat completion and embeddings helper parsing (`openai_compatible_config.dart:117-136`). Official Mistral and Google docs list broader APIs than this package matrix.
- **Impact**: Users need raw Dio calls for provider-native OCR, audio, image, batch, and live APIs, and cannot use a common typed SDK surface.
- **Effort**: L per provider capability; start with one concrete demand (likely Google Live or Mistral OCR).
- **Risk**: MED-HIGH; each API requires a separate lifecycle and output model.
- **Confidence**: HIGH.
- **Fix sketch**: Prioritize APIs with stable official contracts and existing provider demand. Add separate typed model interfaces only after documenting whether they are one-shot, batch, or session-oriented; do not force them into `LanguageModelV4`.

### [DIRECTION-05] Add strategic provider adapters after protocol-specific design spikes

- **Evidence**: The repository currently has adapters only for Anthropic, Azure, Cohere, Google, Groq, Mistral, Ollama, and OpenAI (`packages/`). No Bedrock, Vertex AI, DeepSeek, xAI, or OpenRouter adapter exists. The compatibility package already centralizes OpenAI-shaped providers (`packages/ai_sdk_openai_compatible/lib/ai_sdk_openai_compatible.dart:1-15`).
- **Impact**: Users must hand-roll popular hosted/local providers, while the existing architecture makes OpenAI-shaped additions relatively cheap.
- **Effort**: M for an OpenAI-shaped adapter; L for AWS/Vertex auth and native session APIs.
- **Risk**: MED-HIGH; adding providers expands fixture and release-matrix maintenance.
- **Confidence**: MED; priority depends on actual user demand and official API stability.
- **Fix sketch**: Spike DeepSeek/OpenRouter as compatibility wrappers and Bedrock/Vertex as native auth/protocol adapters. Require an official model/capability matrix, auth design, streaming fixtures, and deprecation policy before implementation.

## Acceptance tests for v3 provider readiness

1. Each provider has dated contract fixtures for one current text model, one reasoning model where applicable, one multimodal model where applicable, and its embedding/rerank/media operation where exposed.
2. Tests assert request URL, auth placement, model field, provider options, stream event ordering, usage, finish reason, tool-call accumulation, malformed 2xx handling, and cancellation.
3. OpenAI has separate Chat Completions and Responses test suites; Responses tests cover text, structured output, reasoning, tool calls, built-in-tool metadata, and streaming event termination.
4. Model descriptors are advisory and versioned: unsupported capability warnings are testable, but arbitrary IDs remain possible for newly released models.
5. Provider docs state which features are implemented locally and which require raw provider APIs; no README claims parity solely because a package uses `OpenAICompatibleConfig`.
6. A scheduled read-only catalog check records model IDs and deprecations with retrieval timestamps; it never silently changes production defaults.

## Source and scope notes

- OpenAI documentation was consulted through the official OpenAI domains only, per the OpenAI Docs skill: [Models](https://developers.openai.com/api/docs/models), [Chat API](https://platform.openai.com/docs/api-reference/chat), [Responses guide](https://developers.openai.com/api/docs/guides/migrate-to-responses), and [Realtime guide](https://developers.openai.com/api/docs/guides/realtime).
- Anthropic, Google, Groq, Mistral, Cohere, Azure, and Ollama links above are official vendor documentation. Their pages are dynamic catalogs; this report records the retrieval time and avoids treating page names as a stable guarantee.
- No secrets were copied or searched for in this report.
