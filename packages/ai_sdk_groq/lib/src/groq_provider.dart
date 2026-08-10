import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

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
  GroqProvider({
    this.apiKey,
    this.baseUrl,
    CredentialProvider? credentialProvider,
    Dio? client,
  }) : _credentialProvider =
           credentialProvider ??
           (() => apiKey ?? const String.fromEnvironment('GROQ_API_KEY')),
       _client = client ?? _groqDio(baseUrl: baseUrl),
       _ownsClient = client == null;

  /// Groq API key (defaults to `GROQ_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.groq.com/openai/v1`.
  final String? baseUrl;

  final CredentialProvider _credentialProvider;
  final Dio _client;
  final bool _ownsClient;

  Future<Map<String, String>> _headers() async {
    final key = await Future.value(_credentialProvider());
    return {if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key'};
  }

  void dispose({bool force = true}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) => OpenAICompatibleChatLanguageModel(
    modelId: modelId,
    config: OpenAICompatibleConfig(
      provider: 'groq',
      baseUrl: baseUrl ?? 'https://api.groq.com/openai/v1',
      headers: _headers,
      client: _client,
      // Groq uses the classic `max_tokens` field.
      maxTokensKey: 'max_tokens',
    ),
  );
}

/// Default Groq provider instance.
final groq = GroqProvider();

Dio _groqDio({String? baseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.groq.com/openai/v1',
      headers: {'Content-Type': 'application/json'},
      responseType: ResponseType.json,
    ),
  );
}
