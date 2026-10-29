# ai_sdk_cohere

The Cohere provider. `CohereProvider` (and the default `cohere` instance) gives a developer a language model, an embedding model and a reranking model for the Cohere v2 API. Cohere uses its own wire format, not the OpenAI one, so the package maps messages, tools, images and SSE events by itself.

## Sub-features

- `cohere-generate` sends `POST <baseUrl>/chat` with the `Authorization: Bearer` key, `model`, `messages`, `max_tokens`, `temperature`, `p`, `k`, `seed` and `stop_sequences`, and returns text, token usage and the finish reason.
- `cohere-stream` sends `stream: true`, reads the v2 SSE events (`content-delta`, `message-end`) into ordered text deltas, and reports usage and the finish reason from `message-end`.
- `cohere-tools` serializes tools as `function` tools, parses `tool_calls` (non-streaming) and `tool-call-start`, `tool-call-delta`, `tool-call-end` events (streaming), sends the result back as a `tool` message with the same `tool_call_id`, maps `ToolChoiceRequired` to `REQUIRED` and `ToolChoiceNone` to `NONE`, and merges `providerOptions['cohere']` into the body.
- `cohere-multimodal` sends an image part as a content array with an `image_url` item that holds a base64 data URI.
- `cohere-embed` sends `POST <baseUrl>/embed` with `texts`, `embedding_types: [float]` and `input_type` (default `search_document`, overridable), and returns the float vectors in input order.
- `cohere-rerank` sends `POST <baseUrl>/rerank` with `query`, `documents` and `top_n`, and returns the ranked documents with their original index, text and score.
- `cohere-provider` covers the provider options: `apiKey`, an async `credentialProvider`, no key (no `Authorization` header), `baseUrl`, the default base URL `https://api.cohere.com/v2`, an injected `client`, and `dispose()`.
- `cohere-errors` maps a non-2xx `{message}` body to `AiApiCallError` for chat, streamed chat, embed and rerank, and reports a stream that ends before `message-end` as a typed error.

## How to get to it (user POV)

- Call `cohere('command-a-03-2025')` or `CohereProvider(apiKey: ...)('...')` and pass the model to `generateText` or `streamText` from `ai_sdk_dart`.
- Call `cohere.embedding('embed-english-v3.0')` and pass it to `embed` or `embedMany`.
- Call `cohere.rerank('rerank-v3.5')` and pass it to `rerank`.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Every check uses an in-process fixture server that answers in the Cohere v2 wire format.

- **All checks.** Run `$V run cohere`. Output `12 passed, 0 failed, 0 skipped`.
- **Generate.** Run `$V run cohere --check generate-text`. In `ai_sdk_cohere/generate-text.json`, `exchanges[0].requestBody` has `max_tokens: 64`, `p: 0.9`, `k: 40`, `seed: 7` and message roles `system, user`. `observed.text` is `Hello from Cohere.`
- **Stream.** Run `$V run cohere --check stream-text`. `observed.deltas` is the list `One, `, `two, `, `three.` and `observed.usage` shows 12 input and 6 output tokens.
- **Truncated stream.** Run `$V run cohere --check stream-truncated`. `observed.error` mentions `Cohere stream ended before message-end.`
- **Tool loop.** Run `$V run cohere --check tool-loop`. `exchanges` has two requests. The second ends with an assistant `tool_calls` message and a `tool` message for `getWeather_k1`. `observed.executions` is `1`.
- **Streaming tool call.** Run `$V run cohere --check stream-tool-call`. `observed.city` is `Rome` (assembled from two argument deltas) and `observed.executions` is `1`.
- **Tool choice and options.** Run `$V run cohere --check tool-choice-and-options`. `observed.toolChoices` is `[REQUIRED, NONE, null]`. The first request body also has `safety_mode: STRICT`.
- **Image input.** Run `$V run cohere --check image-input`. `observed.contentTypes` is `[text, image_url]`. The `image_url.url` starts with `data:image/png;base64,`.
- **Embeddings.** Run `$V run cohere --check embed`. The first request body has `input_type: search_document` and `embedding_types: [float]`. The second has `input_type: search_query`.
- **Rerank.** Run `$V run cohere --check rerank`. The request body has `top_n: 2`. `observed.ranked[0]` is index 2 with score 0.92.
- **Auth and client.** Run `$V run cohere --check auth-and-client`. `observed.authHeaders` is `[Bearer verify-key, Bearer dyn-key, null, Bearer inj-key, Bearer inj-key]` (fake keys), and `observed.clientMarkers` ends with two `injected`.
- **Default URL.** Run `$V run cohere --check default-base-url`. `observed.errorUrl` is `https://api.cohere.com/v2/chat`. No request leaves the machine.
- **Errors.** Run `$V run cohere --check api-error`. `observed.chat.status` is `401`, `observed.embed.status` is `400` and `observed.rerank.status` is `422`.

Live checks do not exist for this package. There is no Cohere key in the verify setup.

## Gotchas

- The fixture responses follow the public Cohere v2 format. They prove the adapter's mapping, not the vendor's current behavior.
- Not covered: structured output (`Output.object`): the adapter does not map `responseFormat` to a Cohere field, so no `response_format` is sent.
- Not covered: reasoning or thinking output: the adapter has no reasoning mapping.
- Not covered: the `cohere` default instance reading `COHERE_API_KEY`: it uses `String.fromEnvironment`, which is fixed at compile time, so a run-time check cannot set it.
- Not covered: citations and documents in the chat request: the adapter has no field for them.
- When the caller sets no `system`, the adapter still sends `{"role": "system", "content": ""}` as the first message. The checks do not assert on this.
- `generateText` retries retryable errors. Use `maxRetries: 0`. Even then a 429 or 5xx arrives wrapped in `AiRetryError`; the `AiApiCallError` is its `lastError`.
- The stream parser also accepts one JSON object per line (no `data:` prefix). The checks use the real SSE framing with `event:` lines.
