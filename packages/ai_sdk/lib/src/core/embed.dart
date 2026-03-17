import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result for a single embedding call.
class EmbedResult<VALUE> {
  const EmbedResult({required this.value, required this.embedding, this.usage});

  final VALUE value;
  final List<double> embedding;
  final EmbeddingModelV2Usage? usage;
}

Future<EmbedResult<VALUE>> embed<VALUE>({
  required EmbeddingModelV2<VALUE> model,
  required VALUE value,
}) async {
  final result = await model.doEmbed(
    EmbeddingModelV2CallOptions(values: [value]),
  );

  final first = result.embeddings.first;
  return EmbedResult<VALUE>(
    value: first.value,
    embedding: first.embedding,
    usage: result.usage,
  );
}
