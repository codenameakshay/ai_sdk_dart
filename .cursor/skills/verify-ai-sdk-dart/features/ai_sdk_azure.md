# ai_sdk_azure

The Azure OpenAI provider. `AzureOpenAIProvider` builds language models for Azure deployments (Chat Completions and the v1 Responses API) and embedding models. It sends the `api-key` header, builds deployment URLs from the resource endpoint and adds the `api-version` query parameter. Chat models run on the shared `ai_sdk_openai_compatible` base. Responses models reuse `OpenAIResponsesLanguageModel` from `ai_sdk_openai`.

## Sub-features

- `azure-url` posts chat to `<endpoint>/openai/deployments/<id>/chat/completions` and embeddings to `.../embeddings`, posts Responses to `<endpoint>/openai/v1/responses`, and does not double the slash when the endpoint ends in `/`.
- `azure-auth` sends the key in the `api-key` header (never `Authorization`), resolves an async `credentialProvider` per request, and sends no header for a null key.
- `azure-api-version` adds `api-version=2024-02-15-preview` to chat and embeddings by default, uses a custom `apiVersion` when set, and adds no query to Responses.
- `azure-chat` sends the deployment as `model`, uses `max_tokens` instead of `max_completion_tokens`, supports streaming and tool calling, merges `providerOptions['azure']` into the body, and `chat()` equals the call syntax.
- `azure-responses` sends the deployment as `model` to the v1 Responses API and maps text, usage and `instructions`.
- `azure-embeddings` sends `input` and `model`, restores input order by `index` and reports token usage for `embed` and `embedMany`.
- `azure-errors` maps non-2xx Azure errors on chat, Responses and embeddings to `AiApiCallError` with status and message, and maps a malformed 2xx embeddings body to an invalid-response error.
- `azure-provider` has `dispose()` close only the client the provider created.

## How to get to it (user POV)

- Construct `AzureOpenAIProvider(endpoint: 'https://<resource>.openai.azure.com', apiKey: ..., apiVersion: ...)`.
- Call `provider('<deployment>')` or `provider.chat(...)` for Chat Completions, `provider.responses(...)` for Responses and `provider.embedding(...)` for embeddings.
- Pass the model to `generateText`, `streamText`, `embed` or `embedMany` from `ai_sdk_dart`.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Every check uses an in-process fixture server that answers in the Azure OpenAI wire format.

- **All checks.** Run `$V run azure`. Output `12 passed, 0 failed, 0 skipped`.
- **URL and key.** Run `$V run azure --check chat-url-and-api-key`. In `ai_sdk_azure/chat-url-and-api-key.json`, `exchanges[0].url` starts with `/openai/deployments/my-gpt4o/chat/completions?api-version=2024-02-15-preview` and `requestHeaders` has `api-key` and no `authorization`.
- **Trailing slash.** Run `$V run azure --check endpoint-trailing-slash`. `observed.paths` lists the three paths with no `//`.
- **API version.** Run `$V run azure --check api-version`. `observed.apiVersions` is `[2024-02-15-preview, 2024-02-15-preview, 2025-03-01-preview, 2025-03-01-preview, null]`.
- **Credential provider.** Run `$V run azure --check credential-provider`. `observed.apiKeyHeaders` is `[rotated-1, rotated-2, null]`.
- **Chat.** Run `$V run azure --check chat-generate`. `exchanges[0].requestBody` has `model: my-gpt4o` and `max_tokens: 24` and no `max_completion_tokens`.
- **Stream and tools.** Run `$V run azure --check chat-stream` and `chat-tool-loop`. The stream request has `stream: true`. The tool loop has two requests to the same deployment URL, and the second ends with a `tool` message for `call_azure_1`.
- **Responses.** Run `$V run azure --check responses-v1`. `exchanges[0].url` is `/openai/v1/responses` with no query string.
- **Embeddings.** Run `$V run azure --check embeddings`. `exchanges[0].url` ends with `/embeddings?api-version=2024-02-15-preview`. `observed.many` is in input order.
- **Errors.** Run `$V run azure --check errors`. `observed.statuses` is `{chat: 401, responses: 429, embedding: 401, malformed: 200}`.

## Gotchas

- The fixtures follow the public Azure OpenAI format. No Azure key was available, so nothing here proves the behavior of a real Azure resource.
- Chat and embeddings use the dated `api-version`. Responses uses the v1 route and sends no `api-version`.
- `generateText` wraps a retryable error (for example a 429) in `AiRetryError`, even with `maxRetries: 0`. The `lastError` field holds the `AiApiCallError`.
- Not covered: the global `azureOpenAI` instance. It has an empty endpoint and exists as a placeholder, so a developer must build their own provider.
- Not covered: image, speech, transcription, files and batches. The package exports only language models and embeddings.
