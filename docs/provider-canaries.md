# Provider canaries

The provider canary harness has two modes:

- The default mode is offline. It validates configuration and lists the
  providers that have both required environment variables without making a
  network request.
- `--live` is an explicit qualification run. It sends requests to each
  configured provider and fails if any check does not pass.

Live runs require an API key and an explicit model ID for each provider. The
harness reads only these environment variable pairs:

| Provider | API key | Explicit model ID |
| --- | --- | --- |
| OpenAI Responses | `OPENAI_API_KEY` | `OPENAI_CANARY_MODEL` |
| Anthropic | `ANTHROPIC_API_KEY` | `ANTHROPIC_CANARY_MODEL` |
| Google | `GOOGLE_API_KEY` | `GOOGLE_CANARY_MODEL` |

The model value is supplied by the operator for the account being tested. The
harness does not select a “latest” model, maintain a model allowlist, or claim
that an arbitrary model supports every operation before the run. A model
catalog can be used as advice, but it does not reject an explicit model ID.

Each configured provider is checked for:

- a non-empty text response;
- a non-empty streamed text response;
- a structured object response;
- a two-step tool continuation, including execution of a required tool; and
- a reasoning-enabled two-step tool continuation that returns reasoning and
  retains it across the continuation.

These checks exercise the shared generation API against the provider's live
adapter. They do not replace provider-specific review of account limits,
model capability, spend, or safety policy. Choose an explicit model that
supports all listed operations; a failed operation means that provider/model
pair is not qualified by the run.

The reasoning continuation uses these provider options:

| Provider | Reasoning profile |
| --- | --- |
| OpenAI Responses | `reasoningEffort: medium` with a detailed reasoning summary |
| Anthropic | Extended thinking with a 1,024-token budget |
| Google | `thinkingConfig.thinkingBudget: 2048` and `includeThoughts: true` |

The operator must choose a model that supports the selected profile. The
forced-tool continuation runs separately from the reasoning continuation so
providers that reject forced tool choice while thinking is enabled can still
be qualified accurately.

## Local runs

Use FVM to resolve the repository's pinned Flutter 3.44.3/Dart toolchain:

```bash
fvm dart analyze tool/canaries
fvm dart test tool/canaries
fvm dart run tool/canaries/provider_canaries.dart
```

The last command is the offline configuration check. To perform a live run,
set at least one complete key/model pair in the process environment and add
`--live`:

```bash
OPENAI_CANARY_MODEL='model-id-for-this-account' \
fvm dart \
  run tool/canaries/provider_canaries.dart --live
```

Inject `OPENAI_API_KEY` into the process environment through a secret manager
before this command. Do not paste the key into the shell example or commit it.

Do not put credentials or prompts in source files, command history, CI logs,
or checked-in artifacts. The harness never prints key values or prompt
content; it reports only provider names, explicit model IDs, and failure types.

## GitHub Actions

The `Provider canaries` workflow supports a manual dispatch and a daily
scheduled run. Manual runs require `run_canaries` and an explicit model ID for
each provider secret that is available. Scheduled runs are disabled unless the
repository variable `AI_SDK_ENABLE_SCHEDULED_CANARIES` is exactly `true`.

When scheduled runs are enabled, model IDs come from the repository variables
`OPENAI_CANARY_MODEL`, `ANTHROPIC_CANARY_MODEL`, and `GOOGLE_CANARY_MODEL`.
The workflow reads the matching API keys from repository secrets. A scheduled
run with no complete key/model pair reports `NOT RUN` and fails, so enabling the
schedule cannot silently claim a qualification result. When the repository
variable is not `true`, the scheduled job is skipped.

Each provider report includes UTC start and completion timestamps, elapsed
milliseconds, provider name, and explicit model ID. The harness bounds each
request with `maxOutputTokens` and a two-minute total timeout; the reasoning
check uses a 4,096-token output limit. These limits keep scheduled runs
reviewable and prevent an unbounded request loop.

The workflow uses the pinned Flutter 3.44.3 toolchain and runs the same
analysis and `--live` command shown above. No live canary run has been
performed in this environment; no provider credentials are configured here.
