import 'dart:async';

/// Exponential retry timing for the legacy HTTP notification listener.
///
/// This is an internal transport helper. A configured initial delay above the
/// 30 second default cap is preserved as the effective cap.
class ListenerReconnectBackoff {
  ListenerReconnectBackoff(this.initialDelay);

  final Duration initialDelay;
  Timer? _timer;
  int _attempt = 0;

  bool get isScheduled => _timer?.isActive ?? false;

  void schedule(void Function() callback) {
    if (isScheduled) return;
    final maximumDelay = initialDelay > const Duration(seconds: 30)
        ? initialDelay
        : const Duration(seconds: 30);
    var delay = initialDelay;
    for (
      var index = 0;
      index < _attempt && delay > Duration.zero && delay < maximumDelay;
      index++
    ) {
      delay = delay > maximumDelay - delay ? maximumDelay : delay + delay;
    }
    _attempt++;
    _timer = Timer(delay, () {
      _timer = null;
      callback();
    });
  }

  /// Resets the exponential sequence after the listener delivers an event.
  void reset() => _attempt = 0;

  /// Cancels a queued retry and resets the sequence for a later session.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _attempt = 0;
  }
}
