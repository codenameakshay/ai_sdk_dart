import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A controllable mock embedding model for testing.
///
/// Mirrors `MockEmbeddingModelV1` from the JS AI SDK v6 `ai/test` sub-path.
///
/// ```dart
/// final model = MockEmbeddingModelV2(
///   embedding: [0.1, 0.2, 0.3],
/// );
/// final result = await embed(model: model, value: 'hello');
/// expect(result.embedding, [0.1, 0.2, 0.3]);
/// ```
class MockEmbeddingModelV2<VALUE> implements EmbeddingModelV2<VALUE> {
  MockEmbeddingModelV2({
    required this.embedding,
    this.usage,
    this.doEmbedError,
    this.provider = 'mock',
    this.modelId = 'mock-embedding-model',
  });

  /// The embedding vector to return for every input value.
  final List<double> embedding;

  /// Token usage to report.
  final EmbeddingModelV2Usage? usage;

  /// If set, [doEmbed] throws this error instead of returning embeddings.
  final Object? doEmbedError;

  @override
  final String provider;

  @override
  final String modelId;

  @override
  String get specificationVersion => 'v2';

  /// All call options passed to [doEmbed] in the order they were called.
  final List<EmbeddingModelV2CallOptions<VALUE>> embedCalls = [];

  @override
  Future<EmbeddingModelV2GenerateResult<VALUE>> doEmbed(
    EmbeddingModelV2CallOptions<VALUE> options,
  ) async {
    embedCalls.add(options);
    if (doEmbedError != null) throw doEmbedError!;
    return EmbeddingModelV2GenerateResult(
      embeddings: options.values
          .map((v) => EmbeddingModelV2Embedding(value: v, embedding: embedding))
          .toList(),
      usage: usage,
    );
  }
}
