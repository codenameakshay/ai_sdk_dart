import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import 'openai_errors.dart';

/// Owns the transport cancellation, caller cancellation and deadline for one
/// OpenAI request. It is deliberately private to this package.
class OpenAIRequestScope {
  OpenAIRequestScope(AbortSignal? signal, Duration? timeout)
    : token = CancelToken(),
      _signal = signal {
    if (timeout != null && (timeout.isNegative || timeout == Duration.zero)) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (signal != null) {
      if (signal.isCancelled) {
        cancel();
      } else {
        final observation = AbortSignalObservation.attach(signal, cancel);
        _observation = observation;
        if (cancelled) {
          _observation = null;
          unawaited(observation.dispose());
        }
      }
    }
    if (timeout != null) {
      _timer = Timer(timeout, () => cancel(timeout: true));
    }
  }

  final CancelToken token;
  final AbortSignal? _signal;
  AbortSignalObservation? _observation;
  Timer? _timer;
  bool cancelled = false;
  bool timedOut = false;
  bool _closed = false;

  Future<T> race<T>(Future<T> Function() operation) {
    if (cancelled) {
      return Future<T>.error(
        timedOut
            ? const OpenAIFileTimeoutException()
            : const AiOperationCancelledError(),
      );
    }
    final pending = operation();
    if (_signal == null && _timer == null) return pending;
    return Future.any<T>([
      pending,
      token.whenCancel.then<T>(
        (_) => throw timedOut
            ? const OpenAIFileTimeoutException()
            : const AiOperationCancelledError(),
      ),
    ]);
  }

  void cancel({bool timeout = false}) {
    if (_closed || cancelled) return;
    cancelled = true;
    timedOut = timeout;
    if (!token.isCancelled) token.cancel();
    final observation = _observation;
    _observation = null;
    unawaited(observation?.dispose());
  }

  Future<void> dispose({bool cancelTransport = false}) async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    if (cancelTransport && !token.isCancelled) token.cancel();
    final observation = _observation;
    _observation = null;
    await observation?.dispose();
  }
}

void throwIfOpenAICancelled(OpenAIRequestScope scope) {
  if (scope.timedOut) throw const OpenAIFileTimeoutException();
  if (scope.cancelled) throw const AiOperationCancelledError();
}
