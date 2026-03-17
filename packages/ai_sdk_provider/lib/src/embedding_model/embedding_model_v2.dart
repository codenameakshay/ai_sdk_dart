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

  Future<EmbeddingModelV2GenerateResult<VALUE>> doEmbed(
    EmbeddingModelV2CallOptions<VALUE> options,
  );
}
