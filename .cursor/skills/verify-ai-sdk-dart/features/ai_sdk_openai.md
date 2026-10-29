# ai_sdk_openai

The OpenAI provider. `OpenAIProvider` (and the default `openai` instance) builds Chat Completions models, Responses API models, embeddings, image, speech and transcription models, and the Files and Batches clients. A developer passes the models to `generateText`, `streamText`, `embed`, `generateImage`, `generateSpeech` and `transcribe` from `ai_sdk_dart`. Chat models run on the shared `ai_sdk_openai_compatible` base. Responses, embeddings, media, files and batches are implemented in this package.

## Sub-features

- `provider-config` sends `Authorization: Bearer <apiKey>` on every request, resolves an async `credentialProvider` per request, sends no header for an empty key, routes chat and Responses under `baseUrl`, uses an injected Dio `client` (and its headers), and `dispose()` closes only a client the provider created.
- `chat-generate` sends `POST /chat/completions` with `model`, `messages`, `max_completion_tokens` and sampling settings, and returns text, usage and the finish reason.
- `chat-stream` sends `stream: true` with `stream_options.include_usage`, yields the SSE deltas in order and reports usage.
- `chat-tools` serializes `function` tools, runs the tool call and sends the result back as a `tool` message.
- `chat-structured` sends `response_format: json_schema` for `Output.object` and parses the reply.
- `chat-options` maps `OpenAILanguageModelOptions`, snake_case and camelCase keys, and the standard `reasoning` enum to `reasoning_effort` and `reasoning_summary`, and passes other keys through.
- `chat-gpt6-warning` adds a `compatibility` warning to every result for a `gpt-6*` id on Chat Completions.
- `responses-generate` sends `POST /responses` with `model`, `input`, `instructions` and `max_output_tokens`, and maps text, usage (cached and reasoning tokens) and the finish reason.
- `responses-stream` turns Responses SSE events into text deltas, usage and the finish reason.
- `responses-tools` serializes function tools, sends `function_call` and `function_call_output` items by `call_id`, and streams tool-call input.
- `responses-structured` sends `text.format` as a strict `json_schema` and parses the reply.
- `responses-reasoning` folds effort and summary into the `reasoning` object and surfaces reasoning items as reasoning text.
- `responses-hosted-tools` serializes `OpenAIWebSearchTool`, `OpenAIFileSearchTool`, `OpenAICodeInterpreterTool`, `OpenAIImageGenerationTool` and `OpenAIMcpTool`, and maps a `web_search_call` and its citations to a provider-executed call, a result and sources.
- `responses-state` passes `previous_response_id` and `store` through provider options and reports the response id.
- `responses-errors` maps HTTP 401 and 429, a `status: failed` body and an SSE `error` event to typed errors.
- `responses-abort` cancels an in-flight Responses call through the abort signal.
- `embeddings` sends `POST /embeddings` for `embed` and `embedMany`, restores input order by `index` and reports token usage.
- `images` sends `POST /images/generations` with `n`, `size` and `response_format: b64_json` (omitted for `gpt-image-1`) and decodes the bytes.
- `speech` sends `POST /audio/speech` with `voice`, `response_format` and `speed` and returns the audio bytes and media type.
- `transcription` sends a multipart `POST /audio/transcriptions` with the file, `model`, `language` and `prompt` and returns the text.
- `files` uploads (multipart, purpose, expiry), retrieves, streams the content of and deletes files with `DataContentProviderReference` ids, and rejects bad uploads and foreign references before any request.
- `batches` uploads the JSONL input, creates, gets, pages through and cancels batches, parses `OpenAIBatchResult` lines, and rejects duplicate ids, empty batches and a bad `limit`.
- `request-scope` ends file and batch calls with `OpenAIFileTimeoutException` on `timeout` and `AiOperationCancelledError` on a cancelled `abortSignal`.
- `errors` maps non-2xx responses on every endpoint to `AiApiCallError` with status, code, type, message and `isRetryable`, and maps a malformed 2xx body to an invalid-response `AiApiCallError`.

## How to get to it (user POV)

- Construct `OpenAIProvider(apiKey: ..., baseUrl: ..., credentialProvider: ..., client: ...)`, or use the global `openai`. Call `provider('gpt-4.1-mini')` or `provider.chat(...)` for Chat Completions, `provider.responses(...)` for the Responses API, and `provider.embedding`, `.image`, `.speech`, `.transcription`, `.files()` and `.batches()` for the rest.
- Pass the model to `generateText`, `streamText`, `embed`, `embedMany`, `generateImage`, `generateSpeech` or `transcribe`. Pass hosted tools in `providerDefinedTools`.
- Call `provider.dispose()` when the provider owns its client.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- Fixture checks need no key. They use an in-process server that answers in the OpenAI wire formats.
- Live checks need a key. Write it to a file and pass `OPENAI_API_KEY_FILE=<file>`. Optional overrides: `OPENAI_VERIFY_MODEL` (default `gpt-4.1-mini`), `OPENAI_VERIFY_EMBEDDING_MODEL` (default `text-embedding-3-small`), `OPENAI_VERIFY_IMAGE_MODEL` (default `gpt-image-1-mini`, sent with `quality: low`), `OPENAI_VERIFY_IMAGE_SIZE` (default `1024x1024` for gpt-image models).

