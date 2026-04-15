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
