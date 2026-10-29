# ai_sdk_dart (text)

The text half of the core package: `generateText`, `streamText`, structured output, tools, approvals, `ToolLoopAgent`, cancellation and timeouts. A developer passes any `LanguageModelV4` and a prompt, and gets text, typed events, typed objects and tool loops back. Embeddings, media, rerank, middleware, the registry, errors, telemetry and testing helpers are in `ai_sdk_dart-platform.md`.

## Sub-features

- `text-generate` returns the full result envelope from `generateText`: text, content parts, steps, usage and totalUsage, finish reason and raw finish reason, request and response metadata, and warnings. Request and response bodies stay out of the result unless `BodyInclusionPolicy` asks for them. Checks: `generate-text-envelope`, `generate-body-inclusion`, `generate-finish-reasons`.
- `text-instructions` gives `instructions` priority over the deprecated `system`. A system-role message in `messages` is rejected unless `allowSystemInMessages` is set. Check: `instructions-precedence`.
- `text-messages` sends user, assistant and tool `ModelMessage`s (text and parts) as the matching roles, and `ModelMessage.text` joins the text parts. Check: `message-roles`.
- `text-multimodal` sends image bytes and image URLs in a user message as content parts. Check: `multimodal-image`.
- `text-content` surfaces reasoning, sources, document sources, files, reasoning files, warnings and provider metadata in results, for both `generateText` and `streamText`. Checks: `generate-reasoning`, `generate-result-parts`, `generate-warnings`, `stream-reasoning`, `stream-result-parts`.
- `text-stream` runs `streamText`: `textStream`, the typed `stream` events in order, `providerStream`, the `fullStream` alias, raw chunks, and the result futures (`text`, `usage`, `finishReason`, `steps`, `response`, `providerMetadata`). Checks: `stream-text-basic`, `stream-event-taxonomy`, `stream-raw-chunks`.
- `text-smooth` splits long deltas with `smoothStream(chunkSize)` and spaces them with `delayInMs`. Check: `smooth-stream`.
- `text-callbacks` fires `onStart`, `onStepStart`, `onToolExecutionStart`, `onToolExecutionEnd`, `onStepEnd`, `onEnd` and `onChunk` in order, and keeps `onStepFinish` and `onFinish` as fallbacks. Checks: `generate-callbacks`, `stream-callbacks`.
- `text-stream-errors` reports an HTTP error or a stream that ends without a finish reason through `onError`, an error event and rejected futures. Checks: `stream-http-error`, `stream-truncated`.
- `text-multistep` runs the tool loop. `maxSteps` bounds it, `prepareStep` overrides each step, `stopWhen` and `stopConditions` end it, and `activeToolNames` limits the tools sent. Checks: `multi-step-max-steps`, `prepare-step`, `stop-conditions`, `active-tools`.
- `text-structured` handles `Output.object`, `Output.array`, `Output.choice` and `Output.json`, plus `partialOutputStream`, `elementStream` and `AiNoObjectGeneratedError`. Checks: `output-object`, `output-array-choice-json`, `output-no-object-error`, `stream-partial-output`, `stream-element-stream`.
- `text-object` runs the object-only helpers `generateObject` and `streamObject`: a typed object, raw JSON, partial snapshots, JSON patch operations, and `AiNoObjectGeneratedError`. Checks: `generate-object`, `stream-object`.
- `text-tools` covers `tool<I, O>`, `dynamicTool`, `toolWithContext`, `toolChoice`, `strict`, input examples, provider-defined tools, the input lifecycle hooks, `maxToolConcurrency`, and tool errors that go back to the model. Checks: `tool-typed-loop`, `tool-dynamic`, `tool-choice`, `tool-error-returned`, `tool-invalid-input`, `tool-input-hooks`, `tool-concurrency`, `tool-context`, `tool-definition-options`.
- `text-approval` pauses a call on `needsApproval` or `approvalPolicy`, resumes it with `toolApprovalResponses`, renews a stale approval, and replays a paused agent turn with `ToolLoopAgent.resume`. Checks: `approval-generate`, `approval-policy`, `approval-agent-resume`.
- `text-agent` runs `ToolLoopAgent.generate` and `.stream` with `instructions` and a tool loop. Checks: `agent-generate`, `agent-stream`.
- `text-cancel` stops a call with `CancellationToken` (`abortSignal`), before the request, while it is in flight, mid-stream, and inside a tool. Checks: `cancel-generate`, `cancel-stream`, `cancel-tool-signal`.
- `text-timeout` ends a call with `TimeoutConfiguration` (`total`, `step`, `firstChunk`, `chunk`, `tool`, `tools`). Checks: `timeout-total`, `timeout-stream-chunk`, `timeout-tool`.

## How to get to it (user POV)

