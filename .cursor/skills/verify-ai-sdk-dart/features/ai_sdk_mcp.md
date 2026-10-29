# ai_sdk_mcp

The Model Context Protocol client for AI SDK Dart. A developer connects `MCPClient` to an MCP server over Streamable HTTP or stdio, discovers the server's tools as a `ToolSet`, and passes that set to `generateText` or `streamText`. The client also reads prompts and resources, handles auth hooks, and reports lost tool responses as `MCPAmbiguousToolCompletionException`. It has two protocol strategies: legacy (`2025-06-18`) and modern (`2026-07-28`).

## Sub-features

- `mcp-handshake` runs the legacy `initialize` request with protocol `2025-06-18`, sends `notifications/initialized`, reuses `Mcp-Session-Id` and `MCP-Protocol-Version`, opens the `GET` listener, and sends `DELETE` on `close()`. A second `initialize()` call does nothing.
- `mcp-protocol-modes` selects `MCPProtocolMode.legacy` or `MCPProtocolMode.modern`. Modern mode probes `server/discover`, adds `_meta` protocol metadata and `Mcp-Method`/`Mcp-Name` headers, uses no session, and rejects results without `resultType`. A server that picks another protocol version fails `initialize` with `MCPException`. A modern `tools/call` can return `MCPInputRequiredResult`, and `requestState` plus `inputResponses` complete it.
- `mcp-tool-discovery` returns every tool from `tools()`, follows `nextCursor` across pages, and rejects a repeated cursor.
- `mcp-tool-calls` makes `callTool` join text parts, keep non-text content as a list, return a structured-only result as the raw map, and throw `MCPException` for `isError` results and JSON-RPC errors.
- `mcp-generate-text` passes the discovered `ToolSet` to `generateText`. The MCP server receives `tools/call` and the result goes back to the model as a `tool` message.
- `mcp-http-responses` reads `application/json` and `text/event-stream` replies, and delivers `notifications/progress` to `client.progress` when `callTool` gets a `progressToken`.
- `mcp-http-session` starts a new session and replays the request when a `404` answers a request that carries `Mcp-Session-Id`.
- `mcp-failure-handling` raises `MCPAmbiguousToolCompletionException` for a lost `tools/call` response or an HTTP `408`, and does not replay it. A definite `400` stays `MCPTransportException`. `retryOnTransportFailure` with an `MCPReconnectPolicy` replays the call. `MCPReconnectPolicy` with `transportFactory` reconnects a read-only request on a fresh transport, and `delayFor` grows to its cap.
- `mcp-http-listener` delivers server notifications from the `GET` listener on `transport.notifications`, resumes with `Last-Event-ID`, and waits longer before each reconnect (`listenerReconnectDelay`, then double).
- `mcp-prompts-resources` covers `listPrompts`, `getPrompt`, `listResources`, `readResource`, `readResourceContents` and `subscribeResource` with a pushed `notifications/resources/updated`.
- `mcp-auth` sends `MCPAuthConfiguration` bearer tokens, refreshes on `401` only with `retryAfterUnauthorized`, discovers metadata with `MCPAuthDiscovery`, and validates issuer, resource and redirect URI.
- `mcp-stdio` runs `StdioMCPTransport` against the pinned TypeScript SDK server: handshake, discovery, Unicode calls, tool errors, `close()` and process failures.

## How to get to it (user POV)

- Remote server: `MCPClient(transport: StreamableHttpClientTransport(url: ..., headers: ..., auth: ...), protocolMode: ...)`, then `initialize()`, `tools()`, `callTool(...)`, `close()`.
- Local server: `MCPClient(transport: StdioMCPTransport(command: 'node', args: [...]))`.
- Use the tools: `generateText(model: ..., tools: await client.tools(), maxSteps: 3)`.
- Other reads: `listPrompts`, `getPrompt`, `listResources`, `readResource`, `subscribeResource`.
- A custom transport implements `MCPTransport`. Those checks run in the package's own tests.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. HTTP checks use an in-process JSON-RPC fixture server. The `stdio-*` checks start `node` with `examples/mcp_reference/js/server.mjs` and need the pinned SDK in `examples/mcp_reference/js/node_modules` (install it with `make test-mcp-reference`). They skip when it is missing.

