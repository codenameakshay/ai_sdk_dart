# Next-Release Hardening Design

## Objective

Ship the next AI SDK Dart release with reliable streaming and tool execution,
modern MCP interoperability, production-grade Flutter interaction states,
reproducible release checks, and a secure path for applications that cannot
safely embed long-lived provider credentials.

The work preserves the provider seam and dependency-light Flutter composition
model. It removes obsolete protocol paths instead of adding compatibility
layers, and it introduces no new package dependencies.

## Scope

### Core stream reliability

- Make Google streaming preserve tool calls and stop sequences exactly as the
  non-streaming path does.
- Flush or reject incomplete Cohere streamed tool calls deterministically.
- Retry only retryable failures, with capped exponential backoff, jitter,
  `Retry-After` support, and timeout-budget awareness.
- Propagate cancellation through Flutter controllers, `ToolLoopAgent`, core
  streaming, providers, and tool execution.
- Supersede stale controller requests so overlapping sends cannot mutate the
  latest UI state.
- Give text-only, full-stream, and structured-output consumers one documented
  error contract without unobserved future failures.
- Replace repeated whole-buffer structured parsing with boundary-aware partial
  parsing, protected by correctness tests and representative benchmarks.
- Split the stream implementation only along proven responsibilities after the
  behavior changes are locked by tests.

### MCP correctness and modernization

- Model JSON-RPC notifications separately from requests; notifications never
  carry an ID and never wait for a response.
- Fail pending stdio requests immediately when the child process exits or the
  transport closes.
- Redact and bound HTTP response details in public exceptions.
- Coalesce resource-update notifications per URI.
- Replace the legacy HTTP+SSE client with MCP Streamable HTTP, including
  protocol-version negotiation, session IDs, resumable SSE event handling,
  cancellation, and explicit lifecycle behavior.
- Keep stdio as the local-process transport. Do not retain the obsolete remote
  HTTP+SSE transport as a fallback.

### Flutter production UX

- Make Stop abort the active model and tool work, not merely local listeners.
- Preserve a reader's scroll position during streaming and pin to the bottom
  only while the reader is already near it.
- Coalesce high-frequency token notifications to at most one visual update per
  frame and limit rebuilding to affected state.
- Render errors, retry actions, pending tool approvals, sources, and tool state
  in the default `AiChatScaffold`, while retaining builder escape hatches.
- Meet the documented WCAG 2.2 AA structural contract: labels for icon-only
  controls, message roles, restrained live-region announcements, focus order,
  touch targets, and reduced-motion behavior.
- Fix example-level stale sources and animation behavior.

### Release engineering and documentation

- Pin the repository and CI to one exact Flutter SDK version.
- Enforce formatting and package-wide lint configuration in CI.
- Make `make test` and coverage include every published package.
- Correct credential, provider, package-version, and controller examples.
- Add compile/smoke coverage for public snippets and primary example flows.
- Reuse provider-owned or injected HTTP clients so repeated calls share
  connection pools and lifecycle configuration.

### Next-release platform capabilities

- Add an asynchronous credential-provider/request-signing seam for proxy,
  brokered, and short-lived credentials; synchronous static API keys remain a
  simple implementation of that seam.
- Introduce the next provider-contract version in stages. First add contract
  fixtures for the behaviors needed from AI SDK 7 (reasoning control, timeout
  scopes, runtime context, approval policy, and telemetry metadata), then move
  core and providers onto the new contract in working increments.
- Do not port web-framework UI transports or server-framework glue that remain
  outside the Dart/Flutter product boundary.

## Architecture

### Cancellation and request ownership

Each core invocation owns one abort controller. `ToolLoopAgent` accepts the
same timeout and abort inputs as `generateText` and `streamText`. Flutter
controllers create an invocation token for each send, abort the preceding
token before replacement, and discard events whose token is no longer active.
Provider adapters map the shared signal to their HTTP client's cancellation
primitive. Tool execution checks the signal before and after asynchronous work.

### Retry policy

A single core retry helper classifies `AiApiCallError.isRetryable`, recognizes
transport failures that are safe to retry, and rejects all other exceptions
immediately. Delay is capped exponential backoff with injectable randomness and
sleep functions for deterministic tests. Server `Retry-After` guidance wins
when it fits within the remaining timeout budget.

### Stream results and structured parsing

The full event stream is the authoritative event/error channel. Derived text,
partial-output, and result futures are fed from that channel and always have an
internal observer, preventing unhandled asynchronous errors. Consumers still
receive the same failure through whichever public result they await.

Structured output parsing tracks whether a new complete structural boundary is
available before invoking JSON decoding. It never emits duplicate partial
objects. Benchmarks cover small, medium, and long incremental JSON streams.

### MCP transport

The JSON-RPC layer exposes request, response, error, and notification messages.
The Streamable HTTP transport uses POST for client messages, accepts JSON or an
SSE response, attaches the negotiated `MCP-Protocol-Version` and session ID,
and maintains the server event stream when instructed. Closing or process exit
atomically fails every pending request.

### Flutter state and rendering

Controllers separate conversation data, generation status, and composer state
into narrowly observable signals while keeping the existing high-level
controller API. Streaming text updates are scheduled once per frame. The chat
list tracks whether it is within a small bottom threshold; only that state
enables automatic pinning. The scaffold composes default error and approval
surfaces that applications can replace with builders.

### Credentials and HTTP lifecycle

Providers receive a reusable transport/client and an asynchronous credential
resolver. Request construction awaits credentials immediately before dispatch,
allowing brokered or rotating tokens. Client applications receive prominent
documentation that long-lived vendor keys do not belong in distributable
mobile or web binaries.

## Error handling

- Cancellation resolves as the SDK's typed abort error and never triggers a
  retry.
- Non-retryable provider errors preserve typed metadata and make one request.
- MCP protocol errors expose status, method, and bounded redacted context, not
  arbitrary response bodies.
- A subprocess exit includes exit code and bounded stderr context, and all
  pending calls fail exactly once.
- UI error state is visible, retryable where safe, screen-reader announced once,
  and cleared only by an explicit retry, reset, or successful new request.

## Verification

- Every behavior change starts with a failing focused test and completes with a
  passing package suite.
- Provider request fixtures verify Google tool calls and stop sequences, Cohere
  finalization, credential resolution, client reuse, and cancellation.
- MCP tests use deterministic fake HTTP/SSE servers and real short-lived stdio
  child processes.
- Flutter widget tests cover stop, supersession, approval, errors, near-bottom
  scrolling, reduced motion, semantics, and rebuild coalescing.
- Repository verification runs formatting, analysis, every package test,
  coverage, example tests, and representative Flutter web builds.
- Final screenshots show the default scaffold's normal, approval, error,
  sources/tool, and long-conversation scroll states and are embedded in the PR.

## Delivery order

1. Reproducible toolchain and complete baseline checks.
2. Core/provider stream correctness and cancellation.
3. JSON-RPC correctness followed by Streamable HTTP replacement.
4. Flutter state, UX, and accessibility improvements.
5. Credential and reusable-client seams.
6. Provider-contract modernization fixtures and incremental migration.
7. Documentation, examples, full verification, screenshots, and PR.

Each stage must leave the repository working. A later capability may depend on
an earlier public seam, but no stage may require an unfinished compatibility
layer or deferred replacement.
