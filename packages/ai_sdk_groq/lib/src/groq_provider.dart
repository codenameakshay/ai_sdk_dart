import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Groq provider for language models.
///
/// Use [call] to create a language model for a given model ID.
///
/// Example:
/// ```dart
/// final model = groq('llama3-8b-8192');
/// final result = await model.doGenerate(options);
/// ```
///
/// Speaks the OpenAI Chat Completions wire format via the shared
/// `ai_sdk_openai_compatible` base, so tool calling and multimodal content are
/// supported.
class GroqProvider {
  const GroqProvider({this.apiKey, this.baseUrl});

  /// Groq API key (defaults to `GROQ_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.groq.com/openai/v1`.
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) => OpenAICompatibleChatLanguageModel(
    modelId: modelId,
    config: OpenAICompatibleConfig(
      provider: 'groq',
      baseUrl: baseUrl ?? 'https://api.groq.com/openai/v1',
      headers: () {
        final key = apiKey ?? const String.fromEnvironment('GROQ_API_KEY');
        return {'Authorization': 'Bearer $key'};
      },
      // Groq uses the classic `max_tokens` field.
      maxTokensKey: 'max_tokens',
    ),
  );
}

/// Default Groq provider instance.
const groq = GroqProvider();
