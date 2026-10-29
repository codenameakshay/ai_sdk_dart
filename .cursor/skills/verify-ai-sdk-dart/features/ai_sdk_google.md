# ai_sdk_google

The Google Generative AI (Gemini) provider for AI SDK Dart. A developer builds a `GoogleGenerativeAIProvider` (or uses the top-level `google` factory), calls it with a Gemini model id for chat or `.embedding(...)` for vectors, and passes the model to `generateText`, `streamText`, `embed` or `embedMany`. The package speaks `generateContent`, `streamGenerateContent?alt=sse` and `batchEmbedContents`.

## Sub-features

- `google-provider` sends the API key as the `?key=` query parameter, adds the `models/` prefix to a model id once, resolves the key from `apiKey` or a `credentialProvider`, fails with `StateError` when the key is empty, honors `baseUrl` and an injected `Dio` client, and `dispose()` closes only a client the provider created.
- `google-generate` sends `POST <base>/models/<id>:generateContent` with `systemInstruction`, `generationConfig` (max tokens, temperature, topP, topK, stop sequences) and role-mapped `contents` (`user`, `model`), and returns text, usage and finish reason.
- `google-stream` sends `POST ...:streamGenerateContent?alt=sse` and yields the text of each SSE `data:` chunk in order, with usage from the last chunk.
- `google-tools` sends `functionDeclarations`, parses `functionCall` parts (also parallel calls and streamed calls), and sends results back as `functionResponse` parts in a user turn.
- `google-tool-choice` maps auto, required, none and a specific tool to `functionCallingConfig` `AUTO`, `ANY`, `NONE` and `ANY` with `allowedFunctionNames`.
- `google-structured` sends `responseMimeType: application/json` with `responseJsonSchema` and parses the JSON reply.
- `google-thinking` passes `providerOptions['google']['thinkingConfig']` (for example `includeThoughts`, `thinkingBudget`) into `generationConfig`, maps the portable `reasoning` level to `thinkingBudget` or `thinkingLevel`, turns `thought` parts into reasoning, adds `thoughtsTokenCount` to output usage, and replays `thoughtSignature`.
- `google-embeddings` sends `POST ...:batchEmbedContents` with one request per value for `google.embedding('text-embedding-004')`, and returns the vectors for `embed` and `embedMany`.
- `google-options` merges `providerOptions['google']` (`safetySettings`, `cachedContent`) into the body, and reports a `SAFETY` candidate or a `promptFeedback` block as a content-filter finish with a warning.
- `google-multimodal` sends image and file parts as `inlineData` (base64) or `fileData` (url), and returns an `inlineData` reply part as a file.
- `google-grounding` sends a provider-defined tool such as `google.google_search` as `googleSearch`, and turns `groundingChunks` into source parts, for generate and stream.
- `google-finish-reasons` maps `STOP`, `MAX_TOKENS`, `SAFETY`, `RECITATION` and `OTHER`, keeps the raw reason, and splits cached tokens in the input usage.
- `google-errors` maps Google error JSON to `AiApiCallError` with status, Google status as `type`, message and `isRetryable` (429 is retryable). It drains the error body of a failed stream request and reports a stream cut off before `finishReason`.

## How to get to it (user POV)

- `import 'package:ai_sdk_google/ai_sdk_google.dart';` then `generateText(model: GoogleGenerativeAIProvider(apiKey: key)('gemini-2.5-flash'), prompt: ...)`.
- Embeddings: `embed(model: provider.embedding('text-embedding-004'), value: ...)`.
- The top-level `google('<model>')` reads `GOOGLE_API_KEY` through `String.fromEnvironment`, so it needs `--define`.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Every check uses an in-process fixture server that answers in the Gemini wire format.

