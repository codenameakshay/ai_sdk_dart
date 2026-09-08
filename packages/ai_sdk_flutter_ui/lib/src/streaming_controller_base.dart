import 'package:flutter/foundation.dart';

import 'frame_notifier.dart';

/// Shared plumbing for the streaming controllers (`ChatController`,
/// `CompletionController`, `ObjectStreamController`): the three
/// [FrameNotifier]s, the request-id guard that lets async callbacks detect
/// they've been superseded, and the [ChangeNotifier] overrides that route
/// through the root notifier.
///
/// Not part of the public API.
abstract class StreamingControllerBase extends ChangeNotifier {
  StreamingControllerBase({FrameNotificationScheduler? notificationScheduler})
    : rootNotifier = FrameNotifier(scheduler: notificationScheduler),
      statusNotifier = FrameNotifier(scheduler: notificationScheduler),
      contentNotifier = FrameNotifier(scheduler: notificationScheduler);

  final FrameNotifier rootNotifier;
  final FrameNotifier statusNotifier;
  final FrameNotifier contentNotifier;

  /// Notifies listeners about status-facing state. What exactly this covers
  /// depends on the subclass.
  Listenable get statusListenable => statusNotifier;

  /// Notifies listeners about content-facing state. What exactly this covers
  /// depends on the subclass.
  Listenable get contentListenable => contentNotifier;

  int nextRequestId = 0;
  int? activeRequestId;
  bool isDisposed = false;

  bool isCurrentRequest(int requestId) =>
      !isDisposed && activeRequestId == requestId;

  void notifyListenersSafely({
    required bool immediate,
    bool status = false,
    bool content = false,
  }) {
    if (isDisposed) return;
    if (immediate) {
      rootNotifier.notifyImmediately();
      if (status) statusNotifier.notifyImmediately();
      if (content) contentNotifier.notifyImmediately();
      return;
    }

    rootNotifier.notifyInFrame();
    if (content) contentNotifier.notifyInFrame();
  }

  void notifyTerminalListeners({required bool statusChanged}) {
    if (isDisposed) return;
    rootNotifier.notifyImmediately();
    if (statusChanged) statusNotifier.notifyImmediately();
    if (contentNotifier.hasPendingNotification) {
      contentNotifier.notifyImmediately();
    }
  }

  @override
  void addListener(VoidCallback listener) => rootNotifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      rootNotifier.removeListener(listener);

  @override
  bool get hasListeners => rootNotifier.hasListeners;

  @override
  void dispose() {
    isDisposed = true;
    rootNotifier.dispose();
    statusNotifier.dispose();
    contentNotifier.dispose();
    super.dispose();
  }
}
