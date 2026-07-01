## 1.2.0

- Rebuilt on the shared **`ai_sdk_openai_compatible`** base; Mistral models now get real
  **tool use** and **multimodal image input**, with Mistral's `random_seed` / `max_tokens` field
  naming mapped through the shared config.
- **Errors:** non-2xx responses now surface as a typed **`AiApiCallError`** (via the shared base).
- Now requires `ai_sdk_openai_compatible ^1.2.0`.
- **100%** line coverage.

---

## 1.1.0

- Bumped `ai_sdk_provider` constraint to `^1.1.0`.
- Version aligned with the rest of the monorepo.

## 1.0.0

First stable release.

- `mistral(modelId)` factory — create language model instances (Mistral Large, Mistral Small, Codestral, etc.).
- `mistralEmbedding(modelId)` — text embedding models (mistral-embed).
- Full SSE streaming via Mistral AI Chat API.
- Tool use support with Mistral tool definitions.
- Configurable `apiKey` and `baseUrl`.
