## 1.1.0

- Bumped `ai_sdk_provider` constraint to `^1.1.0`.
- Version aligned with the rest of the monorepo.

## 1.0.0

First stable release.

- `groq(modelId)` factory — create language model instances for Groq-hosted models (Llama, Mixtral, Gemma, etc.).
- Full SSE streaming via Groq's OpenAI-compatible API.
- Tool call support with delta accumulation.
- `stream_options: {include_usage: true}` for streaming usage reporting.
- Configurable `apiKey` and `baseUrl`.
