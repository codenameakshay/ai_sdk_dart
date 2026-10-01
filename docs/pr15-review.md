# PR #15 continuation review

**Merge verdict: not safe to merge as currently published.** The corrections
below are local commits only. They have not been pushed, and this review does
not establish hosted CI, live provider, browser, simulator or device
qualification. All 45 confirmed findings are fixed locally.

This review continues the earlier work in
`plans/v3-research/evidence/review/` and `plans/v3-review-checkpoints.md`.
Those records include independent checkpoints through `7aece84` and earlier
`8ccdb0b` and `11155a3` reviews. The requested PR range is `b702929..HEAD`;
this run began at `c197d90` and looked for omissions after the previous fixes.
It did not restart the original 446-file review.

The tables cover all 45 correction commits after `c197d90` through final code
head `d79ce5a`. Both verification fixups were consolidated into their findings.
The tested tree remained identical after consolidation, with tree hash
`5e62be9de5409b9c55cb845d8f63ff2a52ca76c2`. Source locations refer to that final
code tree. P1 denotes potentially repeated or unintended tool
execution; P2 denotes a correctness, lifetime or qualification-gate defect.

## Verified corrections

Each row has a regression exercised locally and independently rerun by the
parent reviewer. The report does not infer a passing test from its presence.
Tests used the existing FVM toolchain and installed dependencies. Changes were
checked with affected tests and package analysis; touched Dart files were
formatted. No dependencies were added. MCP's existing `http` minimum was raised
to 1.6 to match the cancellation API already installed.
No full workspace run or external qualification was performed.
Pinned JavaScript reference tests were skipped where their fixtures were
unavailable; no fixture dependencies were installed. Focused test runs overlap,
so this report does not add their counts into an aggregate total.
Advanced example lifetime checks ran with fake `OPENAI_API_KEY`,
`ANTHROPIC_API_KEY` and `GOOGLE_API_KEY` Dart defines against mocked HTTP clients.
The separate keyless run had explicit skips; it is not substituted for the
fixture-enabled lifetime run. These checks made no live provider calls.

Two execution deviations must be disclosed. One worker's initial Flutter test
invocation omitted `--no-pub` and automatically resolved dependencies. Its output
included `Resolving dependencies`, `Downloading packages` and `Got dependencies`.
There were no resulting pubspec, lockfile or toolchain changes; whether it fetched
artifacts is not established. The user did not authorize that resolution.
Subsequent Flutter invocations used `--no-pub`. A secondary reviewer also used a
scratch copy outside the requested worktree for 29 baseline-reversal checks.
Those checks are excluded from accepted parent verification, and no completed
final secondary-review verdict is claimed.

### Core generation and agents

| Severity and impact | Current source | Regression test and behavior | Local fix commit |
|---|---|---|---|
| P1. Cancellation from the tool-start callback still allowed the tool to execute. Cancellation is now checked before entering the executor. | `packages/ai_sdk_dart/lib/src/core/streaming/tool_execution.dart:314` | `packages/ai_sdk_dart/test/conformance/tool_cancellation_admission_test.dart:8`; generation and streaming cancel in the start callback and execute zero tools. | `350758d fix(core): check cancellation before tool execution` |
| P1. Streaming replay copied a provider-executed result into both assistant and tool history. The duplicate could corrupt continuation or repeat provider work. | `packages/ai_sdk_dart/lib/src/core/stream_text.dart:950` | `packages/ai_sdk_dart/test/conformance/hosted_tool_history_test.dart:8`; hosted results occur once in assistant history and invoke no local executor. | `3f4af3f fix(core): replay hosted tool results only once` |
| P2. Public chronological content omitted local tool results although tool collections and tool-role history contained them. | `packages/ai_sdk_dart/lib/src/core/generate_text.dart:746`; `packages/ai_sdk_dart/lib/src/core/stream_text.dart:976` | `packages/ai_sdk_dart/test/conformance/tool_result_content_test.dart:9`; generation and streaming include one call followed by one result, preserving assistant/tool role separation. | `af8f463 fix(core): include local results in step content` |
| P2. Streaming callbacks lost generation context and updated step instructions, producing different callback behavior from generation. | `packages/ai_sdk_dart/lib/src/core/stream_text.dart:280` | `packages/ai_sdk_dart/test/conformance/stream_callback_context_test.dart:7`; agent start and prepare callbacks receive the original context, and step-start receives updated instructions. | `7236f5d fix(core): forward streaming callback context` |
| P2. A failed stream never settled `finalStep`, leaving callers waiting indefinitely. | `packages/ai_sdk_dart/lib/src/core/stream_text.dart:1166` | `packages/ai_sdk_dart/test/conformance/stream_final_step_failure_test.dart:7`; `text` and `finalStep` reject with the same source error. | `28a3287 fix(core): settle final step on stream failure` |
| P2. A transformed stream's cancellation failure could escape separately or replace its original source failure. | `packages/ai_sdk_dart/lib/src/core/stream_text.dart:549` | `packages/ai_sdk_dart/test/conformance/transformed_stream_cleanup_test.dart:9`; a failing transform and failing cleanup preserve the primary error with no escaped zone error. | `1a2857b fix(core): contain transformed stream cleanup errors` |
| P2. Invalid duplicate approval responses opened an operation scope before validation and retained its cancellation observer. | `packages/ai_sdk_dart/lib/src/core/stream_text.dart:167` | `packages/ai_sdk_dart/test/conformance/stream_validation_lifetime_test.dart:10`; rejected duplicate approvals leave no cancellation listener. | `178f263 fix(core): validate approvals before opening scopes` |
| P2. `ToolLoopAgent.resume` executed approved tools without forwarding execution-start and execution-end callbacks. | `packages/ai_sdk_dart/lib/src/agent/tool_loop_agent.dart:296` | `packages/ai_sdk_dart/test/conformance/approval_resume_callbacks_test.dart:8`; resumed execution reports its call ID, success and output exactly once. | `433861d fix(agent): report resumed tool execution callbacks` |

