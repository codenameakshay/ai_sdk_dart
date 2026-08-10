# MCP Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MCP initialization, subprocess lifecycle, resources, errors, and remote transport conform to current Streamable HTTP MCP behavior.

**Architecture:** JSON-RPC message types own request/notification semantics. Transports own framing and lifecycle; `MCPClient` owns capability negotiation and resource/tool APIs.

**Tech Stack:** Dart IO and `package:http`, JSON-RPC 2.0, MCP 2025-06-18, `package:test` fake servers.

---

### Task 1: JSON-RPC notifications

**Files:**
- Modify: `packages/ai_sdk_mcp/lib/src/json_rpc.dart`
- Modify: `packages/ai_sdk_mcp/lib/src/transport.dart`
- Modify: `packages/ai_sdk_mcp/lib/src/mcp_client.dart`
- Test: `packages/ai_sdk_mcp/test/mcp_conformance_test.dart`

- [ ] Add a failing initialization test whose server returns `202` for `notifications/initialized` and assert initialization completes without waiting for a JSON body.
- [ ] Add `JsonRpcNotification`, serialize it without `id`, and add a transport notification operation that has no response future.
- [ ] Send `notifications/initialized` through that operation and run the MCP suite.
- [ ] Commit the protocol-correct notification model.

### Task 2: Stdio lifecycle

**Files:**
- Modify: `packages/ai_sdk_mcp/lib/src/stdio_transport_io.dart`
- Test: `packages/ai_sdk_mcp/test/fixtures/echo_stdio_server.dart`
- Test: `packages/ai_sdk_mcp/test/mcp_conformance_test.dart`

- [ ] Add failing tests for child exit with an outstanding request and explicit close with outstanding requests.
- [ ] Monitor exit code and bounded stderr, atomically fail all pending completers, cancel readers, and prevent new sends after close.
- [ ] Verify each pending call fails once and promptly; commit.

### Task 3: Safe HTTP errors and resource coalescing

**Files:**
- Modify: `packages/ai_sdk_mcp/lib/src/http_transport.dart`
- Modify: `packages/ai_sdk_mcp/lib/src/json_rpc.dart`
- Modify: `packages/ai_sdk_mcp/lib/src/mcp_client.dart`
- Test: `packages/ai_sdk_mcp/test/mcp_conformance_test.dart`

- [ ] Add a failing test with a secret-sized response body and assert `toString()` excludes it.
- [ ] Preserve status/method and bounded redacted context in typed transport errors.
- [ ] Add a failing burst-update test and assert one resource read is in flight per URI plus at most one trailing refresh.
- [ ] Implement per-URI in-flight/trailing state and commit.

### Task 4: Streamable HTTP transport

**Files:**
- Replace remote transport implementation in `packages/ai_sdk_mcp/lib/src/http_transport.dart`
- Modify: `packages/ai_sdk_mcp/lib/src/mcp_client.dart`
- Modify: `packages/ai_sdk_mcp/lib/ai_sdk_mcp.dart`
- Test: `packages/ai_sdk_mcp/test/mcp_conformance_test.dart`
- Test: `packages/ai_sdk_mcp/test/mcp_coverage_test.dart`

- [ ] Build a deterministic fake Streamable HTTP server that supports JSON POST responses, SSE POST responses, session creation, GET event streams, DELETE termination, and resumable event IDs.
- [ ] Add failing tests for required Accept headers, negotiated `MCP-Protocol-Version`, `Mcp-Session-Id`, server notifications, cancellation, reconnect with `Last-Event-ID`, and session termination.
- [ ] Implement `StreamableHttpClientTransport` using the existing web-safe HTTP dependency.
- [ ] Negotiate the current protocol version during initialize and attach it to subsequent requests.
- [ ] Remove `SseClientTransport`, its fixtures, exports, examples, and legacy documentation instead of preserving an alias.
- [ ] Run MCP tests on VM and web-compatible analysis; commit.

### Task 5: MCP documentation and conformance fixtures

**Files:**
- Modify: `packages/ai_sdk_mcp/README.md`
- Modify: `packages/ai_sdk_mcp/example/example.md`
- Modify: `packages/ai_sdk_mcp/CHANGELOG.md`
- Modify: `packages/ai_sdk_dart/test/conformance/specs/mcp.json`

- [ ] Replace every legacy HTTP+SSE example with Streamable HTTP lifecycle examples.
- [ ] Document notification, session, cancellation, and credential-header behavior.
- [ ] Update the conformance fixture to require the new transport and removal of the old export.
- [ ] Run package tests and documentation snippet analysis; commit.

