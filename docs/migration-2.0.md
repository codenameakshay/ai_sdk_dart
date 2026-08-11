# Migrating to AI SDK Dart 2.0

AI SDK Dart 2.0 is a coordinated major release across all `ai_sdk_*`
packages. It removes the obsolete language-model V3 provider seam and makes
V4 the only supported language-model contract.

## Upgrade all packages together

Keep every AI SDK Dart package in an application on the same major version:

```yaml
dependencies:
  ai_sdk_dart: ^2.0.0
  ai_sdk_openai: ^2.0.0
  ai_sdk_flutter_ui: ^2.0.0
```

Run `dart pub get` or `flutter pub get` after updating the constraints. Do not
mix 1.x providers with the 2.x core package.

## Application API renames

The experimental names that graduated in 2.0 have no compatibility aliases:

| 1.x | 2.0 |
|---|---|
| `experimentalContext` | `runtimeContext` |
| `experimentalTelemetry` | `telemetry` |

For example:

```dart
final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'Summarize this request.',
  runtimeContext: const {'requestId': 'example'},
  telemetry: const TelemetrySettings(isEnabled: true),
);
```

## Usage is grouped by token direction

Language-model usage no longer exposes flat prompt, completion, and total
token fields. Read the nested input and output groups instead:

```dart
final usage = result.usage;
final input = usage?.inputTokens.total;
final cacheRead = usage?.inputTokens.cacheRead;
final cacheWrite = usage?.inputTokens.cacheWrite;
final output = usage?.outputTokens.total;
final reasoning = usage?.outputTokens.reasoning;
```

Providers leave a detail field `null` when their API does not report it.

## Custom providers and middleware

Rename the language-model surface from `LanguageModelV3*` to the corresponding
`LanguageModelV4*` types. A V4 model reports `specificationVersion == 'v4'`
and may override `supportedUrls` when it can consume matching URLs directly.

Call options changed as follows:

- `tools` is one `List<LanguageModelV4Tool>`. Function tools and
  provider-defined tools are distinguished by subtype; the separate
  `providerDefinedTools` option was removed.
- `outputSchema` was removed. Use `responseFormat`, including
  `LanguageModelV4JsonResponseFormat` for structured JSON.
- Providers receive `abortSignal`, `reasoning`, and `includeRawChunks`
  directly in `LanguageModelV4CallOptions`.
- Warnings use the structured `LanguageModelV4Warning` variants.
- Request and response metadata use `LanguageModelV4RequestMetadata` and
  `LanguageModelV4ResponseMetadata` instead of a shared raw envelope.

Middleware must forward every V4 option and preserve structured warnings,
request/response metadata, usage, and lifecycle parts when transforming a
result or stream.

## Streaming tool calls

V4 separates tool-input streaming from a complete tool call:

1. `StreamPartToolInputStart`
2. zero or more `StreamPartToolInputDelta` events
3. `StreamPartToolInputEnd`
4. `StreamPartToolCall`

Do not execute a tool at `StreamPartToolInputEnd`. The input is executable only
after the complete, validated `StreamPartToolCall` arrives. Core
`streamText` handles this sequencing automatically; direct provider-stream
consumers must apply the same rule.

## Removed surfaces

- All obsolete `LanguageModelV3*` language-model types and exports.
- The unused video generation API (`generateVideo`, `VideoModelV1`, and its
  related error and mock types).
- The provider-call `providerDefinedTools` and `outputSchema` fields.

There are no migration shims for these removals. Update source imports and
types directly before moving to 2.0.
