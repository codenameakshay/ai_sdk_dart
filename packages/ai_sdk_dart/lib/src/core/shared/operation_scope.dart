import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../../tools/tool.dart';
import '../cancellation.dart';

Future<T> runOperation<T>({
  required Future<T> Function(AbortSignal signal) operation,
  CancellationToken? abortSignal,
  Duration? timeout,
}) async {
  final scope = OperationScope(abortSignal: abortSignal, timeout: timeout);
  try {
    return await scope.run(() {
      if (scope.signal.isCancelled) {
        return Future<T>.error(const AiOperationCancelledError());
      }
      return operation(scope.signal);
    }, raceCancellation: true);
  } finally {
    scope.close();
  }
}

class OperationScope {
  OperationScope({CancellationToken? abortSignal, Duration? timeout}) {
    _stopwatch.start();
    _timeout = timeout;
    if (abortSignal != null) {
      if (abortSignal.isCancelled) {
        signal.cancel();
      } else {
        _callerSubscription = abortSignal.cancellationEvents.listen((_) {
          signal.cancel();
        });
      }
    }
    if (timeout != null) {
      _timer = Timer(timeout, () {
        _stop(
          TimeoutException('Operation deadline exceeded', timeout),
          StackTrace.current,
        );
      });
    }
  }

  final signal = CancellationToken();
  final _terminal =
      StreamController<({Object error, StackTrace stackTrace})>.broadcast(
        sync: true,
      );
  ({Object error, StackTrace stackTrace})? _failure;
  Timer? _timer;
  StreamSubscription<void>? _callerSubscription;
  bool _closed = false;
  final _stopwatch = Stopwatch();
  Duration? _timeout;

  Duration get elapsed => _stopwatch.elapsed;

  void checkDeadline() {
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
    final timeout = _timeout;
    if (timeout != null && elapsed >= timeout) {
      final error = TimeoutException('Operation deadline exceeded', timeout);
      _stop(error, StackTrace.current);
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  Future<T> run<T>(
    Future<T> Function() operation, {
    bool raceCancellation = false,
  }) {
    if (_failure case final failure?) {
      return Future.error(failure.error, failure.stackTrace);
    }
    if (_closed) return Future.error(StateError('Operation is closed'));
    if (raceCancellation && signal.isCancelled) {
      return Future.error(const AiOperationCancelledError());
    }
    final result = Completer<T>();
    final subscription = _terminal.stream.listen((failure) {
      if (!result.isCompleted) {
        result.completeError(failure.error, failure.stackTrace);
      }
    });
    final rawOperation = Future.sync(operation);
    final operationFuture = raceCancellation
        ? raceWithCancellation(rawOperation, signal)
        : rawOperation;
    operationFuture.then(
      (value) {
        if (_timeout != null && _stopwatch.elapsed >= _timeout!) {
          _stop(
            TimeoutException('Operation deadline exceeded', _timeout),
            StackTrace.current,
          );
        }
        unawaited(subscription.cancel());
        if (_failure case final failure?) {
          if (!result.isCompleted) {
            result.completeError(failure.error, failure.stackTrace);
          }
          return;
        }
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stackTrace) {
        unawaited(subscription.cancel());
        if (result.isCompleted) return;
        _stop(error, stackTrace);
        final failure = _failure!;
        result.completeError(failure.error, failure.stackTrace);
      },
    );
    return result.future;
  }

  void _stop(Object error, StackTrace stackTrace) {
    if (_closed || _failure != null) return;
    _failure = (error: error, stackTrace: stackTrace);
    _timer?.cancel();
    _stopwatch.stop();
    _terminal.add(_failure!);
    signal.cancel();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    unawaited(_callerSubscription?.cancel());
    unawaited(_terminal.close());
  }
}
