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

  void completeError(Object error, StackTrace stackTrace) {
    if (settled) return;
    settled = true;
    completer.completeError(error, stackTrace);
  }

  operation.then((value) {
    if (settled) return;
    settled = true;
    completer.complete(value);
  }, onError: completeError);

  abortSignal.onCancelled.then((_) {
    if (settled) return;
    settled = true;
    completer.completeError(
      const AiOperationCancelledError(),
      StackTrace.current,
    );
  });

  return completer.future;
}

Future<bool> moveNextOrCancellation<T>(
  StreamIterator<T> iterator,
  CancellationToken? abortSignal,
) {
  return raceWithCancellation(iterator.moveNext(), abortSignal);
}

void observeFutureError<T>(Future<T> future) {
  future.ignore();
}
