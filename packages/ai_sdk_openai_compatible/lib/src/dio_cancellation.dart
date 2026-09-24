import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Adapts the shared provider signal to Dio cancellation.
CancelToken? cancelTokenFor(AbortSignal? abortSignal) {
  if (abortSignal == null) {
    return null;
  }

  final cancelToken = CancelToken();
  if (abortSignal.isCancelled) {
    cancelToken.cancel('abortSignal');
    return cancelToken;
  }

  unawaited(
    abortSignal.onCancelled.then((_) {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('abortSignal');
      }
    }),
  );
  return cancelToken;
}
