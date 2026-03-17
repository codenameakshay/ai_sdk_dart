import '../shared/json_value.dart';

/// Call options for embedding model operations.
class EmbeddingModelV2CallOptions<VALUE> {
  const EmbeddingModelV2CallOptions({
    required this.values,
    this.headers,
    this.providerOptions,
  });

  /// Input values to embed.
  final List<VALUE> values;

  final Map<String, String>? headers;
  final ProviderOptions? providerOptions;
}
