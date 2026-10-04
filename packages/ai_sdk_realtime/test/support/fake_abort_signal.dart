import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

/// A controllable [AbortSignal] for exercising cancellation paths.
class FakeAbortSignal implements AbortSignal {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get onCancelled => _cancelled.future;

  void cancel() => _cancelled.complete();
}
