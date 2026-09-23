import 'package:ai_sdk_provider/ai_sdk_provider.dart';

int validateEmbeddings<VALUE>(
  EmbeddingModelV2GenerateResult<VALUE> result,
  List<VALUE> values, {
  int? dimensions,
}) {
  if (result.embeddings.isEmpty) {
    throw const AiNoContentGeneratedError('No embedding was generated.');
  }
  if (result.embeddings.length != values.length) {
    throw AiInvalidEmbeddingResponseError(
      'Expected one embedding for each input value.',
      expectedCount: values.length,
      actualCount: result.embeddings.length,
    );
  }
  final expectedDimensions =
      dimensions ?? result.embeddings.first.embedding.length;
  for (var i = 0; i < values.length; i++) {
    final entry = result.embeddings[i];
    final vector = entry.embedding;
    if (entry.value != values[i] ||
        vector.isEmpty ||
        vector.length != expectedDimensions ||
        vector.any((value) => !value.isFinite)) {
      throw AiInvalidEmbeddingResponseError(
        'Embedding values must match input order and contain finite vectors of equal nonzero dimension.',
        expectedCount: values.length,
        actualCount: result.embeddings.length,
        index: i,
      );
    }
  }
  return expectedDimensions;
}
