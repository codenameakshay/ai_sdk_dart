import 'dart:async';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// A fake [AbortSignal] that can be cancelled on demand from a
/// test.
class TestAbortSignal implements AbortSignal {
  final Completer<void> _completer = Completer<void>();
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get onCancelled => _completer.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _completer.complete();
  }
}

/// An [HttpClientAdapter] whose `fetch` never resolves on its own; it only
/// completes (with a [DioException.requestCancelled]) once `cancelFuture`
/// fires, letting tests assert on cancellation/abort behavior.
class CancellationHttpClientAdapter implements HttpClientAdapter {
  int fetchCount = 0;
  RequestOptions? lastOptions;
  final Completer<void> fetchStarted = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    fetchCount++;
    lastOptions = options;
    if (!fetchStarted.isCompleted) {
      fetchStarted.complete();
    }

    final completer = Completer<ResponseBody>();
    cancelFuture?.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          DioException.requestCancelled(
            requestOptions: options,
            reason: 'abortSignal',
          ),
        );
      }
    });
    return completer.future;
  }

  @override
  void close({bool force = false}) {}
}
