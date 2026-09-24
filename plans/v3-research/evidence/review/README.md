# Parent regression evidence

Captured 2026-09-23 on Flutter 3.44.3 / Dart 3.12.2, Linux aarch64.
These are checkpoint logs, not a final whole-workspace qualification.

| Boundary | Before | Verified after |
|---|---|---|
| Telemetry retry identity | One observation invoked redaction 3 times | Full exporter 19 passed; admission redaction/time retained |
| Telemetry resource retention | Public retained resource map contained original private value | Same full exporter run after removing raw second copy |
| Files registration/timeout | Additional edge qualification; no claim these 2 tests failed first | Observer suite 7 passed; registration cancellation skips auth |
| Hosted Responses replay | Same search item serialized twice | Open at this checkpoint |
| Ollama observer lifetime | All 3 operations used future-only observation | Open at this checkpoint |
| MCP TypeScript interoperability | No new failure claimed | Pinned legacy SDK reference 1 passed; modern protocol not covered |

Reproduce with the named test files in each log using `fvm dart test`.
The MCP reference command is `make test-mcp-reference`. Logs preserve failing
assertions and counts; source is still evolving, so later evidence must replace
these checkpoints when claiming release readiness.
