# ai_sdk_telemetry

Optional OTLP/HTTP JSON metrics export for `ai_sdk_dart`. `OtlpHttpMetricSink` implements `TelemetryMetricSink`. A developer puts it in `TelemetrySettings.metricSink`, and `generateText` and `streamText` record content-free gauges such as `ai.latency.totalMs` and `ai.operation.success`. `flush()` POSTs them to a collector.

## Sub-features

- `otlp-export` POSTs to the configured endpoint (for example `/v1/metrics`) with `application/json`, custom headers, resource attributes, the scope name and one gauge point for each SDK metric, for `generateText`, `streamText` and a failed call. Nothing is exported when telemetry is disabled.
- `otlp-attributes` exports string, bool, int, double and list attributes as typed OTLP values, and omits unsupported, cyclic and non-finite values.
- `otlp-redaction` runs `redactAttribute` on metric and resource attributes before they are retained.
- `otlp-batching` groups points of one name into one metric, and starts an export when `batchSize` is reached.
- `otlp-failure` keeps the batch when the collector answers 5xx, reports `onDiagnostic`, and delivers it later with the original timestamp. Generation does not fail because of the collector.
- `otlp-bounds` drops the oldest metric when the buffer is full, rejects a metric above `maxPayloadBytes`, and rejects bad constructor arguments.
- `otlp-lifecycle` ends `flush(deadline:)` with `TimeoutException` and keeps the batch. `dispose()` makes a final attempt and then refuses new records.

## How to get to it (user POV)

- Create `OtlpHttpMetricSink(endpoint: Uri.parse('https://collector/v1/metrics'))`. Pass `TelemetrySettings(isEnabled: true, metricSink: sink)` as `telemetry:` to `generateText` or `streamText`.
- Call `await sink.flush()` at an app boundary and `await sink.dispose()` on shutdown.

## Driving it with verify

Preconditions:

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify` and `$V doctor` prints no `FAIL` line.
- No key is necessary. Export checks use a fixture collector. Checks that call a model use a second fixture server in the Chat Completions format. Constructor validation runs in memory.

- **All checks.** Run `$V run telemetry`. Output `12 passed, 0 failed, 0 skipped`.
- **generateText export.** Run `$V run telemetry --check generate-text-metrics`. In `ai_sdk_telemetry/generate-text-metrics.json`, `exchanges` has the model call and one `POST /v1/metrics`. The metrics body has `ai.latency.totalMs`, `ai.operation.success` and four more names (six in all, listed in `observed.metricNames`). `ai.model.provider` is `verify-compat`.
- **streamText export.** Run `$V run telemetry --check stream-text-metrics`. `observed.metricNames` includes `ai.latency.firstMeaningfulMs`.
- **Failed call.** Run `$V run telemetry --check failed-call-metrics`. `observed.metricNames` includes `ai.operation.failure` and not `ai.operation.success`.
- **Disabled.** Run `$V run telemetry --check disabled-telemetry-exports-nothing`. `exchanges` has no request to `/v1/metrics`.
- **Attributes.** Run `$V run telemetry --check attribute-encoding`. `observed.attributes` shows `c.int` as `int:42` and no `f.object`, `g.nan`, `h.cycle` or `i.over.limit`. The request body has `"intValue":"42"`.
- **Redaction.** Run `$V run telemetry --check redaction-before-export`. `observed.pointAttributes['user.email']` is `[REDACTED]`, and the request body has none of the original secrets.
- **Batching.** Run `$V run telemetry --check batching-and-grouping`. `observed.metrics['verify.group']` is `[1.0, 2.0]` and `exchanges` has one POST.
- **5xx.** Run `$V run telemetry --check collector-5xx-retains-and-recovers`. `exchanges` has two POSTs. The first status is `503`, the second is `200`, and both carry the same `timeUnixNano`.
- **Generation survives.** Run `$V run telemetry --check generation-survives-collector-failure`. The collector status is `500`, and `observed.diagnostics` names it.
- **Bounds.** Run `$V run telemetry --check buffer-and-payload-bounds`. `observed.diagnostics` has a `maxPayloadBytes` line, and `observed.overflowDiagnostics` has a `buffer is full` line.
- **Deadline and dispose.** Run `$V run telemetry --check deadline-and-dispose`. `observed.flushElapsedMs` is under `500`.
- **Constructor.** Run `$V run telemetry --check constructor-validation`. Every bad argument raised `ArgumentError`.

## Gotchas

- Every metric is an independent gauge (`asDouble`). The package does not make counters or histograms. Aggregate in another sink if you need them.
- `streamText` records its closing metrics a moment after `result.text` resolves. Flush again, or wait, before you read `ai.operation.success`.
- Prompts, outputs and tool arguments are not exported unless `captureInputs` or `captureOutputs` is on, and this package exports metrics only.
- Not covered: HTTPS and a real OTLP collector. The fixture collector is plain HTTP on loopback.
- Not covered: browser use. The sink uses `dart:io`.
- Not covered: the stale-client replacement after a connection timeout. It needs a connect that stalls, which a loopback server cannot produce.
