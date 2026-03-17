import '../shared/json_value.dart';

/// Call options for reranking models.
class RerankModelV1CallOptions {
  const RerankModelV1CallOptions({
    required this.query,
    required this.documents,
    this.topN,
    this.headers,
    this.providerOptions,
  });

  /// The search query to rerank against.
  final String query;

  /// The documents to rerank.
  final List<String> documents;

  /// Return only the top N results. If null, returns all.
  final int? topN;

  final Map<String, String>? headers;
  final ProviderOptions? providerOptions;
}
