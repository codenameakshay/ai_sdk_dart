import 'package:ai_sdk_provider/ai_sdk_provider.dart';

class CustomEmbeddingModel implements EmbeddingModelV2<String> {
  @override
  String get specificationVersion => 'v2';
  @override
  String get provider => 'example';
  @override
  String get modelId => 'example-embedding';
  @override
  int get maxEmbeddingsPerCall => 16;
  @override
  bool get supportsParallelCalls => false;

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    if (options.abortSignal?.isCancelled ?? false) {
      throw const AiOperationCancelledError();
    }
    return EmbeddingModelV2GenerateResult<String>(
      embeddings: options.values
          .map(
            (value) => EmbeddingModelV2Embedding<String>(
              value: value,
              embedding: [value.length.toDouble(), 1.0],
            ),
          )
          .toList(),
    );
  }
}

Future<void> main() async {
  final model = CustomEmbeddingModel();
  final result = await model.doEmbed(
    const EmbeddingModelV2CallOptions(values: ['sample']),
  );
  if (result.embeddings.single.embedding.length != 2) {
    throw StateError('Expected two embedding dimensions');
  }
}
