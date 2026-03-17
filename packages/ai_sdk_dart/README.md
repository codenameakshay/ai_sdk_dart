# 🤖 AI SDK Dart

**A Dart/Flutter port of [Vercel AI SDK v6](https://sdk.vercel.ai) — provider-agnostic APIs for text generation, streaming, structured output, tool use, embeddings, image generation, speech, and more.**

[![ai_sdk_dart pub.dev](https://img.shields.io/pub/v/ai_sdk_dart.svg?label=ai_sdk_dart)](https://pub.dev/packages/ai)
[![ai_sdk_openai pub.dev](https://img.shields.io/pub/v/ai_sdk_openai.svg?label=ai_sdk_openai)](https://pub.dev/packages/ai_sdk_openai)
[![ai_sdk_anthropic pub.dev](https://img.shields.io/pub/v/ai_sdk_anthropic.svg?label=ai_sdk_anthropic)](https://pub.dev/packages/ai_sdk_anthropic)
[![ai_sdk_google pub.dev](https://img.shields.io/pub/v/ai_sdk_google.svg?label=ai_sdk_google)](https://pub.dev/packages/ai_sdk_google)
[![ai_sdk_flutter_ui pub.dev](https://img.shields.io/pub/v/ai_sdk_flutter_ui.svg?label=ai_sdk_flutter_ui)](https://pub.dev/packages/ai_sdk_flutter_ui)
[![ai_sdk_mcp pub.dev](https://img.shields.io/pub/v/ai_sdk_mcp.svg?label=ai_sdk_mcp)](https://pub.dev/packages/ai_sdk_mcp)
[![ai_sdk_provider pub.dev](https://img.shields.io/pub/v/ai_sdk_provider.svg?label=ai_sdk_provider)](https://pub.dev/packages/ai_sdk_provider)
[![CI](https://github.com/codenameakshay/ai_sdk_dart/actions/workflows/ci.yml/badge.svg)](https://github.com/codenameakshay/ai_sdk_dart/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D3.11-blue?logo=dart)](https://dart.dev)

---

## What is this?

AI SDK Dart brings the full power of [Vercel AI SDK v6](https://sdk.vercel.ai) to Dart and Flutter. Write your AI logic once, swap providers without changing a line of business code, and ship on every platform — mobile, web, and server. Every API mirrors its JavaScript counterpart so the official Vercel docs apply directly to your Dart code.

---

## Screenshots

### Flutter Chat App (`examples/flutter_chat`)

<table>
  <tr>
    <td align="center"><b>Multi-turn Chat</b></td>
    <td align="center"><b>Streaming Response</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/04_chat_multiturn.png" width="280" alt="Multi-turn chat"/></td>
    <td><img src="docs/screenshots/02_chat_response.png" width="280" alt="Chat response"/></td>
  </tr>
  <tr>
    <td align="center"><b>Completion</b></td>
    <td align="center"><b>Object Stream</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/07_completion_haiku_result.png" width="280" alt="Completion result"/></td>
    <td><img src="docs/screenshots/09_object_japan_result.png" width="280" alt="Object stream result"/></td>
  </tr>
</table>

### Advanced App (`examples/advanced_app`)

<table>
  <tr>
    <td align="center"><b>Provider Chat</b></td>
    <td align="center"><b>Tools Chat</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/adv_01_provider_chat.png" width="280" alt="Provider chat"/></td>
    <td><img src="docs/screenshots/adv_02_tools_chat.png" width="280" alt="Tools chat"/></td>
  </tr>
  <tr>
    <td align="center"><b>Image Generation</b></td>
    <td align="center"><b>Multimodal</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/adv_03_image_gen.png" width="280" alt="Image generation"/></td>
    <td><img src="docs/screenshots/adv_04_multimodal.png" width="280" alt="Multimodal"/></td>
  </tr>
</table>

---

## ✨ Features

### 🗣️ Text Generation & Streaming
- `generateText` — single-turn or multi-step text generation with full result envelope
- `streamText` — real-time token streaming with typed event taxonomy
- `smoothStream` transform — configurable chunk-size smoothing for UX
- Multi-step agentic loops with `maxSteps`, `prepareStep`, and `stopConditions`
- Callbacks: `onFinish`, `onStepFinish`, `onChunk`, `onError`, `experimentalOnStart`

### 🧩 Structured Output
- `Output.object(schema)` — parse model output into a typed Dart object
- `Output.array(schema)` — parse model output into a typed Dart list
- `Output.choice(options)` — constrain output to a fixed set of string values
- `Output.json()` — raw JSON without schema validation
- Automatic code-fence stripping (` ```json ... ``` `)

### 🔧 Type-Safe Tools & Multi-Step Agents
- `tool<Input, Output>()` — fully typed tool definitions with JSON schema
- `dynamicTool()` — tools with unknown input type for dynamic use cases
- Tool choice: `auto`, `required`, `none`, or specific tool
- Tool approval workflow with `needsApproval`
- Multi-step agentic loops with automatic tool result injection
- `onInputStart`, `onInputDelta`, `onInputAvailable` lifecycle hooks

### 🖼️ Multimodal
- `generateImage` — image generation (DALL-E 3 via OpenAI)
- `generateSpeech` — text-to-speech audio synthesis
- `transcribe` — speech-to-text transcription
- Image inputs in prompts (multimodal vision)

### 🧮 Embeddings & Cosine Similarity
- `embed()` — single value embedding with usage tracking
- `embedMany()` — batch embedding for multiple values
- `cosineSimilarity()` — built-in similarity computation

### 🧱 Middleware System
- `wrapLanguageModel(model, middlewares)` — composable middleware pipeline
- `extractReasoningMiddleware` — strips `<think>` tags into `ReasoningPart`
- `extractJsonMiddleware` — strips ` ```json ``` ` fences
- `simulateStreamingMiddleware` — converts non-streaming models to streaming
- `defaultSettingsMiddleware` — applies default temperature/top-p/etc.
- `addToolInputExamplesMiddleware` — enriches tool descriptions with examples

### 🌐 Provider Registry
- `createProviderRegistry` — map provider aliases to model factories
- Resolve models by `'provider:modelId'` string at runtime
- Mix providers in a single registry for multi-provider apps

### 📱 Flutter UI Controllers
- `ChatController` — multi-turn streaming chat with message history
- `CompletionController` — single-turn text completion with status
- `ObjectStreamController` — streaming typed JSON object updates

### 🔌 MCP Client (Model Context Protocol)
- `MCPClient` — connect to MCP servers, discover tools, invoke them
- `SseClientTransport` — HTTP SSE transport
- `StdioMCPTransport` — stdio process transport
- Discovered tools are directly compatible with `generateText`/`streamText`

### 🧪 Conformance Suite
- 178+ tests covering every public API
- Spec-driven JSON fixtures as the source of truth
- Provider wire-format conformance tests for OpenAI, Anthropic, and Google

---

## 📦 Packages

| Package | pub.dev | What it gives you |
|---------|---------|-------------------|
| [`ai_sdk_dart`](https://pub.dev/packages/ai_sdk_dart) | `dart pub add ai` | `generateText`, `streamText`, tools, middleware, embeddings, registry |
| [`ai_sdk_openai`](https://pub.dev/packages/ai_sdk_openai) | `dart pub add ai_sdk_openai` | `openai('gpt-4.1-mini')`, embeddings, image gen, speech, transcription |
| [`ai_sdk_anthropic`](https://pub.dev/packages/ai_sdk_anthropic) | `dart pub add ai_sdk_anthropic` | `anthropic('claude-sonnet-4-5')`, extended thinking |
| [`ai_sdk_google`](https://pub.dev/packages/ai_sdk_google) | `dart pub add ai_sdk_google` | `google('gemini-2.0-flash')`, embeddings |
| [`ai_sdk_flutter_ui`](https://pub.dev/packages/ai_sdk_flutter_ui) | `dart pub add ai_sdk_flutter_ui` | `ChatController`, `CompletionController`, `ObjectStreamController` |
| [`ai_sdk_mcp`](https://pub.dev/packages/ai_sdk_mcp) | `dart pub add ai_sdk_mcp` | `MCPClient`, `SseClientTransport`, `StdioMCPTransport` |
| [`ai_sdk_provider`](https://pub.dev/packages/ai_sdk_provider) | *(transitive)* | Provider interfaces for building custom providers |

> `ai_sdk_provider` is a transitive dependency — you **do not** need to add it directly.

---

## 🚀 Quick Start

### Dart CLI

```sh
dart pub add ai_sdk_dart ai_sdk_openai
export OPENAI_API_KEY=sk-...
```

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';

void main() async {
  // Text generation
  final result = await generateText(
    model: openai('gpt-4.1-mini'),
    prompt: 'Say hello from AI SDK Dart!',
  );
  print(result.text);
}
```

### Streaming

```dart
final result = await streamText(
  model: openai('gpt-4.1-mini'),
  prompt: 'Count from 1 to 5.',
);
await for (final chunk in result.textStream) {
  stdout.write(chunk);
}
```

### Structured Output

```dart
final result = await generateText<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  prompt: 'Return the capital and currency of Japan as JSON.',
  output: Output.object(
    schema: Schema<Map<String, dynamic>>(
      jsonSchema: const {
        'type': 'object',
        'properties': {
          'capital': {'type': 'string'},
          'currency': {'type': 'string'},
        },
      },
      fromJson: (json) => json,
    ),
  ),
);
print(result.output); // {capital: Tokyo, currency: JPY}
```

### Type-Safe Tools

```dart
final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'What is the weather in Paris?',
  maxSteps: 5,
  tools: {
    'getWeather': tool<Map<String, dynamic>, String>(
      description: 'Get current weather for a city.',
      inputSchema: Schema(
        jsonSchema: const {
          'type': 'object',
          'properties': {'city': {'type': 'string'}},
        },
        fromJson: (json) => json,
      ),
      execute: (input, _) async => 'Sunny, 18°C',
    ),
  },
);
print(result.text);
```

### Flutter Chat UI

```sh
dart pub add ai_sdk_dart ai_sdk_openai ai_sdk_flutter
```

```dart
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';

final chat = ChatController(model: openai('gpt-4.1-mini'));

// In your widget:
await chat.append('Tell me a joke');
print(chat.messages.last.content);
```

---

## 🤖 Providers

| Capability | OpenAI | Anthropic | Google |
|---|:---:|:---:|:---:|
| Text generation | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ |
| Structured output | ✅ | ✅ | ✅ |
| Tool use | ✅ | ✅ | ✅ |
| Embeddings | ✅ | — | ✅ |
| Image generation | ✅ | — | — |
| Speech synthesis | ✅ | — | — |
| Transcription | ✅ | — | — |
| Extended thinking | — | ✅ | — |
| Multimodal (image input) | ✅ | ✅ | ✅ |

---

## 🛠️ Flutter UI Controllers

The `ai_sdk_flutter_ui` package provides three reactive controllers that integrate with any Flutter state management approach.

### ChatController — Multi-turn streaming chat

```dart
final chat = ChatController(model: openai('gpt-4.1-mini'));

// In your widget:
ListenableBuilder(
  listenable: chat,
  builder: (context, _) {
    return Column(
      children: [
        for (final msg in chat.messages)
          Text('${msg.role}: ${msg.content}'),
        if (chat.isLoading) const CircularProgressIndicator(),
      ],
    );
  },
);

// Send a message:
await chat.append('What is the capital of France?');
```

### CompletionController — Single-turn completion

```dart
final completion = CompletionController(model: openai('gpt-4.1-mini'));
await completion.complete('Write a haiku about Dart.');
print(completion.text);
```

### ObjectStreamController — Streaming typed JSON

```dart
final controller = ObjectStreamController<Map<String, dynamic>>(
  model: openai('gpt-4.1-mini'),
  schema: Schema<Map<String, dynamic>>(
    jsonSchema: const {'type': 'object'},
    fromJson: (json) => json,
  ),
);
await controller.submit('Describe Japan as a JSON object.');
print(controller.object); // Partial updates arrive in real-time
```

---

## 🔌 MCP Support

Connect to any [Model Context Protocol](https://modelcontextprotocol.io) server and use its tools directly in your AI calls:

```dart
import 'package:ai_sdk_mcp/ai_sdk_mcp.dart';

final client = MCPClient(
  transport: SseClientTransport(
    url: Uri.parse('http://localhost:3000/mcp'),
  ),
);

await client.initialize();
final tools = await client.tools(); // Returns a ToolSet

final result = await generateText(
  model: openai('gpt-4.1-mini'),
  prompt: 'What files are in the project?',
  tools: tools,
  maxSteps: 5,
);
```

For stdio-based MCP servers (local processes):

```dart
final client = MCPClient(
  transport: StdioMCPTransport(
    command: 'npx',
    args: ['-y', '@modelcontextprotocol/server-filesystem', '/path/to/dir'],
  ),
);
```

---

## 🗺️ Roadmap

### ✅ Implemented

- ✅ `generateText` — full result envelope (text, steps, usage, reasoning, sources, files)
- ✅ `streamText` — complete event taxonomy (22 typed event types)
- ✅ `generateObject` / structured output (object, array, choice, json)
- ✅ `embed` / `embedMany` + `cosineSimilarity`
- ✅ `generateImage` (OpenAI DALL-E 3)
- ✅ `generateSpeech` (OpenAI TTS)
- ✅ `transcribe` (OpenAI Whisper)
- ✅ `rerank`
- ✅ Middleware system with 5 built-in middlewares
- ✅ Provider registry (`createProviderRegistry`)
- ✅ Multi-step agentic loops with tool approval
- ✅ Flutter UI controllers (Chat, Completion, ObjectStream)
- ✅ MCP client (SSE + stdio transports)
- ✅ OpenAI, Anthropic, Google providers
- ✅ 178+ conformance tests

### 🔜 Planned

- 🔜 Video generation support
- 🔜 Streaming MCP tool outputs + automatic reconnection
- 🔜 Cohere / Vertex AI / Mistral / Ollama providers
- 🔜 Additional Flutter widgets (file picker, reasoning display, citation cards)
- 🔜 Dart Edge / Cloudflare Workers support
- 🔜 WebSocket transport for MCP

---

## 🤝 Contributing

Contributions are welcome! Please open an issue first to discuss changes before submitting a PR.

- 🐛 **Bug reports** — use the [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.md)
- 💡 **Feature requests** — use the [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.md)
- 💬 **Questions & discussions** — use [GitHub Discussions](https://github.com/codenameakshay/ai_sdk_dart/discussions)

### Running tests

```sh
dart pub global activate melos
melos bootstrap
melos test       # run all package tests
melos analyze    # dart analyze across all packages
```

Or with the Makefile:

```sh
make get      # install all workspace dependencies
make test     # run all package tests
make analyze  # run dart analyze
make format   # format all Dart source files
```

---

## Runnable examples

Set API keys before running:

```sh
export OPENAI_API_KEY=sk-...
export ANTHROPIC_API_KEY=sk-ant-...
export GOOGLE_API_KEY=AIza...
```

| Example | Command | What it shows |
|---------|---------|---------------|
| Dart CLI | `make run-basic` | `generateText`, streaming, structured output, tools, embeddings, middleware |
| Flutter chat | `make run` | ChatController, CompletionController, ObjectStreamController |
| Flutter chat (web) | `make run-web` | Same as above on Chrome |
| Advanced app | `make run-advanced` | All providers, image gen, TTS, STT, multimodal |
| Advanced app (web) | `make run-advanced-web` | Same as above on Chrome |

---

## Development

Managed with [Melos](https://melos.invertase.dev) as a monorepo workspace:

```sh
dart pub global activate melos
melos bootstrap
melos analyze
melos test
```

See [docs/v6-parity-matrix.md](docs/v6-parity-matrix.md) for a feature-by-feature parity matrix against Vercel AI SDK v6.

---

## 📄 License

[MIT](LICENSE)
