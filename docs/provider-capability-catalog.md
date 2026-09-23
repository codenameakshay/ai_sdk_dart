# Provider capability catalog

`provider-capability-catalog.json` is an advisory snapshot retrieved on
2026-09-23 from official provider documentation. Each record describes one
provider, model (or `*` for caller-defined deployments), API surface, scope,
and one feature. `lifecycle` records whether the provider calls the model
stable, preview, or deprecated. `confidence` records evidence strength
separately: `catalog`, `fixture`, or `liveSmoke`.

The catalog is not an allowlist. Provider factories continue to accept unknown
model IDs, private Azure deployments, gateways, and local Ollama tags. No
record in this snapshot claims authenticated live qualification.

Validate it offline with a deterministic date:

```text
fvm dart run tool/provider_capability_catalog.dart check \
  docs/provider-capability-catalog.json --as-of=2026-09-23
```

Generate a stable Markdown view for review:

```text
fvm dart run tool/provider_capability_catalog.dart generate \
  docs/provider-capability-catalog.json --as-of=2026-09-23
```

The checker validates required fields, provider coverage, duplicate records,
source URIs, lifecycle/confidence values, fixture paths, generated Markdown
drift, future dates, and evidence age. It reports evidence older than 90 days
as `STALE`; scheduled automation can run it without credentials, network access,
API keys, or provider cost.
