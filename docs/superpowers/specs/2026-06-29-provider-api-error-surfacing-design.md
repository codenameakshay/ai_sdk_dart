# Surface provider API errors as typed `AiApiCallError`

**Date:** 2026-06-29
**Status:** Design — awaiting approval
**Branch:** improve/v6-hardening

## Problem

When a provider's HTTP API returns a non-2xx response, the SDK currently lets a
raw `DioException` propagate. The provider's real error payload
(`{error:{message,type,code}}` and variants) is discarded, so callers only see a
generic Dio message. This made a real bug hard to diagnose: the image model sent
`response_format` to `gpt-image-1`, the API returned `400 Unknown parameter:
'response_format'`, and the UI/SDK showed only a generic `DioException` (the
parameter was gated in commit `dd5178e`; the error-surfacing gap remained).

No provider package does any API-error mapping today — confirmed across
`ai_sdk_openai` (`_openAiDio`), the `ai_sdk_openai_compatible` chat base, and
`anthropic`/`google`/`cohere`/`mistral`/`groq`/`ollama`. None install a Dio error
interceptor; all let `DioException` bubble.

## Goal

A non-2xx response throws a meaningful, typed error carrying the provider's
`message`/`type`/`code`/`statusCode`, consistently across **all** provider
packages, with conformance tests proving the message is surfaced.

## Key constraints discovered

- `ai_sdk_provider` is the base package (depends only on `meta`). **Every**
  provider package depends on `ai_sdk_provider`, **not** on `ai_sdk_dart`.
- The `AiSdkError` hierarchy is **`sealed`** and lives in `ai_sdk_dart`
  (`lib/src/errors/ai_errors.dart`). `sealed` requires all subtypes in the same
  library, and providers can't even import `ai_sdk_dart`. So providers cannot
  reuse `AiApiCallError` as-is.
- `ai_sdk_provider` currently defines **no** exception type (only
  `StreamPartError`, a stream-part value).
- `ai_sdk_dart`'s barrel re-exports errors via `export 'src/errors/ai_errors.dart'`;
  4 core files (`generate_text`, `stream_text`, `generate_object`,
  `stream_object`) import that same path. `ai_sdk_dart` does **not** currently
  re-export the provider barrel.
- The errors file only depends on `LanguageModelV3ResponseMetadata` and
  `LanguageModelV3Usage`, both already in `ai_sdk_provider`.

## Decisions (approved by user)

1. **Scope:** all providers — OpenAI (image/speech/transcription/embeddings),
   the openai_compatible chat base, and anthropic/google/cohere/mistral/groq/ollama.
2. **Hierarchy:** unify — relocate the `AiSdkError` hierarchy into
   `ai_sdk_provider` so the API-call error is part of the existing hierarchy.

## Design

### 1. Relocate the error hierarchy into `ai_sdk_provider` (low-churn)

- Move the full contents of
  `ai_sdk_dart/lib/src/errors/ai_errors.dart` →
  `ai_sdk_provider/lib/src/errors/ai_errors.dart`, switching its imports to
  package-relative (`../language_model/...`). The hierarchy stays in **one
  library**, so `sealed AiSdkError` remains valid.
- Add `export 'src/errors/ai_errors.dart';` to the `ai_sdk_provider` barrel.
- Replace `ai_sdk_dart/lib/src/errors/ai_errors.dart` with a **re-export shim**:
  `export 'package:ai_sdk_provider/ai_sdk_provider.dart' show AiSdkError, AiApiCallError, …;`
  This keeps the `ai_sdk_dart` barrel export and the 4 core-file imports working
  **unchanged** — no churn in `generate_text`/`stream_text`/`generate_object`/
  `stream_object`, and `ai_sdk_dart`'s public surface is identical.

### 2. Enrich `AiApiCallError` (one type for all API-call failures)

`AiApiCallError` gains optional named fields; the existing positional-message
constructor stays `const` and backward-compatible (existing
`AiApiCallError('…')` call sites compile untouched):

```dart
class AiApiCallError extends AiSdkError {
  const AiApiCallError(
    super.message, {
    this.statusCode,
    this.url,
    this.responseBody,
    this.responseHeaders,
    this.type,
    this.code,
    this.isRetryable = false,
    this.cause,
  });

  final int? statusCode;
  final String? url;
  final String? responseBody;            // raw body for debugging
  final Map<String, String>? responseHeaders;
  final String? type;                    // provider error "type"
  final String? code;                    // provider error "code"/"status"
  final bool isRetryable;                // 408/409/429/5xx
  final Object? cause;                   // underlying DioException

  static bool isInstance(Object e) => e is AiApiCallError;

  /// Build from a materialized provider HTTP error response (pure, no Dio).
  factory AiApiCallError.fromResponse({
    required int? statusCode,
    String? url,
    Object? body,                        // Map | String | List<int> | null
    Map<String, String>? responseHeaders,
    String? provider,
    Object? cause,
  }) { /* tolerant parse — see table */ }
}
```

