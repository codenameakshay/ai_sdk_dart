# ai_sdk_groq

The Groq provider. `GroqProvider` (and the default `groq` instance) gives a developer a language model for Groq's OpenAI-compatible API. The package configures `ai_sdk_openai_compatible` with the Groq base URL, a bearer key, the `max_tokens` field and `providerOptions['groq']` pass-through.

## Sub-features

- `groq-generate` sends `POST <baseUrl>/chat/completions` with the bearer key, `model`, `messages`, `seed` and `max_tokens` (never `max_completion_tokens`), and returns text, usage and the finish reason.
- `groq-stream` sends `stream: true` with `stream_options.include_usage`, yields the SSE deltas in order, and reports usage from the trailing chunk.
- `groq-tools` serializes tools as `function` tools, parses `tool_calls`, and sends the result back as a `tool` message with the same `tool_call_id`.
- `groq-structured` sends `response_format: {type: json_schema}` for `Output.object` and parses the JSON reply.
- `groq-reasoning` merges `providerOptions['groq']` (for example `reasoning_format: parsed`) into the body and returns the `reasoning` field of a reply or stream as `reasoningText`, apart from the answer.
- `groq-provider` covers the provider options: `apiKey`, an async `credentialProvider`, no key (no `Authorization` header), `baseUrl`, the default base URL `https://api.groq.com/openai/v1`, an injected `client`, and `dispose()`.
- `groq-errors` maps a non-2xx `{error: {message, type, code}}` body to `AiApiCallError` with status, message, type, code and `isRetryable`, for plain and streamed requests.

## How to get to it (user POV)

- Call `groq('llama-3.3-70b-versatile')` or `GroqProvider(apiKey: ...)('...')` and pass the model to `generateText` or `streamText` from `ai_sdk_dart`.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Every check uses an in-process fixture server that answers in the Chat Completions format.

- **All checks.** Run `$V run groq`. Output `8 passed, 0 failed, 0 skipped`.
- **Generate.** Run `$V run groq --check generate-text`. In `ai_sdk_groq/generate-text.json`, `exchanges[0].requestBody` has `seed: 42` and `max_tokens: 64` and no `max_completion_tokens`. `observed.text` is `Hello from Groq.`
- **Stream.** Run `$V run groq --check stream-text`. The request body has `stream: true`. `observed.deltas` joins to `One, two, three.`
- **Tool loop.** Run `$V run groq --check tool-loop`. `exchanges` has two requests. The second ends with a `tool` message for `call_groq_1`. `observed.executions` is `1`.
- **Structured output.** Run `$V run groq --check structured-output`. `observed.output` is `{capital: Tokyo, currency: JPY}`.
- **Reasoning.** Run `$V run groq --check reasoning`. Both request bodies have `reasoning_format: parsed`. `observed.generated.reasoning` and `observed.streamed.reasoning` are `Think: two plus two.` and both answers are `4`.
- **Auth and client.** Run `$V run groq --check auth-and-client`. `observed.authHeaders` is `[Bearer verify-key, Bearer dyn-key, null, Bearer inj-key, Bearer inj-key]` (fake keys; `null` is the keyless call), and `observed.clientMarkers` ends with two `injected`.
- **Default URL.** Run `$V run groq --check default-base-url`. `observed.errorUrl` is `https://api.groq.com/openai/v1/chat/completions`. No request leaves the machine.
- **Errors.** Run `$V run groq --check api-error`. `observed.unauthorized` has status `401`, code `invalid_api_key` and `isRetryable: false`. `observed.rateLimited.isRetryable` is `true`.

Live checks do not exist for this package. There is no Groq key in the verify setup.

## Gotchas

- The fixture responses follow the public Groq (OpenAI-compatible) format. They prove the adapter's mapping, not the vendor's current behavior.
- With an injected `client`, also pass `baseUrl` to the provider. The shared base builds the endpoint from the provider's `baseUrl` (or the Groq default), so the Dio's own `baseUrl` is ignored and the call would go to `api.groq.com`.
- Groq reports usage in `x_groq.usage` as well as, in current versions, a top-level `usage`. The stream check uses the top-level shape, which the shared base reads.
- Not covered: audio (speech and transcription) and Groq-only endpoints: the package exposes language models only.
- Not covered: the `groq` default instance reading `GROQ_API_KEY`: it uses `String.fromEnvironment`, which is fixed at compile time.
- `generateText` retries retryable errors. Use `maxRetries: 0`. A 429 or 5xx still arrives wrapped in `AiRetryError`; the `AiApiCallError` is its `lastError`.
