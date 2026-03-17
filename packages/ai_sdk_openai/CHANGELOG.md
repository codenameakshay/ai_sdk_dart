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