### Provider adapters

| Severity and impact | Current source | Regression test and behavior | Local fix commit |
|---|---|---|---|
| P2. Chat emitted finish before the trailing empty-choices usage chunk, discarding usage totals and placing later parts after finish. | `packages/ai_sdk_openai_compatible/lib/src/openai_compatible_chat_language_model.dart:380` | `packages/ai_sdk_openai_compatible/test/openai_compatible_chat_language_model_test.dart:452`; trailing usage is included and finish is last. | `49fb159 fix(compatible): retain trailing stream usage` |
| P2. Terminal Responses events emitted finish but kept waiting on an open HTTP body and retained the subscription. | `packages/ai_sdk_openai/lib/src/openai_responses_language_model.dart:589` | `packages/ai_sdk_openai/test/responses_cancellation_test.dart:13`; completed, failed and error events settle and cancel a source that stays open. | `643513d fix(openai): close terminal Responses streams` |
| P2. Cohere and Ollama decoded each network chunk independently and dropped a final line without LF. Split UTF-8 characters failed and valid terminal events vanished. | `packages/ai_sdk_cohere/lib/src/cohere_provider.dart:476`; `packages/ai_sdk_ollama/lib/src/ollama_provider.dart:368` | `packages/ai_sdk_cohere/test/stream_framing_test.dart:11`; `packages/ai_sdk_ollama/test/stream_framing_test.dart:11`; fragmented multilingual UTF-8 and a final event without newline retain text and finish usage. | `1170fb0 fix(providers): decode fragmented NDJSON streams` |
| P2. Chat consumer cancellation without an AbortSignal had no transport token and left a silent response alive. | `packages/ai_sdk_openai_compatible/lib/src/openai_compatible_chat_language_model.dart:218` | `packages/ai_sdk_openai_compatible/test/stream_consumer_cancellation_test.dart:11`; cancelling the consumer cancels the underlying silent body. | `eefa898 fix(compatible): abort cancelled stream consumers` |
| P2. Responses emitted a known message as both canonical text and an opaque raw item. The next request repeated the assistant answer. | `packages/ai_sdk_openai/lib/src/openai_responses_language_model.dart:461` | `packages/ai_sdk_openai/test/responses_message_replay_test.dart:11`; two actual `streamText` turns send one assistant answer on replay. | `65c988c fix(openai): avoid duplicate assistant replay` |
| P2. Schema-free Chat JSON mode sent `json_schema` with a null schema, an invalid wire shape. | `packages/ai_sdk_openai_compatible/lib/src/openai_compatible_chat_language_model.dart:83` | `packages/ai_sdk_openai_compatible/test/json_response_format_test.dart:11`; generation and streaming send exactly `{"type":"json_object"}`. | `d59a2df fix(compatible): send schema-free JSON mode` |
| P2. Anthropic, Google and Cohere retained caller observers when reasoning configuration or request serialization failed before dispatch. | `packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:107`; `packages/ai_sdk_google/lib/src/google_provider.dart:92`; `packages/ai_sdk_cohere/lib/src/cohere_provider.dart:317` | `packages/ai_sdk_anthropic/test/request_serialization_lifecycle_test.dart:10`; `packages/ai_sdk_google/test/request_serialization_lifecycle_test.dart:10`; `packages/ai_sdk_cohere/test/request_serialization_lifecycle_test.dart:10`; generation and streaming failures detach observers, including Anthropic invalid reasoning configuration. | `9a53005 fix(providers): detach failed serialization scopes` |
| P2. OpenAI transcription multipart construction could fail outside cleanup and retain its cancellation listener. | `packages/ai_sdk_openai/lib/src/openai_provider.dart:397` | `packages/ai_sdk_openai/test/openai_observer_lifetime_test.dart:12`; invalid audio media type leaves zero active observers. | `8592b9a fix(openai): clean up failed multipart requests` |
| P2. Anthropic, Google, Cohere and Ollama consumer cancellation without an AbortSignal left silent HTTP bodies active. | `packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:253`; `packages/ai_sdk_google/lib/src/google_provider.dart:306`; `packages/ai_sdk_cohere/lib/src/cohere_provider.dart:392`; `packages/ai_sdk_ollama/lib/src/ollama_provider.dart:284` | `packages/ai_sdk_anthropic/test/stream_consumer_cancellation_test.dart:10`; `packages/ai_sdk_google/test/stream_consumer_cancellation_test.dart:10`; `packages/ai_sdk_cohere/test/stream_consumer_cancellation_test.dart:10`; `packages/ai_sdk_ollama/test/stream_consumer_cancellation_test.dart:10`; consumer cancellation closes the silent underlying source without a caller signal. | `6307ed8 fix(providers): abort cancelled stream consumers` |
| P1. Anthropic mapped disabled tool choice to `auto`, allowing tools when the caller explicitly disabled them. | `packages/ai_sdk_anthropic/lib/src/anthropic_provider.dart:696` | `packages/ai_sdk_anthropic/test/tool_choice_test.dart:11`; generation and streaming send tool choice `none`. | `d4eae1a fix(anthropic): honor disabled tool choice` |
| P2. Google discarded thought signatures attached to ordinary answer text, including an empty terminal text chunk. Replayed history lost required signed continuation data. | `packages/ai_sdk_google/lib/src/google_provider.dart:202`; `packages/ai_sdk_google/lib/src/google_provider.dart:425`; `packages/ai_sdk_google/lib/src/google_provider.dart:875` | `packages/ai_sdk_google/test/text_signature_replay_test.dart:12`; generated and streamed answers retain and resend their signature; line 52 covers an empty signature-bearing terminal chunk. | `d64bc05 fix(google): preserve signed answer text on replay` |
| P1. Google merged distinct same-name calls at the same streamed part index, losing the first call or assigning arguments to the wrong call. | `packages/ai_sdk_google/lib/src/google_provider.dart:462` | `packages/ai_sdk_google/test/tool_call_identity_test.dart:10`; separate call IDs retain their exact inputs and emit separate input-end events. | `4626baf fix(google): preserve distinct streamed tool calls` |

