## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Depends on `ai_sdk_dart` 1.0.0.

- `openai('gpt-4.1-mini')` factory — create language model instances for any OpenAI-compatible endpoint.
- `openaiEmbedding(modelId)` — text embedding models (text-embedding-3-small / large).
- `openaiImage(modelId)` — image generation (DALL-E 3).
- Full SSE streaming with tool call delta accumulation.
- `stream_options: {include_usage: true}` for streaming usage reporting.
- Tool choice mapping: auto / required / none / specific.
- Strict tool schema forwarding (`strict: true`).
- Extended thinking passthrough via provider metadata.
- Source, file content, and raw finish reason forwarding.
- Configurable `baseUrl` for Azure OpenAI and compatible endpoints.

---

## 0.2.0

- Initial release.
- `openai(modelId)` factory for language model instances.
- `openaiEmbedding(modelId)` factory for embedding model instances.
- `openaiImage(modelId)` factory for image generation model instances.
- Full SSE streaming with tool call accumulation.
- Tool choice mapping (`auto` / `required` / `none` / specific tool).
- Strict tool schema forwarding (`strict: true`).
- Source and file content extraction from responses.
- Provider metadata and raw finish reason forwarding.