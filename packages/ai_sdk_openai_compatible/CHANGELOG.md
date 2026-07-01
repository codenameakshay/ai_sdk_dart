## 1.2.0

First release (versioned 1.2.0 to align with the AI SDK Dart monorepo).

- `OpenAICompatibleChatLanguageModel` — a full `LanguageModelV3` implementation
  of the OpenAI Chat Completions wire format: multimodal content parts (text +
  image + audio + file), `tools` / `tool_choice` (with `strict`),
  `response_format` JSON-schema, SSE streaming (text deltas + index-based
  tool-call delta state machine + finish + usage), non-streaming tool-call
  parsing, and finish-reason mapping.
- `apiErrorFromDioException(...)` — a shared Dio→`AiApiCallError` bridge (delegating to
  `AiApiCallError.fromResponse`) so non-2xx responses surface as a typed `AiApiCallError` on both
  the non-streaming and stream-setup paths. Imported by the OpenAI / Azure / Groq / Mistral
  providers.
- `OpenAICompatibleConfig` — a small config object parameterizing the
  per-provider quirks: auth header scheme, base URL, query parameters
  (e.g. Azure `api-version`), body field name overrides (`seed` vs
  `random_seed`, `max_tokens` vs `max_completion_tokens`), feature flags
  (`supportsTools`, `supportsMultimodal`, `supportsResponseFormatJsonSchema`),
  an `extraBody` hook for provider-specific fields, and a `Dio` factory.
