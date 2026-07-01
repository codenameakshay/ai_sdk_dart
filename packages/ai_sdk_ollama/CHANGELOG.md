## 1.2.0

- Added **tool use** and **multimodal image input** to the Ollama implementation, and fixed
  prompt / completion **usage token** reporting.
- **Errors:** non-2xx API responses now throw a typed **`AiApiCallError`** (carrying Ollama's
  `error` string and the `statusCode`) instead of a raw `DioException`.

---

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
