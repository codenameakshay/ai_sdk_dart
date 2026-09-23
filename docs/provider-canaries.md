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

The `Provider canaries` workflow is manual only. Dispatch it with
`run_canaries` enabled, enter the explicit model ID for each secret that is
available, and leave other providers blank. The workflow maps only the three
API key secrets and the three model inputs to the harness environment. It has
no schedule, so a credentialed network request cannot start from a pull
request or a timer.

The dispatch form becomes available after this workflow is present on the
repository's default branch. Until then, use the local command above.

The workflow uses the pinned Flutter 3.44.3 toolchain and runs the same
analysis and `--live` command shown above. No live canary run has been
performed in this environment; no provider credentials are configured here.
