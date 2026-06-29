import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Mistral AI provider for language models and embeddings.
///
/// Use [call] to create a language model for a given model ID, and [embedding]
/// for an embedding model.
///
/// Example:
/// ```dart
/// final model = mistral('mistral-large-latest');
/// final embedder = mistral.embedding('mistral-embed');
/// ```
///
/// Language models speak the OpenAI Chat Completions wire format via the shared
/// `ai_sdk_openai_compatible` base, so tool calling and multimodal content are
/// supported. Mistral's `random_seed` and `max_tokens` field names are applied.
class MistralProvider {
  const MistralProvider({this.apiKey, this.baseUrl});

  /// Mistral API key (defaults to `MISTRAL_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.mistral.ai/v1`.
  final String? baseUrl;

  /// Returns a language model for the given [modelId].
  LanguageModelV3 call(String modelId) => OpenAICompatibleChatLanguageModel(
    modelId: modelId,
    config: OpenAICompatibleConfig(
      provider: 'mistral',
      baseUrl: baseUrl ?? 'https://api.mistral.ai/v1',
      headers: () {
        final key = apiKey ?? const String.fromEnvironment('MISTRAL_API_KEY');
        return {'Authorization': 'Bearer $key'};
      },
      // Mistral names the seed field `random_seed` and uses `max_tokens`.
      seedKey: 'random_seed',
      maxTokensKey: 'max_tokens',
    ),
  );

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) => _MistralEmbeddingModel(
    modelId: modelId,
    apiKey: apiKey,
    baseUrl: baseUrl,
  );
}

/// Default Mistral provider instance.
const mistral = MistralProvider();

// ---------------------------------------------------------------------------
// HTTP helper (embedding model only)
// ---------------------------------------------------------------------------

Dio _mistralDio({String? apiKey, String? baseUrl}) {
  final key = apiKey ?? const String.fromEnvironment('MISTRAL_API_KEY');
  return Dio(
    BaseOptions(
      baseUrl: baseUrl ?? 'https://api.mistral.ai/v1',
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      },
    ),
  );
}

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _MistralEmbeddingModel implements EmbeddingModelV2<String> {
  const _MistralEmbeddingModel({
    required this.modelId,
    this.apiKey,
    this.baseUrl,
  });

  @override
  final String modelId;
  final String? apiKey;
  final String? baseUrl;

  @override
  String get provider => 'mistral';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _mistralDio(apiKey: apiKey, baseUrl: baseUrl);

    final body = <String, dynamic>{'model': modelId, 'input': options.values};

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/embeddings',
        data: body,
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }
    final data = response.data!;
    final dataList = (data['data'] as List?) ?? [];
    final embeddings = dataList.asMap().entries.map((entry) {
      final item = entry.value as Map<String, dynamic>;
      final vector = (item['embedding'] as List).cast<double>();
      return EmbeddingModelV2Embedding<String>(
        value: options.values[entry.key],
        embedding: vector,
      );
    }).toList();

    return EmbeddingModelV2GenerateResult<String>(embeddings: embeddings);
  }
}
