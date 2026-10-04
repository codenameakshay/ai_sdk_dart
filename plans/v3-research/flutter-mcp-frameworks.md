# v3.0.0 Flutter, MCP, and framework-readiness research

This is a read-only readiness plan for the Flutter UI and MCP surfaces. It uses
the repository's `improve` audit playbook (sections 1, 3, 4, 5, 7, and 9) and
separates confirmed implementation gaps from proposals that require a v3
decision. Effort is coarse: S is hours, M is roughly a day, and L is multiple
days including tests and documentation.

## Current shape and constraints

The UI package is deliberately a Flutter-native replacement for Vercel AI SDK
hooks. `ChatController`, `CompletionController`, and `ObjectStreamController`
are `ChangeNotifier`s over `ToolLoopAgent`/core streams; `StreamingControllerBase`
adds request-id guards and three frame-coalescing notifiers
(`packages/ai_sdk_flutter_ui/lib/src/streaming_controller_base.dart:6-81`).
`AiChatScaffold` composes the message list, status/metadata panels, approvals,
scroll affordance, and composer without owning business logic
(`packages/ai_sdk_flutter_ui/lib/src/widgets/ai_chat_scaffold.dart:39-61`).

MCP already has a public transport seam, Streamable HTTP, native stdio, session
handling, pagination, resource subscriptions, and optional reconnect
(`packages/ai_sdk_mcp/lib/src/json_rpc.dart:161-181`,
`packages/ai_sdk_mcp/lib/src/mcp_client.dart:157-225`, `:495-530`). The current
MCP parity gap is live tool-output streaming; reconnect and server-pushed
resource notifications are implemented (`docs/v6-parity-matrix.md:95-103`).

The repository explicitly rejected the JS UI-message-stream transport and
framework glue in ADR 0002 (`docs/adr/0002-v6-parity-scope.md:10-27`). Any
interoperability layer below is therefore a new v3 decision proposal, not an
unquestioned parity fix.

Primary references checked:

- Flutter architecture guide: <https://docs.flutter.dev/app-architecture/guide>
- Flutter performance best practices: <https://docs.flutter.dev/perf/best-practices>
- Flutter accessibility guidance: <https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility>
- Dart concurrency: <https://dart.dev/language/concurrency>
- MCP architecture: <https://modelcontextprotocol.io/specification/2026-07-28/architecture>
- MCP authorization: <https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization>
- MCP resources/subscriptions: <https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions>
- Current MCP specification (retrieved 2026-09-23): <https://modelcontextprotocol.io/specification/latest> resolves to `2026-07-28`; changelog: <https://modelcontextprotocol.io/specification/2026-07-28/changelog>
- MCP Apps extension (page modified 2026-09-02): <https://modelcontextprotocol.io/extensions/apps/overview>
- A2A current official docs: <https://a2a-protocol.org/latest/specification/>; latest GitHub release retrieved 2026-09-23: `v1.0.1` (2026-05-28), <https://github.com/a2aproject/A2A/releases/latest>
- AI SDK UI stream protocols: <https://ai-sdk.dev/docs/ai-sdk-ui/stream-protocol>
- Riverpod onboarding: <https://riverpod.dev/docs/introduction/getting_started>
- Bloc onboarding: <https://bloclibrary.dev/getting-started/>

## Findings, ordered by leverage

### [ARCH-01] Define a durable typed conversation model before adding persistence

- **Evidence**: `packages/ai_sdk_flutter_ui/lib/src/chat_controller.dart:78-149` stores an in-memory `List<ModelMessage>` plus latest-turn metadata; `packages/ai_sdk_flutter_ui/lib/src/chat_controller.dart:189-203` appends turns directly and has no serialization, stable message ID, or persistence boundary. `examples/flutter_chat/lib/main.dart:22-67` restores only the selected navigation index. `CONTEXT.md:72-75` records that the web UI-message stream is intentionally absent.
- **Impact**: A production app cannot safely restore a conversation, reconcile a server acknowledgement, paginate history, deduplicate a retried turn, or preserve tool/reasoning/source/approval parts across process death. Treating `ModelMessage.content` as the durable record would lose typed parts and streaming lifecycle information.
- **Effort**: L for a design plus implementation; M for a serialization spike and compatibility tests.
- **Risk**: HIGH — changing message identity/part encoding affects controllers, widgets, providers, examples, and any persisted caller data.
- **Confidence**: HIGH for the missing seam; MED for the final schema because product/server requirements are not yet selected.
- **Fix sketch**: Design a versioned, typed conversation envelope with stable turn/message/part IDs, timestamps, status, tool approval state, usage, and provider metadata. Add lossless JSON codecs and explicit migration tests; keep `ModelMessage` as the core wire-independent value while letting a host supply persistence.

