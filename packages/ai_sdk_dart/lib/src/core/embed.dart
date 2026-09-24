import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'shared/embedding_validation.dart';
import '../tools/tool.dart';
import 'shared/operation_scope.dart';

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
  Map<String, String>? headers,
  ProviderOptions? providerOptions,
  Duration? timeout,
  CancellationToken? abortSignal,
}) async {
  final result = await runOperation(
    abortSignal: abortSignal,
    timeout: timeout,
    operation: (signal) => model.doEmbed(
      EmbeddingModelV2CallOptions(
        values: [value],
        headers: headers,
        providerOptions: providerOptions,
        abortSignal: signal,
      ),
    ),
  );

  validateEmbeddings(result, [value]);

  final first = result.embeddings.first;
  return EmbedResult<VALUE>(
    value: first.value,
    embedding: first.embedding,
    usage: result.usage,
  );
}
