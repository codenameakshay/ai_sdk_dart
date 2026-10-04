import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

class ControlledModel extends FakeTextModel {
  ControlledModel(this.source) : super('');

  final Stream<LanguageModelV4StreamPart> source;
  final started = Completer<void>();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    lastCallOptions = options;
    if (!started.isCompleted) started.complete();
    return LanguageModelV4StreamResult(stream: source);
  }
}

class LateStartupModel extends FakeTextModel {
  LateStartupModel(this.source) : super('');
  final StreamController<LanguageModelV4StreamPart> source;
  final started = Completer<void>();
  bool returned = false;

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    if (!started.isCompleted) started.complete();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    returned = true;
    return LanguageModelV4StreamResult(stream: source.stream);
  }
}

void main() {
  test('total deadline cancels transport during a silent stream', () {
    fakeAsync((clock) {
      var cancelled = false;
      var acquired = false;
      Object? failure;
      final source = StreamController<LanguageModelV4StreamPart>(
        onCancel: () => cancelled = true,
      );
      final model = ControlledModel(source.stream);
      unawaited(
        streamObject(
          model: model,
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          timeout: const Duration(hours: 1),
        ).then<void>((result) {
          acquired = true;
          unawaited(
            result.object.then<void>(
              (_) => fail('A silent stream cannot produce a final object.'),
              onError: (Object error, StackTrace stack) {
                failure = error;
              },
            ),
          );
        }),
      );
      clock.flushMicrotasks();
      expect(acquired, isTrue);
      expect(failure, isNull);
      clock.elapse(const Duration(hours: 1));
      clock.flushMicrotasks();
      expect(failure, isA<TimeoutException>());
      expect(cancelled, isTrue);
      expect(model.lastCallOptions!.abortSignal!.isCancelled, isTrue);
      unawaited(source.close());
      clock.flushMicrotasks();
    });
  });

  test('already cancelled request never invokes the model', () async {
    final model = FakeTextModel('{}');
    await expectLater(
      streamObject(
        model: model,
        schema: Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) => json,
        ),
        abortSignal: CancellationToken()..cancel(),
      ),
      throwsA(isA<AiOperationCancelledError>()),
    );
    expect(model.lastCallOptions, isNull);
  });

  test('late stream startup is drained after deadline cancellation', () async {
    var cancelled = false;
    final source = StreamController<LanguageModelV4StreamPart>(
      onCancel: () => cancelled = true,
    );
    final model = LateStartupModel(source);
    await expectLater(
      streamObject(
        model: model,
        schema: Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) => json,
        ),
        timeout: const Duration(milliseconds: 5),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(model.returned, isTrue);
    expect(cancelled, isTrue);
    await source.close();
  });

  test(
    'caller cancellation settles a silent stream and cancels upstream',
    () async {
      var cancelled = false;
      final source = StreamController<LanguageModelV4StreamPart>(
        onCancel: () => cancelled = true,
      );
      final token = CancellationToken();
      final result = await streamObject(
        model: ControlledModel(source.stream),
        schema: Schema<Map<String, dynamic>>(
          jsonSchema: const {'type': 'object'},
          fromJson: (json) => json,
        ),
        abortSignal: token,
      );
      final error = expectLater(
        result.object,
        throwsA(isA<AiOperationCancelledError>()),
      );
      token.cancel();
      await error.timeout(const Duration(seconds: 1));
      expect(cancelled, isTrue);
      await source.close();
    },
  );

  for (final failure in ['decoder', 'in-band']) {
    test(
      '$failure failure cancels source and is available to late listeners',
      () async {
        var cancelled = false;
        final source = StreamController<LanguageModelV4StreamPart>(
          onCancel: () => cancelled = true,
        );
        final error = StateError(failure);
        final result = await streamObject(
          model: ControlledModel(source.stream),
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (_) => throw error,
          ),
        );
        final check = expectLater(result.object, throwsA(same(error)));
        source.add(
          failure == 'decoder'
              ? const StreamPartTextDelta(id: 'text', delta: '{"value":1}')
              : StreamPartError(error: error),
        );
        if (failure == 'decoder') unawaited(source.close());
        await check.timeout(const Duration(seconds: 1));
        expect(cancelled, isTrue);
        await expectLater(
          result.stream,
          emitsInOrder([emitsError(same(error)), emitsDone]),
        );
        await expectLater(result.partialObjectStream, emitsDone);
        await expectLater(result.patchStream, emitsDone);
        await expectLater(result.rawStream, emitsDone);
        await expectLater(result.textStream, emitsDone);
        await source.close();
      },
    );
  }

  test('source failure settles every surface and cancels upstream', () async {
    var cancelled = false;
    final source = StreamController<LanguageModelV4StreamPart>(
      onCancel: () => cancelled = true,
    );
    final error = StateError('transport failed');
    final result = await streamObject(
      model: ControlledModel(source.stream),
      schema: Schema<Map<String, dynamic>>(
        jsonSchema: const {'type': 'object'},
        fromJson: (json) => json,
      ),
    );
    final checks = <Future<void>>[
      expectLater(result.object, throwsA(same(error))),
      for (final stream in <Stream<Object?>>[
        result.stream,
        result.partialObjectStream,
        result.patchStream,
        result.rawStream,
        result.textStream,
      ])
        expectLater(
          stream.timeout(const Duration(seconds: 1)),
          emitsInOrder([emitsError(same(error)), emitsDone]),
        ),
    ];
    source.addError(error, StackTrace.current);
    await Future.wait(checks).timeout(const Duration(seconds: 2));
    expect(cancelled, isTrue);
    await source.close();
  });
}
