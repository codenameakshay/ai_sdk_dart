import 'rerank_model_v1_call_options.dart';

/// Result of a reranking call.
class RerankModelV1Result {
  const RerankModelV1Result({required this.documents});

  /// Documents in ranked order (highest relevance first).
  final List<RerankDocument> documents;
}

/// A document with its reranking score.
class RerankDocument {
  const RerankDocument({
    required this.index,
    required this.document,
    required this.relevanceScore,
  });

  /// The original index of this document in the input list.
  final int index;

  /// The document text.
  final String document;

  /// Relevance score in [0, 1] — higher means more relevant.
  final double relevanceScore;
}

/// Provider contract for reranking models.
abstract interface class RerankModelV1 {
  String get specificationVersion;
  String get provider;
  String get modelId;

  Future<RerankModelV1Result> doRerank(RerankModelV1CallOptions options);
}
