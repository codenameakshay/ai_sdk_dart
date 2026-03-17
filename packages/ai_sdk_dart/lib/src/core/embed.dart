import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result returned by [embed].
///
/// Contains [value], [embedding] vector, and optional [usage].
/// Mirrors the embed result from the JS AI SDK v6.
class EmbedResult<VALUE> {
  const EmbedResult({required this.value, required this.embedding, this.usage});

  final VALUE value;
  final List<double> embedding;
  final EmbeddingModelV2Usage? usage;
}

/// Embeds a single value into a vector.
///
/// Mirrors `embed` from the JS AI SDK v6. Use for semantic search,
/// similarity, or retrieval-augmented generation.
///
/// Example:
/// ```dart
/// final result = await embed(
///   model: embeddingModel,
///   value: 'Hello, world!',
/// );
/// print(result.embedding);
/// ```
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
