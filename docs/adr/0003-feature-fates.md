# ADR 0003: Feature fates — keep only relevant, working code

Status: Accepted

## Context

A grounded audit (`docs/codebase-audit-2026-06.md`) found surface that was half-baked, dead, or
mis-suited to Dart/Flutter. The goal is "nothing useless": every ported feature must be real and
useful in a Dart/Flutter context.

## Decision

| Surface | Fate | Reason |
|---|---|---|
| `generateVideo` + `VideoModelV1` + mock + registry `video` category | **Remove** | No provider implements it; not a stable v6 API. Dead leverage. |
| `telemetry` (no-op default recorder) | **Keep** as a bring-your-own pluggable hook | Real seam for callers who supply a recorder; adding an OpenTelemetry dependency would bloat a client SDK. |
| `wrapImageModel` (implemented, unexported) | **Export + test** | Legitimate middleware; image models exist (OpenAI). Dead only because the barrel omitted it. |
| MCP top-level `dart:io` import | **Isolate behind conditional imports** | The HTTP transport must work on Flutter web; `dart:io` poisons the whole package. |
| MCP `StdioMCPTransport` | **Keep, desktop-only** behind the conditional seam | Useful for desktop/CLI; not for mobile/web. |
| MCP `SseClientTransport` | **Implement real SSE streaming** | It currently does plain HTTP POST despite the name; real SSE unlocks server-push (resource subscriptions). |
| `simulateStreamingMiddleware` | **Keep** | Genuinely useful for non-streaming models. |

## Consequences

- Removing `generateVideo` is a breaking change for any caller using it; acceptable given no
  backing provider ever shipped. Versions bump accordingly.
- Architecture reviews should not re-suggest adding a video model type until a provider exists.
