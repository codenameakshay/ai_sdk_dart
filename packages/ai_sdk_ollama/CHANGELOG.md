## 1.1.0

- Bumped `ai_sdk_provider` constraint to `^1.1.0`.
- Version aligned with the rest of the monorepo.

## 1.0.0

First stable release.

- `ollama(modelId)` factory — create language model instances for locally-running Ollama models.
- `ollamaEmbedding(modelId)` — text embedding models via Ollama.
- Full SSE streaming via Ollama's OpenAI-compatible `/api/chat` endpoint.
- Tool call support for models that support function calling.
- Configurable `baseUrl` (default `http://localhost:11434`).
