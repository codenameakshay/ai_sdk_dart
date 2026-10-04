# Reliability audit — 2026-10-04

This audit records two-pass source reviews, deterministic reproductions, accepted fixes, validation evidence, and remaining qualification work for the AI SDK Dart v3 branch. Pinned local validation passed; hosted CI and live-provider qualification remain external gates.

## Scope and method

The review covered all 18 library packages: `ai_sdk_dart`, `ai_sdk_provider`, `ai_sdk_json_schema`, `ai_sdk_openai`, `ai_sdk_openai_compatible`, `ai_sdk_anthropic`, `ai_sdk_google`, `ai_sdk_azure`, `ai_sdk_cohere`, `ai_sdk_groq`, `ai_sdk_mistral`, `ai_sdk_ollama`, `ai_sdk_mcp`, `ai_sdk_conversation`, `ai_sdk_remote`, `ai_sdk_realtime`, `ai_sdk_telemetry`, and `ai_sdk_flutter_ui`. It also covered the `basic`, `advanced_app`, and `flutter_chat` examples, the Dart and JavaScript remote-backend fixtures, the MCP reference fixture, and workspace tooling: Makefile targets, coverage scripts, CI workflows, provider canaries, and capability-catalog generation.

The 18 packages and examples received two source-review passes, followed by deterministic reproductions for accepted findings. Workspace tooling received a Makefile/CI/catalog/canary audit and follow-up failure investigation; this is not represented as two complete file-by-file tooling passes.

| Area | Pass 1 | Pass 2 |
|---|---|---|
| Core, provider contracts, JSON Schema (3 packages) | Contract, output, tool, cancellation, provider-value, and schema-boundary inventory with baseline repros | Independent review plus 428-case stream-boundary sweep |
| Provider adapters (9 packages) | Request mapping, content serialization, errors, and stream terminals | Independent adapter review plus 32-seed compatible-stream/tool sweep |
| Companions and UI (6 packages) | Conversation, remote, MCP, realtime, telemetry, UI, and examples review | Independent review plus conversation 512, remote 275, and temporary composer 32-case sweeps |
| Examples and tooling | All three apps, Dart/JS fixtures, Makefile, coverage, CI, catalog, canary paths inspected | App/controller lifecycle and affected integration paths revisited; tooling received an audit and failure follow-up |

## Final pinned validation

| Area | Result |
|---|---|
| Full coverage/test run | 1,869 Dart and 294 Flutter tests passed; coverage 99.07% (14,174/14,307), meeting the 99% threshold |
| Package and focused suites | MCP: 199 tests; Flutter controller/retry/approval: 43 tests; Anthropic reasoning budgets: 12 tests |
| Remote and examples | Remote reference suite: 53 tests; example runners: 39, 21, and 5 cases, plus 6 CLI assertions |
| JavaScript fixture | 3 tests passed locally on Node 24.21; hosted CI uses Node 22 |
| Analyzer, format, web build, and Wasm dry run | Passed |
| Browser flows | Final-code checks passed for two remote turns and four local/remote approve/deny flows |
| Tooling and benchmark | 22 tooling tests passed; catalog check covered 16 records/9 providers; benchmark passed 12 × 30 samples |
| Independent review | Two full Sol review rounds ended with no remaining actionable issues after fixes; final standards review of the MCP and Anthropic test delta found none |
| Hosted CI and simulator | Hosted CI status and simulator screenshots are tracked separately in the PR checks/artifact bundle |

The audit began from the existing v3 PR branch after a clean baseline. The pinned baseline used Flutter 3.44.3 / Dart 3.12.2 through FVM. Baseline `make test` reported 2,170 tests across package and example runners (22, 1,792, 291, 39, 21, and 5), plus six basic CLI executable assertions. Baseline analyzer, remote HTTP/MCP stdio fixture tests, Flutter web release build, Wasm dry run, and the benchmark assertions passed. The benchmark used 12 cases with 30 measured samples per case; the shared host was busy, so these results are not latency claims.

Deterministic adversarial sweeps actually completed were: core 428 cases, conversation 512, remote SSE 275, OpenAI-compatible SSE/tool chunking 32, temporary Flutter composer input 32, and JavaScript HTTP abort cuts 182. The JS abort sweep used paced cuts and passed with a subsequent request accepted. A separate partial-body abort probe reproduced the baseline process crash. These counts describe selected boundaries, not exhaustive input spaces.

