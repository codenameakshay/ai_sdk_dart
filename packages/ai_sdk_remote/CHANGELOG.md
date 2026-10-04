## 3.0.0

- Added the optional Vercel AI UI-message stream transport and typed reducer.
- Added strict SSE framing, cancellation, authentication hooks, and unknown
  event preservation.
- Added validated UIMessage request conversion, per-request aborts, terminal
  finish enforcement, and pinned AI SDK reference-server coverage.
- Preserve existing assistant content and prior tool results when a continuation
  reuses the same message ID.
- The JS reference backend now assigns distinct assistant IDs per turn and
  survives clients aborting partial request bodies.
