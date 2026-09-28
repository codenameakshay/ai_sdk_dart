# basic

Dart CLI examples for [AI SDK Dart](https://github.com/codenameakshay/ai_sdk_dart). No Flutter required.

## Demos

### `lib/main.dart` — v3 feature tour

A concise walk through the v3 public contract. Runs every demo by default, or
pass a demo number to run just one:

```sh
fvm dart run lib/main.dart        # run every demo
fvm dart run lib/main.dart 5      # run only demo 5
```

| # | Demo | API |
|---|------|-----|
| 1 | `generateText` | `instructions`, aggregate `usage` vs `finalStep.usage` |
| 2 | `streamText` | canonical `result.stream` events (switch over event types); `providerStream` for raw provider parts |
| 3 | Lifecycle callbacks | `onStart`, `onStepStart`, `onToolExecutionStart`, `onToolExecutionEnd`, `onStepEnd`, `onEnd` |
| 4 | Multi-turn history | `result.responseMessages.map(ModelMessage.fromProvider)` appended to caller-owned history |
| 5 | Tools v3 | `toolWithContext`, `maxToolConcurrency`, `approvalPolicy: ToolApprovalPolicy.always`, resuming with a bound `LanguageModelV4ToolApprovalResponse` |
| 6 | Cancellation and deadlines | `abortSignal: CancellationToken` cancelled mid-stream, `timeout: TimeoutConfiguration(...)` |
| 7 | Structured output | `Schema.decoderOnly` vs `validatedJsonSchema` (`ai_sdk_json_schema`) |
| 8 | `streamObject` | immutable partial snapshots, `patchStream`, awaiting the validated `object` |
| 9 | `embedMany` | `maxEmbeddingsPerCall` + `maxParallelCalls`, input order preserved |
| 10 | OpenAI Responses API | `openai.responses(...)` + hosted `OpenAIWebSearchTool`, printing `result.sources` |
| 11 | Reasoning | `reasoning: LanguageModelV4Reasoning.medium`, aggregate `result.reasoning` vs `finalStep.reasoning` |
| 12 | Body inclusion | default omits request/response bodies; `BodyInclusionPolicy.all()` opts in |
| 13 | Conversation persistence | `Conversation` built from an exchange, round-tripped via `ConversationCodec.encode`/`decode` (`ai_sdk_conversation`) |
| 14 | Middleware | `defaultSettingsMiddleware`, `extractReasoningMiddleware` |
| 15 | Provider registry | `createProviderRegistry` |

Requires `OPENAI_API_KEY`. Demos that need it print a skip line and return
instead of crashing when it is absent — `fvm dart run lib/main.dart` with no
key exits cleanly after printing 15 skip lines. Prefer the repo target, which
forwards the key to the provider factory correctly:

```sh
OPENAI_API_KEY=sk-... make run-basic
```

Equivalent direct invocation:

```sh
OPENAI_API_KEY=sk-... \
  fvm dart run --define=OPENAI_API_KEY=sk-... lib/main.dart
```

### `lib/mcp_demo.dart` — MCP (Model Context Protocol)

Uses [`ai_sdk_mcp`](../../packages/ai_sdk_mcp) to connect to an MCP server,
discover its tools, and hand them to the model:

1. Connect over HTTP with `StreamableHttpClientTransport`, selecting the
   modern stateless strategy with `protocolMode: MCPProtocolMode.modern` — it
   probes `server/discover`, adds per-request protocol metadata, and skips
   MCP sessions and the GET/DELETE lifecycle requests legacy mode uses.
2. Discover tools with `client.tools()` — which returns a `ToolSet` ready for
   `generateText`/`streamText`.
3. Call a discovered tool directly via `client.callTool(...)`.
4. Handle a lost `tools/call` response: the server may have already executed
   the tool, so the client raises `MCPAmbiguousToolCompletionException`
   instead of silently retrying. Set `retryOnTransportFailure: true` only for
   a call whose replay is safe (a read-only lookup here); a
   non-idempotent call (rolling a die) is left to surface the exception so the
   app can reconcile before deciding whether to retry.
5. Pass the discovered `ToolSet` to `generateText` so the model invokes the
   MCP tools itself.

So the example runs with **zero external setup**, it spins up a tiny in-process
MCP server (a `dart:io` `HttpServer` speaking MCP's JSON-RPC) and connects to it
over loopback. Point the transport at a real server URL to talk to a remote one.

The remote transport path matches MCP Streamable HTTP: in modern mode it
negotiates via `server/discover`, sends the modern `_meta` protocol metadata
on every request, and does not use MCP sessions or GET/DELETE lifecycle
requests. Legacy mode (`MCPProtocolMode.legacy`, the default) negotiates the
protocol version during `initialize()`, sends `notifications/initialized`,
and starts the optional `GET` SSE listener for server-pushed notifications,
reconnecting it with `Last-Event-ID` if the stream drops unexpectedly.

```sh
# Tool discovery + a direct tool call — no API key needed:
fvm dart run lib/mcp_demo.dart        # or: make run-mcp

# Also let the model call the MCP tools via generateText:
OPENAI_API_KEY=sk-... make run-mcp
```

> Note: stdio-based MCP servers (`StdioMCPTransport`) are desktop/native only.
> `StreamableHttpClientTransport` works everywhere `package:http` does,
> including Flutter web. Put required credential headers in `headers`, but do
> not ship long-lived secrets inside browser or mobile clients.
