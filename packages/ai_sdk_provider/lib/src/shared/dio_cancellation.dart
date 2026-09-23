import 'dart:async';

import 'package:dio/dio.dart';

import 'abort_signal.dart';

/// Owns a Dio cancellation token and its request-scoped signal observer.
class DioCancellationScope {
  DioCancellationScope(AbortSignal? signal, {bool alwaysCreateToken = false})
    : token = signal == null && !alwaysCreateToken ? null : CancelToken() {
    if (signal == null || token == null) return;
    _observation = AbortSignalObservation.attach(signal, () {
      if (!token!.isCancelled) token!.cancel('abortSignal');
    });
  }

  final CancelToken? token;
  AbortSignalObservation? _observation;

  bool get isCancelled => token?.isCancelled ?? false;

  Future<void> dispose() async {
    final observation = _observation;
    _observation = null;
    await observation?.dispose();
  }
}
