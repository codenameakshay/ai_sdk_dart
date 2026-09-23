import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_dart/src/core/retry_helper.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import 'helpers/fake_models.dart';

class _CancelOnListenSignal extends CancellationToken {
  final _cancelled = Completer<void>();
  var _listenCount = 0;
  late final StreamController<void> _events = StreamController<void>.broadcast(
    sync: true,
    onListen: () {
      _listenCount++;
      if (_listenCount == 2) {
        _isCancelled = true;
        _cancelled.complete();
        _events.add(null);
        unawaited(_events.close());
      }
    },
  );
  var _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get onCancelled => _cancelled.future;

  @override
  Stream<void> get cancellationEvents => _events.stream;
}

class _PassiveSignal extends CancellationToken {
  final _events = StreamController<void>.broadcast(sync: true);
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get onCancelled => _cancelled.future;

  @override
  Stream<void> get cancellationEvents => _events.stream;

  Future<void> close() => _events.close();
}

class _LateStreamModel extends LanguageModelV4 {
  _LateStreamModel(this.source, this.released);

  final StreamController<LanguageModelV4StreamPart> source;
  final Completer<void> released;

  @override
  String get provider => 'fake';

  @override
  String get modelId => 'late-stream';

  @override
  String get specificationVersion => 'v4';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) => throw UnimplementedError();

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return LanguageModelV4StreamResult(stream: source.stream);
  }
}

Schema<Map<String, dynamic>> _objectSchema() => Schema<Map<String, dynamic>>(
  jsonSchema: const {'type': 'object'},
  fromJson: (json) => json,
);

void main() {
  tearDown(debugResetRetryHooksForTests);

  test('retry reports timeout when a retry starts after its budget', () async {
    var elapsedCalls = 0;
    debugConfigureRetryHooksForTests(
      elapsed: () {
        elapsedCalls++;
        return elapsedCalls >= 3
            ? const Duration(milliseconds: 10)
            : Duration.zero;
      },
      sleep: (_) async {},
      randomDouble: () => 0,
    );

    await expectLater(
      withRetry<void>(
        maxRetries: 1,
        totalTimeout: const Duration(milliseconds: 10),
        stepTimeout: const Duration(milliseconds: 10),
        fn: (_) async {
          throw const AiApiCallError('retry', isRetryable: true);
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'retry disposes a cancellation observer that fires during attach',
    () async {
      final signal = _CancelOnListenSignal();
      await expectLater(
        withRetry<void>(
          maxRetries: 1,
          totalTimeout: null,
          stepTimeout: null,
          abortSignal: signal,
          fn: (_) async {
            throw const AiApiCallError('retry', isRetryable: true);
          },
        ),
        throwsA(isA<AiApiCallError>()),
      );
    },
  );

  test(
    'retry propagates a failing backoff and detaches its observer',
    () async {
      final signal = _PassiveSignal();
      final error = StateError('backoff failed');
      debugConfigureRetryHooksForTests(
        sleep: (_) => Future<void>.error(error),
        randomDouble: () => 1,
      );

      await expectLater(
        withRetry<void>(
          maxRetries: 1,
          totalTimeout: null,
          stepTimeout: null,
          abortSignal: signal,
          fn: (_) async {
            throw const AiApiCallError('retry', isRetryable: true);
          },
        ),
        throwsA(same(error)),
      );
      expect(signal._events.hasListener, isFalse);
      await signal.close();
    },
  );

  test(
    'streamObject captures the prompt when telemetry input capture is enabled',
    () async {
      final result = await streamObject(
        model: textDeltaStream(['{"ok":true}']),
        schema: _objectSchema(),
        prompt: 'captured prompt',
        telemetry: const TelemetrySettings(
          isEnabled: true,
          captureInputs: true,
        ),
      );
      expect(await result.object, {'ok': true});
    },
  );

  test(
    'streamObject drains a late response after startup cancellation',
    () async {
      final released = Completer<void>();
      final source = StreamController<LanguageModelV4StreamPart>(
        onCancel: () {
          if (!released.isCompleted) released.complete();
        },
      );
      final result = streamObject(
        model: _LateStreamModel(source, released),
        schema: _objectSchema(),
        prompt: 'late',
        timeout: const Duration(milliseconds: 1),
      );

      await expectLater(result, throwsA(isA<TimeoutException>()));
      await released.future.timeout(const Duration(seconds: 1));
      await source.close();
    },
  );
}
