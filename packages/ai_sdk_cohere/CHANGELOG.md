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