### Conversation, remote, schema, MCP and realtime

| Severity and impact | Current source | Regression test and behavior | Local fix commit |
|---|---|---|---|
| P2. MCP subscriptions cancelled before acknowledgement could be retained after the late acknowledgement, leaving server work active. | `packages/ai_sdk_mcp/lib/src/mcp_client.dart:1195` | `packages/ai_sdk_mcp/test/resource_subscription_lifecycle_test.dart:9`; cancellation before acknowledgement closes the late subscription. | `58c7c66 fix(mcp): cancel subscriptions acknowledged late` |
| P2. Authentic modern subscription acknowledgements did not resolve stdio subscriptions; HTTP accepted missing or mismatched acknowledgement IDs and retained streams after completion. | `packages/ai_sdk_mcp/lib/src/stdio_transport_io.dart:118`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:876`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:913` | `packages/ai_sdk_mcp/test/subscription_acknowledgement_test.dart:10`; valid stdio acknowledgement enables cancellation, malformed acknowledgements cannot settle it, HTTP rejects incorrect metadata/version and closes completed streams. | `089a77a fix(mcp): validate modern subscription acknowledgments` |
| P2. MCP HTTP deadlines did not own auth, the complete response body or the underlying connection. Closing or timing out could leave callers pending, dispatch late requests or leak unread bodies; cleanup errors could mask source failures. | `packages/ai_sdk_mcp/lib/src/http_transport.dart:682`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:695`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:1295` | `packages/ai_sdk_mcp/test/http_request_lifetime_test.dart:10`; six regressions cover invalid-header body cancellation, source/cleanup error preservation, close during auth, socket closure at header deadline, silent-body deadline and auth expiry preventing late dispatch. | `fe8a8a7 fix(mcp): bound and cancel HTTP request lifetimes` |
| P2. Modern HTTP subscription cancellation also sent a legacy-style JSON-RPC cancellation notification. Modern HTTP cancellation must close its subscription response. | `packages/ai_sdk_mcp/lib/src/mcp_client.dart:1210` | `packages/ai_sdk_mcp/test/mcp_protocol_edges_test.dart:605`; strengthened resource-stream cancellation test requires body cancellation and forbids `notifications/cancelled`. | `e5acb93 fix(mcp): use HTTP closure for modern cancellation` |
| P2. Replaced MCP notification listeners could accept late events, retain old responses or reconnect without cancelling the old listener. Delayed old cleanup could also abort its replacement. | `packages/ai_sdk_mcp/lib/src/http_transport.dart:1141`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:1195`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:1248` | `packages/ai_sdk_mcp/test/notification_listener_lifecycle_test.dart:10`; three regressions preserve a replacement during delayed cancellation, reject a late old-session response and cancel the failing old listener before reconnecting. | `1f66ae8 fix(mcp): retire obsolete notification listeners` |
| P2. A null or empty refreshed MCP credential returned the already-drained 401 response, causing a stream-listening error or leaving the caller pending. | `packages/ai_sdk_mcp/lib/src/http_transport.dart:724`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:762` | `packages/ai_sdk_mcp/test/auth_rejection_test.dart:9`; null and empty refresh results reject within the deadline with a sanitized typed 401 and exactly one HTTP send. | `1395322 fix(mcp): preserve unauthorized refresh failures` |
| P1. Sending a new local conversation turn left an earlier approval executable. Approving that stale request could run a tool against the wrong turn. | `packages/ai_sdk_flutter_ui/lib/src/conversation_controller.dart:548` | `packages/ai_sdk_flutter_ui/test/conversation_controller_test.dart:2417`; new send invalidates the earlier approval and executes zero tools. | `51bd77f fix(flutter): invalidate approvals on a new send` |
| P2. Disposed public Flutter controllers and conversation adapters still dispatched requests or modified state, including calls through shared backends. | `packages/ai_sdk_flutter_ui/lib/src/conversation_controller.dart:95`; `packages/ai_sdk_flutter_ui/lib/src/chat_controller.dart:196`; `packages/ai_sdk_flutter_ui/lib/src/completion_controller.dart:87`; `packages/ai_sdk_flutter_ui/lib/src/object_stream_controller.dart:167` | `packages/ai_sdk_flutter_ui/test/conversation_lifetime_test.dart:38`; six cases cover chat, completion, object submission/binding, conversation backend operations and adapter actions after disposal. | `a10095c fix(flutter): reject actions after controller disposal` |
| P2. Simultaneous local or remote sends could start superseded requests after asynchronous interruption, leaving an unreachable active request or publishing the stale user turn. | `packages/ai_sdk_flutter_ui/lib/src/conversation_controller.dart:547`; `packages/ai_sdk_flutter_ui/lib/src/conversation_controller.dart:1414` | `packages/ai_sdk_flutter_ui/test/backend_request_replacement_test.dart:32`; concurrent remote sends create one cancellable transport request, and concurrent local sends publish only the latest turn. | `15a91ca fix(flutter): reject superseded backend requests` |
| P2. An older asynchronous stop cleared subscription fields or loading state belonging to a newer chat, completion or object request. | `packages/ai_sdk_flutter_ui/lib/src/chat_controller.dart:167`; `packages/ai_sdk_flutter_ui/lib/src/chat_controller.dart:533`; `packages/ai_sdk_flutter_ui/lib/src/completion_controller.dart:181`; `packages/ai_sdk_flutter_ui/lib/src/object_stream_controller.dart:219` | `packages/ai_sdk_flutter_ui/test/stream_request_replacement_test.dart:21`; delayed object cleanup and late completion/chat stops preserve the newer stream and its state. | `f618f4c fix(flutter): preserve newer streams during stop cleanup` |
| P2. Remote metadata updates replaced prior metadata and ignored finish metadata, losing nested usage and model details. | `packages/ai_sdk_remote/lib/src/remote.dart:569`; `packages/ai_sdk_remote/lib/src/remote.dart:580` | `packages/ai_sdk_remote/test/message_metadata_test.dart:10`; start, update and finish metadata merge and survive codec restoration. | `119ed52 fix(remote): merge streamed message metadata` |
| P2. Remote non-base64 data URLs were encoded as literal URL text, corrupting percent-encoded file bytes. | `packages/ai_sdk_remote/lib/src/remote.dart:1045` | `packages/ai_sdk_remote/test/file_data_url_test.dart:10`; percent-encoded data URLs restore the original bytes. | `248f08e fix(remote): preserve encoded data URL bytes` |
| P2. Compiled JSON Schema validation referenced the caller's mutable schema. Later mutations silently changed validation behavior. | `packages/ai_sdk_json_schema/lib/ai_sdk_json_schema.dart:55` | `packages/ai_sdk_json_schema/test/validator_snapshot_test.dart:5`; mutating the original nested enum does not alter the compiled validator. | `6112192 fix(schema): snapshot compiled validation input` |
| P1. Conversation restoration coerced malformed execution flags to false, potentially turning provider-executed work into local work. | `packages/ai_sdk_conversation/lib/src/conversation.dart:845`; `packages/ai_sdk_conversation/lib/src/conversation.dart:958` | `packages/ai_sdk_conversation/test/tool_flag_validation_test.dart:22`; restore rejects nonboolean `providerExecuted`, `preliminary` and `isDynamic` values. | `175eef8 fix(conversation): reject malformed tool flags` |
| P2. Remote transient data events entered persisted history and replayed after restart despite their transient contract. | `packages/ai_sdk_remote/lib/src/remote.dart:937` | `packages/ai_sdk_remote/test/transient_data_test.dart:10`; transient data stays out of snapshots and codec-restored history while ordinary data remains. | `9e6b28a fix(remote): exclude transient data from history` |
| P2. Realtime startup subtracted an already-running clock from the timeout, causing immediate or premature expiry when a clock was reused. | `packages/ai_sdk_realtime/lib/src/realtime.dart:698` | `packages/ai_sdk_realtime/test/realtime_clock_test.dart:8`; startup receives its full budget from the current clock reading. | `585606f fix(realtime): start deadlines at the current clock` |
| P2. Cancelling one realtime listener released an audio budget still retained or already delivered to another listener, permitting additional audio beyond the shared budget. | `packages/ai_sdk_realtime/lib/src/realtime.dart:1396` | `packages/ai_sdk_realtime/test/realtime_event_queue_test.dart:10`; cancelling one listener preserves another listener's queued and delivered audio budget. | `cfab0fe fix(realtime): retain shared queued audio budgets` |

### Examples, migration and qualification gates

| Severity and impact | Current source | Regression test and behavior | Local fix commit |
|---|---|---|---|
| P2. Provider canary runs created owned HTTP clients and left them open after failure. | `tool/canaries/provider_canaries.dart:186` | `tool/canaries/provider_client_lifetime_test.dart:9`; failing OpenAI, Anthropic and Google canaries close their owned client once. | `cd80aee fix(canaries): dispose owned provider clients` |
| P2. The ordinary test matrix omitted the basic example's executable lifecycle assertions and the new canary lifetime tests. | `Makefile:120`; `Makefile:121` | `tool/makefile_test.dart:14`; the dry-run matrix includes the assertion-enabled basic lifecycle command; line 25 proves its failure propagates. | `319d9a6 fix(ci): run basic example lifetime checks` |
| P2. Repository format gates excluded Dart tooling, allowing unformatted tooling to pass the documented check. | `Makefile:164`; `Makefile:168` | `tool/makefile_test.dart:7`; `format` and `format-check` dry runs include `tool/`. | `4940aed fix(ci): include tooling in format gates` |
| P2. The migration guide claimed aggregate `result.reasoning` although the API returns final-step reasoning, steering callers toward incomplete history. | `docs/migration/v2-to-v3.md:225` | `packages/ai_sdk_dart/test/migration_reasoning_contract_test.dart:10`; a two-step result demonstrates aggregate reasoning through `steps` and final-step reasoning through `result.reasoning`. | `10f2e77 docs(migration): correct reasoning result scope` |
| P2. README timeout guidance still described a `Duration` shorthand after text and agent APIs changed to `TimeoutConfiguration`, leaving migration callers with a compile error. | `README.md:62`; `README.md:172`; `docs/migration/v2-to-v3.md:69` | `packages/ai_sdk_dart/test/timeout_documentation_test.dart:18`; documented typed timeout examples execute for generation, streaming and agents, while embedding retains its `Duration` deadline. | `47cd2c4 docs: align timeout examples with public types` |
| P2. The advanced tools-chat example retained only assistant text after an approved tool turn, dropping the call/result history needed for the next request. | `examples/advanced_app/lib/pages/tools_chat_page.dart:281` | `examples/advanced_app/test/widget_test.dart:478`; the approved turn's next request contains the exact original tool call and matching result. | `5bf17e4 fix(examples): preserve complete tool chat history` |
| P2. Nine example pages created provider clients without owning their disposal. Removing a page left active provider requests and HTTP clients alive, and late media completion could update removed widgets. | `examples/advanced_app/lib/pages/completion_page.dart:43`; `examples/advanced_app/lib/pages/image_gen_page.dart:81`; `examples/advanced_app/lib/pages/multimodal_page.dart:129`; `examples/advanced_app/lib/pages/provider_chat_page.dart:77`; `examples/advanced_app/lib/pages/stt_page.dart:93`; `examples/advanced_app/lib/pages/tts_page.dart:74`; `examples/flutter_chat/lib/pages/chat_page.dart:40`; `examples/flutter_chat/lib/pages/completion_page.dart:52`; `examples/flutter_chat/lib/pages/object_stream_page.dart:71`; `Makefile:126` | `examples/advanced_app/test/provider_lifecycle_test.dart:31`; `examples/advanced_app/test/media_page_lifetime_test.dart:13`; `examples/flutter_chat/test/provider_page_lifetime_test.dart:16`; removing pages during requests closes the owned client and aborts its request; `tool/makefile_test.dart:36` keeps fixture-enabled media/provider checks in the ordinary gate. | `29bcdcc fix(examples): dispose page-owned provider requests` |
| P2. Recording permission and image-picker callbacks returning after page disposal could restart recording, read a late selected file or call `setState` on a removed widget. | `examples/advanced_app/lib/pages/stt_page.dart:68`; `examples/advanced_app/lib/pages/multimodal_page.dart:38`; `examples/advanced_app/lib/pages/multimodal_page.dart:56` | `examples/advanced_app/test/media_picker_lifetime_test.dart:13`; permission granted/denied and late gallery/camera results finish without errors, recording starts or removed-widget updates. | `d79ce5a fix(examples): ignore media callbacks after disposal` |

## Final local gates

All 45 confirmed findings were corrected locally. No confirmed code finding or
product decision remains open from this run. The parent independently reran the
accepted regressions and affected analysis. The final separate gate results are:

- Advanced example provider, media-request and permission/picker lifetime tests
  passed 21 tests with three fake API-key defines and `--no-pub`.
- Flutter-chat provider-page lifetime tests passed 3 tests with `--no-pub`.
- `fvm dart test tool/makefile_test.dart` passed 5 tests; tooling analysis was clean.
- Formatting the 86 changed Dart files changed zero files.

These counts describe distinct final commands, not an aggregate SDK test count.

## Review coverage and limits

Library code was checked before examples. The audit traced generation and
streaming callers, approval replay, provider-executed results, terminal order,
usage, signal observers, transport cancellation, malformed persistence flags,
metadata restoration, queued realtime events, shared audio budgets and compiled
schema ownership. OpenAI Files and Batch were checked against the earlier
deadline, metadata, submission-file ownership, pagination and JSONL corrections.
Azure-specific endpoint, credential and embedding paths were checked with its
affected shared-adapter tests. No additional verified Files, Batch or Azure
defect was found in this continuation pass.

The absence of a new finding in an inspected area is not a complete protocol or
platform qualification. This run does not claim fresh live canaries, real-model
two-turn acceptance, pinned-reference interoperability across every protocol,
browser execution, RTL device behavior, profile frame/raster measurements or
physical realtime audio proof. Earlier checkpoint evidence was used as review
context, not represented as current external verification. No unresolved product
decision is recorded among the completed fixes.

No push or merge was performed. The current published PR still lacks these
local corrections. Qualification limits remain separate from the completed
code findings. A merge verdict for the corrected PR requires the applicable
qualification evidence for that exact revision.
