import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'shared/embedding_validation.dart';
import '../tools/tool.dart';
import 'cancellation.dart';
import 'shared/operation_scope.dart';

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
/// The default concurrency is one. [maxEmbeddingsPerCall] limits values per
/// request independently; a smaller provider limit always takes precedence.
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
  int? maxEmbeddingsPerCall,
  Map<String, String>? headers,
  ProviderOptions? providerOptions,
  Duration? timeout,
  CancellationToken? abortSignal,
}) async {
  if (maxParallelCalls != null && maxParallelCalls < 1) {
    throw ArgumentError.value(
      maxParallelCalls,
      'maxParallelCalls',
      'must be greater than zero.',
    );
  }
  final providerLimit = model.maxEmbeddingsPerCall;
  for (final limit in [maxEmbeddingsPerCall, providerLimit]) {
    if (limit != null && limit < 1) {
      throw ArgumentError.value(
        limit,
        'maxEmbeddingsPerCall',
        'must be positive.',
      );
    }
  }
  throwIfCancelled(abortSignal);
  if (values.isEmpty) {
    return const EmbedManyResult(embeddings: [], usage: null);
  }
  var batchSize = maxEmbeddingsPerCall ?? providerLimit ?? values.length;
  if (providerLimit != null && providerLimit < batchSize) {
    batchSize = providerLimit;
  }
  final concurrency = model.supportsParallelCalls ? maxParallelCalls ?? 1 : 1;
  int? dimensions;
  final scope = OperationScope(abortSignal: abortSignal, timeout: timeout);
  try {
    Future<EmbeddingModelV2GenerateResult<VALUE>> doEmbed(List<VALUE> chunk) =>
        scope.run(() async {
          final result = await model.doEmbed(
            EmbeddingModelV2CallOptions<VALUE>(
              values: chunk,
              headers: headers,
              providerOptions: providerOptions,
              abortSignal: scope.signal,
            ),
          );
          dimensions = validateEmbeddings(
            result,
            chunk,
            dimensions: dimensions,
          );
          return result;
        }, raceCancellation: true);

    final chunks = <List<VALUE>>[];
    for (var i = 0; i < values.length; i += batchSize) {
      final end = i + batchSize < values.length ? i + batchSize : values.length;
      chunks.add(values.sublist(i, end));
    }
    final results = List<EmbeddingModelV2GenerateResult<VALUE>?>.filled(
      chunks.length,
      null,
    );
    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (!failed && next < chunks.length) {
        final index = next++;
        try {
          results[index] = await doEmbed(chunks[index]);
        } catch (_) {
          failed = true;
          rethrow;
        }
      }
    }

    final workerCount = concurrency < chunks.length
        ? concurrency
        : chunks.length;
    await Future.wait(
      List.generate(workerCount, (_) => worker()),
      eagerError: true,
    );

    final allEntries = <EmbedManyEntry<VALUE>>[];
    int? totalInputTokens;
    var hasUsage = false;
    for (final completed in results) {
      final result = completed!;
      allEntries.addAll(
        result.embeddings.map(
          (entry) =>
              EmbedManyEntry(value: entry.value, embedding: entry.embedding),
        ),
      );
      if (result.usage case final usage?) {
        hasUsage = true;
        if (usage.tokens case final tokens?) {
          totalInputTokens = (totalInputTokens ?? 0) + tokens;
        }
      }
    }
    return EmbedManyResult<VALUE>(
      embeddings: allEntries,
      usage: hasUsage ? EmbeddingModelV2Usage(tokens: totalInputTokens) : null,
    );
  } finally {
    scope.close();
  }
}
