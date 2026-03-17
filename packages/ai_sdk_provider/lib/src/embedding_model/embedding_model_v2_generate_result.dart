import '../shared/provider_metadata.dart';

/// Usage stats for embedding generation.
class EmbeddingModelV2Usage {
  const EmbeddingModelV2Usage({this.tokens});
  final int? tokens;
}

/// Embedding result for one value.
class EmbeddingModelV2Embedding<VALUE> {
  const EmbeddingModelV2Embedding({
    required this.value,
    required this.embedding,
  });

  final VALUE value;
  final List<double> embedding;
}

/// Batch embedding result.
class EmbeddingModelV2GenerateResult<VALUE> {
  const EmbeddingModelV2GenerateResult({
    required this.embeddings,
    this.usage,
    this.warnings = const [],
    this.providerMetadata,
  });

  final List<EmbeddingModelV2Embedding<VALUE>> embeddings;
  final EmbeddingModelV2Usage? usage;
  final List<String> warnings;
  final ProviderMetadata? providerMetadata;
}