## Confirmed findings and fixes

### 1. A cancellation race leaves a provider error future unobserved

**Symptom and cause:** If a model cancels the supplied signal synchronously and returns an already-failed future, `raceWithCancellation` can return the cancellation result before attaching an error handler to that future. The caller sees cancellation while the provider failure escapes as an unhandled zone error.

**Fix:** The cancellation race now observes the operation future even when cancellation wins. The public operation still reports cancellation.

**Regression evidence:** [`core_regression_contracts_test.dart`](../../packages/ai_sdk_dart/test/conformance/core_regression_contracts_test.dart) includes a late provider failure and verifies the zone stays clean; the full core package suite passed in the core fix report.

### 2. Approval resume can execute a tool before message-policy validation

**Symptom and cause:** `ToolLoopAgent.resume` executed an approved replay call before reconstructed history reached `streamText`, where a disallowed system message was rejected. A rejected resume could therefore have a tool side effect.

**Fix:** Resume validates replay history before opening execution scopes or invoking tools.

**Regression evidence:** [`approval_replay_prevalidation_test.dart`](../../packages/ai_sdk_dart/test/conformance/approval_replay_prevalidation_test.dart) asserts the system-role input is rejected with zero executor calls; core regression tests cover the policy boundary.

### 3. Simulated and mock reasoning streams lose signatures

**Symptom and cause:** Simulated middleware ended a reasoning block without forwarding its signature, and mock-model streams did not preserve the provider reasoning options. Downstream consumers saw unsigned reasoning despite the source result carrying a signature.

**Fix:** Simulated and mock streams now retain reasoning signatures and provider options.

**Regression evidence:** [`core_regression_contracts_test.dart`](../../packages/ai_sdk_dart/test/conformance/core_regression_contracts_test.dart) and [`mock_models_coverage_test.dart`](../../packages/ai_sdk_dart/test/conformance/mock_models_coverage_test.dart) assert parity.

### 4. `Output.json()` rejects valid top-level JSON `null`

**Symptom and cause:** The strict parser declared a non-nullable `Object` result even though `jsonDecode('null')` returns null. The runtime failure was wrapped as “no object generated.”

**Fix:** Parsing now models nullable JSON values and accepts both fenced and unfenced `null`.

**Regression evidence:** [`core_regression_contracts_test.dart`](../../packages/ai_sdk_dart/test/conformance/core_regression_contracts_test.dart) covers raw and fenced null output.

### 5. `Output.array<T>` fails for typed list results

**Symptom and cause:** Array output was built as `List<dynamic>` and cast to the requested `TOutput`; typed results such as `List<Map<String, dynamic>>` failed at the final cast.

**Fix:** Array output construction preserves the requested element runtime type.

**Regression evidence:** [`core_regression_contracts_test.dart`](../../packages/ai_sdk_dart/test/conformance/core_regression_contracts_test.dart) requests a typed map list and verifies the returned type and value.

### 6. Partial array previews can remain stuck on an earlier tool-loop step

**Symptom and cause:** One `PartialJsonArrayTracker` was retained for the whole `streamText` run. Once a step closed its root array, later steps could not replace the partial snapshot, even when the final output was correct.

**Fix:** Structured partial state is reset/scoped per step; object and array previews follow the current step, including an empty final root.

**Regression evidence:** The core regression suite verifies that the latest-step preview replaces the earlier value and covers an empty final root.

### 7. Approval resume omits its newly executed tool result from response history

**Symptom and cause:** A resumed tool ran inside the agent before `streamText` collected generated response messages. The provider prompt contained the result, but the returned response history did not, contrary to the contract for new assistant/tool messages.

**Fix:** Resume prefixes the executed result once into returned history and propagates it consistently to the response, canonical finish event, and `onEnd`. The derived response future is observed to prevent ignored failures escaping asynchronously.

**Regression evidence:** [`core_regression_contracts_test.dart`](../../packages/ai_sdk_dart/test/conformance/core_regression_contracts_test.dart) checks result identity/count across all three surfaces.

### 8. Specific required tool choice accepts no tool call

**Symptom and cause:** Specific-tool validation compared every returned call with the requested name. An empty list passed vacuously, although the selected tool was required.

**Fix:** Specific and required choices now reject a response without a matching call on the effective step.

