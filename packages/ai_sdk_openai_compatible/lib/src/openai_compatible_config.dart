import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

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
///   client: Dio(BaseOptions(baseUrl: 'https://api.groq.com/openai/v1')),
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
    required this.client,
    this.queryParameters,
    this.seedKey = 'seed',
    this.maxTokensKey = 'max_completion_tokens',
    this.supportsTools = true,
    this.supportsMultimodal = true,
    this.supportsResponseFormatJsonSchema = true,
    this.includeStreamUsageOption = true,
    this.reasoningKeys = const ['reasoning_content', 'reasoning', 'thinking'],
    this.extraBody,
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
  final RequestHeadersProvider headers;

  /// Reusable client owned by the provider instance or injected by the caller.
  ///
  /// Request-time auth stays out of this client's base options; [headers] are
  /// resolved immediately before dispatch and merged into each request instead.
  final Dio client;

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

  /// Response field names that carry the model's reasoning/thinking text,
  /// checked in order until a non-empty string is found.
  ///
  /// OpenAI-compatible providers disagree on the field name: DeepSeek emits
  /// `reasoning_content`, OpenRouter emits `reasoning`, and some hosts use
  /// `thinking`. The first match on a streaming `delta` is emitted as a
  /// [StreamPartReasoningDelta]; on a non-streaming `message` it becomes a
  /// [LanguageModelV4ReasoningPart]. Defaults to
  /// `['reasoning_content', 'reasoning', 'thinking']`; set to `const []` to
  /// disable reasoning extraction entirely.
  final List<String> reasoningKeys;

  /// Hook for provider-specific request-body fields derived from the call
  /// options (e.g. OpenAI's `reasoning_effort`). The returned map is merged
  /// into the request body after the base has set the standard fields, so any
  /// overlapping key here wins — prefer non-conflicting keys. Returning `null`
  /// (or an empty map) adds nothing.
  ///
  /// The [LanguageModelV4CallOptions] are passed so the hook can read
  /// `providerOptions[provider]`.
  final Map<String, dynamic>? Function(LanguageModelV4CallOptions options)?
  extraBody;
}

/// Parses an OpenAI-shaped `data: [{ embedding: [...] }]` embeddings
/// response body, pairing each returned embedding with the input [values] it
/// corresponds to.
EmbeddingModelV2GenerateResult<String> parseOpenAiEmbeddings(
  Map<String, dynamic> data,
  List<String> values,
) {
  final rows = data['data'];
  if (rows is! List || rows.length != values.length) {
    throw const FormatException('Expected one embedding row for each input.');
  }
  final ordered = List<List<double>?>.filled(values.length, null);
  final indexed = rows.any((row) => row is Map && row.containsKey('index'));
  int? dimensions;
  for (var position = 0; position < rows.length; position++) {
    final row = rows[position];
    if (row is! Map) {
      throw const FormatException('An embedding row is not an object.');
    }
    final index = indexed ? row['index'] : position;
    if (index is! int ||
        index < 0 ||
        index >= values.length ||
        ordered[index] != null) {
      throw const FormatException(
        'Embedding indices must be unique and cover every input.',
      );
    }
    final raw = row['embedding'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.any((value) => value is! num || !value.isFinite)) {
      throw const FormatException(
        'Embedding vectors must contain finite numbers.',
      );
    }
    dimensions ??= raw.length;
    if (raw.length != dimensions) {
      throw const FormatException('Embedding dimensions differ between rows.');
    }
    ordered[index] = raw.map((value) => (value as num).toDouble()).toList();
  }
  final rawUsage = data['usage'];
  if (rawUsage != null && rawUsage is! Map) {
    throw const FormatException('Embedding usage is not an object.');
  }
  return EmbeddingModelV2GenerateResult<String>(
    embeddings: [
      for (var i = 0; i < values.length; i++)
        EmbeddingModelV2Embedding(value: values[i], embedding: ordered[i]!),
    ],
    usage: rawUsage == null
        ? null
        : EmbeddingModelV2Usage(tokens: intOrNull(rawUsage['total_tokens'])),
  );
}
