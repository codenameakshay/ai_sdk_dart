import 'dart:async';

import 'package:meta/meta.dart';

@internal
extension CompleteIfPending<T> on Completer<T> {
  void completeIfPending(T value) {
    if (!isCompleted) complete(value);
  }

  void completeErrorIfPending(Object error, StackTrace stackTrace) {
    if (!isCompleted) completeError(error, stackTrace);
  }
}

@internal
Stream<T> terminalAwareBroadcastStream<T>({
  required Stream<T> source,
  required bool Function() isTerminal,
  required Object? Function() terminalError,
  required StackTrace? Function() terminalStackTrace,
  Iterable<T> Function()? replayOnError,
}) {
  return Stream<T>.multi((controller) {
    if (isTerminal()) {
      final error = terminalError();
      if (error != null) {
        final replayItems = replayOnError?.call();
        if (replayItems != null) {
          for (final item in replayItems) {
            controller.add(item);
          }
        }
        controller.addError(error, terminalStackTrace());
      }
      controller.close();
      return;
    }

    final subscription = source.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  }, isBroadcast: true);
}
