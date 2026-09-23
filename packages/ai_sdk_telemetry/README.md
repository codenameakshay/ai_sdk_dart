# ai_sdk_telemetry

Optional OTLP/HTTP JSON metrics export for `ai_sdk_dart`.

`OtlpHttpMetricSink` implements the core `TelemetryMetricSink` interface with
a bounded in-memory queue. Call `flush()` at an application-defined boundary
and `dispose()` when the exporter is no longer needed. Both accept an export
deadline. Export failures are reported through `onDiagnostic`; failed flushes
retain metrics for a later flush while the sink remains open. Disposal closes
admission immediately and makes one bounded final flush attempt.

The adapter exports numeric `TelemetryMetric` values as independent OTLP gauge
data points. It does not aggregate observations into counters or histograms.
Metric attributes support strings, booleans, numbers, and lists of those
values. Unsupported, cyclic, non-finite, or over-limit values are omitted.
Payloads are bounded by default to 64 KiB and 64 attributes per data point.
The package supports native Dart platforms through `dart:io`; browser builds
need a separate HTTP implementation of `TelemetryMetricSink`. It supports
metrics only; it does not claim OTLP tracing, logs, exemplars, or retry
scheduling beyond the bounded in-memory queue.

Redaction runs once before metric/resource attributes enter retained state.
Retries preserve the original observation time and sanitized attributes.
Observations with the same name share one OTLP metric containing their data
points. Hosts that need counters or histograms should aggregate through a
different sink.

An injected `HttpClient` stays caller-owned; dispose it in the host's lifecycle.
Without an injected client, the sink owns and closes its client, replacing it
after a connection timeout so later flushes can recover. A timeout before a
caller-owned client returns a request cannot cancel that pending connection;
if the request arrives later, the sink aborts it before sending content.
