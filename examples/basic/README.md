# basic

Dart CLI examples for [AI SDK Dart](https://github.com/codenameakshay/ai_sdk_dart). No Flutter required.

## Demos

### `lib/main.dart` — core features tour

A single run that walks through the major core APIs:

| # | Demo | API |
|---|------|-----|
| 1 | Single-turn text | `generateText` |
| 2 | Streaming text | `streamText` + `onChunk` |
| 3 | Structured output | `Output.object` + `Schema` |
| 4 | Tools + multi-step loop | `tool`, `maxSteps`, `onStepFinish` |
| 5 | Embeddings | `embed`, `cosineSimilarity` |
| 6 | Middleware | `defaultSettingsMiddleware`, `extractReasoningMiddleware` |
| 7 | Provider registry | `createProviderRegistry` |

Requires an OpenAI key. Prefer the repo target, which forwards the key to the
provider factory correctly:

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

1. Connect over HTTP with `StreamableHttpClientTransport`.
2. Run the `initialize` handshake and discover tools with `client.tools()` —
   which returns a `ToolSet` ready for `generateText`/`streamText`.
3. Call a discovered tool directly via `client.callTool(...)`.
4. Pass the discovered `ToolSet` to `generateText` so the model invokes the
   MCP tools itself.

So the example runs with **zero external setup**, it spins up a tiny in-process
MCP server (a `dart:io` `HttpServer` speaking MCP's JSON-RPC) and connects to it
over loopback. Point the transport at a real server URL to talk to a remote one.

The remote transport path matches MCP Streamable HTTP (`2025-06-18`): it
negotiates the protocol version during `initialize()`, sends
`notifications/initialized`, accepts JSON or SSE responses to request `POST`s,
starts the optional `GET` SSE listener for server-pushed notifications, and
reconnects that listener with `Last-Event-ID` if the stream drops unexpectedly.

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
