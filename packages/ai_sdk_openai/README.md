# ai_sdk_openai

OpenAI provider for [AI SDK Dart](https://pub.dev/packages/ai_sdk_dart). Supports language models, embeddings, and image generation via the OpenAI API.

## Installation

```yaml
dependencies:
  ai_sdk_dart: ^3.0.0
  ai_sdk_openai: ^3.0.0
```

## Usage

The top-level `openai` factory reads
`const String.fromEnvironment('OPENAI_API_KEY')`. Use it with
`fvm dart run --define=OPENAI_API_KEY=sk-... bin/app.dart`, or read
`Platform.environment['OPENAI_API_KEY']` yourself and pass `apiKey:` to
`OpenAIProvider` in server and CLI apps.

### Language model

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final result = await generateText(
  model: openai.responses('gpt-6-luna'),
  prompt: 'Say hello!',
);
print(result.text);
```

The provider has two language-model entry points:

- `openai.responses(modelId)` sends OpenAI Responses API requests. Use it for
  the GPT-6 models (`gpt-6-luna`, `gpt-6-sol`, `gpt-6-astra`). The
  [provider capability catalog](https://github.com/codenameakshay/ai_sdk_dart/blob/main/docs/provider-capability-catalog.md)
  lists them on the Responses API. The canary harness is configured to use
  this path, but no live canary run has been performed.
- `openai(modelId)` and `openai.chat(modelId)` send Chat Completions requests.
  This package has not qualified the GPT-6 models on that path. Use it for
  models that support Chat Completions, such as `gpt-4.1`.

### Streaming

```dart
import 'dart:io';

final result = await streamText(
  model: openai.responses('gpt-6-luna'),
  prompt: 'Tell me a joke.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Embeddings

```dart
final result = await embed(
  model: openai.embedding('text-embedding-3-small'),
  value: 'Hello, world!',
);
print(result.embedding); // List<double>
```

### Image generation

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final result = await generateImage(
  model: openai.image('dall-e-3'),
  prompt: 'A futuristic city at sunset.',
);
```

### Reasoning

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

final result = await generateText(
  model: openai.responses('gpt-6-luna'),
  prompt: 'Solve the Tower of Hanoi for 4 disks.',
  providerOptions: {
    'openai': OpenAILanguageModelOptions(
      reasoningEffort: 'high',
      reasoningSummary: 'detailed',
    ).toMap(),
  },
);
print(result.text);
```

### Responses API + hosted tools

`openai.responses(modelId)` returns a `LanguageModelV4` backed by the OpenAI
Responses API instead of Chat Completions — same `generateText`/`streamText`
usage as `openai(modelId)`. The adapter supports streaming, structured output,
reasoning, and function tools on this API surface. Use it for hosted,
server-side tools, passed via `providerDefinedTools:` (a
`List<LanguageModelV4ProviderDefinedTool>`, separate from the `tools:` map):

```dart
final result = await generateText(
  model: openai.responses('gpt-6-luna'),
  prompt: 'What happened in the news today?',
  providerDefinedTools: [OpenAIWebSearchTool()],
);
```

`OpenAIWebSearchTool`, `OpenAIFileSearchTool` (vector-store search),
`OpenAICodeInterpreterTool`, and `OpenAIMcpTool` (a remote MCP server) are all
available — see [`example/example.md`](example/example.md) for the full set,
plus runnable file/batch lifecycle examples.

### Native structured output

For Chat Completions, using `generateObject` or `Output.object()` with
`generateText` sends schema-validated output through
`response_format: json_schema`. Responses API requests use `text.format` for
structured output instead:

```dart
final result = await generateObject(
  model: openai.chat('gpt-4.1'),
  schema: Schema<Map<String, dynamic>>(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
        'country': {'type': 'string'},
      },
      'required': ['city', 'country'],
      'additionalProperties': false,
    },
    fromJson: (json) => json,
  ),
  prompt: 'Capital of France?',
);
print(result.object); // {city: Paris, country: France}
```

### Computer tool output

Computer screenshots use a provider-neutral, camelCase result shape at the
public `LanguageModelV4` boundary. Supply the screenshot under `output` and
include safety acknowledgements under `acknowledgedSafetyChecks`:

```dart
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

const computerToolResult = LanguageModelV4ToolResultPart(
  toolCallId: 'call-computer',
  toolName: 'computer',
  output: ToolResultOutputJson({
    'output': {
      'type': 'computer_screenshot',
      'imageUrl': 'https://example.test/screenshot.png',
      'detail': 'high',
    },
    'acknowledgedSafetyChecks': [
      {
        'id': 'safety-1',
        'code': 'external_side_effect',
        'message': 'Reviewed by the user',
      },
    ],
  }),
);
```

The OpenAI Responses adapter converts this public shape to the wire shape
(`image_url`, `acknowledged_safety_checks`, and related fields) when it sends
the computer result. Older provisional integrations that put `type` and
`image_url` directly at the top level should migrate to the wrapper above and
use `imageUrl`/`fileId` and `acknowledgedSafetyChecks` at the public boundary.

### Custom API key / base URL

```dart
final myOpenAi = OpenAIProvider(
  apiKey: 'sk-...',
  baseUrl: 'https://my-proxy.example.com/v1',
);

final result = await generateText(
  model: myOpenAi.responses('gpt-6-luna'),
  prompt: 'Hello!',
);
```

### With provider registry

```dart
final registry = createProviderRegistry({
  'openai': RegistrableProvider(
    languageModelFactory: openai.responses,
    embeddingModelFactory: openai.embedding,
  ),
});

final model = registry.languageModel('openai:gpt-6-luna');
```

Pass `openai.call` as `languageModelFactory` to route the registry through
Chat Completions instead.

## License

MIT
