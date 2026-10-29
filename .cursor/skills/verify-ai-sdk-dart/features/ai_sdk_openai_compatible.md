# ai_sdk_openai_compatible

The shared OpenAI Chat Completions base that provider authors configure (`OpenAICompatibleConfig`) and wrap in `OpenAICompatibleChatLanguageModel`. A developer gets text generation, SSE streaming, tool calling, structured output and typed errors from one config object, and changes the wire format with config fields instead of code. `ai_sdk_openai` (chat models), `ai_sdk_azure`, `ai_sdk_groq` and `ai_sdk_mistral` are built on it.

## Sub-features

- `compat-generate` sends `POST <baseUrl>/chat/completions` with the auth header from `headers`, `model`, `messages`, `seed`, `max_completion_tokens` and sampling settings, and returns text, usage and the finish reason.
- `compat-stream` sends `stream: true` with `stream_options.include_usage`, yields the SSE deltas in order, and reports usage from the final chunk.
- `compat-tools` serializes tools as `function` tools, parses `tool_calls`, and sends the executed result back as a `tool` message with the same `tool_call_id`.
- `compat-structured` sends `response_format: {type: json_schema}` for `Output.object` and parses the JSON reply.
- `compat-config` adds `queryParameters` to the URL, renames the seed and max-token keys, and omits tools when `supportsTools` is false.
- `compat-errors` maps a non-2xx JSON error to `AiApiCallError` with status, message and `isRetryable`.

## How to get to it (user POV)

- Construct `OpenAICompatibleChatLanguageModel(config: OpenAICompatibleConfig(...), modelId: ...)` and pass it to `generateText` or `streamText` from `ai_sdk_dart`.
- Indirectly, through any `ai_sdk_azure`, `ai_sdk_groq` or `ai_sdk_mistral` model, or an `ai_sdk_openai` chat model. Those packages have their own feature files.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Every check uses an in-process fixture server that answers in the Chat Completions wire format.

- **All checks.** Run `$V run openai_compatible`. Output `6 passed, 0 failed, 0 skipped`.
- **Generate.** Run `$V run openai_compatible --check generate-text`. In `ai_sdk_openai_compatible/generate-text.json`, `exchanges[0].requestBody` has `seed: 42`, `max_completion_tokens: 64` and message roles `system, user`. `observed.text` is `Hello from the fixture.`
- **Stream.** Run `$V run openai_compatible --check stream-text`. `observed.deltas` lists at least three pieces that join to `One, two, three.`
- **Tool loop.** Run `$V run openai_compatible --check tool-loop`. `exchanges` has two requests. The second request body ends with a `tool` message for `call_verify_1` with the content `Sunny, 18C in Paris`. `observed.executions` is `1`.
- **Structured output.** Run `$V run openai_compatible --check structured-output`. `observed.output` is `{capital: Tokyo, currency: JPY}`.
- **Config quirks.** Run `$V run openai_compatible --check config-quirks`. The request URL ends with `?api-version=2024-10-21`, and the body has `random_seed` and `max_tokens` and no `tools`.
- **Errors.** Run `$V run openai_compatible --check api-error`. `observed.statusCode` is `401` and `observed.isRetryable` is `false`.

## Gotchas

- The fixture responses follow the public Chat Completions format. They prove the adapter's mapping, not a vendor's current behavior. Only `ai_sdk_openai` and `ai_sdk_anthropic` have live checks.
- This package has no provider factory and no default base URL. A check must always pass `baseUrl` and `client`.
- `generateText` retries retryable errors. `maxRetries: 0` prevents retries, but a retryable error is still wrapped in `AiRetryError`. Read `lastError` for its `AiApiCallError`.
