import 'dart:collection';
import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test('embed total timeout includes embedding validation', () async {
    await expectLater(
      embed(
        model: _SlowValidationModel(),
        value: 'value',
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });
}

class _SlowValidationModel implements EmbeddingModelV2<String> {
  @override
  String get modelId => 'slow-validation';
  @override
  String get provider => 'fixture';
  @override
  String get specificationVersion => 'v2';
  @override
  int? get maxEmbeddingsPerCall => null;
  @override
  bool get supportsParallelCalls => true;

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async => EmbeddingModelV2GenerateResult(
    embeddings: [
      EmbeddingModelV2Embedding(
        value: options.values.single,
        embedding: _SlowVector(),
      ),
    ],
  );
}

class _SlowVector extends ListBase<double> {
  @override
  int get length => 1;

  @override
  set length(int value) => throw UnsupportedError('read-only');

  @override
  double operator [](int index) {
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsedMilliseconds < 40) {}
    return 1;
  }

  @override
  void operator []=(int index, double value) =>
      throw UnsupportedError('read-only');
}