**Regression evidence:** Core conformance tests cover specific selection with no calls and update the multi-step text-answer fixture to use automatic selection for its next step.

### 9. Anthropic in-band stream errors are raw and parsing continues

**Symptom and cause:** An Anthropic `error` event was surfaced as raw JSON and the parser continued, allowing a later terminal event to produce a successful finish.

**Fix:** Error events are converted to `AiApiCallError` with response metadata and terminate stream parsing.

**Regression evidence:** [`anthropic_provider_test.dart`](../../packages/ai_sdk_anthropic/test/anthropic_provider_test.dart) asserts typed error metadata and no later finish. The test is the durable regression for the reproduced protocol error.

### 10. Five provider streams silently accept premature EOF

**Symptom and cause:** Anthropic, Google, Cohere, Ollama, and OpenAI-compatible parsers closed successfully when a 2xx body ended before each protocol’s terminal event. Shared OpenAI/Azure/Groq/Mistral Chat paths inherit the compatible adapter behavior.

**Fix:** Parsers emit typed truncation errors on clean EOF before their terminal (`message_delta.stop_reason`, candidate finish, `message-end`, `done: true`, or a finish reason, with optional trailing `[DONE]`). `[DONE]` alone only stops reading and is not a successful terminal. Empty bodies and partial content are errors; valid terminal-only responses remain empty finishes. Cancellation stays quiet and trailing-usage handling remains intact.

**Regression evidence:** [`anthropic_provider_test.dart`](../../packages/ai_sdk_anthropic/test/anthropic_provider_test.dart), [`google_provider_test.dart`](../../packages/ai_sdk_google/test/google_provider_test.dart), [`stream_framing_test.dart`](../../packages/ai_sdk_cohere/test/stream_framing_test.dart), [`stream_framing_test.dart`](../../packages/ai_sdk_ollama/test/stream_framing_test.dart), and [`openai_compatible_chat_language_model_test.dart`](../../packages/ai_sdk_openai_compatible/test/openai_compatible_chat_language_model_test.dart) cover empty and partial EOF, valid terminal-only responses, cancellation, and trailing usage. The five affected package suites passed together (352 tests including the two active-subscriber regressions).

### 11. Ollama drops non-text tool-result content

**Symptom and cause:** The serializer selected text parts from rich tool-result content and silently discarded images/files/source parts, changing the submitted tool result.

**Fix:** Ollama now rejects non-text tool-result parts with `UnsupportedError` before dispatch.

**Regression evidence:** [`ollama_provider_test.dart`](../../packages/ai_sdk_ollama/test/ollama_provider_test.dart) verifies the unsupported content fails and the server was never called.

### 12. Remote same-ID continuation loses prior assistant history

**Symptom and cause:** A stream start reusing an existing assistant message ID cleared the reducer’s parts and tool indexes. Continuation output for an already known tool call could fail as “output without input,” while earlier text, call, approval, and metadata were discarded. The first repair also needed to preserve continuation position, custom part IDs and extra fields, and reset-step boundaries; it must not reindex completed text/reasoning IDs as active IDs.

**Fix:** The reducer retains and indexes existing assistant state, merges continuation metadata, and replaces duplicate result data in place while preserving the continuation position, custom IDs/extras, and reset-step history. Completed text/reasoning parts are retained without treating their IDs as active stream IDs.

**Regression evidence:** [`remote_continuation_history_test.dart`](../../packages/ai_sdk_remote/test/remote_continuation_history_test.dart) retains original text/call/approval and checks repeated output updates do not duplicate results. It verifies that reusing a completed text wire ID does not replace its content and that reset-step retains earlier history. The 275-case remote SSE sweep verifies UTF-8 framing and complete text.

### 13. An acknowledged MCP subscription disappears on response EOF

**Symptom and cause:** After `subscriptions/listen` returned its acknowledgement, an EOF on its SSE response removed the stream. No caller was waiting for the acknowledgement anymore, so the registered resource listener silently stopped receiving updates. Reconnect handling also needed to bound subscription lifetime state, distinguish attempts with tokens, suppress stale streams, and surface errors that occur before acknowledgement.

**Fix:** The transport reopens acknowledged subscriptions after EOF/errors with bounded exponential backoff and bounded lifetime state. Attempt tokens suppress stale stream events; cancellation/close prevents late acknowledgements from reviving subscriptions, while errors before acknowledgement are delivered to the pending caller.

