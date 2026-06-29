# 🤖 AI SDK Dart

**A Dart/Flutter port of [Vercel AI SDK v6](https://sdk.vercel.ai) — provider-agnostic APIs for text generation, streaming, structured output, tool use, embeddings, image generation, speech, and more.**

[![ai_sdk_dart pub.dev](https://img.shields.io/pub/v/ai_sdk_dart.svg?label=ai_sdk_dart)](https://pub.dev/packages/ai_sdk_dart)
[![ai_sdk_openai pub.dev](https://img.shields.io/pub/v/ai_sdk_openai.svg?label=ai_sdk_openai)](https://pub.dev/packages/ai_sdk_openai)
[![ai_sdk_anthropic pub.dev](https://img.shields.io/pub/v/ai_sdk_anthropic.svg?label=ai_sdk_anthropic)](https://pub.dev/packages/ai_sdk_anthropic)
[![ai_sdk_google pub.dev](https://img.shields.io/pub/v/ai_sdk_google.svg?label=ai_sdk_google)](https://pub.dev/packages/ai_sdk_google)
[![ai_sdk_azure pub.dev](https://img.shields.io/pub/v/ai_sdk_azure.svg?label=ai_sdk_azure)](https://pub.dev/packages/ai_sdk_azure)
[![ai_sdk_cohere pub.dev](https://img.shields.io/pub/v/ai_sdk_cohere.svg?label=ai_sdk_cohere)](https://pub.dev/packages/ai_sdk_cohere)
[![ai_sdk_groq pub.dev](https://img.shields.io/pub/v/ai_sdk_groq.svg?label=ai_sdk_groq)](https://pub.dev/packages/ai_sdk_groq)
[![ai_sdk_mistral pub.dev](https://img.shields.io/pub/v/ai_sdk_mistral.svg?label=ai_sdk_mistral)](https://pub.dev/packages/ai_sdk_mistral)
[![ai_sdk_ollama pub.dev](https://img.shields.io/pub/v/ai_sdk_ollama.svg?label=ai_sdk_ollama)](https://pub.dev/packages/ai_sdk_ollama)
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
- `smoothStream` transform — configurable chunk-size smoothing; `delayInMs` option adds per-chunk delay for UX pacing
- Multi-step agentic loops with `maxSteps`, `prepareStep`, and `stopConditions`
- `timeout` parameter on all core functions — apply `Duration` deadlines to any model call
- Callbacks: `onFinish`, `onStepFinish`, `onChunk`, `onError`, `experimentalOnStart`, `onAbort`

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
- `generateImage` — image generation (gpt-image-1 / DALL·E via OpenAI)
- `generateSpeech` — text-to-speech audio synthesis
- `transcribe` — speech-to-text transcription
- Image inputs in prompts (multimodal vision)

### 🧮 Embeddings & Cosine Similarity
- `embed()` — single value embedding with usage tracking
- `embedMany()` — batch embedding for multiple values with configurable chunk size
- `cosineSimilarity()` — built-in similarity computation
- `wrapEmbeddingModel()` — composable middleware pipeline for embedding models

### 🧱 Middleware System
- `wrapLanguageModel(model, middlewares)` — composable middleware pipeline
- `extractReasoningMiddleware` — strips `<think>` tags into `ReasoningPart`
- `extractJsonMiddleware` — strips ` ```json ``` ` fences
- `simulateStreamingMiddleware` — converts non-streaming models to streaming
- `defaultSettingsMiddleware` — applies default temperature/top-p/etc.
- `addToolInputExamplesMiddleware` — enriches tool descriptions with examples
- `wrapEmbeddingModel` / `wrapImageModel` — the same composable middleware pattern for embedding and image models

### 🌐 Provider Registry
- `createProviderRegistry` — map provider aliases to model factories
- `customProvider()` — lightweight on-the-fly provider construction without a full registry
- Resolve models by `'provider:modelId'` string at runtime
- Supports 5 model categories: language, embedding, image, speech, transcription
- Mix providers in a single registry for multi-provider apps

### 📱 Flutter UI Controllers & Widgets
- `ChatController` — multi-turn streaming chat with message history
- `CompletionController` — single-turn text completion with status
- `ObjectStreamController` — streaming typed JSON object updates
- **19 prebuilt, themeable Material widgets** — `AiChatScaffold`, message list/bubbles, composer,
  streaming text, typing indicator, tool-call & approval cards, reasoning, citations, usage, and more

### 🔌 MCP Client (Model Context Protocol)
- `MCPClient` — connect to MCP servers, discover tools, invoke them
- `SseClientTransport` — real Server-Sent-Events streaming transport (MCP HTTP+SSE 2024-11-05)
- `HttpClientTransport` — plain request/response POST transport for single-endpoint servers
- `StdioMCPTransport` — stdio process transport (native platforms)
- **Web-safe** — `dart:io` is isolated behind conditional imports, so the client runs on Flutter web
- Discovered tools are directly compatible with `generateText`/`streamText`

### 🧪 Conformance Suite
- **999 tests** (878 Dart + 121 Flutter) covering every public API
- **99.6% line coverage** overall — 9 of 12 packages at 100%, enforced by a CI coverage gate
- Spec-driven JSON fixtures as the source of truth
- Provider wire-format conformance tests for every provider
- `MockEmbeddingModelV3` testing utility for embedding model conformance

---

## 📦 Packages

| Package | pub.dev | What it gives you |
|---------|---------|-------------------|
| [`ai_sdk_dart`](https://pub.dev/packages/ai_sdk_dart) | `dart pub add ai_sdk_dart` | `generateText`, `streamText`, tools, middleware, embeddings, registry |
| [`ai_sdk_openai`](https://pub.dev/packages/ai_sdk_openai) | `dart pub add ai_sdk_openai` | `openai('gpt-4.1-mini')`, embeddings, image gen, speech, transcription, reasoning options |
| [`ai_sdk_anthropic`](https://pub.dev/packages/ai_sdk_anthropic) | `dart pub add ai_sdk_anthropic` | `anthropic('claude-sonnet-4-5')`, extended thinking, speed options |
| [`ai_sdk_google`](https://pub.dev/packages/ai_sdk_google) | `dart pub add ai_sdk_google` | `google('gemini-2.0-flash')`, embeddings |
| [`ai_sdk_azure`](https://pub.dev/packages/ai_sdk_azure) | `dart pub add ai_sdk_azure` | `AzureOpenAIProvider(endpoint, apiKey)`, language models, embeddings |
| [`ai_sdk_cohere`](https://pub.dev/packages/ai_sdk_cohere) | `dart pub add ai_sdk_cohere` | `cohere('command-r-plus')`, embeddings, reranking |
| [`ai_sdk_groq`](https://pub.dev/packages/ai_sdk_groq) | `dart pub add ai_sdk_groq` | `groq('llama3-8b-8192')`, ultra-low latency inference |
| [`ai_sdk_mistral`](https://pub.dev/packages/ai_sdk_mistral) | `dart pub add ai_sdk_mistral` | `mistral('mistral-large-latest')`, embeddings |
| [`ai_sdk_ollama`](https://pub.dev/packages/ai_sdk_ollama) | `dart pub add ai_sdk_ollama` | `ollama('llama3')`, local inference, embeddings |
| [`ai_sdk_flutter_ui`](https://pub.dev/packages/ai_sdk_flutter_ui) | `dart pub add ai_sdk_flutter_ui` | `ChatController`, `CompletionController`, `ObjectStreamController` + 19 prebuilt chat widgets |
| [`ai_sdk_mcp`](https://pub.dev/packages/ai_sdk_mcp) | `dart pub add ai_sdk_mcp` | `MCPClient`, `SseClientTransport`, `HttpClientTransport`, `StdioMCPTransport` (web-safe) |
| [`ai_sdk_provider`](https://pub.dev/packages/ai_sdk_provider) | *(transitive)* | Provider interfaces for building custom providers |
| `ai_sdk_openai_compatible` | *(transitive)* | Shared OpenAI Chat Completions base — powers the OpenAI/Azure/Groq/Mistral language models |

> `ai_sdk_provider` and `ai_sdk_openai_compatible` are transitive dependencies — you **do not** need to add them directly.

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
dart pub add ai_sdk_dart ai_sdk_openai ai_sdk_flutter_ui
```

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';

final agent = ToolLoopAgent(
  model: openai('gpt-4.1-mini'),
  instructions: 'You are a helpful assistant.',
);
final chat = ChatController();

// In your widget — a complete chat surface:
AiChatScaffold(controller: chat, agent: agent);
```

---

## 🤖 Providers

| Capability | OpenAI | Anthropic | Google | Azure | Cohere | Groq | Mistral | Ollama |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Text generation | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Structured output | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Native JSON schema output | ✅ | — | — | ✅ | — | ✅ | ✅ | — |
| Tool use | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Embeddings | ✅ | — | ✅ | ✅ | ✅ | — | ✅ | ✅ |
| Reranking | — | — | — | — | ✅ | — | — | — |
| Image generation | ✅ | — | — | — | — | — | — | — |
| Speech synthesis | ✅ | — | — | — | — | — | — | — |
| Transcription | ✅ | — | — | — | — | — | — | — |
| Extended thinking | — | ✅ | — | — | — | — | — | — |
| Reasoning options | ✅ | — | — | — | — | — | — | — |
| Multimodal (image input) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## 🛠️ Flutter UI

The `ai_sdk_flutter_ui` package provides three reactive controllers plus a library of **19 prebuilt,
themeable Material widgets** — so you can wire up a full chat UI in a few lines, or drop down to the
controllers and render everything yourself.

### Drop-in chat UI

```dart
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';

final agent = ToolLoopAgent(model: openai('gpt-4.1-mini'));
final chat = ChatController();

// A complete message list + composer, wired to the controller + agent:
AiChatScaffold(controller: chat, agent: agent);
```

Other widgets — `ChatMessageList`, `ChatMessageBubble`, `ChatComposer`, `StreamingTextView`,
`TypingIndicator`, `ToolCallCard`, `ToolApprovalCard`, `ReasoningView`, `SourceCitations`,
`UsageView`, `PromptSuggestions`, `ObjectStreamView`, and more — can be composed à la carte. They
read only the controllers' public state, so they work with any state-management approach.

### ChatController — Multi-turn streaming chat

```dart
final agent = ToolLoopAgent(model: openai('gpt-4.1-mini'));
final chat = ChatController();

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
await chat.sendMessage(agent: agent, text: 'What is the capital of France?');
```

### CompletionController — Single-turn completion

```dart
final completion = CompletionController(
  agent: ToolLoopAgent(model: openai('gpt-4.1-mini')),
);
await completion.complete('Write a haiku about Dart.');
print(completion.completion);
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
print(controller.value); // Partial updates arrive in real-time
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

`SseClientTransport` does real Server-Sent-Events streaming (and surfaces server-pushed
notifications); for servers that expose a single JSON-RPC POST endpoint without SSE, use
`HttpClientTransport`. The HTTP/SSE transports are web-safe — `dart:io` is only pulled in by
`StdioMCPTransport` on native platforms, behind a conditional import — so the client also runs on
Flutter web.

---

## 🗺️ Roadmap

### ✅ Implemented

- ✅ `generateText` — full result envelope (text, steps, usage, reasoning, sources, files)
- ✅ `streamText` — complete event taxonomy (20 typed event types), `onAbort` callback
- ✅ `generateObject` / structured output (object, array, choice, json) with native JSON schema
- ✅ `embed` / `embedMany` + `cosineSimilarity`, `wrapEmbeddingModel`
- ✅ `generateImage` (OpenAI gpt-image-1 / DALL·E)
- ✅ `generateSpeech` (OpenAI TTS)
- ✅ `transcribe` (OpenAI Whisper)
- ✅ `rerank`
- ✅ `timeout` parameter on all core functions
- ✅ `customProvider()` for lightweight on-the-fly provider construction
- ✅ Middleware system — 5 built-in language-model middlewares, plus embedding & image model middleware
- ✅ Provider registry (`createProviderRegistry`) — 5 model categories
- ✅ Multi-step agentic loops with tool approval
- ✅ Flutter UI controllers (Chat, Completion, ObjectStream) + 19 prebuilt Material widgets
- ✅ MCP client (real SSE + HTTP + stdio transports, prompts, resources, web-safe)
- ✅ OpenAI (with reasoning options), Anthropic (with thinking options), Google providers
- ✅ Cohere, Mistral, Groq, Ollama, Azure OpenAI providers — all with tools + multimodal
- ✅ 999 tests, 99.6% line coverage with a CI coverage gate

### 🔜 Planned

- 🔜 Streaming MCP tool outputs
- 🔜 Richer attachment widgets (file/image pickers, audio capture)
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
| Advanced app | `make run-advanced` | All providers, tools, image gen, TTS, STT, multimodal, embeddings, completion, object stream + widget gallery |
| Advanced app (web) | `make run-advanced-web` | Same as above on Chrome |
| MCP demo | `make run-mcp` | MCP tool discovery + direct tool calls (works without an API key) |

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
