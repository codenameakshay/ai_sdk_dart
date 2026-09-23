import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';

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
  AzureOpenAIProvider({
    required this.endpoint,
    this.apiKey,
    CredentialProvider? credentialProvider,
    Dio? client,
    this.apiVersion = '2024-02-15-preview',
  }) : _credentialProvider = credentialProvider ?? (() => apiKey),
       _client = client ?? _azureDio(endpoint: endpoint),
       _ownsClient = client == null;

  /// The Azure OpenAI endpoint URL, e.g.
  /// `https://my-resource.openai.azure.com`.
  final String endpoint;

  /// The Azure OpenAI API key.
  final String? apiKey;

  /// The API version to use for all requests.
  final String apiVersion;

  final CredentialProvider _credentialProvider;
  final Dio _client;
  final bool _ownsClient;

  Future<Map<String, String>> _headers() async {
    final key = await _credentialProvider();
    return {if (key != null && key.isNotEmpty) 'api-key': key};
  }

  void dispose({bool force = true}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  /// Returns a language model for the given Azure deployment [deploymentId].
  LanguageModelV4 call(String deploymentId) =>
      OpenAICompatibleChatLanguageModel(
        modelId: deploymentId,
        config: OpenAICompatibleConfig(
          provider: 'azure',
          baseUrl: providerEndpoint(
            endpoint,
            '/openai/deployments/$deploymentId',
          ),
          headers: _headers,
          client: _client,
          queryParameters: {'api-version': apiVersion},
          extraBody: (options) => options.providerOptions?['azure'],
          // Azure (like classic OpenAI deployments) uses `max_tokens`.
          maxTokensKey: 'max_tokens',
        ),
      );

  /// Returns a model backed by Azure's Responses API.
  LanguageModelV4 responses(String deploymentId) =>
      OpenAIResponsesLanguageModel(
        modelId: deploymentId,
        providerName: 'azure',
        baseUrl: providerEndpoint(
          endpoint,
          '/openai/deployments/$deploymentId',
        ),
        headers: _headers,
        client: _client,
        queryParameters: {'api-version': apiVersion},
      );

  /// Explicit Chat Completions escape hatch.
  LanguageModelV4 chat(String deploymentId) => call(deploymentId);

  /// Returns an embedding model for the given Azure deployment [deploymentId].
  EmbeddingModelV2<String> embedding(String deploymentId) =>
      _AzureEmbeddingModel(
        deploymentId: deploymentId,
        endpoint: endpoint,
        client: _client,
        headers: _headers,
        apiVersion: apiVersion,
      );
}

/// Default Azure OpenAI provider instance (endpoint and apiKey must be set
/// before use).
final azureOpenAI = AzureOpenAIProvider(endpoint: '');

// ---------------------------------------------------------------------------
// HTTP helper
// ---------------------------------------------------------------------------

Dio _azureDio({required String endpoint}) => createProviderDio(
  baseUrl: endpoint,
  headers: {'Content-Type': 'application/json'},
);

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _AzureEmbeddingModel implements EmbeddingModelV2<String> {
  @override
  int? get maxEmbeddingsPerCall => 2048;

  @override
  bool get supportsParallelCalls => true;

  _AzureEmbeddingModel({
    required this.deploymentId,
    required this.endpoint,
    required this.client,
    required this.headers,
    required this.apiVersion,
  });

  final String deploymentId;
  final String endpoint;
  final Dio client;
  final RequestHeadersProvider headers;
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
    final resolvedHeaders = await headers();
    final providerOptions = options.providerOptions?['azure'];
    final body = <String, dynamic>{
      'input': options.values,
      'model': deploymentId,
      ...?providerOptions,
    };

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        providerEndpoint(
          endpoint,
          '/openai/deployments/$deploymentId/embeddings',
        ),
        queryParameters: {'api-version': apiVersion},
        data: body,
        options: Options(headers: {...?options.headers, ...resolvedHeaders}),
        cancelToken: cancelTokenFor(options.abortSignal),
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }
    final data = response.data;
    if (data == null) {
      throw _invalidResponse(response);
    }
    try {
      return parseOpenAiEmbeddings(data, options.values);
    } on Object catch (error) {
      throw _invalidResponse(response, error);
    }
  }
}

AiApiCallError _invalidResponse<T>(Response<T> response, [Object? cause]) =>
    AiApiCallError(
      'Azure returned an invalid 2xx response body.',
      statusCode: response.statusCode,
      url: response.requestOptions.uri.toString(),
      cause: cause,
    );
