# ai_sdk_anthropic

The Anthropic provider for AI SDK Dart. A developer builds an `AnthropicProvider` (or uses the top-level `anthropic` factory), calls it with a Claude model id, and passes the model to `generateText` or `streamText`. The package speaks the Messages API: JSON responses, named SSE events, tool_use blocks, extended thinking with signatures, prompt caching and typed errors.

## Sub-features

- `anthropic-provider` sends `x-api-key` and `anthropic-version: 2023-06-01`, resolves the key from `apiKey` or a `credentialProvider`, honors `baseUrl` and an injected `Dio` client, forwards per-call headers, and `dispose()` closes only a client the provider created.
- `anthropic-generate` sends `POST <base>/messages` with `model`, `max_tokens`, `system`, `messages`, sampling settings and `stop_sequences`, and returns text, usage, finish reason and response id.
- `anthropic-stream` sends `stream: true` and turns the named SSE events (`message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `ping`, `message_delta`, `message_stop`) into ordered text deltas, usage and a finish reason.
- `anthropic-tools` sends tools with `input_schema`, parses `tool_use` blocks (also from `input_json_delta` fragments), and sends the executed result back as a `tool_result` block with the same `tool_use_id`.
- `anthropic-tool-choice` maps auto, required, none and a specific tool to `tool_choice` `auto`, `any`, `none` and `tool` with a name.
- `anthropic-structured` sends `output_config.format` as `json_schema` for `Output.object` and parses the JSON reply.
- `anthropic-thinking` covers `AnthropicThinkingOptions` (`budgetTokens`, `speed: 'fast'`, `adaptive`), `AnthropicLanguageModelOptions.effort`, and the portable `reasoning` level. Thinking and redacted thinking blocks become reasoning parts. The signature is kept and replayed before `tool_use` in the next step, for generate and for stream.
- `anthropic-cache` sends `AnthropicCacheControlOptions` as a top-level `cache_control` with `ttl`, and a part-level `cacheControl` option on that content block.
- `anthropic-usage` reports cache read and cache creation tokens separately and adds them to the input total, for generate and for stream.
- `anthropic-multimodal` sends image and file parts as `image` and `document` blocks with base64 or url sources, media types and document titles.
- `anthropic-provider-tools` sends a provider-defined tool by its versioned `type` (for example `web_search_20250305`) with its args, and turns `citations` into source parts.
- `anthropic-finish-reasons` maps `end_turn`, `max_tokens`, `stop_sequence`, `tool_use` and unknown reasons, and keeps the raw reason.
- `anthropic-errors` maps Anthropic error JSON to `AiApiCallError` with status, type, message and `isRetryable`. It treats 529 `overloaded_error` as retryable. It reports a mid-stream `error` event and a stream cut off before `message_delta` as typed errors.

## How to get to it (user POV)

- `import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';` then `generateText(model: AnthropicProvider(apiKey: key)('claude-haiku-5-5'), prompt: ...)`.
- The top-level `anthropic('<model>')` reads `ANTHROPIC_API_KEY` through `String.fromEnvironment`, so it needs `--define`.
- Thinking and cache options go in `providerOptions: {'anthropic': <options>.toMap()}`.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- Fixture checks need no key. They use an in-process server that answers in the Messages API wire format.
- Live checks need `ANTHROPIC_API_KEY` (or `ANTHROPIC_API_KEY_FILE=<file>` with the wrapper). Optional: `ANTHROPIC_VERIFY_MODEL` (default `claude-haiku-5-5`) and `ANTHROPIC_VERIFY_REASONING_MODEL` (default: the same model).

- **All fixture checks.** Run `$V run anthropic`. Output `19 passed, 0 failed, 7 skipped`. The 7 skips are the live checks.
- **Live skip proof.** Run `$V run anthropic --live` with no key. The seven `live-*` checks print `SKIP ... missing ANTHROPIC_API_KEY`.
- **Headers.** Run `$V run anthropic --check provider-headers`. In `ai_sdk_anthropic/provider-headers.json`, `exchanges[0].requestHeaders` has `x-api-key: <redacted>`, `anthropic-version: 2023-06-01` and `x-verify-trace: trace-1`. `exchanges[1]` was sent with the key from the `credentialProvider`.
- **Base URL and dispose.** Run `$V run anthropic --check provider-base-url-dispose`. The first exchange URL is `/proxy/v1/messages`. `observed.injectedClientStatusAfterDispose` is `200`.
- **Generate.** Run `$V run anthropic --check generate-text`. `exchanges[0].requestBody` has `max_tokens: 64`, `system: Be brief.` and `stop_sequences: [STOP]`. `observed.text` is `Hello from the fixture.`
- **Stream.** Run `$V run anthropic --check stream-text`. `exchanges[0].requestBody.stream` is `true`. `observed.deltas` is `["One, ", "two, ", "three."]`.
- **Tool loop.** Run `$V run anthropic --check tool-loop`. `exchanges` has two requests. The second ends with a user `tool_result` block for `toolu_01Verify` with content `Sunny, 18C in Paris`. `observed.executions` is `1`. `stream-tool-loop` does the same from `input_json_delta` fragments.
- **Tool choice.** Run `$V run anthropic --check tool-choice`. `observed.tool_choice` is `auto`, `any`, `none` and `tool/getWeather`.
- **Structured output.** Run `$V run anthropic --check structured-output`. The request has `output_config.format.type: json_schema`. `observed.output` is `{capital: Tokyo, currency: JPY}`.
- **Thinking.** Run `$V run anthropic --check thinking-generate`, `thinking-continuation`, `thinking-stream` and `reasoning-options`. The request has `thinking: {type: enabled, budget_tokens: 1024}`. The second request of `thinking-continuation` has an assistant message with blocks `thinking` (signature `sig-continuation-1`) then `tool_use`. `observed.adaptive` in `reasoning-options` is `{type: adaptive}`.
- **Cache.** Run `$V run anthropic --check prompt-cache-control`, then `usage-cache-tokens`. The first request has `cache_control: {type: ephemeral, ttl: 1h}`. The second reports input total 310, cache read 200 and cache write 100 for generate and stream.
- **Multimodal and provider tools.** Run `$V run anthropic --check image-document-input`, then `provider-defined-tool-citations`. `observed.blocks` lists `text, image, image, document, document`. The tool entry is `{type: web_search_20250305, name: web_search, max_uses: 2}`. `observed.sources` has `https://dart.dev`.
- **Finish reasons.** Run `$V run anthropic --check stop-reasons`. `observed.mapping` has five raw reasons.
- **Errors.** Run `$V run anthropic --check api-errors`, then `stream-errors`. `observed.401` is `[401, authentication_error]` and `observed.529` is `[529, overloaded_error]`. The 5th request returns `recovered` after a retry.
- **Live.** Run `ANTHROPIC_API_KEY_FILE=<file> $V run anthropic --live`. Expect `26 passed`. In `live-generate.json`, `exchanges[0].status` is `200` and `observed.text` is not empty. In `live-reasoning.json`, `observed.rawThinkingBlocks` must equal `observed.reasoningParts`. `live-thinking-tool-loop` runs a tool loop with adaptive thinking. When the first response has a thinking block, `observed.replayedAssistantBlocks` must contain `thinking`. In `live-invalid-key.json`, `observed.statusCode` is `401` and `observed.type` is `authentication_error`.

## Gotchas

- Not covered: provider-level custom headers: `AnthropicProvider` has no `headers` option. Only the per-call `headers` of `generateText` exist, and `provider-headers` covers them.
- Not covered: streamed `redacted_thinking` blocks and `includeRawChunks`: no user-facing result beyond the other stream checks.
- Fixture responses follow the public Messages API. They prove the adapter's mapping, not the current vendor behavior. The `live-*` checks are the vendor proof.
- Current Claude models such as `claude-haiku-5-5` reject `thinking.type: enabled` with a budget, and accept only `thinking.type: adaptive` plus `output_config.effort`. The live reasoning checks use adaptive mode with `effort: high` by default. `ANTHROPIC_VERIFY_THINKING=budget` with an older model (`ANTHROPIC_VERIFY_REASONING_MODEL=claude-sonnet-4-5`) runs the 1,024-token budget form instead, which passed on 2026-10-29 with 329 reasoning characters. In budget mode, `maxOutputTokens` must be greater than the budget.
- With adaptive thinking, the API can return a `thinking` block whose `thinking` text is empty and whose `signature` is set. The adapter used to drop that block, so `result.reasoning` was empty and a tool continuation could not replay the signature (fixed in PR #30). `live-reasoning` and `live-thinking-tool-loop` guard against a regression. Evidence: `live-reasoning.json`, `exchanges[0].responseBody.content[0]`.
- `generateText` retries retryable errors and wraps the last one in `AiRetryError`. Use `maxRetries: 0` to see the first error, and read `lastError` for a retryable status such as 529.
- `result.reasoning` and `result.reasoningText` cover the final step only. In a tool loop, read them from `result.steps`.
- The live key is sent through `ctx.recordingDio`. The harness redacts `x-api-key` in the evidence JSON.
