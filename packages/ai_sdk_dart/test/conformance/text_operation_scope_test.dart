import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

class _HangingTextModel extends LanguageModelV4 {
  AbortSignal? signal;
  final started = Completer<void>();

  @override
  String get provider => 'test';
  @override
  String get modelId => 'hanging-text';
  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) {
    signal = options.abortSignal;
    started.complete();
    return Completer<LanguageModelV4GenerateResult>().future;
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) {
    signal = options.abortSignal;
    started.complete();
    return Completer<LanguageModelV4StreamResult>().future;
  }
}

void main() {
  for (final startOnly in [false, true]) {
    test(
      startOnly
          ? 'stream-start metadata does not satisfy first meaningful chunk deadline'
          : 'step deadline remains active after stream acquisition',
      () async {
        final source = StreamController<LanguageModelV4StreamPart>();
        final cancelled = Completer<void>();
        source.onCancel = () => cancelled.complete();
        final model = _ReadyTextModel(source.stream);
        final caller = CancellationToken();
        final result = await streamText(
          model: model,
          prompt: 'hi',
          abortSignal: caller,
          maxRetries: 0,
          timeout: startOnly
              ? const TimeoutConfiguration(
                  firstChunk: Duration(milliseconds: 20),
                )
              : const TimeoutConfiguration(step: Duration(milliseconds: 20)),
        );
        source.add(const StreamPartStreamStart());
        if (!startOnly) {
          source.add(const StreamPartTextDelta(id: 'text', delta: 'partial'));
        }
        Object? error;
        try {
          await result.text.timeout(const Duration(seconds: 1));
        } catch (caught) {
          error = caught;
        }
        final wasCancelled = model.signal?.isCancelled;
        caller.cancel();
        await cancelled.future;
        expect(error, isA<TimeoutException>());
        expect(wasCancelled, isTrue);
        await source.close();
      },
    );
  }

  test(
    'caller cancellation interrupts a stalled prepareStep callback',
    () async {
      final caller = CancellationToken();
      final preparing = Completer<void>();
      final model = _HangingTextModel();
      final future = generateText(
        model: model,
        prompt: 'hi',
        abortSignal: caller,
        prepareStep: (_) {
          preparing.complete();
          return Completer<GenerateTextPrepareStepResult?>().future;
        },
      );
      await preparing.future;
      caller.cancel();
      await expectLater(
        future.timeout(const Duration(seconds: 1)),
        throwsA(isA<AiOperationCancelledError>()),
      );
      expect(model.started.isCompleted, isFalse);
    },
  );

  test(
    'synchronous final decoder cannot return success after total deadline',
    () async {
      final model = _ReadyTextModel(const Stream.empty());
      final future = generateText<Map<String, dynamic>>(
        model: model,
        prompt: 'hi',
        timeout: const TimeoutConfiguration(total: Duration(milliseconds: 20)),
        output: Output.object(
          schema: Schema(
            jsonSchema: const {'type': 'object'},
            fromJson: (value) {
              final elapsed = Stopwatch()..start();
              while (elapsed.elapsed < const Duration(milliseconds: 40)) {}
              return value;
            },
          ),
        ),
      );
      await expectLater(future, throwsA(isA<TimeoutException>()));
      expect(model.signal?.isCancelled, isTrue);
    },
  );

  test('generateText step timeout cancels provider work', () async {
    final model = _HangingTextModel();
    final future = generateText(
      model: model,
      prompt: 'hi',
      timeout: const TimeoutConfiguration(step: Duration(milliseconds: 10)),
      maxRetries: 0,
    );
    await model.started.future;
    await expectLater(future, throwsA(isA<TimeoutException>()));
    expect(model.signal?.isCancelled, isTrue);
  });

  test(
    'streamText first chunk deadline includes provider acquisition',
    () async {
      final model = _HangingTextModel();
      final caller = CancellationToken();
      final result = await streamText(
        model: model,
        prompt: 'hi',
        abortSignal: caller,
        timeout: const TimeoutConfiguration(
          firstChunk: Duration(milliseconds: 10),
        ),
        maxRetries: 0,
      );
      await model.started.future;
      Object? error;
      try {
        await result.text.timeout(const Duration(seconds: 1));
      } catch (caught) {
        error = caught;
      }
      final providerCancelledBeforeCleanup = model.signal?.isCancelled;
      caller.cancel();
      expect(error, isA<TimeoutException>());
      expect(providerCancelledBeforeCleanup, isTrue);
    },
  );

  test('generateText timeout cancels owned provider signal only', () async {
    final model = _HangingTextModel();
    final caller = CancellationToken();
    final future = generateText(
      model: model,
      prompt: 'hi',
      abortSignal: caller,
      timeout: const TimeoutConfiguration(total: Duration(milliseconds: 10)),
    );
    await model.started.future;
    await expectLater(future, throwsA(isA<TimeoutException>()));
    expect(model.signal, isNot(same(caller)));
    expect(model.signal?.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
  });

  test('streamText timeout cancels owned provider signal only', () async {
    final model = _HangingTextModel();
    final caller = CancellationToken();
    final result = await streamText(
      model: model,
      prompt: 'hi',
      abortSignal: caller,
      timeout: const TimeoutConfiguration(total: Duration(milliseconds: 10)),
    );
    await model.started.future;
    await expectLater(result.text, throwsA(isA<TimeoutException>()));
    expect(model.signal, isNot(same(caller)));
    expect(model.signal?.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
  });
}

class _ReadyTextModel extends _HangingTextModel {
  _ReadyTextModel(this.source);
  final Stream<LanguageModelV4StreamPart> source;

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    signal = options.abortSignal;
    started.complete();
    return LanguageModelV4StreamResult(stream: source);
  }

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    signal = options.abortSignal;
    started.complete();
    return const LanguageModelV4GenerateResult(
      content: [LanguageModelV4TextPart(text: '{"ok":true}')],
      finishReason: LanguageModelV4FinishReason.stop,
    );
  }
}
