import 'embedding_model_v2_call_options.dart';
import 'embedding_model_v2_generate_result.dart';

/// Provider contract for text embeddings.
///
/// Provider packages implement this interface for [embed] and similar APIs.
/// Mirrors the embedding model contract from the JS AI SDK v6.
abstract interface class EmbeddingModelV2<VALUE> {
  String get specificationVersion;
  String get provider;
  String get modelId;

  /// Maximum values per request, or null when no limit is declared.
  int? get maxEmbeddingsPerCall;

  /// Whether independent requests may run concurrently.
  bool get supportsParallelCalls;

  Future<EmbeddingModelV2GenerateResult<VALUE>> doEmbed(
    EmbeddingModelV2CallOptions<VALUE> options,
  );
}