**Regression evidence:** [`modern_subscription_lifecycle_test.dart`](../../packages/ai_sdk_mcp/test/modern_subscription_lifecycle_test.dart) covers EOF recovery, repeated EOF backoff, cancellation during reconnect startup, and close during backoff.

### 14. MCP HTTP 400 tool rejection is labeled ambiguous completion

**Symptom and cause:** `tools/call` wrapped all transport exceptions as ambiguous when a retry did not occur. An explicit HTTP request rejection therefore lost its transport-error identity inside the generic ambiguity wrapper.

**Fix:** Selected standard rejection status codes preserve their `MCPTransportException`; HTTP 408 and unclassified statuses remain ambiguous, and the client does not automatically replay an ambiguous call. The status alone is not presented as proof about remote side effects.

**Regression evidence:** [`replay_safety_test.dart`](../../packages/ai_sdk_mcp/test/replay_safety_test.dart) and [`mcp_protocol_edges_test.dart`](../../packages/ai_sdk_mcp/test/mcp_protocol_edges_test.dart) cover rejection handling and preserve timeout/unknown-status ambiguity.

### 15. The JavaScript reference backend reuses assistant IDs across turns

**Symptom and cause:** The fixture used one constant assistant message ID and tool-call/approval IDs. A new user turn could replace the previous assistant turn in the reducer.

**Fix:** New turns receive fresh IDs; only a real same-assistant approval continuation reuses its IDs.

**Regression evidence:** [`server.test.mjs`](../../examples/remote_backend/js/server.test.mjs) checks fresh IDs on ordinary and post-approval turns. The HTTP/native-browser baseline demonstrated two users but only one assistant message before the fix. Browser captures: [before](assets/reliability-remote-before.png) and [after](assets/reliability-remote-after.png).

### 16. Anthropic thinking budget can exceed `max_tokens`

**Symptom and cause:** Portable reasoning could derive an xhigh thinking budget from the default 4096-token ceiling that exceeds the request’s default `max_tokens` of 1024; Anthropic requires the thinking budget to be strictly smaller.

**Fix:** Generated legacy reasoning uses a compatible default maximum; explicit budgets get a maximum above the budget when unspecified; explicit maxima at/below the budget fail before dispatch; larger explicit maxima are preserved. Validation is within the cancellation scope.

**Regression evidence:** [`audit_reasoning_budget_test.dart`](../../packages/ai_sdk_anthropic/test/audit_reasoning_budget_test.dart) captures both generate and stream bodies, tests explicit budgets/defaults and max preservation, and verifies invalid boundaries do not dispatch.

### 17. The 3.0 changelog headings replaced existing 2.0 history

**Symptom and cause:** The existing 2.0 V4-migration entries were relabeled 3.0, so package history lost its published 2.0 record and the new heading repeated the old release notes.

**Fix:** For the 13 packages that existed in 2.0, changelog history from `origin/main` is restored verbatim under `## 2.0.0`; a separate `## 3.0.0` section now describes the v3-specific additions and applicable reliability fixes. Conversation, JSON Schema, remote, realtime, and telemetry did not exist in 2.0, so no 2.0 history was invented. The realtime preview qualification banner remains in place.

**Regression evidence:** Compared each restored history with `git show origin/main:packages/<package>/CHANGELOG.md`; reviewed new release notes against the v3 branch changes and accepted fix reports. This is a documentation correction, not a runtime bug.

### 18. JSON Schema `maxNodes` does not bound broad traversal work

**Symptom and cause:** The validator enumerated and queued all children in a wide map/list before applying its node limit. A value configured for eight nodes could still cause reads of 2,048 siblings.

**Fix:** The validator checks the remaining node budget as it enqueues children and validates map keys during bounded entry traversal.

**Regression evidence:** [`json_schema_resource_bounds_test.dart`](../../packages/ai_sdk_json_schema/test/json_schema_resource_bounds_test.dart) counts lazy-list reads and covers wide maps, wide lists, and an exact-limit value. The JSON Schema suite passed in the core fix report.

### 19. Google prompt-level safety block loses content-filter finish

**Symptom and cause:** A response with only `promptFeedback.blockReason` and no candidates had no candidate-level finish reason. Generation returned `unknown` and streaming closed without a finish.

