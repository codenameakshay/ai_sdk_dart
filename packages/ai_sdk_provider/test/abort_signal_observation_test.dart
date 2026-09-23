import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
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

  int get listenerCount => _events.hasListener ? 1 : 0;

  Future<void> close() => _events.close();
}
