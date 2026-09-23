import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  test('registration fires cancellation only once', () async {
    final signal = _RegistrationSignal(true);
    addTearDown(signal.close);
    expect(signal.isCancelled, isFalse);
    var calls = 0;
    final observation = AbortSignalObservation.attach(signal, () => calls++);
    expect(calls, 1);
    await observation.dispose();
  });

  for (final duringStateCheck in [true, false]) {
    test(
      'registration cancellation skips work (state check: $duringStateCheck)',
      () async {
        final signal = _RegistrationSignal(duringStateCheck);
        addTearDown(signal.close);
        var calls = 0;
        await expectLater(
          Future.sync(
            () => runWithAbortSignal(() async {
              calls++;
              return 42;
            }, signal),
          ),
          throwsA(isA<AiOperationCancelledError>()),
        );
        expect(calls, 0);
        expect(signal.hasListener, isFalse);
      },
    );
  }
}

class _RegistrationSignal implements ObservableAbortSignal {
  _RegistrationSignal(this.duringStateCheck);
  final bool duringStateCheck;
  final _events = StreamController<void>.broadcast();
  var checks = 0;
  var cancelled = false;
  @override
  bool get isCancelled {
    checks++;
    if (duringStateCheck && checks == 2) cancelled = true;
    return cancelled;
  }

  @override
  Stream<void> get cancellationEvents {
    cancelled = true;
    return _events.stream;
  }

  @override
  Future<void> get onCancelled => Future.value();
  bool get hasListener => _events.hasListener;
  Future<void> close() => _events.close();
}
