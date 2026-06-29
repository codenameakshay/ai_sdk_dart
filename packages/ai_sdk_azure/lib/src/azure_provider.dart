import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Azure OpenAI provider for language models and embeddings.
///
/// Use [call] to create a language model for a deployment, and [embedding]
/// for an embedding model.
///
/// Example:
/// ```dart
/// final provider = AzureOpenAIProvider(
///   endpoint: 'https://my-resource.openai.azure.com',
///   apiKey: 'my-api-key',
/// );
/// final model = provider('gpt-4-deployment');
/// final result = await model.doGenerate(options);
/// ```
///
/// Language models speak the OpenAI Chat Completions wire format via the shared
/// `ai_sdk_openai_compatible` base, so tool calling, multimodal content, and
/// structured output are supported. Azure's `api-key` header and `api-version`
/// query parameter are applied.
class AzureOpenAIProvider {
  const AzureOpenAIProvider({
    required this.endpoint,
    required this.apiKey,
    this.apiVersion = '2024-02-15-preview',
  });

  /// The Azure OpenAI endpoint URL, e.g.
  /// `https://my-resource.openai.azure.com`.
  final String endpoint;

  /// The Azure OpenAI API key.
  final String apiKey;

  /// The API version to use for all requests.
  final String apiVersion;

  /// Returns a language model for the given Azure deployment [deploymentId].
  LanguageModelV3 call(String deploymentId) =>
      OpenAICompatibleChatLanguageModel(
        modelId: deploymentId,
        config: OpenAICompatibleConfig(
          provider: 'azure',
          baseUrl: '$endpoint/openai/deployments/$deploymentId',
          headers: () => {'api-key': apiKey},
          queryParameters: {'api-version': apiVersion},
          // Azure (like classic OpenAI deployments) uses `max_tokens`.
          maxTokensKey: 'max_tokens',
        ),
      );

  /// Returns an embedding model for the given Azure deployment [deploymentId].
  EmbeddingModelV2<String> embedding(String deploymentId) =>
      _AzureEmbeddingModel(
        deploymentId: deploymentId,
        endpoint: endpoint,
        apiKey: apiKey,
        apiVersion: apiVersion,
      );
}

/// Default Azure OpenAI provider instance (endpoint and apiKey must be set
/// before use).
const azureOpenAI = AzureOpenAIProvider(endpoint: '', apiKey: '');

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _azureDio({
  required String endpoint,
  required String deploymentId,
  required String apiKey,
}) {
  return Dio(
    BaseOptions(
      baseUrl: '$endpoint/openai/deployments/$deploymentId',
      headers: {'api-key': apiKey, 'Content-Type': 'application/json'},
    ),
  );
}

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _AzureEmbeddingModel implements EmbeddingModelV2<String> {
  const _AzureEmbeddingModel({
    required this.deploymentId,
    required this.endpoint,
    required this.apiKey,
    required this.apiVersion,
  });

  final String deploymentId;
  final String endpoint;
  final String apiKey;
  final String apiVersion;

  @override
  String get modelId => deploymentId;

  @override
  String get provider => 'azure';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final client = _azureDio(
      endpoint: endpoint,
      deploymentId: deploymentId,
      apiKey: apiKey,
    );

    final body = <String, dynamic>{
      'input': options.values,
      'model': deploymentId,
    };

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        '/embeddings',
        queryParameters: {'api-version': apiVersion},
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
