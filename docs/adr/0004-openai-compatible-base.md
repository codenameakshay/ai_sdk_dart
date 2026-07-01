# ADR 0004: Shared `ai_sdk_openai_compatible` base module

Status: Accepted

## Context

`ai_sdk_openai`, `ai_sdk_azure`, `ai_sdk_groq`, and `ai_sdk_mistral` all speak the **OpenAI Chat
Completions wire format** over SSE. Today Azure/Groq/Mistral each reimplement a minimal,
text-only client: SSE parsing is ~98% duplicated, finish-reason maps and message building are
identical. That duplication is why they lack tool-calling and multimodal support — adding it
would mean writing the same code three times. Ollama and Cohere use bespoke NDJSON formats and
are out of scope for this seam (ADR 0001 keeps them standalone).

## Decision

Introduce a dedicated package **`ai_sdk_openai_compatible`** — a **deep module** behind a small
interface — that owns the OpenAI Chat Completions request building, SSE parsing, tool
serialization, multimodal content mapping, and finish-reason mapping. It is parameterized for
per-provider quirks (auth scheme, base URL, `api-version` query param, `seed` vs `random_seed`,
`max_tokens` vs `max_completion_tokens`, feature toggles).

`ai_sdk_openai`, `ai_sdk_azure`, `ai_sdk_groq`, and `ai_sdk_mistral` become thin adapters over it.
This mirrors Vercel's own `@ai-sdk/openai-compatible`.

## Consequences

- Tool-calling, multimodal, and structured output are implemented **once** and inherited by all
  four providers (resolves the WS2 capability gaps).
- Adds a 13th published package; the four providers gain a dependency on it. This is
  infrastructure, not a new vendor provider.
- The test surface is the base module's interface; provider tests shrink to adapter-specific
  quirks. Bespoke providers (Ollama, Cohere) are unaffected.
