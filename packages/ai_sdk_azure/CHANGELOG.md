## 1.2.0

- Rebuilt on the shared **`ai_sdk_openai_compatible`** base. Azure deployments now get real
  **tool use**, **multimodal image input**, and native **`response_format` JSON-schema** output
  (previously text + streaming only). The Azure `api-version` query parameter and `api-key` auth
  scheme are supplied through the shared config.
- Now requires `ai_sdk_openai_compatible ^1.2.0`.
- **100%** line coverage.

---

## 1.1.0

- Bumped `ai_sdk_provider` constraint to `^1.1.0`.
- Version aligned with the rest of the monorepo.

## 1.0.0

First stable release.

- `azureOpenAI(deploymentId)` factory — create language model instances for Azure-hosted OpenAI models.
- `azureOpenAIEmbedding(deploymentId)` — text embedding models via Azure OpenAI.
- Configurable `resourceName`, `apiVersion`, and `apiKey`.
- Full SSE streaming with tool call delta accumulation.
- Tool choice mapping: auto / required / none / specific.
- `response_format` structured output forwarding.
