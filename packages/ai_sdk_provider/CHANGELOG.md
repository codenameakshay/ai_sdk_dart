## 1.1.0

- **`LanguageModelV3CallOptions.outputSchema`** — new optional `Map<String, dynamic>?` field. When non-null, providers that support native structured output (e.g. OpenAI `response_format: json_schema`) should use it to request schema-validated responses directly from the model API.

---

## 1.0.0+1

- Improved pubspec descriptions for better pub.dev discoverability.
- Added `example/example.md` with usage examples and links to runnable apps.

## 1.0.0

First stable release. Defines the provider interface contract for all AI SDK Dart providers.

- `LanguageModelV3` — `doGenerate` / `doStream` interface.
- `EmbeddingModelV2<VALUE>` — `doEmbed` interface.
- `ImageModelV3` — `doGenerate` interface.
- `SpeechModelV1` — `doGenerate` interface.
- `TranscriptionModelV1` — `doGenerate` interface.
- `RerankModelV1` — `doRerank` interface.
- Full `LanguageModelV3StreamPart` sealed class hierarchy (text, tool call, reasoning, source, file, finish, error parts).
- `LanguageModelV3CallOptions` with all v6 call-time options.
- `LanguageModelV3GenerateResult` and `LanguageModelV3StreamResult`.
- Shared types: `JsonValue`, `ProviderMetadata`, content parts, finish reasons, tool definitions, usage.

---

## 0.2.0

- Initial release.
- `LanguageModelV3` interface with `doGenerate` / `doStream`.
- `EmbeddingModelV2<VALUE>` interface with `doEmbed`.
- `ImageModelV3` interface with `doGenerate`.
- `SpeechModelV1` interface with `doGenerate`.
- `TranscriptionModelV1` interface with `doGenerate`.
- `RerankModelV1` interface with `doRerank`.
- Full `LanguageModelV3StreamPart` sealed class hierarchy.
- `LanguageModelV3CallOptions` with all v6 call-time options.
- `LanguageModelV3GenerateResult` and `LanguageModelV3StreamResult`.
- Shared types: `JsonValue`, `ProviderMetadata`, content parts, finish reasons, tool definitions.