# ai_sdk_mistral

The Mistral provider. `MistralProvider` (and the default `mistral` instance) gives a developer a language model and an embedding model for the Mistral API. Chat uses `ai_sdk_openai_compatible` with Mistral's field names (`random_seed`, `max_tokens`). Embeddings use their own small model class.

## Sub-features

- `mistral-generate` sends `POST <baseUrl>/chat/completions` with the bearer key, `model`, `messages`, `random_seed` (never `seed`) and `max_tokens` (never `max_completion_tokens`), and returns text, usage and the finish reason.
- `mistral-stream` sends `stream: true` with `stream_options.include_usage`, yields the SSE deltas in order, and reports usage from the trailing chunk.
- `mistral-tools` serializes tools as `function` tools, parses `tool_calls`, and sends the result back as a `tool` message with the same `tool_call_id`.
- `mistral-structured` sends `response_format: {type: json_schema}` for `Output.object` and parses the JSON reply.
- `mistral-options` merges `providerOptions['mistral']` (for example `safe_prompt`, `prompt_mode`) into the chat body.
- `mistral-embed` sends `POST <baseUrl>/embeddings` with `model` and `input` (plus `providerOptions['mistral']`), and returns the vectors in input order with the token usage.
- `mistral-provider` covers the provider options: `apiKey`, an async `credentialProvider`, no key (no `Authorization` header), `baseUrl`, the default base URL `https://api.mistral.ai/v1`, an injected `client`, and `dispose()`.
- `mistral-errors` maps a non-2xx Mistral error body (`{message, request_id}` or `{object: error, message, type, code}`) to `AiApiCallError` with status, message and `isRetryable`, for chat, streamed chat and embeddings.

## How to get to it (user POV)

- Call `mistral('mistral-large-latest')` or `MistralProvider(apiKey: ...)('...')` and pass the model to `generateText` or `streamText` from `ai_sdk_dart`.
- Call `mistral.embedding('mistral-embed')` and pass it to `embed` or `embedMany`.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Every check uses an in-process fixture server that answers in the Mistral wire format.

- **All checks.** Run `$V run mistral`. Output `9 passed, 0 failed, 0 skipped`.
- **Generate.** Run `$V run mistral --check generate-text`. In `ai_sdk_mistral/generate-text.json`, `exchanges[0].requestBody` has `random_seed: 42` and `max_tokens: 64` and neither `seed` nor `max_completion_tokens`. `observed.text` is `Hello from Mistral.`
- **Stream.** Run `$V run mistral --check stream-text`. The request body has `stream: true`. `observed.deltas` joins to `One, two, three.`
- **Tool loop.** Run `$V run mistral --check tool-loop`. `exchanges` has two requests. The second ends with a `tool` message for `call_mistral_1`. `observed.executions` is `1`.
- **Structured output.** Run `$V run mistral --check structured-output`. `observed.output` is `{capital: Tokyo, currency: JPY}`.
- **Provider options.** Run `$V run mistral --check provider-options`. The request body has `safe_prompt: true`, `prompt_mode: reasoning` and `max_tokens: 16`.
- **Embeddings.** Run `$V run mistral --check embed`. Two requests go to `/v1/embeddings`. The second body has `input: [alpha, beta]` and `output_dtype: float`. `observed.manyUsage` is `8`.
- **Auth and client.** Run `$V run mistral --check auth-and-client`. `observed.authHeaders` is `[Bearer verify-key, Bearer dyn-key, null, Bearer inj-key, Bearer inj-key]` (fake keys; `null` is the keyless call), and `observed.clientMarkers` ends with two `injected`.
- **Default URL.** Run `$V run mistral --check default-base-url`. `observed.errorUrl` is `https://api.mistral.ai/v1/chat/completions`. No request leaves the machine.
- **Errors.** Run `$V run mistral --check api-error`. `observed.unauthorized.status` is `401` with message `Unauthorized`. `observed.rateLimited.isRetryable` is `true`. `observed.embed.status` is `422`.

Live checks do not exist for this package. There is no Mistral key in the verify setup.

## Gotchas

- The fixture responses follow the public Mistral format. They prove the adapter's mapping, not the vendor's current behavior.
- With an injected `client`, also pass `baseUrl` to the provider. The chat model builds its endpoint from the provider's `baseUrl` (or the Mistral default), so the Dio's own `baseUrl` is ignored for chat.
- Not covered: reasoning output (Magistral thinking chunks): no fixture proves a Mistral reasoning shape in this package.
- Not covered: the `mistral` default instance reading `MISTRAL_API_KEY`: it uses `String.fromEnvironment`, which is fixed at compile time.
- Not covered: OCR, moderation, agents and Codestral endpoints: the package exposes language and embedding models only.
- `generateText` retries retryable errors. Use `maxRetries: 0`. A 429 or 5xx still arrives wrapped in `AiRetryError`; the `AiApiCallError` is its `lastError`.
