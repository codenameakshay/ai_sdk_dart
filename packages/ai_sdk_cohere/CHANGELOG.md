## 1.2.0

- Added **tool use** and **multimodal image input** to the Cohere v2 implementation. Cohere uses a
  bespoke wire format rather than the OpenAI Chat Completions one, so these were implemented
  natively rather than via `ai_sdk_openai_compatible`.
- **Errors:** non-2xx API responses now throw a typed **`AiApiCallError`** (carrying Cohere's error
  `message` and the `statusCode`) instead of a raw `DioException`.

---

## 1.1.0

- Bumped `ai_sdk_provider` constraint to `^1.1.0`.
- Version aligned with the rest of the monorepo.

## 1.0.0

First stable release.

- `cohere(modelId)` factory — create language model instances (Command R, Command R+, etc.).
- `cohereEmbedding(modelId)` — text embedding models (embed-english-v3.0, etc.).
- `cohereRerank(modelId)` — reranking models (rerank-english-v3.0, etc.).
- Full streaming via Cohere Chat API.
- Tool use support with Cohere tool definitions.
- Source and document grounding forwarding.
