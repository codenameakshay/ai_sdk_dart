# ai_sdk_dart (platform)

The non-text half of `ai_sdk_dart`: embeddings, image, speech, transcription and rerank calls, the middleware system, the provider registry, typed errors with retries, core telemetry and the testing mocks. An app developer calls these functions with any provider model. These checks use the real `ai_sdk_openai`, `ai_sdk_cohere` and OpenAI-compatible chat adapters against a loopback server. Text generation, streaming, structured output, tools and agents have their own feature file.

## Sub-features

- `platform-embed` sends `POST /v1/embeddings` with auth, model and input, returns the vector and token usage, and rejects wrong-count, wrong-order, wrong-dimension or non-finite vectors with `AiInvalidEmbeddingResponseError`.
- `platform-embed-many` splits values by `maxEmbeddingsPerCall`, keeps input order, sums token usage, returns an empty result for no values, and runs `maxParallelCalls` requests at once (default one).
- `platform-cosine` computes `cosineSimilarity` for equal, orthogonal, opposite and zero vectors, and throws `ArgumentError` for mismatched or empty vectors.
- `platform-image` sends `POST /v1/images/generations` and returns decoded PNG bytes and usage. An empty result throws `AiNoImageGeneratedError`.
- `platform-speech` sends `POST /v1/audio/speech` with voice, format and speed, and returns audio bytes and the response media type. Empty audio throws `AiNoSpeechGeneratedError`.
- `platform-transcribe` uploads the audio as multipart form data with model, language and prompt, and returns the transcript. An empty transcript throws `AiNoTranscriptGeneratedError`.
- `platform-rerank` sends `POST /v2/rerank` to Cohere with query, documents and `top_n`, and returns documents in ranked order with their original indices.
- `platform-timeout` makes a per-call `Duration` timeout abort `embed`, `embedMany`, `generateImage`, `generateSpeech`, `transcribe` and `rerank` with `TimeoutException`.
- `platform-middleware-language` covers `wrapLanguageModel` with `extractReasoningMiddleware` (generate and stream), `extractJsonMiddleware`, `simulateStreamingMiddleware`, `defaultSettingsMiddleware`, `addToolInputExamplesMiddleware` and middleware list order.
- `platform-middleware-media` covers `wrapEmbeddingModel` and `wrapImageModel`: `transformParams` and the wrap hook run on real requests.
- `platform-registry` covers `createProviderRegistry` with `provider:modelId` resolution for all six model categories, ids that contain more colons, `ArgumentError` for unknown providers, `UnsupportedError` for missing factories, and `customProvider` with named models and fallbacks.
- `platform-errors` maps non-2xx responses from every category to `AiApiCallError` with status, message, type, code, url, body and `isRetryable`.
- `platform-retry` makes `generateText` retry retryable errors up to `maxRetries`, throw `AiRetryError` with the attempts and error history when they run out, skip non-retryable errors, and wait for a numeric `Retry-After` header.
- `platform-telemetry` sends spans and metrics from `generateText` and `streamText` through `TelemetrySettings`, keeps prompts out unless `captureInputs` is on, applies `redactAttribute`, records failures, and isolates a broken backend through `onDiagnostic`.
- `platform-testing` drives `MockEmbeddingModelV2`, `MockEmbeddingModelV3`, `MockImageModelV3`, `MockLanguageModelV4`, `mockText`, `mockReasoning`, `mockToolCall`, `mockId` and `mockValues` from `package:ai_sdk_dart/test.dart`.
- `platform-utils` covers `generateId`, `createIdGenerator`, `simulateReadableStream`, `convertToModelMessages` and `pruneMessages`.

## How to get to it (user POV)