Acceptance targets: round-trip every `LanguageModelV4*Part`, including tool approval request/response, redacted reasoning, source/file/image parts, and partial structured output; restore an interrupted turn into a deterministic terminal or resumable state; reject unknown schema versions with a typed error; prove duplicate delivery does not duplicate a message.

### [INTEROP-01] Make Vercel/remote-agent interoperability an explicit v3 option

- **Evidence**: ADR 0002 explicitly omits the UI-message-stream/transport protocol and Node/Edge glue (`docs/adr/0002-v6-parity-scope.md:10-27`); `packages/ai_sdk_flutter_ui/README.md:1-12` assumes the Flutter app owns a `ToolLoopAgent`; `packages/ai_sdk_mcp/lib/src/json_rpc.dart:161-181` exposes only MCP JSON-RPC transports. The official AI SDK protocol reference documents UI Message Stream and Data Stream Protocol/SSE (<https://ai-sdk.dev/docs/ai-sdk-ui/stream-protocol>).
- **Impact**: Teams with a trusted proxy, Vercel AI SDK backend, or remote agent cannot reuse this UI layer without writing an adapter that translates stream events, IDs, attachments, approval states, and errors. Direct provider calls also encourage shipping credentials in apps, despite the package README warning.
- **Effort**: L for a supported transport; M for a spike and compatibility fixture suite.
- **Risk**: HIGH — protocol drift, auth handling, partial-stream recovery, and duplicated semantics can create silent transcript corruption.
- **Confidence**: HIGH that the capability is absent; MED that it belongs in core rather than a companion package.
- **Fix sketch**: Run a design spike for a `RemoteAgentTransport`/`ConversationStream` interface that can consume a documented AI SDK UI stream or an SDK-neutral typed event stream. Keep it optional and separate from direct-provider controllers; decide whether a companion package should own HTTP/SSE and auth.

Acceptance targets: a local reference server emits text, reasoning, tool-call/input/result, approval, source, file, usage, finish, and error events; Flutter renders the same transcript as direct `ChatController`; reconnect/resume tests prove no duplicate IDs; the protocol and security boundary are documented before implementation.

### [MCP-01] Add capability-aware OAuth and secure credential lifecycle

- **Evidence**: `packages/ai_sdk_mcp/lib/src/http_transport.dart:16-18,80-110` accepts caller-supplied static headers and negotiates protocol/session headers; `packages/ai_sdk_mcp/README.md:39-43` warns against long-lived browser/mobile secrets but provides no OAuth implementation or token-refresh interface. `packages/ai_sdk_mcp/lib/src/mcp_client.dart:495-530` retries every failed request under `MCPReconnectPolicy`, while `:592-630` uses the same path for `tools/call`; a lost response after a server-side side effect can therefore replay the call. MCP authorization requires OAuth 2.1/PKCE and metadata-driven authorization (<https://modelcontextprotocol.io/specification/2026-07-28/basic/authorization>).
- **Impact**: A mobile/web client integrating an OAuth-protected MCP server must hand-roll discovery, PKCE, token refresh, secure storage, scope/audience checks, and redacted error handling. Static headers can become stale during long-lived sessions; retrying a request after refresh must not duplicate a non-idempotent tool call.
- **Effort**: L for a companion auth package and conformance harness; M for an injectable token-provider seam plus documentation.
- **Risk**: HIGH — mistakes expose credentials or replay side effects.
- **Confidence**: HIGH for missing auth seam; MED for which OAuth flows each platform can support.
- **Fix sketch**: Add an injectable asynchronous credential provider with expiry/refresh and request-scoped headers, never persisting tokens in the SDK. Add server metadata discovery, PKCE guidance, scope/audience validation, redacted transport errors, and an explicit retry/idempotency policy for `tools/call`; do not silently retry side-effecting calls.

Acceptance targets: tests cover expired-token refresh, concurrent refresh coalescing, cancellation, invalid audience/scope, and no token values in exceptions/logs; `tools/list` may retry, while `tools/call` requires an opt-in idempotency key or returns the original failure without replay; native/web examples use short-lived credentials through a host callback.

### [MCP-02] Finish MCP capability negotiation and live tool-output streaming

- **Evidence**: `packages/ai_sdk_mcp/lib/src/mcp_client.dart:407-452` sends a fixed client capability set and only accepts protocol `2025-06-18`; `packages/ai_sdk_mcp/lib/src/mcp_client.dart:565-630` maps a completed `tools/call` response into a `Tool`; `docs/v6-parity-matrix.md:101-103` marks live tool-output streaming pending. The current official MCP revision is `2026-07-28`, whose changelog removes protocol sessions/`initialize`, replaces HTTP GET/resource subscribe with `subscriptions/listen`, removes `Last-Event-ID` resumability, adds per-request capabilities/extensions, and moves long-running work to the `io.modelcontextprotocol/tasks` extension (<https://modelcontextprotocol.io/specification/2026-07-28/changelog>). Resource push is implemented only for the older `notifications/resources/updated` flow; the client has no typed progress/task/subscription stream.
- **Impact**: Long-running MCP tools appear frozen until completion, cannot expose standard progress or task state, and cannot be rendered by `ToolCallCard` as incremental state. A client that treats the latest standard as interchangeable with the implemented 2025-06-18 session protocol will fail against modern stateless servers. “Live tool output” should not be promised as a base MCP feature: the standard provides progress notifications and the Tasks extension’s durable status/final-result polling, not arbitrary partial tool-result payloads.
- **Effort**: L; compatibility/protocol spike first, then transport/client integration. Supporting both legacy `2025-06-18` and modern `2026-07-28` is a larger L than a one-revision upgrade.
- **Risk**: HIGH — concurrent JSON-RPC responses, notification ordering, cancellation, and partial-result durability are easy to get wrong.
- **Confidence**: HIGH.
- **Fix sketch**: First choose a compatibility policy: pin legacy support, add a dual-era transport, or move to `2026-07-28`. Then model per-request capabilities/extensions, modern stateless Streamable HTTP, `subscriptions/listen`, progress tokens, and the Tasks extension. Expose progress/task events through a typed stream while retaining one-shot `callTool`; label any partial-result protocol as an extension, not MCP core.

Acceptance targets: conformance fixtures cover both `2025-06-18` and `2026-07-28` negotiation, absent/partial capabilities, `Mcp-Method`/`Mcp-Name` headers, stateless requests, `subscriptions/listen` acknowledgements/reconnect, progress notifications, Tasks polling/update/cancel, interleaved requests, and final results; a tool cannot emit two terminal results; the Flutter example renders progress without rebuilding the entire history. Do not call progress a partial tool-output stream unless an extension contract and fixture exist.

### [MCP-03] Choose and test the MCP revision before calling the transport production-ready

- **Evidence**: `packages/ai_sdk_mcp/lib/src/mcp_client.dart:410-451` hardcodes `protocolVersion: '2025-06-18'`, sends `initialize`/`notifications/initialized`, and advertises `resources.subscribe`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:86-108` carries `Mcp-Session-Id`, `MCP-Protocol-Version`, and `Last-Event-ID`; `packages/ai_sdk_mcp/lib/src/http_transport.dart:490-530` opens a GET SSE listener. The official `2026-07-28` changelog says these session, handshake, GET, resource subscribe, and resumability mechanisms were removed, and requires per-request metadata/capabilities plus `Mcp-Method`/`Mcp-Name` headers (<https://modelcontextprotocol.io/specification/2026-07-28/changelog>, <https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http>).
- **Impact**: The shipped client is a conforming legacy client for `2025-06-18`, but modern MCP servers may reject it or require a compatibility fallback. Updating blindly can break existing session-oriented servers, so the exact supported-version policy must be explicit in package docs and tests.
- **Effort**: L for dual-era support; M for a deliberately pinned legacy policy plus docs and a conformance matrix.
- **Risk**: HIGH — transport lifecycle, session semantics, reconnect behavior, and public exceptions change across revisions.
- **Confidence**: HIGH; this is a direct spec/code mismatch, not a speculative bug.
- **Fix sketch**: Add a versioned transport conformance suite before implementation. Test modern stateless Streamable HTTP separately from legacy sessions, then either implement a dual-era fallback or state that v3 remains pinned to 2025-06-18 with a migration path and server compatibility check.

Acceptance targets: fixtures assert exact wire behavior for each supported revision; modern tests verify no `Mcp-Session-Id`, no `Last-Event-ID`, no GET listener, per-request capability metadata, required method/name headers, and `subscriptions/listen`; legacy tests retain current initialize/session behavior; unsupported servers produce an actionable typed error.

### [UI-01] Add framework-neutral controller adapters without coupling the UI package

- **Evidence**: All controllers inherit `ChangeNotifier` (`packages/ai_sdk_flutter_ui/lib/src/streaming_controller_base.dart:10-81`), and examples consume them via `ListenableBuilder` (`examples/flutter_chat/lib/pages/completion_page.dart:87-103`, `examples/advanced_app/lib/pages/provider_chat_page.dart:93-121`). No Riverpod/Bloc integration or adapter interfaces exist. Flutter's architecture guide describes separable view/view-model responsibilities (<https://docs.flutter.dev/app-architecture/guide>); Riverpod and Bloc both provide their own lifecycle/state abstractions.
- **Impact**: Apps already standardized on Riverpod, Bloc, or another state layer must write repetitive listeners, disposal, loading/error projections, and cancellation glue. Adding those frameworks as dependencies would violate the package's dependency-light design (`PRODUCT.md:55-58`).
- **Effort**: M for an adapter SPI and examples; S for cookbook recipes if an SPI is judged unnecessary.
- **Risk**: MED — adapters can accidentally become a second state machine or leak listeners.
- **Confidence**: HIGH for the integration gap; MED that first-party adapters are preferable to recipes.
- **Fix sketch**: Keep `ai_sdk_flutter_ui` framework-free. Stabilize a small controller event/state interface and publish optional `ai_sdk_flutter_ui_riverpod` and `ai_sdk_flutter_ui_bloc` companions, or document tested recipes using `statusListenable`/`contentListenable`; never make Riverpod/Bloc transitive dependencies of the core UI package.

Acceptance targets: Riverpod and Bloc sample apps pass lifecycle tests (provider disposal, route removal, hot replacement), expose separate status/content rebuilds, and have no duplicate subscriptions; core package dependency graph remains unchanged.

### [PERF-01] Benchmark and bound streaming rebuild cost for long histories

- **Evidence**: `ChatMessageList` listens to the whole controller and obtains the complete message list on every notification (`packages/ai_sdk_flutter_ui/lib/src/widgets/chat_message_list.dart:148-198`), while each streaming delta schedules a root/content notification (`packages/ai_sdk_flutter_ui/lib/src/streaming_controller_base.dart:48-70`). `ListView.builder` virtualizes layout, but the parent still rebuilds and re-evaluates row construction/seen-state each token; `_seen` is cleared and repopulated through a post-frame callback (`chat_message_list.dart:177-186`). Flutter's performance guidance emphasizes minimizing unnecessary rebuilds (<https://docs.flutter.dev/perf/best-practices>).
- **Impact**: Long transcripts and high-token-rate models can spend frame time rebuilding the list shell and metadata while users type or tokens arrive. The current coalescing reduces notification volume but has no measured budget or regression guard.
- **Effort**: M for profiling/benchmarks; L if keyed incremental transcript architecture is required.
- **Risk**: MED — aggressive memoization can leave stale streaming rows or break scroll anchoring.
- **Confidence**: MED; verify with profile-mode traces before changing architecture.
- **Fix sketch**: Add a benchmark harness with 10/100/1,000 messages and token rates, record frame build/raster time and memory, then isolate streaming-row updates from stable history using keys/slivers or a transcript model. Preserve pinned-bottom and reduced-motion behavior.

Acceptance targets: define a profile-mode budget (for example, no missed frames at the supported token rate on a declared reference device), publish trace results, and add a regression benchmark for append, stream, approval, and long-history scroll cases.

### [A11Y-01] Close semantic and keyboard/focus gaps in every stateful widget

- **Evidence**: The package has good explicit semantics in `ChatMessageBubble` (`packages/ai_sdk_flutter_ui/lib/src/widgets/chat_message_bubble.dart:53-79`), status live regions in `AiChatScaffold` (`ai_chat_scaffold.dart:286-316`), and source/tool semantics. However, the product requirement explicitly promises WCAG 2.2 AA for message roles, streaming status, approvals, labels, and targets (`PRODUCT.md:90-105`), while several controls rely on default labels and no package-level focus/keyboard traversal contract is documented (`chat_composer.dart:1-209`, `tool_approval_card.dart:1-179`).
- **Impact**: Screen-reader users may hear streaming content repeatedly or miss state transitions; desktop/web keyboard users may not reach approval/send/stop actions in a predictable order. Custom builders can also remove the package's semantics without guidance.
- **Effort**: M including semantics tests and manual audit.
- **Risk**: MED — changing announcements can be noisy or alter host semantics trees.
- **Confidence**: MED; confirm with TalkBack/VoiceOver/web keyboard runs.
- **Fix sketch**: Define semantic contracts for message boundaries, live streaming announcements, tool approval actions, errors, and completion. Add focus traversal, keyboard shortcuts, disabled-state labels, and custom-builder guidance; honor `MediaQuery.disableAnimations` as already done by `AiMotion`.

Acceptance targets: widget tests assert labels/actions/live regions and reduced-motion behavior; manual VoiceOver, TalkBack, and Flutter web keyboard passes cover chat, error, approval, completion, and object-stream flows.

### [DX-01] Add a production integration harness and supported-platform matrix

- **Evidence**: `Makefile`/`AGENTS.md` provide package tests, but examples need provider keys for live flows; `examples/advanced_app/lib/config.dart:1-15` and `examples/flutter_chat/lib/config.dart:1-12` inject keys with `String.fromEnvironment`. The advanced app combines `image_picker`, `record`, and `audioplayers` (`examples/advanced_app/pubspec.yaml:11-24`), while MCP stdio is native-only (`packages/ai_sdk_mcp/lib/src/stdio_transport_stub.dart:3-12`). No single matrix exercises Flutter web, mobile, desktop, remote MCP, expired sessions, or accessibility.
- **Impact**: Contributors can pass unit tests while platform-specific transport, permission, audio, restoration, or stream behavior is broken. Onboarding remains dependent on undocumented device/browser setup and provider credentials.
- **Effort**: M for a fixture-driven harness and matrix documentation; L for hosted device/browser CI.
- **Risk**: LOW-MED — mostly additive, but real-device checks can be flaky and costly.
- **Confidence**: HIGH.
- **Fix sketch**: Add deterministic fake provider/MCP servers and a Flutter integration harness with no secrets. Document capability matrix (web/mobile/desktop/server Dart), permission prerequisites, and which tests require real providers; add profile-mode UI and accessibility smoke checks.

Acceptance targets: one command runs core/UI/MCP tests plus fixture-based Flutter integration tests; CI verifies web compilation and native stdio separately; no test requires an API key; README setup matches the matrix.

## Direction proposals requiring maintainer choice

### [DIRECTION-01] Keep agent-framework and A2A integrations at the edge

The existing `ToolLoopAgent`, `ToolSet`, `MCPTransport`, and provider seam make
an adapter layer cheap (`CONTEXT.md:26-50`, `packages/ai_sdk_mcp/lib/src/json_rpc.dart:161-181`).
The current official A2A documentation describes agent cards, tasks, messages,
artifacts, streaming, and push notifications as a separate agent-to-agent
protocol (<https://a2a-protocol.org/latest/specification/>); the latest official
release retrieved 2026-09-23 is `v1.0.1` (2026-05-28). MCP is a concrete
tool/context standard, not an A2A task protocol. A2A/agent-framework
integration would add identity, task lifecycle, discovery, and streaming
semantics that are not represented in the current domain model. Investigate
only after a real user flow requires remote agent tasks, and prototype an
adapter package around the proposed typed conversation/remote-agent event seam.
Do not add a framework dependency to core or claim broad A2A support from MCP
tool compatibility alone.

### [DIRECTION-02] Treat MCP Apps/UI as a separate capability

Current MCP only discovers tools, prompts, and resources; it has no UI/resource
component model (`packages/ai_sdk_mcp/lib/src/mcp_client.dart:565-837`). The
official MCP Apps extension now describes interactive HTML served through
`ui://` resources, `_meta.ui`, sandboxed iframes, CSP/permissions, and a
postMessage JSON-RPC App Bridge (<https://modelcontextprotocol.io/extensions/apps/overview>,
page modified 2026-09-02). That is a real extension with host support varying
by client, not a reason to treat arbitrary server HTML as Flutter widgets. A
future Flutter host would need a WebView/iframe boundary, origin/CSP policy,
tool consent, lifecycle, and accessibility model. Run a threat-model and
minimal host-rendered card/WebView spike only if a concrete MCP App server is
in scope; keep arbitrary server UI out of the core Flutter widget package.

### [DIRECTION-03] Offer a remote-agent companion package rather than changing direct mode

`PRODUCT.md:15-35` optimizes for fast, polished direct Flutter AI surfaces,
while `CONTEXT.md:72-75` intentionally omits server/framework glue. The least
disruptive v3 path is an opt-in companion package for proxy/remote-agent
transport, typed event decoding, OAuth callbacks, and persistence integration.
The direct provider path should remain dependency-light and continue to work
without a backend.

## Recommended sequence

1. Run the persistence/event-schema and remote-stream interoperability spikes
   together; they define whether a v3 conversation can be local, proxied, or
   both.
2. Add MCP capability negotiation, OAuth/token-provider seams, idempotent retry
   rules, and live tool progress after the transport/event contract is settled.
3. Add framework adapters as companion packages or publish tested recipes,
   followed by accessibility and long-history performance baselines.
4. Finish with the integration matrix and update ADR 0002/parity docs so the
   chosen interoperability boundary is explicit and does not drift.