- Import `package:ai_sdk_dart/ai_sdk_dart.dart` and pass a model from a provider package to `generateText` or `streamText`.
- Add `tools`, `maxSteps` or `stopWhen`, and an `output:` for a typed result. Use `ToolLoopAgent(model:, instructions:, tools:)` for a reusable tool loop.
- Pass `abortSignal: CancellationToken()` and `timeout: TimeoutConfiguration(...)` to bound a call.
- Flutter apps reach the same functions through `ai_sdk_flutter_ui` controllers. Those are not covered here.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Most checks use a loopback fixture in the Chat Completions wire format through `OpenAICompatibleChatLanguageModel`. A few use a hand-written `LanguageModelV4`; each says why in its `notes`.

- **All checks.** Run `$V run ai_sdk_dart`. The 50 checks of this file print `PASS`. The platform half adds its own lines (see `ai_sdk_dart-platform.md`).
- **Envelope.** Run `$V run ai_sdk_dart --check generate-text-envelope`. In `ai_sdk_dart/generate-text-envelope.json`, `exchanges[0].requestBody` has `seed: 42`, `stop: [END]`, `top_p: 0.9` and roles `system, user`. `exchanges[0].requestHeaders` has `x-verify-trace`. `observed.usage` has 11 input and 7 output tokens.
- **Event order.** Run `$V run ai_sdk_dart --check stream-event-taxonomy`. `observed.events` is `Start, StartStep, TextStart, TextDelta, TextDelta, TextEnd, Usage, FinishStep, Finish`.
- **Smooth stream.** Run `$V run ai_sdk_dart --check smooth-stream`. `observed.chunks` is `abcd, efgh, ijkl`. `observed.delayedElapsedMs` is at least 120.
- **Tool loop.** Run `$V run ai_sdk_dart --check tool-typed-loop`. `exchanges` has two requests. The first body has the tool with `strict: true`. The second ends with a `tool` message for `call_1` with the content `Sunny, 18C in Paris`.
- **Tool errors.** Run `$V run ai_sdk_dart --check tool-error-returned`. `observed.toolMessage` has `isError: true` and the text `boom`. The call does not throw.
- **Object helpers.** Run `$V run ai_sdk_dart --check stream-object`. `observed.partials` grows from `A long soup` to the full name with `minutes: 25`. `observed.patches` lists `replace` and `add /minutes` operations.
- **Structured output.** Run `$V run ai_sdk_dart --check output-object`. `observed.responseFormat` has `type: json_schema`, `name: recipe` and the schema.
- **Partial output.** Run `$V run ai_sdk_dart --check stream-partial-output`. `observed.partials` lists growing `name` values, and the final typed object has `minutes: 25`.
- **Approval.** Run `$V run ai_sdk_dart --check approval-generate`. `observed.approvalRequest` shows the approval id `approval_call_a`. The first request has no tool execution. The third request carries the tool result.
- **Resume.** Run `$V run ai_sdk_dart --check approval-agent-resume`. The second exchange has roles `user, assistant, tool` and the original id `call_r`.
- **Cancel.** Run `$V run ai_sdk_dart --check cancel-stream`. `observed.deltas` has two pieces, `observed.clientClosedConnection` is `true`, and `observed.serverEventsWritten` is far below 16.
- **Timeouts.** Run `$V run ai_sdk_dart --check timeout-tool`. Both messages are `Tool "getWeather" timed out.`

## Gotchas

- The fixtures follow the public Chat Completions format. They prove the SDK's behavior and the adapter's mapping, not a vendor's current behavior. The live checks in `ai_sdk_openai` and `ai_sdk_anthropic` are the vendor proof.
- `FixtureResponse.sse(delay:)` flushes each chunk with response buffering disabled, and waits before each chunk when a delay is set. The `cancel-stream` and `timeout-stream-chunk` checks use a separate raw-socket server to control pacing and observe whether the client closed the connection.
- `partialOutputStream` emits at growing length checkpoints (16 characters, then doubling), not on every delta. A check needs long enough JSON and small chunks to see several partials.
- A complete fenced JSON block (` ```json ... ``` `) parses as structured output. Truncated JSON and schema mismatches throw `AiNoObjectGeneratedError`.
- The Chat Completions adapter reads flat `url_citation` and `file_citation` annotations and sends no provider metadata for `generateText`. Sources, files and provider metadata are therefore verified through a hand-written model (`generate-result-parts`, `stream-result-parts`).
- `generateText` retries retryable errors. `maxRetries: 0` prevents retries, but a retryable error is still wrapped in `AiRetryError`. Read `lastError` for its `AiApiCallError`.
- Not covered: Flutter controllers that wrap these functions (`ai_sdk_flutter_ui`). They are a separate package and need a Flutter test host.
