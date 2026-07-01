# ai_sdk_openai_compatible

Shared base for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart) providers that
speak the **OpenAI Chat Completions** wire format over SSE — `ai_sdk_openai`,
`ai_sdk_azure`, `ai_sdk_groq`, and `ai_sdk_mistral`.

This is **infrastructure**, not a vendor provider: it has no callable factory of
its own. It implements tool calling, multimodal content, structured output, and
streaming **once** so the four providers above inherit them. See
[ADR 0004](https://github.com/codenameakshay/ai_sdk_dart/blob/main/docs/adr/0004-openai-compatible-base.md).

## Usage (provider authors)

```dart
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:dio/dio.dart';

LanguageModelV3 myModel(String modelId) => OpenAICompatibleChatLanguageModel(
  config: OpenAICompatibleConfig(
    provider: 'groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    headers: () => {'Authorization': 'Bearer $apiKey'},
  ),
  modelId: modelId,
);
```

The `OpenAICompatibleConfig` parameterizes per-provider quirks (auth scheme,
base URL, query params like Azure's `api-version`, `seed` vs `random_seed`,
`max_tokens` vs `max_completion_tokens`, capability flags, and an `extraBody`
hook). Everything else — request building, SSE parsing, tool serialization,
multimodal mapping, finish-reason mapping — is shared.

## License

MIT
