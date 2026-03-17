## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Depends on `ai_sdk_dart` 1.0.0.

- `google('gemini-2.0-flash')` factory — create language model instances.
- `googleEmbedding(modelId)` — text embedding models.
- Full SSE streaming via `:streamGenerateContent` endpoint.
- `functionCall` parts → `ToolCallPart` mapping.
- Function tool declarations and `toolConfig` choice mapping.
- `STOP` / `MAX_TOKENS` / `SAFETY` finish reason mapping.
- Source, file content, and raw finish reason forwarding.
- Configurable `baseUrl`.

---

## 0.2.0

- Initial release.
- `google(modelId)` factory for language model instances.
- `googleEmbedding(modelId)` factory for embedding model instances.
- Full SSE streaming with tool call support.
- Function tool declarations and tool choice config mapping.
- Source and file content extraction.
- Provider metadata and raw finish reason forwarding.