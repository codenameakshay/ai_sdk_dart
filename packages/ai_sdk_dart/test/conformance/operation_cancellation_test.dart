import 'dart:async';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

class HangingModel
    implements
        EmbeddingModelV2<String>,
        ImageModelV3,
        SpeechModelV1,
        TranscriptionModelV1,
        RerankModelV1 {
  final signals = <AbortSignal?>[];
  final pending = <Completer<Never>>[];
  final started = Completer<void>();
  @override
  String get provider => 'fixture';
  @override
  String get modelId => 'hanging';
  @override
  String get specificationVersion => 'fixture';
  @override
  int? get maxEmbeddingsPerCall => 1;
  @override
  bool get supportsParallelCalls => true;

  Future<Never> hang(AbortSignal? signal) {
    signals.add(signal);
    final completer = Completer<Never>();
    pending.add(completer);
    if (!started.isCompleted) started.complete();
    return completer.future;
  }

  @override
  Future<Never> doGenerate(Object options) => hang(switch (options) {
    ImageModelV3CallOptions() => options.abortSignal,
    SpeechModelV1CallOptions() => options.abortSignal,
    TranscriptionModelV1CallOptions() => options.abortSignal,
    _ => throw StateError('Unexpected operation'),
  });
  @override
  Future<Never> doEmbed(EmbeddingModelV2CallOptions<String> options) =>
      hang(options.abortSignal);
  @override
  Future<Never> doRerank(RerankModelV1CallOptions options) =>
      hang(options.abortSignal);

  void completeLateErrors() {
    for (final completer in pending) {
      completer.completeError(StateError('late transport failure'));
    }
  }
}

void main() {
  final operations =
      <
        String,
        Future<Object?> Function(HangingModel, CancellationToken?, Duration?)
      >{
        'embed': (model, token, timeout) => embed(
          model: model,
          value: 'a',
          abortSignal: token,
          timeout: timeout,
        ),
        'embedMany': (model, token, timeout) => embedMany(
          model: model,
          values: ['a', 'b', 'c'],
          maxParallelCalls: 2,
          abortSignal: token,
          timeout: timeout,
        ),
        'image': (model, token, timeout) => generateImage(
          model: model,
          prompt: 'image',
          abortSignal: token,
          timeout: timeout,
        ),
        'speech': (model, token, timeout) => generateSpeech(
          model: model,
          text: 'hello',
          abortSignal: token,
          timeout: timeout,
        ),
        'transcription': (model, token, timeout) => transcribe(
          model: model,
          audio: Uint8List.fromList([1]),
          abortSignal: token,
          timeout: timeout,
        ),
        'rerank': (model, token, timeout) => rerank(
          model: model,
          query: 'hello',
          documents: ['a'],
          abortSignal: token,
          timeout: timeout,
        ),
      };
  for (final entry in operations.entries) {
    test(
      '${entry.key}: pre-cancellation prevents provider invocation',
      () async {
        final model = HangingModel();
        await expectLater(
          entry.value(model, CancellationToken()..cancel(), null),
          throwsA(isA<AiOperationCancelledError>()),
        );
        expect(model.signals, isEmpty);
      },
    );
    test(
      '${entry.key}: cancellation settles a non-cooperative provider and forwards abort',
      () async {
        final model = HangingModel();
        final token = CancellationToken();
        final error = expectLater(
          entry.value(model, token, null),
          throwsA(isA<AiOperationCancelledError>()),
        );
        await model.started.future;
        token.cancel();
        await error.timeout(const Duration(seconds: 1));
        expect(model.signals, isNotEmpty);
        expect(
          model.signals.every((signal) => signal?.isCancelled == true),
          isTrue,
        );
        if (entry.key == 'embedMany') expect(model.signals, hasLength(2));
        model.completeLateErrors();
        await Future<void>.delayed(Duration.zero);
      },
    );
    test('${entry.key}: deadline aborts provider work', () async {
      final model = HangingModel();
      await expectLater(
        entry.value(model, null, const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        model.signals.every((signal) => signal?.isCancelled == true),
        isTrue,
      );
      model.completeLateErrors();
      await Future<void>.delayed(Duration.zero);
    });
  }
}
