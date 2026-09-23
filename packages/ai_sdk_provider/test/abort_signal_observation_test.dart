import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runs without an abort signal and rejects a pre-cancelled signal',
    () async {
      expect(await runWithAbortSignal(() async => 42, null), 42);

      final signal = _FutureAbortSignal()..cancel();
      await expectLater(
        runWithAbortSignal<void>(() async {
          fail('a pre-cancelled operation must not start');
        }, signal),
        throwsA(isA<AiOperationCancelledError>()),
      );
    },
  );

  test(
    'observes a non-streaming signal and detaches after cancellation',
    () async {
      final signal = _FutureAbortSignal();
      var started = false;
      final operation = runWithAbortSignal(() async {
        started = true;
        await Completer<void>().future;
        return 1;
      }, signal);

      signal.cancel();
      await expectLater(operation, throwsA(isA<AiOperationCancelledError>()));
      expect(started, isTrue);
    },
  );

  test('request observers detach after repeated success and failure', () async {
    final signal = _CountingAbortSignal();
    addTearDown(signal.close);

    for (var index = 0; index < 50; index++) {
      final scope = DioCancellationScope(signal);
      try {
        await runWithAbortSignal(() async {}, signal);
      } finally {
        await scope.dispose();
      }
      expect(signal.listenerCount, 0);
    }

    for (var index = 0; index < 50; index++) {
      final scope = DioCancellationScope(signal);
      try {
        await expectLater(
          runWithAbortSignal<void>(() async {
            throw StateError('request failed');
          }, signal),
          throwsA(isA<StateError>()),
        );
      } finally {
        await scope.dispose();
      }
      expect(signal.listenerCount, 0);
    }

    expect(signal.attaches, 100);
    expect(signal.detaches, signal.attaches);
  });

  test('observable cancellation events invoke the callback once', () async {
    final signal = _CountingAbortSignal();
    addTearDown(signal.close);
    var calls = 0;
    final observation = AbortSignalObservation.attach(signal, () => calls++);

    signal.cancel();
    await Future<void>.delayed(Duration.zero);
    signal.cancel();

    expect(calls, 1);
    await observation.dispose();
    expect(signal.listenerCount, 0);
  });

  test(
    'Dio cancellation scope mirrors signal state and disposes its observer',
    () async {
      final signal = _CountingAbortSignal();
      addTearDown(signal.close);
      final scope = DioCancellationScope(signal);
      expect(scope.token, isNotNull);
      expect(scope.isCancelled, isFalse);

      signal.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(scope.isCancelled, isTrue);
      await scope.dispose();
      expect(signal.listenerCount, 0);
    },
  );
}

class _CountingAbortSignal implements ObservableAbortSignal {
  int attaches = 0;
  int detaches = 0;
  late final StreamController<void> _events = StreamController<void>.broadcast(
    onListen: () => attaches++,
    onCancel: () => detaches++,
  );

  @override
  bool get isCancelled => false;

  @override
  Future<void> get onCancelled => Completer<void>().future;

  @override
  Stream<void> get cancellationEvents => _events.stream;

  void cancel() => _events.add(null);

  int get listenerCount => _events.hasListener ? 1 : 0;

  Future<void> close() => _events.close();
}

class _FutureAbortSignal implements AbortSignal {
  final _cancelled = Completer<void>();
  var _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get onCancelled => _cancelled.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
  }
}
