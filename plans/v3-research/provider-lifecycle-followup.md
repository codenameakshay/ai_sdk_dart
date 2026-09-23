# Provider lifetime review — 2026-09-23

This is a remaining-work audit, not a qualification claim.

## Reproduced: cancelled Responses calls still acquire credentials

`responses_cancellation_test.dart` now tests an already-cancelled signal for
both `doGenerate` and `doStream`. Both reject with the cancellation error but
invoke the authentication callback once. Expected calls: zero; actual: one.

Command:

```sh
fvm dart test packages/ai_sdk_openai/test/responses_cancellation_test.dart --name pre-cancelled
```

Initial result: two failures, exit 1. Log:
`/tmp/v3-responses-precancel-before.log`.

Cause: `cancellation.race(headers())` evaluates the credentials callback before
the cancellation bridge can check its state. Use lazy acquisition and preserve
the existing tests for cancellation while acquisition is pending. This matters
even without HTTP dispatch: credential acquisition can refresh a token or start
another network operation. The OpenAI worker owns the correction.

```diff
 request
-  invoke authentication callback
-  check cancellation
+  check cancellation
+  invoke authentication callback
   race pending authentication against cancellation
   dispatch only if still active
```

## Remaining: detachable provider observers

The core `CancellationToken.cancellationEvents` supports detachable observation,
but `AbortSignal` exposes only `isCancelled` and `onCancelled`. The shared Dio
adapter, Google and Cohere helpers attach callbacks to `onCancelled`. The new
OpenAI request scope also uses that future. Disposing a completed request makes
its callback inert; it does not detach it from a long-lived caller signal.

An additive observable-signal interface can let provider scopes detach without
breaking custom providers that implement the existing interface. Each request
must own and dispose its observer after success, error, timeout, startup abort,
stream termination and consumer cancellation. Existing future-only signals need
a documented fallback; do not claim they acquire detachability automatically.

Acceptance should use a counting observable fake to prove zero retained
observers after repeated successful and failing direct provider calls. Pair this
with loopback socket-close tests. Core-only tests do not prove direct provider
lifetimes, and socket closure alone does not prove observer cleanup.

## Remaining: capability qualification

`ProviderCapabilityDescriptor` exists as an advisory evidence type. The provider
implementations do not currently expose a matching capability lookup. The dated
catalog and its validation are useful but do not replace a per-operation audit
of cancellation, wire settings, model limits, usage and error mapping. Preserve
unknown model IDs and distinguish documentation, fixture and live evidence.