- **All checks.** Run `$V run ai_sdk_mcp`. Output `20 passed, 0 failed, 0 skipped`.
- **Legacy handshake.** Run `$V run ai_sdk_mcp --check http-legacy-handshake`. In `ai_sdk_mcp/http-legacy-handshake.json`, `observed.requests` lists three `POST`, one `GET` and one `DELETE` (initialize, initialized and `tools/list`; the listener; close). The `initialize` exchange has `requestBody.params.protocolVersion` `2025-06-18` and no session header. Later exchanges have `mcp-session-id: sess-1`.
- **Protocol negotiation.** Run `$V run ai_sdk_mcp --check protocol-negotiation`. `observed['legacy mismatch.error']` names the unsupported `2024-11-05`. `observed['modern mismatch.error']` says the server does not support `2026-07-28`.
- **Modern mode.** Run `$V run ai_sdk_mcp --check modern-mode-http`. `observed.requests` has no `initialize`, `GET` or `DELETE`. The first exchange is `server/discover` with `_meta` and header `mcp-method: server/discover`. The `tools/call` exchange has `mcp-name: echo`.
- **Input required.** Run `$V run ai_sdk_mcp --check modern-input-required`. `observed.requestState` is `state-1`. The second `tools/call` body carries `requestState` and `inputResponses`. `observed.second` is `confirmed:accept`.
- **Pagination.** Run `$V run ai_sdk_mcp --check tools-pagination`. `observed.cursors` is `[null, c1, c2]` and `observed.toolNames` is `[alpha, beta, gamma]`.
- **Tool results.** Run `$V run ai_sdk_mcp --check tool-results`. `observed.joined` is `line one\nline two`. `observed.mixed` keeps the image part. `observed.structured` holds `structuredContent`. Both error cases appear as `observed['isError result.error']` and `observed['JSON-RPC error.error']`.
- **generateText with MCP tools.** Run `$V run ai_sdk_mcp --check generate-text-mcp-tools`. The `exchanges` hold two chat requests and one MCP `tools/call` with `arguments: {text: hello mcp}`. The second chat request ends with a `tool` message for `call_mcp_1` that contains `echo:hello mcp`. `observed.text` is the final answer.
- **SSE and progress.** Run `$V run ai_sdk_mcp --check sse-response-progress`. The `tools/list` exchange has `responseContentType` `application/json` and the `tools/call` exchange has `text/event-stream`. `observed.progress` lists updates 1 and 2 for `task-1`.
- **Session expiry.** Run `$V run ai_sdk_mcp --check session-expiry-recovery`. `observed.posts` shows a second `initialize@-` after the `404`, then `tools/call@sess-2`.
- **Ambiguous completion.** Run `$V run ai_sdk_mcp --check ambiguous-tool-completion`. `observed.lost` has `toolName: lost`, a `requestId` equal to the wire id, and `cause: MCPTransportException`. The dropped exchange has `error: connection dropped before any response`. `observed.rejectStatus` is `400`.
- **Opt-in retry.** Run `$V run ai_sdk_mcp --check retry-on-transport-failure`. `observed.recovered` is `echo:safe read` and the server saw two `tools/call` requests for it.
- **Reconnect.** Run `$V run ai_sdk_mcp --check reconnect-policy`. `observed.methods` has two `initialize` and two `tools/list` requests. `observed.delaysMs` is `[100, 200, 350, 350]`.
- **Listener.** Run `$V run ai_sdk_mcp --check listener-resume-backoff`. `observed.lastEventIds` is `[null, evt-7, evt-7, evt-7]`. `observed.getAtMs` has gaps of at least 40, 80 and 160 ms.
- **Prompts and resources.** Run `$V run ai_sdk_mcp --check prompts-and-resources`. The `prompts/get` body has `arguments: {text: hello}`. `observed.blobParts` is `2`.
- **Resource subscription.** Run `$V run ai_sdk_mcp --check resource-subscription-push`. The exchanges show `resources/subscribe`, a `GET` stream with the pushed event, `resources/read`, then `resources/unsubscribe`. `observed.update` is `version 1`.
- **Auth refresh.** Run `$V run ai_sdk_mcp --check auth-bearer-refresh`. `observed.authorization` is `[Bearer stale-token, Bearer fresh-token]` (the harness redacts the header values in `exchanges`, but the fixture saw them).
- **Auth discovery.** Run `$V run ai_sdk_mcp --check auth-discovery`. `observed.requestPaths` shows the path-insertion request, the root fallback, the `WWW-Authenticate` hint and the authorization-server request.
- **Stdio handshake and tools.** Run `$V run ai_sdk_mcp --check stdio-reference-handshake-tools`. `observed.stdioFrames` lists the JSON-RPC frames in both directions. The server replies with `serverInfo.name` `dart-sdk-reference` and protocol `2025-06-18`.
- **Stdio calls.** Run `$V run ai_sdk_mcp --check stdio-reference-calls`. `observed.results` is `[echo:snow ☃, echo:after]`, and the failure frame has `isError: true`.
- **Stdio close and failures.** Run `$V run ai_sdk_mcp --check stdio-close-and-failures`. `observed.childExitCode` shows the child ended after `close()`. The error observations name `Failed to start stdio MCP process` and `exited with code 3`.

## Gotchas

- Not covered: modern `subscriptions/listen` streaming and its reconnect: it needs a long-lived SSE POST with acknowledgements. The package tests cover it with a fake transport.
- Not covered: the 30 second default request timeout and the `notifications/cancelled` it sends: the check would need a 30 second wait or a custom timeout hook. `requestTimeout` is set to 5 seconds here.
- Not covered: the 1 MiB stdio frame cap and the web stub (`UnsupportedError`): they need an oversized child process and a web build.
- Not covered: an injected `http.Client`: the verify driver has no `package:http` dependency.
- Not covered: the `io.modelcontextprotocol/tasks` extension and cache hints: the package does not implement them (see its README).
- Not covered: the modern strategy against the TypeScript reference server: the pinned SDK 1.30.0 serves legacy only.
- `tools()` builds each tool with `dynamicTool`. The model gets the tool name and description, but not the MCP `inputSchema` (`parameters` is `{type: object}`). The `generate-text-mcp-tools` check records this in its notes. Put argument names in the tool description, as `examples/basic/lib/mcp_demo.dart` does.
- A structured-only result (empty `content` plus `structuredContent`) comes back as the raw result map. When `content` is present, `structuredContent` is dropped.
- The lost-response check uses a local server that destroys the socket. The harness fixture server cannot drop a connection.
- Fixture MCP replies follow the public MCP JSON-RPC shapes from the spec and the package tests. They prove the client mapping. The stdio checks are the interoperability proof for the legacy path.
