import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

const _defaultBaseUrl = 'https://api.mistral.ai/v1';

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
  MistralProvider({
    this.apiKey,
    this.baseUrl,
    CredentialProvider? credentialProvider,
    Dio? client,
  }) : _credentialProvider =
           credentialProvider ??
           (() => apiKey ?? const String.fromEnvironment('MISTRAL_API_KEY')),
       _client = client ?? _mistralDio(baseUrl: baseUrl),
       _ownsClient = client == null;

  /// Mistral API key (defaults to `MISTRAL_API_KEY` env variable).
  final String? apiKey;

  /// Base URL — defaults to `https://api.mistral.ai/v1`.
  final String? baseUrl;

  final CredentialProvider _credentialProvider;
  final Dio _client;
  final bool _ownsClient;

  Future<Map<String, String>> _headers() async {
    final key = await _credentialProvider();
    return {if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key'};
  }

  void dispose({bool force = true}) {
    if (_ownsClient) {
      _client.close(force: force);
    }
  }

  /// Returns a language model for the given [modelId].
  LanguageModelV4 call(String modelId) => OpenAICompatibleChatLanguageModel(
    modelId: modelId,
    config: OpenAICompatibleConfig(
      provider: 'mistral',
      baseUrl: baseUrl ?? _defaultBaseUrl,
      headers: _headers,
      client: _client,
      extraBody: (options) => options.providerOptions?['mistral'],
      // Mistral names the seed field `random_seed` and uses `max_tokens`.
      seedKey: 'random_seed',
      maxTokensKey: 'max_tokens',
    ),
  );

  /// Returns an embedding model for the given [modelId].
  EmbeddingModelV2<String> embedding(String modelId) => _MistralEmbeddingModel(
    modelId: modelId,
    baseUrl: baseUrl,
    client: _client,
    headers: _headers,
  );
}

/// Default Mistral provider instance.
final mistral = MistralProvider();

// ---------------------------------------------------------------------------
// HTTP helper (embedding model only)
// ---------------------------------------------------------------------------

Dio _mistralDio({String? baseUrl}) => createProviderDio(
  baseUrl: baseUrl ?? _defaultBaseUrl,
  headers: {'Content-Type': 'application/json'},
);

// ---------------------------------------------------------------------------
// Embedding model
// ---------------------------------------------------------------------------

class _MistralEmbeddingModel implements EmbeddingModelV2<String> {
  _MistralEmbeddingModel({
    required this.modelId,
    required this.baseUrl,
    required this.client,
    required this.headers,
  });

  @override
  final String modelId;
  final String? baseUrl;
  final Dio client;
  final RequestHeadersProvider headers;

  @override
  String get provider => 'mistral';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final resolvedHeaders = await headers();
    final providerOptions = options.providerOptions?['mistral'];
    final body = <String, dynamic>{
      'model': modelId,
      'input': options.values,
      ...?providerOptions,
    };

    final Response<Map<String, dynamic>> response;
    try {
      response = await client.post<Map<String, dynamic>>(
        providerEndpoint(baseUrl ?? _defaultBaseUrl, '/embeddings'),
        data: body,
        options: Options(headers: {...?options.headers, ...resolvedHeaders}),
      );
    } on DioException catch (e) {
      throw await apiErrorFromDioException(e, provider: provider);
    }
    final data = response.data!;
    return parseOpenAiEmbeddings(data, options.values);
  }
}