- Import `package:ai_sdk_dart/ai_sdk_dart.dart` and call `embed`, `embedMany`, `cosineSimilarity`, `generateImage`, `generateSpeech`, `transcribe` and `rerank` with a model from a provider package (`openai.embedding(...)`, `cohere.rerank(...)`).
- Wrap a model with `wrapLanguageModel`, `wrapEmbeddingModel` or `wrapImageModel` and pass the wrapper to the same functions.
- Build a registry with `createProviderRegistry({...})` or `customProvider(...)` and resolve models with `registry.languageModel('openai:gpt-4.1-mini')`.
- Pass `telemetry: TelemetrySettings(...)` to `generateText` or `streamText`. Catch `AiApiCallError` and `AiRetryError` around any call.
- In tests, import `package:ai_sdk_dart/test.dart` for the mocks.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Network checks use an in-process fixture server that answers in the OpenAI, Cohere or Chat Completions wire format. Math and testing helpers also run in memory.

- **All checks.** Run `$V run ai_sdk_dart`. This runs the text checks too. For the platform checks alone, the expected result is 29 passed and 2 failed (see Gotchas for the two known failures).
- **Embeddings.** Run `$V run ai_sdk_dart --check embed-many-chunking`. In `ai_sdk_dart/embed-many-chunking.json`, `observed.requestInputs` is `[[a, bb], [ccc, dddd], [eeeee]]` and `observed.usage` is `15`.
- **Parallel calls.** Run `$V run ai_sdk_dart --check embed-many-parallel`. `observed.serialPeak` is `1` and `observed.parallelPeak` is at least `2`.
- **Media.** Run `$V run ai_sdk_dart --check transcribe-openai`. `exchanges[0].requestHeaders` has a `multipart/form-data` content type. `observed.text` is `hello from the audio`.
- **Rerank.** Run `$V run ai_sdk_dart --check rerank-cohere`. `exchanges[0].url` is `/v2/rerank` and `observed.ranked[0].index` is `1`.
- **Timeouts.** Run `$V run ai_sdk_dart --check media-timeouts`. `exchanges` has seven requests. Six calls threw `TimeoutException`. The seventh call used a 5-second timeout and succeeded.
- **Middleware.** Run `$V run ai_sdk_dart --check middleware-chain-order`. `observed.log` is `[A:transform, A:before, B:transform, B:before, B:after, A:after]`, and the request header `x-mw-b` reached the fixture.
- **Registry.** Run `$V run ai_sdk_dart --check registry-resolve`. `observed.paths` lists one request per category in this order: chat, embeddings, images, speech, transcriptions, rerank.
- **Retries.** Run `$V run ai_sdk_dart --check retry-exhausted`. `observed.attempts` is `3` and `exchanges` has three requests. Run `--check retry-after-header` to see `observed.gapMs` of about 1000.
- **Telemetry.** Run `$V run ai_sdk_dart --check telemetry-spans-metrics`. `observed.span.name` is `ai.generateText`, and `observed.metrics` includes `ai.operation.success=1`.
- **Testing utilities.** Run `$V run ai_sdk_dart --check testing-utilities`. The check passes with no fixture traffic.

## Gotchas

- The known package bugs are in the streaming `extractReasoningMiddleware`. `middleware-extract-reasoning-stream` fails because the text after `</think>` is emitted under the placeholder id `mw-text`, so `textStream` shows it but the final `text` future is empty. `middleware-extract-reasoning-stream-one-delta` fails because a whole `<think>...</think>` block inside one delta is never closed. Leave both failing until the package is fixed.
- Only `generateText` and `streamText` retry. `embed`, `embedMany`, `generateImage`, `generateSpeech`, `transcribe` and `rerank` have no `maxRetries` and throw the first `AiApiCallError`.
- `maxRetries: 0` with a retryable status still throws `AiRetryError` with `attempts: 1`, not the bare `AiApiCallError`.
- `Retry-After` support covers numeric delta-seconds only. The check uses a 1-second value, so `retry-after-header` takes about one second.
- `generateText().usage` is the sum over steps and drops `raw`. The raw provider usage is on `finalStep.usage`.
- `customProvider` has no rerank model map. Use `createProviderRegistry` with `rerankModelFactory` for rerank.
- Not covered: cancellation with `abortSignal` in `generateText` and `streamText`: the text checks own it. The provider feature file covers cancellation of `embed`.
- Not covered: live provider checks: the OpenAI and Anthropic feature files own them.
- The fixture responses follow the public wire formats of OpenAI and Cohere. They prove the adapter mapping, not current vendor behavior.
