# v3 provider capability evidence

This table is advisory. Provider factories continue to accept arbitrary model
and deployment IDs; descriptors do not form an allowlist. `Catalog-listed`
means the provider documents the model. `Fixture-tested` means this repository
has a deterministic request/response fixture. `Live-smoke-tested` requires an
authenticated, dated run and is intentionally absent from this table.

Verified 2026-09-23 from the official documentation linked below:

| Provider / surface | Model examples from the current catalog | Embedding batch declaration | Evidence |
| --- | --- | ---: | --- |
| OpenAI `/v1/embeddings` | `text-embedding-3-small`, `text-embedding-3-large` | 2048 | Catalog-listed; request/response fixtures |
| Azure OpenAI embeddings | Region/deployment-specific IDs | 2048 | API contract and fixture; deployment remains caller-defined |
| Google `batchEmbedContents` | `gemini-embedding-001`, preview `gemini-embedding-2` | Unknown | Official API docs expose the endpoint but no stable per-request count in the checked source; fixtures only |
| Cohere `/v2/embed` | `embed-v4.0` | 96 | Official Embed reference and fixtures |
| Mistral `/v1/embeddings` | `mistral-embed` | Unknown | No current official hard limit verified; adapter reports `null` |
| Groq | No embedding factory in this SDK | N/A | Language-model adapter only; no embedding support claim |
| Ollama `/api/embed` | Installed local tags such as `nomic-embed-text` | Unknown | Local server configuration; adapter reports `null` |

The OpenAI, Azure, and Cohere values are exposed through
`EmbeddingModelV2.maxEmbeddingsPerCall`; all other adapters retain `null` until
their current server documentation provides a stable limit. Every adapter
declares parallel-call behavior separately from request size. This release has
fixture evidence only; no live authenticated provider claim is made.

Sources:

- [OpenAI embeddings guide](https://platform.openai.com/docs/guides/embeddings)
- [Azure OpenAI quotas](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/quotas-limits?view=foundry-classic)
- [Gemini embeddings](https://ai.google.dev/gemini-api/docs/embeddings)
- [Cohere Embed reference](https://docs.cohere.com/v2/reference/embed)
- [Mistral models](https://docs.mistral.ai/getting-started/models/models_overview/)
- [Groq models](https://console.groq.com/docs/models)
- [Ollama Embed API](https://docs.ollama.com/api/embed)

The descriptors are evidence records, not model capability discovery. Unknown
model IDs, private deployments, gateways, and local Ollama tags remain valid.

Parent source verification: Azure's quota table explicitly states 2,048 maximum inputs per embeddings array; Cohere's v2 reference explicitly states 96 texts/inputs per call. OpenAI's generated official Python request type documents a 2,048 array limit and a separate 300,000 aggregate token limit. A count limit does not account for token/byte limits. Google's 100-request claim still needs an exact current source passage; its fetched API reference and protobuf definition did not establish that number.
