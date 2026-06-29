import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Builds a [Dio] client for a given base URL and headers.
///
/// Providers may override this to inject interceptors or reuse a client; the
/// default ([OpenAICompatibleConfig.defaultClientFactory]) creates a fresh
/// [Dio] with the base URL and JSON content type configured.
typedef DioFactory =
    Dio Function({
      required String baseUrl,
      required Map<String, String> headers,
    });

/// Per-provider configuration for [OpenAICompatibleChatLanguageModel].
///
/// This is the small interface in front of a deep module: everything that
/// differs between OpenAI-compatible providers (auth scheme, base URL, query
/// params, body field names, feature support) lives here. The model itself owns
/// all the shared OpenAI Chat Completions behavior.
///
/// Example (Groq):
/// ```dart
/// OpenAICompatibleConfig(
///   provider: 'groq',
///   baseUrl: 'https://api.groq.com/openai/v1',
///   headers: () => {'Authorization': 'Bearer $apiKey'},
/// );
/// ```
class OpenAICompatibleConfig {
  /// Creates a configuration. Only [provider], [baseUrl] and [headers] are
  /// required; the rest carry sensible OpenAI-compatible defaults.
  const OpenAICompatibleConfig({
    required this.provider,
    required this.baseUrl,
    required this.headers,
    this.queryParameters,
    this.seedKey = 'seed',
    this.maxTokensKey = 'max_completion_tokens',
    this.supportsTools = true,
    this.supportsMultimodal = true,
    this.supportsResponseFormatJsonSchema = true,
    this.includeStreamUsageOption = true,
    this.extraBody,
    this.clientFactory = defaultClientFactory,
  });

  /// Short provider name, e.g. `'openai'`, `'azure'`, `'groq'`, `'mistral'`.
  ///
  /// Used as the `provider` of the model and as the key under which
  /// `providerOptions` and stream `providerMetadata` are read/written.
  final String provider;

  /// The base URL the `/chat/completions` path is appended to,
  /// e.g. `https://api.groq.com/openai/v1` or
  /// `https://my-resource.openai.azure.com/openai/deployments/my-deployment`.
  final String baseUrl;

  /// Builds the request headers (typically the auth header).
  ///
  /// OpenAI/Groq/Mistral use `{'Authorization': 'Bearer <key>'}`; Azure uses
  /// `{'api-key': <key>}`. `Content-Type: application/json` is added by the
  /// default client factory, so it need not be returned here.
  final Map<String, String> Function() headers;

  /// Static query parameters added to every request, e.g. Azure's
  /// `{'api-version': '2024-02-15-preview'}`. `null` when none are needed.
  final Map<String, String>? queryParameters;

  /// The request body key for the deterministic sampling seed.
  ///
  /// `'seed'` for OpenAI/Azure/Groq, `'random_seed'` for Mistral.
  final String seedKey;

  /// The request body key for the maximum output token count.
  ///
  /// `'max_completion_tokens'` for OpenAI/Azure (the modern key),
  /// `'max_tokens'` for Groq/Mistral.
  final String maxTokensKey;

  /// Whether to serialize `tools` / `tool_choice`. Defaults to `true`.
  final bool supportsTools;

  /// Whether to serialize multimodal content parts (image/audio/file). When
  /// `false`, message content is flattened to text. Defaults to `true`.
  final bool supportsMultimodal;

  /// Whether to serialize `response_format: {type: json_schema, ...}` from
  /// `outputSchema`. Defaults to `true`.
  final bool supportsResponseFormatJsonSchema;

  /// Whether to send `stream_options: {include_usage: true}` on streaming
  /// requests so usage is reported in the final SSE chunk. Defaults to `true`.
  final bool includeStreamUsageOption;

  /// Hook for provider-specific request-body fields derived from the call
  /// options (e.g. OpenAI's `reasoning_effort`). The returned map is merged
  /// into the request body after the base has set the standard fields, so any
  /// overlapping key here wins — prefer non-conflicting keys. Returning `null`
  /// (or an empty map) adds nothing.
  ///
  /// The [LanguageModelV3CallOptions] are passed so the hook can read
  /// `providerOptions[provider]`.
  final Map<String, dynamic>? Function(LanguageModelV3CallOptions options)?
  extraBody;

  /// Factory for the underlying HTTP client. Defaults to
  /// [defaultClientFactory].
  final DioFactory clientFactory;

  /// Default [Dio] factory: a fresh client with the base URL and a JSON
  /// content type, plus the provider headers.
  static Dio defaultClientFactory({
    required String baseUrl,
    required Map<String, String> headers,
  }) {
    return Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {'Content-Type': 'application/json', ...headers},
        responseType: ResponseType.json,
      ),
    );
  }
}
