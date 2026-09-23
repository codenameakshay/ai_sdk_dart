import 'dart:async';

import '../errors/ai_errors.dart';
import '../tools/tool.dart';

void throwIfCancelled(CancellationToken? abortSignal) {
  if (abortSignal?.isCancelled ?? false) {
    throw const AiOperationCancelledError();
  }
}

Future<T> raceWithCancellation<T>(
  Future<T> operation,
  CancellationToken? abortSignal,
) {
  if (abortSignal == null) {
    return operation;
  }
  if (abortSignal.isCancelled) {
    return Future<T>.error(const AiOperationCancelledError());
  }

  final completer = Completer<T>();
  var settled = false;
  StreamSubscription<void>? cancellationSubscription;

  void detach() {
    final subscription = cancellationSubscription;
    cancellationSubscription = null;
    if (subscription != null) Future<void>.sync(subscription.cancel).ignore();
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (settled) return;
    settled = true;
    detach();
    completer.completeError(error, stackTrace);
  }

  operation.then((value) {
    if (settled) return;
    settled = true;
    detach();
    completer.complete(value);
  }, onError: completeError);

  void cancel() {
    if (settled) return;
    settled = true;
    detach();
    completer.completeError(
      const AiOperationCancelledError(),
      StackTrace.current,
    );
  }

  cancellationSubscription = abortSignal.cancellationEvents.listen(
    (_) => cancel(),
  );

  return completer.future;
}
