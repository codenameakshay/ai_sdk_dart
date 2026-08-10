import 'dart:async';
import 'dart:math';

import '../errors/ai_errors.dart';
import '../tools/tool.dart';

const Duration _retryBaseDelay = Duration(milliseconds: 100);
const Duration _retryMaxDelay = Duration(milliseconds: 500);

final Random _retryRandom = Random();
final _RetryHooks _retryHooks = _RetryHooks();

class RetryAttemptObservation {
  const RetryAttemptObservation({
    required this.attemptNumber,
    required this.timeout,
  });

  final int attemptNumber;
  final Duration? timeout;
}

class _RetryHooks {
  DateTime Function() now = DateTime.now;
  Future<void> Function(Duration) sleep = Future.delayed;
  double Function() randomDouble = _retryRandom.nextDouble;
  void Function(RetryAttemptObservation)? onAttempt;

  void reset() {
    now = DateTime.now;
    sleep = Future.delayed;
    randomDouble = _retryRandom.nextDouble;
    onAttempt = null;
  }
}

void debugConfigureRetryHooksForTests({
  DateTime Function()? now,
  Future<void> Function(Duration)? sleep,
  double Function()? randomDouble,
  void Function(RetryAttemptObservation)? onAttempt,
}) {
  if (now != null) _retryHooks.now = now;
  if (sleep != null) _retryHooks.sleep = sleep;
  if (randomDouble != null) _retryHooks.randomDouble = randomDouble;
  if (onAttempt != null) _retryHooks.onAttempt = onAttempt;
}

void debugResetRetryHooksForTests() {
  _retryHooks.reset();
}

Future<T> withRetry<T>({
  required int maxRetries,
  required Duration? timeout,
  CancellationToken? abortSignal,
  required Future<T> Function(Duration? attemptTimeout) fn,
}) async {
  final startedAt = _retryHooks.now();
  var retryCount = 0;

  while (true) {
    final attemptTimeout = _remainingTimeout(
      totalTimeout: timeout,
      startedAt: startedAt,
    );
    if (retryCount > 0 && attemptTimeout == Duration.zero) {
      throw TimeoutException('Retry budget exhausted.', timeout);
    }
    _retryHooks.onAttempt?.call(
      RetryAttemptObservation(
        attemptNumber: retryCount + 1,
        timeout: attemptTimeout,
      ),
    );

    try {
      return await fn(attemptTimeout);
    } catch (error) {
      if (!_shouldRetry(
        error,
        retryCount: retryCount,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
      )) {
        rethrow;
      }

      final remaining = _remainingTimeout(
        totalTimeout: timeout,
        startedAt: startedAt,
      );
      if (remaining == Duration.zero) {
        throw TimeoutException('Retry budget exhausted.', timeout);
      }

      final requestedDelay = _retryDelayFor(
        retryAttempt: retryCount + 1,
        error: error,
      );
      final delay = timeout == null
          ? requestedDelay
          : _minDuration(requestedDelay, remaining!);
      if (delay > Duration.zero) {
        await _retryHooks.sleep(delay);
      }
      retryCount++;
    }
  }
}

bool _shouldRetry(
  Object error, {
  required int retryCount,
  required int maxRetries,
  required CancellationToken? abortSignal,
}) {
  if (retryCount >= maxRetries) return false;
  if (abortSignal?.isCancelled ?? false) return false;
  if (error is TimeoutException) return false;
  if (error is AiApiCallError) return error.isRetryable;
  return true;
}

Duration _retryDelayFor({required int retryAttempt, required Object error}) {
  final retryAfter = _retryAfterDelay(error);
  if (retryAfter != null) return retryAfter;

  final exponentialDelayMs = min(
    _retryBaseDelay.inMilliseconds * (1 << (retryAttempt - 1)),
    _retryMaxDelay.inMilliseconds,
  );
  final jitteredDelayMs = (exponentialDelayMs * _retryHooks.randomDouble())
      .round();
  return Duration(milliseconds: jitteredDelayMs);
}

Duration? _retryAfterDelay(Object error) {
  if (error is! AiApiCallError) return null;

  // ai_sdk_provider currently exposes raw response headers but no typed
  // Retry-After field. Honor numeric delta-seconds here without expanding
  // provider-package ownership for one consumer-specific policy.
  String? retryAfterValue;
  for (final entry
      in error.responseHeaders?.entries ?? const <MapEntry<String, String>>[]) {
    if (entry.key.toLowerCase() == 'retry-after') {
      retryAfterValue = entry.value;
      break;
    }
  }
  if (retryAfterValue == null) return null;

  final seconds = num.tryParse(retryAfterValue.trim());
  if (seconds == null || seconds.isNegative) return null;
  return Duration(milliseconds: (seconds * 1000).round());
}

Duration? _remainingTimeout({
  required Duration? totalTimeout,
  required DateTime startedAt,
}) {
  if (totalTimeout == null) return null;

  final elapsed = _retryHooks.now().difference(startedAt);
  if (elapsed >= totalTimeout) return Duration.zero;
  return totalTimeout - elapsed;
}

Duration _minDuration(Duration left, Duration right) {
  return left <= right ? left : right;
}
