# MCP coverage checkpoint

Parent command: `fvm dart test --coverage=/tmp/v3-mcp-parent-coverage packages/ai_sdk_mcp/test`. Result: **139 passed**. After tests completed, formatted with `fvm dart run coverage:format_coverage --lcov --check-ignore --in=/tmp/v3-mcp-parent-coverage --out=/tmp/v3-mcp-parent.lcov --report-on=packages/ai_sdk_mcp/lib --packages=.dart_tool/package_config.json`.

| File | Covered / measured executable lines | Coverage |
|---|---:|---:|
| json_rpc.dart | 47 / 47 | 100.00% |
| mcp_client.dart | 435 / 454 | 95.81% |
| http_transport.dart | 563 / 616 | 91.40% |
| stdio_transport_io.dart | 132 / 133 | 99.25% |
| Total | 1177 / 1250 | 94.16% |

This is a current package measurement, not the aggregate release gate and not external protocol conformance. Avoid adding ignore directives to inflate it. Uncovered executable branches include modern HTTP SSE/content-type handling, modern notification dispatch/error cleanup, legacy session deletion failures, and recovery lifecycle paths. Add scenario tests proving semantic outcomes (resource closure, no replay of ambiguous tool calls, response-ID validation and error preservation), rather than testing private branches merely to raise the percentage.

The full modern/legacy external conformance and selected extension audit remains outstanding.

## HTTP lifecycle additions and pinned SDK reference

Five new parent loopback scenarios cover modern SSE notifications/results, mismatched IDs, unsupported media types, and modern notification success/failure without legacy sessions. The first test load had a fixture-only invalid `const` constructor; after correcting that, all five scenarios passed against existing production code. These are new proof, not reproduced product failures. Full local MCP suite **144 passed** under coverage, with **1196/1250 lines (95.68%)** measured. Analysis is clean.

`make test-mcp-reference` also passed. It runs the Dart legacy client against the real published TypeScript SDK **1.30.0** over stdio, checking handshake, discovery, Unicode tool input/output, tool failure and a subsequent successful call. The Node dependency and transitive integrity hashes are pinned under `examples/mcp_reference/js`. No external server or credentials are required after npm installation.

The reference SDK's latest protocol constant is2025-11-25 and its supported versions include2025-06-18; it does **not** qualify Dart's2026-07-28 mode. This is bounded interoperability evidence, not full protocol conformance. New tests: `modern_http_lifecycle_review_test.dart` and `typescript_reference_test.dart`. Logs: `/tmp/v3-mcp-http-review.log`, `/tmp/v3-mcp-coverage-after.log`, `/tmp/v3-mcp-reference-target.log`.

## Modern MRTR and host-auth follow-up

The modern strategy now validates ordinary result envelopes (`resultType` is
`complete` or `input_required`) and rejects malformed MRTR state before it is
returned to a caller. Input-required responses are limited to the three
specification-supported request methods, require at least one of
`inputRequests`/`requestState`, require an opaque string `requestState`, and
validate request-map entries as JSON-RPC requests. Protocol validation errors
remain distinct from transport ambiguity, so a malformed response is not
reported as an invitation to replay a tool call.

The HTTP auth hook coalesces concurrent 401 refreshes into one host callback;
the refreshed credential is still supplied only by the host and is never
stored by the package. Focused modern tests cover malformed result envelopes,
invalid MRTR state, and concurrent refresh coalescing. Progress remains a
typed monotonic notification stream. Negative or stale updates are discarded.

The 2026-07-28 `io.modelcontextprotocol/tasks` extension and cacheable-result
`ttlMs`/`cacheScope` hints remain explicitly unsupported. The package exposes
progress and MRTR, but does not invent a partial tool-result protocol; any
Tasks polling or cache policy belongs to a future versioned adapter.
