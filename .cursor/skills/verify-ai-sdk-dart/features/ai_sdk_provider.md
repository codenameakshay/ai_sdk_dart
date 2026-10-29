# ai_sdk_provider

The interface package that a provider author implements: `LanguageModelV4`, `EmbeddingModelV2`, `ImageModelV3`, `SpeechModelV1`, `TranscriptionModelV1` and `RerankModelV1`, with their call options, results, stream parts, usage, finish reasons, warnings, abort signals and typed errors. These checks act as a provider author. Each one writes a small custom model against the public interfaces, runs it through the public `ai_sdk_dart` functions, and asserts that the contract holds end to end.

## Sub-features

- `provider-language` maps a custom `doGenerate` result and a custom `doStream` part sequence to `generateText` and `streamText` fields. It covers text, reasoning with signature, tool calls, sources, files, usage (input total, no-cache, cache read and write; output total, text and reasoning), the seven finish reasons with raw strings, the four warning types, response metadata and provider metadata. It also asserts that the model receives complete `LanguageModelV4CallOptions`: prompt messages with URL, base64 and file data content, sampling settings, headers, provider options, reasoning level, function tools with strict flag and input examples, tool choice, JSON response format and an abort signal.
- `provider-errors` covers the error contract. A model that throws `AiApiCallError` reaches the caller as is. A retryable one becomes `AiRetryError` after `maxRetries`. Other exceptions pass through unwrapped and are not retried. A `StreamPartError` reaches `onError`. `AiApiCallError.fromResponse` parses nested, flat, byte and plain-text bodies and applies the retryable status table.
- `provider-embedding` shows that `maxEmbeddingsPerCall` sets the batch size, `supportsParallelCalls: false` forces serial calls, and headers, provider options and the abort signal reach `doEmbed`. Token usage is summed.
- `provider-image` shows that `generateImage` passes prompt, `n`, size, aspect ratio, seed, headers and provider options to `doGenerate`. It returns the images and usage, and an empty result throws `AiNoImageGeneratedError`.
- `provider-speech-transcription` shows the same for `SpeechModelV1` and `TranscriptionModelV1`, including `AiNoSpeechGeneratedError` and `AiNoTranscriptGeneratedError`.
- `provider-rerank` shows that `RerankModelV1` receives query, documents, `topN`, headers and provider options, and that the ranked order of the provider is kept.
- `provider-abort-signal` shows that the `AbortSignal` in the call options fires on caller cancellation, the call ends with `AiOperationCancelledError`, and `runWithAbortSignal` and `AbortSignalObservation` behave as documented.
- `provider-http-helpers` covers `createProviderDio`, `providerEndpoint`, `apiErrorFromDioException` (status, message, type, `Retry-After` header, cancellation) and `sseDataLines` (comments, event names and multi-line data) against a real HTTP server.
- `provider-shared-types` covers all 22 stream part types through an exhaustive `switch`, tool result error flags, `dataContentToBase64`, `intOrNull`, `safeParseJson`, `prefixedId` and `ProviderCapabilityDescriptor` defaults.

## How to get to it (user POV)

- A provider author adds `ai_sdk_provider` to `pubspec.yaml` and implements `LanguageModelV4` (or another model interface) in a package.
- An app developer never imports it directly for normal use. They get the same types through `ai_sdk_dart` and a provider package such as `ai_sdk_openai`.
- Provider packages reuse `apiErrorFromDioException`, `createProviderDio`, `providerEndpoint` and `sseDataLines` for HTTP, error mapping and SSE parsing.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. The custom models are in-process. Only `http-helpers` uses the loopback fixture server.

- **All checks.** Run `$V run ai_sdk_provider`. Output `13 passed, 0 failed, 0 skipped`.
- **Generate contract.** Run `$V run ai_sdk_provider --check language-generate-contract`. `observed.warnings` is `[unsupported, compatibility, deprecated, other]` and `observed.finishReason` is `toolCalls`.
- **Stream contract.** Run `$V run ai_sdk_provider --check language-stream-contract`. `observed.eventTypes` lists reasoning, text, tool input, source, file and finish events in order. `observed.text` is `Hello`.
- **Finish reasons.** Run `$V run ai_sdk_provider --check language-finish-reasons`. `observed.mapped` has seven entries, each `<reason>/<reason>`.
- **Call options.** Run `$V run ai_sdk_provider --check language-call-options`. `observed.responseFormat` is `LanguageModelV4JsonResponseFormat`.
- **Errors.** Run `$V run ai_sdk_provider --check language-errors`. `observed` holds the `AiApiCallError`, `AiRetryError` and `StateError` text from each case.
- **HTTP helpers.** Run `$V run ai_sdk_provider --check http-helpers`. `exchanges` has the `429` response with its `retry-after` header, `observed.mapped.status` is `429`, and `observed.ssePayloads` is `[{"n":1}, "multi\nline", "[DONE]"]`.
- **Abort.** Run `$V run ai_sdk_provider --check abort-signal`. `observed.providerSawCancel` is `true`.

## Gotchas

- `generateText().usage` is the sum over steps and drops `raw`. The check reads `finalStep.usage.raw`.
- `streamText` derived streams are single-pass. Subscribe to `textStream` before you drain `stream`, or `textStream` is empty.
- `FixtureResponse.sse` turns every string into a `data:` line. The `http-helpers` check sends the SSE comment line as raw text.
- A tool call in a custom model response with a tool that has no `execute` produces a tool-error step in `responseMessages` after the assistant message.
- Not covered: `LanguageModelV4.supportedUrls`: no public `ai_sdk_dart` function reads it.
- Not covered: `StreamPartRaw` and `includeRawChunks`: the check path needs a body inclusion policy that the text checks own.
- Not covered: `ImageModelV3CallOptions.promptObject` (image-to-image inputs): `generateImage` has no parameter for it.
- Not covered: `EmbeddingModelV2GenerateResult.warnings` and `providerMetadata`: `embed` and `embedMany` do not expose them.