- **All fixture checks.** Run `$V run openai`. Output `30 passed, 0 failed, 10 skipped`. The 10 skips are the live checks.
- **Provider auth.** Run `$V run openai --check provider-auth`. In `ai_sdk_openai/provider-auth.json`, `observed.authorizationHeaders` is `[Bearer static-key, Bearer rotated-1, Bearer rotated-2, null]`. The harness redacts the headers inside `exchanges[...]`.
- **Chat.** Run `$V run openai --check chat-generate`. `exchanges[0].url` is `/v1/chat/completions` and `requestBody.max_completion_tokens` is `32`. `observed.text` is `Hello there.`
- **Chat tool loop.** Run `$V run openai --check chat-tool-loop`. `exchanges` has two requests. The second ends with a `tool` message for `call_verify_1`. `observed.executions` is `1`.
- **GPT-6 warning.** Run `$V run openai --check chat-gpt6-warning`. `observed.warnings` has one entry with `feature: chat-completions`.
- **Responses.** Run `$V run openai --check responses-generate`. `exchanges[0].url` is `/v1/responses`, `requestBody.instructions` is `Be brief.` and `observed.usage` has cached tokens `4` and reasoning tokens `3`.
- **Responses tool loop.** Run `$V run openai --check responses-tool-loop`. The second request body `input` has a `function_call` and a `function_call_output` with the same `call_id`.
- **Hosted tools.** Run `$V run openai --check responses-hosted-tools`. `observed.tools` lists `web_search_preview, file_search, code_interpreter, image_generation, mcp`. `observed.toolCalls` has one call with `providerExecuted: true`.
- **Responses errors.** Run `$V run openai --check responses-errors`. The 401 has code `invalid_api_key` and is not retryable. The 429 is retryable.
- **Embeddings.** Run `$V run openai --check embeddings`. The fixture returns the vectors in reverse order. `observed.many` is in input order.
- **Media.** Run `$V run openai --check image-generation`, `speech` or `transcription`. For `transcription`, the request body in `exchanges[0].requestBody` is the multipart text with `whisper-1`, `json`, `en` and `fox`.
- **Files and batches.** Run `$V run openai --check files-lifecycle` and `batches-lifecycle`. The files exchanges are `POST /v1/files`, `GET /v1/files/file-verify`, `GET .../content` and `DELETE`. The batches exchanges are one file upload, then `POST /v1/batches`, `GET`, a list with `limit=2&after=batch_0`, and `POST .../cancel`.
- **Timeout and abort.** Run `$V run openai --check files-timeout-abort`. `observed.elapsedMs` is below 2000 although the fixture waits 3 s.
- **Live.** Run `OPENAI_API_KEY_FILE=<file> $V run openai --live`. Output `40 passed, 0 failed, 0 skipped`. The live checks are `live-chat-generate`, `live-chat-stream`, `live-responses-generate`, `live-responses-stream`, `live-structured-output`, `live-tool-loop`, `live-embeddings`, `live-speech-transcription`, `live-image` and `live-invalid-key`. Every call is capped at small token counts and the cheapest media sizes. Check `exchanges[...].status` is `200` (and `401` for `live-invalid-key`). Without a key, `$V run openai --live` shows `SKIP ... missing OPENAI_API_KEY` for those ten checks.

## Gotchas

- Fixture responses follow the public OpenAI formats. They prove the adapter's mapping, not the current vendor behavior. The live checks are the vendor proof.
- `OpenAIProvider.baseUrl` only affects chat, Responses, files and batches. Embeddings, images, speech and transcription use relative paths on the Dio client. An injected `client` must carry its own `baseUrl`. Without an injected client, `baseUrl` also configures the owned client.
- `generateText` wraps a retryable error (for example a 429) in `AiRetryError`, even with `maxRetries: 0`. The `lastError` field holds the `AiApiCallError`.
- `dispose()` does nothing for an injected client. The caller owns it.
- `live-invalid-key` sends a fake key and costs nothing, but it still needs `OPENAI_API_KEY` set so that the live set skips as a unit.
- Not covered: `organization` and `project` options. The provider has no such option. The injected-client route is covered in `provider-base-url-client`.
- Not covered: the global `openai` instance. It reads `OPENAI_API_KEY` at compile time with `String.fromEnvironment`, which a runtime check cannot set.
- Not covered: stream-based `OpenAIFileUpload`, `OpenAIBatchSubmissionException` and the `stopwatchFactory` seam. They need a failure after upload or a fake clock. The package tests cover them.
- Not covered: Responses computer-use, MCP approval replay, and image or file input parts. Only the request shape of the hosted tools and the web search result are verified.
- Not covered: `OpenAIRequestScope`. It is private to the package. `request-scope` verifies its effect through the public Files and Batches calls.
- The `dall-e-2` and `dall-e-3` models are retired. On 2026-10-29 the live API rejected `dall-e-2` with `Unknown parameter: 'response_format'`. The adapter adds `response_format: b64_json` for every model whose id does not start with `gpt-image`. The fixture check `image-generation` still asserts that mapping. The live check defaults to `gpt-image-1-mini`, and `gpt-image-2` also passed. `gpt-image-1` returned `does not exist` for the verifying account, which depends on organization access, not on the package.