**Fix:** Candidate-less prompt blocks now produce an empty finish with the raw block reason; known safety/content block reasons map to `contentFilter`. Candidate finish mapping is unchanged.

**Regression evidence:** [`audit_empty_safety_response_pass2_test.dart`](../../packages/ai_sdk_google/test/audit_empty_safety_response_pass2_test.dart) covers generation, empty blocked streams, known block reasons, and candidate-terminal behavior.

### 20. Existing iOS E2E assertion expects an unsupported Retry action

**Symptom and cause:** A historical hosted iOS run failed only because the error-only fixture’s backend did not advertise retry support, while the integration test expected a Retry button. The product correctly hid that unsupported action; this was a stale test assertion, not a runtime retry defect.

**Fix:** The error-only integration case now expects no Retry action; a separate local-backend test continues to verify that supported retry works. The flow also checks a normal second turn and a post-approval new turn.

**Regression evidence:** The historical hosted iOS run `36851825587` establishes the old assertion failure. The changed test is [`conversation_e2e_test.dart`](../../examples/flutter_chat/integration_test/conversation_e2e_test.dart). Hosted simulator results and screenshots are recorded in the PR checks/artifact bundle; this Linux environment cannot run the simulator workflow locally.

### 21. An aborted partial JS HTTP request can crash the fixture process

**Symptom and cause:** An aborted client caused `ECONNRESET` to escape `for await (const chunk of request)` from the async request handler, terminating the Node process.

**Fix:** The fixture treats `ECONNRESET` as expected only when the request was aborted and returns from that handler; other request errors remain visible. The server accepts a configurable port for isolated tests.

**Regression evidence:** [`server.test.mjs`](../../examples/remote_backend/js/server.test.mjs) aborts a partial request body and verifies a subsequent request succeeds. The original socket probe reproduced the crash and a paced 182-cut sweep passed with a subsequent request accepted. The fixture’s 3 tests passed locally on Node 24.21; hosted CI uses Node 22, and its result belongs in the PR checks/artifact bundle.

### 22. Chained Flutter approvals lose earlier replay results and history

**Symptom and cause:** When the first resumed model step requested a second approval, the controller built the next replay snapshot from only that step. Earlier assistant text, tool calls, and completed results could be missing from the later prompt or persisted conversation, breaking the call/result pairing across a multi-approval turn.

**Fix:** The controller merges tool results from resumed response history into the live assistant message, deduplicates by tool-call ID, retains denial metadata, and builds the next replay snapshot from the complete assistant message.

**Regression evidence:** [`conversation_controller_test.dart`](../../packages/ai_sdk_flutter_ui/test/conversation_controller_test.dart) contains a three-step/two-approval regression. It verifies earlier text/calls, one result per call, the later provider prompt, and a subsequent user turn. The final controller/retry/approval focused Flutter suite passed 43 tests.

### 23. Restoring between chained approvals reruns completed tools

**Symptom and cause:** Restoring a persisted conversation while a later tool approval was pending reconstructed the replay snapshot with approvals for calls whose non-preliminary results were already present. Accepting the remaining approval then executed a previously completed tool again; the deterministic probe observed the tool execution sequence `[first, first, second]` instead of `[first, second]`.

**Fix:** `_restorePendingApproval` filters approvals whose call IDs already have completed, non-preliminary results. An approval that was answered but whose tool has not yet executed remains eligible for replay.

**Regression evidence:** [`conversation_controller_test.dart`](../../packages/ai_sdk_flutter_ui/test/conversation_controller_test.dart) includes `restoring between chained approvals does not rerun completed tools`; it persists/restores between approvals and checks each tool executes once. The test passed with the Flutter UI suite.

## Audit limits and outstanding qualification

Companion regressions cover conversation chronology, denial-error metadata, and stable remote IDs. Findings #22 and #23 cover the chained-approval history and restore-replay issues. Review follow-up also caught and fixed a reused completed-text wire ID issue in remote continuation handling. The spec review confirmed that the completed-tool replay issue in #23 is resolved.

No live provider requests were made; provider acceptance still requires credentials and canary qualification. This Linux environment cannot run the iOS simulator workflow or Android SDK checks. The headless Flutter semantics/text-input mismatch also reproduced in a plain Flutter `TextField` with no SDK imports; native pointer and keyboard input passed, so no SDK workaround was made. Realtime remains preview-qualified and unpublished pending transport, device, and lifecycle qualification.
