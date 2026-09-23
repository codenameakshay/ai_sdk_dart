import 'dart:async';

import '../errors/ai_errors.dart';

/// Cooperative cancellation shared by every provider operation.
abstract interface class AbortSignal {
  bool get isCancelled;
  Future<void> get onCancelled;
}

/// Optional detachable cancellation capability for request-scoped observers.
///
/// Implementations that only provide [AbortSignal.onCancelled] remain
/// supported. Their observer callback is cleared on disposal, but the future
/// itself cannot be unsubscribed.
abstract interface class ObservableAbortSignal implements AbortSignal {
  Stream<void> get cancellationEvents;
}

/// A request-scoped observer registration for an [AbortSignal].
class AbortSignalObservation {
  AbortSignalObservation._();

  StreamSubscription<void>? _subscription;
  void Function()? _activeCallback;

  static AbortSignalObservation attach(
    AbortSignal signal,
    void Function() callback,
  ) {
    final observation = AbortSignalObservation._();
    observation._activeCallback = callback;
    if (signal.isCancelled) {
      observation._fire();
    } else if (signal is ObservableAbortSignal) {
      observation._subscription = signal.cancellationEvents.listen((_) {
        observation._fire();
      });
    } else {
      unawaited(signal.onCancelled.then((_) => observation._fire()));
    }
    if (signal.isCancelled) observation._fire();
    return observation;
  }

  void _fire() {
    final callback = _activeCallback;
    _activeCallback = null;
    callback?.call();
  }

  Future<void> dispose() async {
    _activeCallback = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}

/// Runs lazy work only when [signal] is active and races its completion
/// against cancellation. The observer is detached on every terminal path.
Future<T> runWithAbortSignal<T>(
  Future<T> Function() operation,
  AbortSignal? signal,
) {
  if (signal == null) return operation();
  if (signal.isCancelled) {
    return Future<T>.error(const AiOperationCancelledError());
  }
  final completer = Completer<T>();
  var settled = false;
  AbortSignalObservation? observation;

  void finish(void Function() complete) {
    if (settled) return;
    settled = true;
    unawaited(observation?.dispose());
    complete();
  }

  observation = AbortSignalObservation.attach(signal, () {
    finish(() {
      completer.completeError(
        const AiOperationCancelledError(),
        StackTrace.current,
      );
    });
  });
  if (settled) {
    unawaited(observation.dispose());
    return completer.future;
  }
  Future.sync(operation).then(
    (value) => finish(() => completer.complete(value)),
    onError: (Object error, StackTrace stackTrace) =>
        finish(() => completer.completeError(error, stackTrace)),
  );
  return completer.future;
}
