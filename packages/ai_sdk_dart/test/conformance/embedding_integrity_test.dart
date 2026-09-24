import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

class InvalidEmbeddingModel extends FakeEmbeddingModel {
  InvalidEmbeddingModel(this.entries) : super(const [1]);

  final List<EmbeddingModelV2Embedding<String>> entries;

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async => EmbeddingModelV2GenerateResult(embeddings: entries);
}

void main() {
  final invalid = <String, List<EmbeddingModelV2Embedding<String>>>{
    'extra row': const [
      EmbeddingModelV2Embedding(value: 'a', embedding: [1]),
      EmbeddingModelV2Embedding(value: 'b', embedding: [2]),
      EmbeddingModelV2Embedding(value: 'c', embedding: [3]),
    ],
    'wrong association': const [
      EmbeddingModelV2Embedding(value: 'b', embedding: [1]),
      EmbeddingModelV2Embedding(value: 'a', embedding: [2]),
    ],
    'empty vector': const [
      EmbeddingModelV2Embedding(value: 'a', embedding: []),
      EmbeddingModelV2Embedding(value: 'b', embedding: [2]),
    ],
    'mixed dimensions': const [
      EmbeddingModelV2Embedding(value: 'a', embedding: [1]),
      EmbeddingModelV2Embedding(value: 'b', embedding: [2, 3]),
    ],
    'nonfinite value': const [
      EmbeddingModelV2Embedding(value: 'a', embedding: [double.nan]),
      EmbeddingModelV2Embedding(value: 'b', embedding: [2]),
    ],
  };
  for (final entry in invalid.entries) {
    test('embedMany rejects ${entry.key}', () {
      expect(
        embedMany(
          model: InvalidEmbeddingModel(entry.value),
          values: ['a', 'b'],
        ),
        throwsA(isA<AiInvalidEmbeddingResponseError>()),
      );
    });
  }
  test('embed rejects extra vectors', () {
    expect(
      embed(model: InvalidEmbeddingModel(invalid['extra row']!), value: 'a'),
      throwsA(isA<AiInvalidEmbeddingResponseError>()),
    );
  });

  test('embedMany rejects a short response instead of losing an input', () {
    expect(
      embedMany(
        model: InvalidEmbeddingModel(const [
          EmbeddingModelV2Embedding(value: 'a', embedding: [1]),
        ]),
        values: ['a', 'b'],
      ),
      throwsA(isA<AiSdkError>()),
    );
  });
}