`toString()` stays inherited (`'$runtimeType: $message'`).

### 3. Tolerant body parser (`fromResponse`)

Normalizes body (utf8-decode `List<int>`; `jsonDecode` strings) then extracts
across the surveyed provider shapes:

| Provider(s)                         | Body shape                              | message / type / code |
|-------------------------------------|-----------------------------------------|-----------------------|
| OpenAI, openai_compatible, Groq, Mistral | `{error:{message,type,code,param}}` | error.message / error.type / error.code |
| Anthropic                           | `{type:"error",error:{type,message}}`   | error.message / error.type / — |
| Google                              | `{error:{code,message,status}}`         | error.message / error.status / error.code |
| Cohere                              | `{message}`                             | message / — / — |
| Ollama                              | `{error:"…"}` (string)                  | error / — / — |

Fallback message when none parses: `'<provider> API error (<statusCode>)'` (or a
truncated raw body). `responseBody` always retains the raw string for debugging.
`isRetryable = statusCode == 408 || 409 || 429 || statusCode >= 500`.

### 4. Wire into every Dio request site

Mechanism: **`on DioException catch` → throw `AiApiCallError.fromResponse(...)`**
at request sites (not a Dio interceptor — Dio interceptors can only `reject` with
a `DioException`, so a try/catch is what lets `await` throw `AiApiCallError`
directly, giving `throwsA(isA<AiApiCallError>())` semantics).

- **Shared Dio bridge** `apiErrorFromDioException(DioException, {provider})` in
  `ai_sdk_openai_compatible` (already Dio-dependent; imported by openai/groq/mistral).
  Returns `Future<AiApiCallError>`: extracts `statusCode`/`url`/`headers`, drains
  a streamed `ResponseBody` when present (stream responseType), then delegates to
  the pure `AiApiCallError.fromResponse`.
- **OpenAI** (`_openAiDio` paths): wrap `/embeddings`, `/images/generations`,
  `/audio/speech` (bytes), `/audio/transcriptions` with the bridge.
- **openai_compatible** chat base: wrap non-stream `/chat/completions` and the
  stream-setup `post<ResponseBody>`; streaming already wraps thrown errors into
  `StreamPartError(error:)`, so the typed error surfaces there too.
- **Standalone providers** (anthropic/google/cohere/ollama, mistral embeddings):
  inline `try/catch → AiApiCallError.fromResponse(...)` at their request sites
  (these don't depend on openai_compatible; the body-shape logic stays shared in
  the pure parser). Stream-setup sites drain `ResponseBody` locally.

`ai_sdk_provider` stays transport-agnostic (no Dio dep) — it owns the error type
+ pure parser only. *(Alternative considered: add `dio` to `ai_sdk_provider` for
a single shared bridge; rejected to keep the spec package faithful to
`@ai-sdk/provider`.)*

### 5. Conformance tests (per package)

Using the existing local-`HttpServer` mock pattern, each provider package gets a
test that returns a 4xx with that provider's error-body shape and asserts the call
throws an `AiApiCallError` whose `message`, `statusCode`, and `code`/`type` match
the payload. For streaming paths, assert the surfaced `StreamPartError.error` is
an `AiApiCallError` with the message. Add a unit test for `AiApiCallError.fromResponse`
covering each body shape + bytes/string/null normalization.

## Out of scope

- No retry/backoff behavior change (only the `isRetryable` flag is set).
- No change to 2xx response handling or parsing.
- No new public API beyond the enriched `AiApiCallError` + `fromResponse`.

## Risks / mitigations

- **Sealed move:** keep the whole hierarchy in one relocated library → `sealed`
  stays valid. Verify `dart analyze` across the workspace.
- **Churn:** the re-export shim preserves `ai_sdk_dart` imports/exports verbatim.
- **Stream error bodies:** drained from `ResponseBody` before parsing; covered by
  a streaming conformance test.
- **Const call sites:** new fields are optional named → existing
  `const AiApiCallError(msg)` usages unaffected.

## Verification

`dart analyze` (workspace) + `dart test` in each touched package, run via the
repo's melos/workspace tooling.
