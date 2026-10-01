# Structured stream benchmark

Run:

```sh
fvm dart run packages/ai_sdk_dart/benchmark/structured_stream_benchmark.dart --json
```

The benchmark uses the same generated object and array payload traces for the
legacy full-copy snapshot path and the append-only structural path. Each case receives three untimed warmups followed by 30 measured runs.
The execution order rotates across object/copy/structural cases. JSON includes
all elapsed-time samples, empirical nearest-rank p50/p95/p99, minimum and maximum.
With 30 samples, p99 is the observed maximum, not a calibrated population tail estimate.
The existing `elapsedMicroseconds` field contains the p50 observation. Counters are
deterministic: the legacy path records the sum of list elements copied, while
the structural path records zero full-list element copies. It separately reports
new persistent nodes and copied root references; it is not allocation-free. Timings are measurements for the current machine, not performance
claims.

The structural builder returns a read-only `List` snapshot. Appends create a
new persistent balanced nodes and retain old snapshots. Snapshot construction
copies at most logarithmically many root references. Random indexing is
logarithmic; materializing every element remains linear. The existing helper
`createTrackedImmutableSnapshot` remains available for callers that explicitly
need a full detached list copy. Stream integration is intentionally separate so
callers can choose snapshot creation only when consumers are listening.

Measured results and environment/source hashes are recorded in [the v3 benchmark evidence](../../../plans/v3-research/evidence/benchmarks/README.md). The host is shared and the comparisons concern these algorithms, not whole SDK versions or network latency. Heap bytes and Flutter frame timings are separate pending measurements.

## Tool concurrency benchmark

Run:

```sh
fvm dart run packages/ai_sdk_dart/benchmark/tool_concurrency_benchmark.dart --json
```

This benchmark executes twelve controlled local futures with a 25 ms delay and
compares serial scheduling with a four-call bound. It reports wall-clock time,
the observed peak concurrency, and the speedup. It measures scheduler-controlled
I/O only; it does not contact a model provider or measure network throughput.
