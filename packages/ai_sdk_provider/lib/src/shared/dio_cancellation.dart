import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/ai_errors.dart';
import 'abort_signal.dart';

/// Owns a Dio cancellation token and its request-scoped signal observer.
class DioCancellationScope {
  DioCancellationScope(AbortSignal? signal, {bool alwaysCreateToken = false})
    : _signal = signal,
      token = signal == null && !alwaysCreateToken ? null : CancelToken() {
    if (signal == null || token == null) return;
    _observation = AbortSignalObservation.attach(signal, () {
      if (!token!.isCancelled) token!.cancel('abortSignal');
    });
  }

  final AbortSignal? _signal;
  final CancelToken? token;
  AbortSignalObservation? _observation;

  bool get isCancelled => token?.isCancelled ?? false;

  /// Runs pre-request work such as header resolution under the scope's signal.
  ///
  /// Disposes the scope and rethrows when [operation] fails, and throws
  /// [AiOperationCancelledError] when the signal fired meanwhile.
  Future<T> run<T>(FutureOr<T> Function() operation) async {
    try {
      final value = await runWithAbortSignal(() async => operation(), _signal);
      if (_signal?.isCancelled ?? false) {
        throw const AiOperationCancelledError();
      }
      return value;
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  Future<void> dispose() async {
    final observation = _observation;
    _observation = null;
    await observation?.dispose();
  }
}
