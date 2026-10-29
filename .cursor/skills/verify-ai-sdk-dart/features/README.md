# AI SDK Dart verification map

This directory is the maintained source for verifying the user-facing features of the 18 AI SDK Dart packages. Read this index before a run, then use the matching package file as the recipe.

## Baseline preconditions

- `V=.cursor/skills/verify-ai-sdk-dart/scripts/verify`.
- `$V setup` has been run once, and `$V doctor` prints no `FAIL` line.
- For live checks, `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` (or their `*_FILE` forms) are set in the same call, and the user has approved the spend.
- For `ai_sdk_flutter_ui`, the preconditions of the verify-flutter-chat skill apply instead.

## Driving conventions

- Run one package with `$V run <package>`, or one sub-feature with `$V run <package> --check <id>`. `$V list <package>` shows the ids.
- Use one `VERIFY_RUN_ID` for a whole verification task, so that `summary.md` collects every package you ran.
- Treat the commands and expected values in the feature files as literal.
- Fixture mode needs no external network. A check that reaches an external host in fixture mode is a defect in the check.

## Proof and skip reporting

- A sub-feature is verified within the scope of its passing assertions. For network checks, inspect the asserted request (`exchanges`) and result (`observed`). In-memory codecs, validators, helpers, and custom models can pass with no exchanges. Some transports record their frames in `observed` or artifacts instead.
- Name the mode: fixture (adapter mapping against the documented wire format) or live (current vendor behavior). They are different claims.
- Report a SKIP with its reason (`live check; rerun with --live`, `missing OPENAI_API_KEY`). Never report a skip as a pass.
- Report the feature file's "Not covered" lines for any package you claim to have verified.
- A failing check is a finding. Report its evidence path and reason. Do not weaken the check.

## Feature entry contract

Each feature file starts with an H1 (the package name) and one paragraph that describes what a developer gets. Then it has exactly four H2s in this order:

1. `Sub-features`: one line per short ID.
2. `How to get to it (user POV)`: the public entry points (constructors, functions, factories).
3. `Driving it with verify`: starts with `Preconditions:`, then labeled bullets. Each bullet pairs a sub-feature with an exact command and the evidence that proves it.
4. `Gotchas`: traps, documented behavior that surprises, and "Not covered: <item>: <reason>" lines.

## Features

Core and contracts:

- [ai_sdk_provider](./ai_sdk_provider.md): the model interfaces a provider author implements, checked end to end through custom providers.
- [ai_sdk_dart: text, structured output, tools, agents](./ai_sdk_dart-text.md): generateText, streamText, Output, generateObject, tools, approval, ToolLoopAgent, cancellation and timeouts.
- [ai_sdk_dart: embeddings, media, middleware, registry, errors](./ai_sdk_dart-platform.md): embed, image, speech, transcription, rerank, middleware, the registry, retries, telemetry and testing utilities.
- [ai_sdk_json_schema](./ai_sdk_json_schema.md): runtime validation of tool inputs and structured output.

Conversations and transport:

- [ai_sdk_conversation](./ai_sdk_conversation.md): lossless snapshots, codecs, and agent turns that resume after approval.
- [ai_sdk_remote](./ai_sdk_remote.md): the UI-message stream transport, against the pinned Vercel AI SDK backend.
- [ai_sdk_realtime](./ai_sdk_realtime.md): the experimental Realtime WebSocket session, fixture only.
- [ai_sdk_telemetry](./ai_sdk_telemetry.md): the OTLP HTTP metrics exporter, against a fixture collector.
- [ai_sdk_mcp](./ai_sdk_mcp.md): the MCP client over Streamable HTTP and stdio, against the pinned TypeScript SDK server.

Providers:

- [ai_sdk_openai_compatible](./ai_sdk_openai_compatible.md): the shared Chat Completions base (the reference module).
- [ai_sdk_openai](./ai_sdk_openai.md): Chat, Responses, embeddings, images, speech, transcription, files and batches. Live checks.
- [ai_sdk_anthropic](./ai_sdk_anthropic.md): Messages, streaming, tools, thinking and caching. Live checks.
- [ai_sdk_google](./ai_sdk_google.md): Gemini generateContent, streaming, tools, thinking, embeddings and grounding.
- [ai_sdk_azure](./ai_sdk_azure.md): Azure OpenAI deployments, api-key and api-version.
- [ai_sdk_cohere](./ai_sdk_cohere.md): chat v2, embeddings and rerank.
- [ai_sdk_groq](./ai_sdk_groq.md): Groq chat, structured output and reasoning.
- [ai_sdk_mistral](./ai_sdk_mistral.md): Mistral chat, options and embeddings.
- [ai_sdk_ollama](./ai_sdk_ollama.md): the local Ollama NDJSON chat and embeddings.

UI:

- [ai_sdk_flutter_ui](./ai_sdk_flutter_ui.md): the controllers and widgets, driven in flutter_chat and advanced_app through the verify-flutter-chat skill.