- **All checks.** Run `$V run google`. Output `20 passed, 0 failed, 0 skipped`.
- **Key and URL.** Run `$V run google --check provider-key-url`. In `ai_sdk_google/provider-key-url.json`, `exchanges[0].url` is `/v1beta/models/gemini-verify:generateContent?key=%3Credacted%3E` and has no `authorization` header. `exchanges[1]` uses the same path for `models/gemini-verify`.
- **Base URL and dispose.** Run `$V run google --check provider-base-url-dispose`. The first exchange URL starts with `/proxy/v1beta/models/`.
- **Generate.** Run `$V run google --check generate-text`. `exchanges[0].requestBody` has `systemInstruction`, `generationConfig.maxOutputTokens: 64` and roles `user, model, user`. `observed.text` is `Hello from Gemini.`
- **Stream.** Run `$V run google --check stream-text`. The URL ends with `:streamGenerateContent?alt=sse&key=%3Credacted%3E`. `observed.deltas` is three pieces.
- **Tools.** Run `$V run google --check tool-loop`, `parallel-tool-calls`, `stream-tool-loop` and `tool-choice`. In `tool-loop`, the second request has roles `user, model, user`, and `observed.functionResponse.name` is `getWeather`. `observed.functionCallingConfig` in `tool-choice` lists four configs.
- **Structured output.** Run `$V run google --check structured-output`. `generationConfig.responseMimeType` is `application/json`. `observed.output` is `{capital: Tokyo, currency: JPY}`.
- **Thinking.** Run `$V run google --check thinking-config`, `reasoning-levels` and `stream-thinking`. `generationConfig.thinkingConfig` is `{includeThoughts: true, thinkingBudget: 1024}` and the second request replays `thoughtSignature: sig-google-1`. `observed.levels` in `reasoning-levels` is `thinkingBudget 600`, `thinkingBudget 0` and `thinkingLevel medium`.
- **Embeddings.** Run `$V run google --check embeddings`. The URL is `/v1beta/models/text-embedding-004:batchEmbedContents`. `observed.embedding` is `[0.1, 0.2, 0.3]`.
- **Options and safety.** Run `$V run google --check safety-settings-options`, then `safety-blocks`. The body has top-level `safetySettings` and `cachedContent`. `observed.promptBlock` shows `contentFilter` and `PROHIBITED_CONTENT`.
- **Multimodal and grounding.** Run `$V run google --check multimodal-input-output`, then `grounding-sources`. `observed.requestParts` has `inlineData` and `fileData` parts. `observed.tools` has a `functionDeclarations` entry and a `googleSearch` entry.
- **Finish reasons and usage.** Run `$V run google --check finish-reasons-usage`. `observed.mapping` has five reasons. `observed.usage` has cache read 60 and no-cache 40.
- **Errors.** Run `$V run google --check api-errors`, then `stream-errors`. `observed.400` has type `INVALID_ARGUMENT`. `observed.429` is `[429, RESOURCE_EXHAUSTED]`. `observed.rejected` in `stream-errors` holds the message `Invalid JSON payload.`

## Gotchas

- There is no Google key in this harness, so there are no live checks. The fixtures follow the public Gemini REST format. They prove the adapter's mapping, not the current vendor behavior.
- Not covered: Vertex AI, OAuth credentials and the `x-goog-api-key` header: the package only sends the key as the `key` query parameter.
- Not covered: image generation models and code execution results: no user-facing path beyond the multimodal and provider-tool checks.
- `providerOptions['google']` entries other than `thinkingConfig` are merged into the top level of the body. For embeddings, they are merged into the batch body and not into each request, so per-request fields such as `outputDimensionality` do not reach the API. This check does not assert that case.
- `generateText` retries retryable errors and wraps the last one in `AiRetryError`. Use `maxRetries: 0` for the first error, and read `lastError` for 429.
- `result.reasoning` and `result.reasoningText` cover the final step only. In a tool loop, read them from `result.steps`.
- The harness redacts the `key` query parameter in the evidence URL. The fixture server sees the real value.
