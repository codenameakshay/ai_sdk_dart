import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

typedef CancelFrameNotification = void Function();

/// Schedules coalesced visual notifications onto a future Flutter frame.
abstract interface class FrameNotificationScheduler {
  CancelFrameNotification schedule(VoidCallback callback);
}

/// Default scheduler backed by Flutter's transient frame callbacks.
final class SchedulerBindingFrameNotificationScheduler
    implements FrameNotificationScheduler {
  const SchedulerBindingFrameNotificationScheduler();

  @override
  CancelFrameNotification schedule(VoidCallback callback) {
    try {
      final binding = SchedulerBinding.instance;
      final callbackId = binding.scheduleFrameCallback(
        (_) => callback(),
        scheduleNewFrame: false,
      );
      binding.ensureVisualUpdate();
      return () => binding.cancelFrameCallbackWithId(callbackId);
    } on Object {
      final timer = Timer(Duration.zero, callback);
      return timer.cancel;
    }
  }
}

/// A [ChangeNotifier] that can either notify immediately or coalesce multiple
/// synchronous updates into a single frame notification.
class FrameNotifier extends ChangeNotifier {
  FrameNotifier({FrameNotificationScheduler? scheduler})
    : _scheduler =
          scheduler ?? const SchedulerBindingFrameNotificationScheduler();

  final FrameNotificationScheduler _scheduler;

  CancelFrameNotification? _cancelScheduledNotification;
  bool _isDisposed = false;

  /// Whether a coalesced frame notification is currently queued.
  bool get hasPendingNotification => _cancelScheduledNotification != null;

  /// Notify listeners on the next frame, collapsing repeated calls into one.
  void notifyInFrame() {
    if (_isDisposed || _cancelScheduledNotification != null) return;
    _cancelScheduledNotification = _scheduler.schedule(_flushScheduledNotify);
  }

  /// Notify listeners now and cancel any queued frame notification.
  void notifyImmediately() {
    if (_isDisposed) return;
    _cancelPendingNotification();
    super.notifyListeners();
  }

  @override
  void notifyListeners() => notifyImmediately();

  void _flushScheduledNotify() {
    _cancelScheduledNotification = null;
    if (_isDisposed) return;
    super.notifyListeners();
  }

  void _cancelPendingNotification() {
    final cancelScheduledNotification = _cancelScheduledNotification;
    _cancelScheduledNotification = null;
    cancelScheduledNotification?.call();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cancelPendingNotification();
    super.dispose();
  }
}
