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
