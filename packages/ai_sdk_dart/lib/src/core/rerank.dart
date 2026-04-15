import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result returned by [rerank].
///
/// [documents] are in ranked order (highest relevance first).
/// Use [document] for the top result.
class RerankResult {
  const RerankResult({required this.documents});

  /// Documents in ranked order (highest relevance first).
  final List<RankedDocument> documents;

  /// The most relevant document.
  RankedDocument get document => documents.first;
}

/// A document with its relevance score from [rerank].
///
/// [index] is the original position in the input list.
/// [relevanceScore] is in the range [0, 1].
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
  Duration? timeout,
}) async {
  final call = model.doRerank(
    RerankModelV1CallOptions(
      query: query,
      documents: documents,
      topN: topN,
      headers: headers,
      providerOptions: providerOptions,
    ),
  );
  final result = await (timeout != null ? call.timeout(timeout) : call);

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
