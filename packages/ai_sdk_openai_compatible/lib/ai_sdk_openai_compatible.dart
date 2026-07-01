/// Shared OpenAI Chat Completions base for AI SDK Dart providers.
///
/// Implements tool calling, multimodal content, structured output, and SSE
/// streaming once, behind a small per-provider [OpenAICompatibleConfig]. Used by
/// `ai_sdk_openai`, `ai_sdk_azure`, `ai_sdk_groq`, and `ai_sdk_mistral`.
///
/// This is infrastructure, not a vendor provider — it has no callable factory of
/// its own. See `docs/adr/0004-openai-compatible-base.md`.
library ai_sdk_openai_compatible;

export 'src/api_error.dart';
export 'src/openai_compatible_chat_language_model.dart';
export 'src/openai_compatible_config.dart';
