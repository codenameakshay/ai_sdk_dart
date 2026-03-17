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
