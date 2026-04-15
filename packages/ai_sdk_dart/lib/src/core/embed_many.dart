import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// Result returned by [embedMany].
///
/// Contains the [embeddings] list — one entry per input value — plus aggregate
/// [usage] across the whole batch.
class EmbedManyResult<VALUE> {
  const EmbedManyResult({required this.embeddings, this.usage});

  /// One [EmbedResult] per input value, in the same order as the input.
  final List<EmbedManyEntry<VALUE>> embeddings;

  /// Aggregate token usage across all provider calls in the batch.
  final EmbeddingModelV2Usage? usage;
}

/// A single entry in an [EmbedManyResult].
class EmbedManyEntry<VALUE> {
  const EmbedManyEntry({required this.value, required this.embedding});

  final VALUE value;
  final List<double> embedding;
}

/// Embeds multiple values in a batch, with optional parallelism control.
///
/// Mirrors `embedMany` from the JS AI SDK v6. Use for semantic search,
/// similarity, or retrieval-augmented generation over a list of values.
///
/// [maxParallelCalls] limits how many provider calls are in-flight at once.
/// The default (null) sends all values in a single call when the provider
/// supports it, or in parallel otherwise.
///
/// Example:
/// ```dart
/// final result = await embedMany(
///   model: embeddingModel,
///   values: ['Hello', 'World', 'Dart'],
///   maxParallelCalls: 2,
/// );
/// for (final entry in result.embeddings) {
///   print('${entry.value}: ${entry.embedding.length} dimensions');
/// }
/// ```
Future<EmbedManyResult<VALUE>> embedMany<VALUE>({
  required EmbeddingModelV2<VALUE> model,
  required List<VALUE> values,
  int? maxParallelCalls,
}) async {
  if (values.isEmpty) {
    return const EmbedManyResult(embeddings: [], usage: null);
  }

  // If maxParallelCalls is null or >= values.length, send all at once.
  final parallel = (maxParallelCalls == null || maxParallelCalls >= values.length)
      ? null
      : maxParallelCalls;

  if (parallel == null) {
    // Single batch call.
    final result = await model.doEmbed(
      EmbeddingModelV2CallOptions<VALUE>(values: values),
    );
    return EmbedManyResult<VALUE>(
      embeddings: result.embeddings
          .map(
            (e) => EmbedManyEntry<VALUE>(
              value: e.value,
              embedding: e.embedding,
            ),
          )
          .toList(),
      usage: result.usage,
    );
  }

  // Split into chunks and run in parallel with limited concurrency.
  final chunks = <List<VALUE>>[];
  for (var i = 0; i < values.length; i += parallel) {
    final end = (i + parallel) > values.length ? values.length : i + parallel;
    chunks.add(values.sublist(i, end));
  }

  // Process chunks with maxParallelCalls concurrency.
  final allEntries = <EmbedManyEntry<VALUE>>[];
  var totalInputTokens = 0;
  var hasUsage = false;

  for (var chunkStart = 0; chunkStart < chunks.length; chunkStart += parallel) {
    final batchEnd = (chunkStart + parallel) > chunks.length
        ? chunks.length
        : chunkStart + parallel;
    final batch = chunks.sublist(chunkStart, batchEnd);

    final results = await Future.wait(
      batch.map(
        (chunk) => model.doEmbed(
          EmbeddingModelV2CallOptions<VALUE>(values: chunk),
        ),
      ),
    );

    for (final result in results) {
      for (final e in result.embeddings) {
        allEntries.add(EmbedManyEntry<VALUE>(value: e.value, embedding: e.embedding));
      }
      if (result.usage != null) {
        hasUsage = true;
        totalInputTokens += result.usage!.tokens ?? 0;
      }
    }
  }

  return EmbedManyResult<VALUE>(
    embeddings: allEntries,
    usage: hasUsage ? EmbeddingModelV2Usage(tokens: totalInputTokens > 0 ? totalInputTokens : null) : null,
  );
}
