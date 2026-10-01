import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

class QueuedEmbeddingModel extends FakeEmbeddingModel {
  QueuedEmbeddingModel({this.parallel = true}) : super(const [1]);
  final bool parallel;
  final calls = <List<String>>[];
  final first = Completer<void>();
  final thirdStarted = Completer<void>();
  int active = 0;
  int peak = 0;

  @override
  int get maxEmbeddingsPerCall => 20;
  @override
  bool get supportsParallelCalls => parallel;

  @override
  Future<EmbeddingModelV2GenerateResult<String>> doEmbed(
    EmbeddingModelV2CallOptions<String> options,
  ) async {
    calls.add(List.of(options.values));
    active++;
    if (active > peak) peak = active;
    if (calls.length == 3) thirdStarted.complete();
    if (calls.length == 1) await first.future;
    active--;
    return super.doEmbed(options);
  }
}

void main() {
  test(
    'provider can require serial requests despite caller concurrency',
    () async {
      final model = QueuedEmbeddingModel(parallel: false)..first.complete();
      await embedMany(
        model: model,
        values: List.generate(41, (i) => '$i'),
        maxParallelCalls: 4,
      );
      expect(model.calls.map((values) => values.length), [20, 20, 1]);
      expect(model.peak, 1);
    },
  );

  test('caller may lower the provider batch limit', () async {
    final model = QueuedEmbeddingModel()..first.complete();
    await embedMany(
      model: model,
      values: List.generate(41, (i) => '$i'),
      maxEmbeddingsPerCall: 15,
    );
    expect(model.calls.map((values) => values.length), [15, 15, 11]);
  });

  test('caller cannot raise the provider batch limit', () async {
    final model = QueuedEmbeddingModel()..first.complete();
    await embedMany(
      model: model,
      values: List.generate(41, (i) => '$i'),
      maxEmbeddingsPerCall: 50,
    );
    expect(model.calls.map((values) => values.length), [20, 20, 1]);
  });

  test(
    '101 inputs use six bounded batches and keep a free worker busy',
    () async {
      final model = QueuedEmbeddingModel();
      final values = List.generate(101, (i) => '$i');
      final operation = embedMany(
        model: model,
        values: values,
        maxParallelCalls: 2,
      );
      try {
        await model.thirdStarted.future.timeout(const Duration(seconds: 1));
        expect(model.first.isCompleted, isFalse);
      } finally {
        model.first.complete();
      }
      final result = await operation;
      expect(model.calls.map((values) => values.length), [
        20,
        20,
        20,
        20,
        20,
        1,
      ]);
      expect(model.peak, 2);
      expect(result.embeddings.map((entry) => entry.value), values);
    },
  );
}
