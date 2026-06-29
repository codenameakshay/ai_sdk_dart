# ADR 0001: Provider-interface seam in `ai_sdk_provider`

Status: Accepted

## Context

The SDK must let callers swap AI vendors without changing business code. Vendors differ in wire
format, capabilities, and auth.

## Decision

`ai_sdk_provider` defines the model-interface contracts (`LanguageModelV3`, `EmbeddingModelV2`,
`ImageModelV3`, `SpeechModelV1`, `TranscriptionModelV1`, `RerankModelV1`) plus the content/part/
stream types. This is **the seam**. The core engine (`ai_sdk_dart`) depends only on the seam,
never on a concrete provider. Each provider package implements the seam and depends only on it
plus an HTTP client.

## Consequences

- Adding a provider never touches the core. Mocking the seam tests the core without HTTP.
- The seam's interface versions (`V3`/`V2`/`V1`) are the unit of breaking change; bumping them
  (e.g. a future v7 migration) ripples through every provider at once. Accepted cost.
- Providers are independently versioned/published on pub.dev.
