import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result from `rerank`.
class RerankResult {
  const RerankResult({required this.documents});

  /// Documents in ranked order (highest relevance first).
  final List<RankedDocument> documents;

  /// The most relevant document.
  RankedDocument get document => documents.first;
}

/// A single document with its relevance score.
class RankedDocument {
  const RankedDocument({
    required this.index,
    required this.document,
    required this.relevanceScore,
  });

  /// Original index in the input list.
  final int index;

  /// The document text.
  final String document;

  /// Relevance score in [0, 1].
  final double relevanceScore;
}

/// Reranks [documents] by relevance to [query] using the provided [model].
///
/// Mirrors `rerank()` from the JS AI SDK v6.
///
/// ```dart
/// final result = await rerank(
///   model: cohere.reranking('rerank-english-v3.0'),
///   query: 'What is the capital of France?',
///   documents: ['Paris is the capital of France.', 'Berlin is in Germany.'],
/// );
/// print(result.document.document); // Paris is the capital of France.
/// ```
Future<RerankResult> rerank({
  required RerankModelV1 model,
  required String query,
  required List<String> documents,
  int? topN,
  Map<String, String>? headers,
  ProviderOptions? providerOptions,
}) async {
  final result = await model.doRerank(
    RerankModelV1CallOptions(
      query: query,
      documents: documents,
      topN: topN,
      headers: headers,
      providerOptions: providerOptions,
    ),
  );

  return RerankResult(
    documents: result.documents
        .map(
          (d) => RankedDocument(
            index: d.index,
            document: d.document,
            relevanceScore: d.relevanceScore,
          ),
        )
        .toList(),
  );
}
