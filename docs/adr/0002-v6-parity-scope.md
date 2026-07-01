# ADR 0002: v6 parity scope — omit the web/framework surface

Status: Accepted

## Context

Vercel AI SDK is split into AI SDK Core, AI SDK UI (React/Svelte/Vue/Solid hooks), and AI SDK RSC
(React Server Components). A faithful Dart/Flutter port cannot and should not mirror all of it.

## Decision

Port **AI SDK Core** in full and replace **AI SDK UI** with idiomatic Flutter controllers
(`ai_sdk_flutter_ui`). Do **not** port:

- The UI hooks (`useChat`, `useCompletion`, `useObject`) — replaced by `*Controller`s.
- The UI-message-stream / data-stream HTTP protocol and the Transport abstraction — these are the
  server↔client wire format for the JS hooks; a Flutter app calling providers directly does not
  need them.
- AI SDK RSC (`streamUI`, `createStreamableUI`, server-component state) — React-only.
- Next.js / Node / Edge runtime glue (route handlers, `use client`/`use server`).

Track parity against v6 in `docs/v6-parity-matrix.md`.

## Consequences

- The Dart surface is Core + Flutter UI + MCP. Architecture reviews should not propose porting the
  omitted surface.
- If a future need arises to interoperate with a JS AI-SDK backend over its wire protocol, that is
  a new, separate decision — not a gap in this port.
