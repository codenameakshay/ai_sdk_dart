# CONTEXT

Domain vocabulary and architecture map for **AI SDK Dart** — a Dart/Flutter port of Vercel
AI SDK v6. Use these terms consistently in code, docs, and architecture reviews.

## What this is

A provider-agnostic client SDK: write AI logic once, swap providers without touching business
code. Pure client-side (mobile, web, desktop, server Dart) — no backend required.

## Domain vocabulary

- **Provider** — a vendor integration package (`ai_sdk_openai`, `ai_sdk_anthropic`, …). Exposes a
  callable factory (e.g. `openai('gpt-4.1-mini')`) returning a **model**.
- **Model interface** — the contract a provider implements, defined in `ai_sdk_provider`:
  `LanguageModelV3`, `EmbeddingModelV2`, `ImageModelV3`, `SpeechModelV1`, `TranscriptionModelV1`,
  `RerankModelV1`. Each has `doGenerate` / `doStream` / `doEmbed` etc. and a
  `specificationVersion`.
- **Call options** — `LanguageModelV3CallOptions`: the normalized request (prompt, messages,
  tools, toolChoice, outputSchema, sampling params, providerOptions) handed to a model.
- **Content part** — a typed piece of a message: text, image, file, reasoning, source, tool-call,
  tool-result, tool-approval. Both at the provider level (`LanguageModelV3*Part`) and the
  user-facing level (`ModelMessage`).
- **Core function** — a top-level entry point in `ai_sdk_dart`: `generateText`, `streamText`,
  `generateObject`, `streamObject`, `embed`, `embedMany`, `generateImage`, `generateSpeech`,
  `transcribe`, `rerank`.
- **Tool** — a typed callable the model can invoke: `tool<INPUT, OUTPUT>()` / `dynamicTool()`.
  A `ToolSet` is `Map<String, Tool>`. Tools may set `needsApproval` for human-in-the-loop.
- **Tool loop** — the multi-step agentic loop: call model → execute tool calls → feed results
  back → repeat until a **stop condition** trips or no tools are called. Embodied by
  `ToolLoopAgent` and inlined in `generateText`/`streamText`.
- **Stop condition** — a predicate over a `StepSnapshot` (`stepCountIs`, `hasToolCall`,
  `hasFinishReason`, `never`, `stopWhenAny/All`). `stopWhen` governs the loop; when set it
  overrides `maxSteps`.
- **Output** — structured-output spec (`Output.text/object/array/choice/json`) parsed from model
  text, with `partialOutputStream` / `elementStream` for streaming.
- **Middleware** — a `LanguageModelMiddleware` (or embedding/image) wrapping a model via
  `wrapLanguageModel`: `extractReasoning`, `extractJson`, `simulateStreaming`, `defaultSettings`,
  `addToolInputExamples`.
- **Stream event taxonomy** — the 20 `StreamTextEvent` subtypes emitted by `streamText.fullStream`
  (start, start-step, text-*, reasoning-*, source, file, tool-input-*, tool-result, tool-error,
  raw, error, finish-step, usage, finish).
- **Registry** — `createProviderRegistry` / `customProvider`: resolve a model by
  `'provider:modelId'` across categories.
- **Controller** — a Flutter `ChangeNotifier` adapting a core function/agent to reactive UI:
  `ChatController`, `CompletionController`, `ObjectStreamController` (`ai_sdk_flutter_ui`).
- **MCP** — Model Context Protocol client (`ai_sdk_mcp`): discovers remote tools and exposes them
  as a `ToolSet`.

## Architecture map

```
ai_sdk_provider   — model-interface contracts + content/part/stream types (the seam)
      ▲
ai_sdk_dart       — core engine: core functions, tool loop, Output, middleware, registry, agent
      ▲                                   ▲
providers         flutter_ui / mcp        examples
(openai, anthropic, google, azure,
 cohere, groq, mistral, ollama)
```

- Providers depend only on `ai_sdk_provider` (the seam) + an HTTP client. The core depends on the
  seam too, never on a concrete provider — that is what makes providers swappable.
- **OpenAI-compatible providers** (those speaking the OpenAI Chat Completions wire format) are a
  natural sub-seam — see `docs/adr/`.

## Intentionally omitted (not ported from v6)

The web/framework-bound surface of Vercel AI SDK has no place in Dart/Flutter and is deliberately
absent: the React/Svelte/Vue/Solid UI hooks (`useChat` etc.), the UI-message-stream/transport
HTTP protocol, RSC (`streamUI`), and Next.js/Node/Edge runtime glue. Flutter controllers replace
the hooks. See `docs/adr/0002-v6-parity-scope.md`.
