import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

void main() {
  group('embedMany conformance', () {
    // ── basic usage ──────────────────────────────────────────────────────

    group('basic usage', () {
      test('returns embeddings for all values', () async {
        final model = FakeEmbeddingModel([0.1, 0.2, 0.3]);
        final result = await embedMany(
          model: model,
          values: ['hello', 'world'],
        );
        expect(result.embeddings, hasLength(2));
        expect(result.embeddings[0].value, 'hello');
        expect(result.embeddings[1].value, 'world');
        expect(result.embeddings[0].embedding, [0.1, 0.2, 0.3]);
        expect(result.embeddings[1].embedding, [0.1, 0.2, 0.3]);
      });

      test('empty input returns empty result', () async {
        final model = FakeEmbeddingModel([0.1, 0.2]);
        final result = await embedMany(model: model, values: []);
        expect(result.embeddings, isEmpty);
        expect(result.usage, isNull);
      });

      test('single value returns one embedding', () async {
        final model = FakeEmbeddingModel([0.5, 0.5]);
        final result = await embedMany(model: model, values: ['only']);
        expect(result.embeddings, hasLength(1));
        expect(result.embeddings[0].value, 'only');
      });

      test('preserves order of input values', () async {
        const input = ['a', 'b', 'c', 'd', 'e'];
        final model = FakeEmbeddingModel([1.0]);
        final result = await embedMany(model: model, values: input);
        final values = result.embeddings.map((e) => e.value).toList();
        expect(values, input);
      });
    });

    // ── usage aggregation ─────────────────────────────────────────────────

    group('usage aggregation', () {
      test('returns usage from model', () async {
        final model = FakeEmbeddingModel([
          0.1,
          0.2,
        ], usage: const EmbeddingModelV2Usage(tokens: 6));
        final result = await embedMany(model: model, values: ['a', 'b', 'c']);
        expect(result.usage, isNotNull);
        expect(result.usage!.tokens, 6);
      });

      test('usage is null when model returns no usage', () async {
        final model = FakeEmbeddingModel([0.1, 0.2]);
        final result = await embedMany(model: model, values: ['a', 'b']);
        expect(result.usage, isNull);
      });

      test(
        'preserves usage when the provider reports unknown tokens',
        () async {
          final model = _UsageEmbeddingModel(const [
            EmbeddingModelV2Usage(),
            EmbeddingModelV2Usage(),
          ]);
          final result = await embedMany(
            model: model,
            values: ['a', 'b'],
            maxParallelCalls: 1,
          );
          expect(result.usage, isNotNull);
          expect(result.usage!.tokens, isNull);
        },
      );

      test('preserves explicitly reported zero token usage', () async {
        final model = _UsageEmbeddingModel(const [
          EmbeddingModelV2Usage(tokens: 0),
          EmbeddingModelV2Usage(tokens: 0),
        ]);
        final result = await embedMany(
          model: model,
          values: ['a', 'b'],
          maxParallelCalls: 1,
        );
        expect(result.usage, isNotNull);
        expect(result.usage!.tokens, 0);
      });

      test(
        'aggregates known tokens while preserving mixed usage reports',
        () async {
          final model = _UsageEmbeddingModel([
            const EmbeddingModelV2Usage(tokens: 0),
            const EmbeddingModelV2Usage(),
            const EmbeddingModelV2Usage(tokens: 4),
          ]);
          final result = await embedMany(
            model: model,
            values: ['a', 'b', 'c'],
            maxParallelCalls: 1,
          );
          expect(result.usage, isNotNull);
          expect(result.usage!.tokens, 4);
        },
      );
    });

    // ── maxParallelCalls ──────────────────────────────────────────────────

    group('maxParallelCalls', () {
      test('null sends all values in one call', () async {
        final model = _CountingEmbeddingModel([0.1, 0.2]);
        await embedMany(model: model, values: ['a', 'b', 'c']);
        expect(model.callCount, 1);
      });

      test('maxParallelCalls=1 sends each value separately', () async {
        final model = _CountingEmbeddingModel([0.1, 0.2]);
        await embedMany(
          model: model,
          values: ['a', 'b', 'c'],
          maxParallelCalls: 1,
        );
        expect(model.callCount, 3);
      });

      test('maxParallelCalls=2 with 4 values makes 2 calls', () async {
        final model = _CountingEmbeddingModel([0.1, 0.2]);
        await embedMany(
          model: model,
          values: ['a', 'b', 'c', 'd'],
          maxParallelCalls: 2,
        );
        expect(model.callCount, 2);
      });

      test('maxParallelCalls >= values.length behaves like null', () async {
        final model = _CountingEmbeddingModel([0.1, 0.2]);
        await embedMany(model: model, values: ['a', 'b'], maxParallelCalls: 10);
        expect(model.callCount, 1);
      });

      test('result order is preserved with maxParallelCalls', () async {
        final model = FakeEmbeddingModel([0.9]);
        const input = ['x', 'y', 'z', 'w'];
        final result = await embedMany(
          model: model,
          values: input,
          maxParallelCalls: 2,
        );
        final values = result.embeddings.map((e) => e.value).toList();
        expect(values, input);
      });
    });

    // ── embedding vectors ─────────────────────────────────────────────────

    group('embedding vectors', () {
      test('embedding vectors are non-empty', () async {
        final model = FakeEmbeddingModel([0.1, 0.2, 0.3, 0.4]);
        final result = await embedMany(model: model, values: ['test']);
        expect(result.embeddings.first.embedding, isNotEmpty);
        expect(result.embeddings.first.embedding, hasLength(4));
      });

      test('throws AiNoContentGeneratedError for an empty provider result', () {
        expect(
          () => embedMany(model: _EmptyEmbeddingModel(), values: ['test']),
          throwsA(isA<AiNoContentGeneratedError>()),
        );
      });
    });
  });
}

class _EmptyEmbeddingModel implements EmbeddingModelV2<String> {
  @override
  String get provider => 'fake';

  @override
  String get modelId => 'empty-embedding-model';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async => const EmbeddingModelV2GenerateResult(embeddings: []);
}

/// A fake embedding model that counts how many times doEmbed is called.
class _CountingEmbeddingModel implements EmbeddingModelV2<String> {
  _CountingEmbeddingModel(this.embedding);

  final List<double> embedding;
  int callCount = 0;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'fake-counting-embedding-model';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    callCount++;
    return EmbeddingModelV2GenerateResult(
      embeddings: options.values
          .map((v) => EmbeddingModelV2Embedding(value: v, embedding: embedding))
          .toList(),
    );
  }
}

class _UsageEmbeddingModel implements EmbeddingModelV2<String> {
  _UsageEmbeddingModel(this.usages);

  final List<EmbeddingModelV2Usage> usages;
  var _callIndex = 0;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'fake-usage-embedding-model';

  @override
  String get specificationVersion => 'v2';

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    final usage = usages[_callIndex++];
    return EmbeddingModelV2GenerateResult(
      embeddings: options.values
          .map(
            (value) =>
                EmbeddingModelV2Embedding(value: value, embedding: const [1.0]),
          )
          .toList(),
      usage: usage,
    );
  }
}
