Duration? remainingTimeout({
  required Duration? timeout,
  required Duration elapsed,
}) {
  if (timeout == null) return null;
  if (elapsed >= timeout) return Duration.zero;
  return timeout - elapsed;
}

Duration? minTimeout(Duration? left, Duration? right) {
  if (left == null) return right;
  if (right == null) return left;
  return left <= right ? left : right;
}
