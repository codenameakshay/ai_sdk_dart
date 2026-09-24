import 'dart:async';
import 'dart:math';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import 'cancellation.dart';
import 'timeout_helpers.dart';
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
  Duration Function()? elapsed;
  Future<void> Function(Duration) sleep = Future.delayed;
  double Function() randomDouble = _retryRandom.nextDouble;
  void Function(RetryAttemptObservation)? onAttempt;

  void reset() {
    elapsed = null;
    sleep = Future.delayed;
    randomDouble = _retryRandom.nextDouble;
    onAttempt = null;
  }
}

void debugConfigureRetryHooksForTests({
  Duration Function()? elapsed,
  Future<void> Function(Duration)? sleep,
  double Function()? randomDouble,
  void Function(RetryAttemptObservation)? onAttempt,
}) {
  if (elapsed != null) _retryHooks.elapsed = elapsed;
  if (sleep != null) _retryHooks.sleep = sleep;
  if (randomDouble != null) _retryHooks.randomDouble = randomDouble;
  if (onAttempt != null) _retryHooks.onAttempt = onAttempt;
}

void debugResetRetryHooksForTests() {
  _retryHooks.reset();
}

Future<T> withRetry<T>({
  required int maxRetries,
  required Duration? totalTimeout,
  required Duration? stepTimeout,
  CancellationToken? abortSignal,
  void Function()? onRetry,
  required Future<T> Function(Duration? attemptTimeout) fn,
}) async {
  final stopwatch = Stopwatch()..start();
  var retryCount = 0;
  final attemptErrors = <Object>[];

  while (true) {
    throwIfCancelled(abortSignal);

    final attemptTimeout = _remainingTimeout(
      totalTimeout: totalTimeout,
      stepTimeout: stepTimeout,
      elapsed: _elapsedSinceStart(stopwatch),
    );
    if (retryCount > 0 && attemptTimeout == Duration.zero) {
      throw TimeoutException(
        'Retry budget exhausted.',
        minTimeout(totalTimeout, stepTimeout),
      );
    }
    _retryHooks.onAttempt?.call(
      RetryAttemptObservation(
        attemptNumber: retryCount + 1,
        timeout: attemptTimeout,
      ),
    );

    try {
      return await raceWithCancellation(fn(attemptTimeout), abortSignal);
    } catch (error) {
      attemptErrors.add(error);
      if (!_shouldRetry(
        error,
        retryCount: retryCount,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
      )) {
        if (!(abortSignal?.isCancelled ?? false) &&
            error is AiApiCallError &&
            error.isRetryable &&
            retryCount >= maxRetries) {
          throw AiRetryError(
            message: 'Retry attempts exhausted.',
            attempts: attemptErrors.length,
            lastError: error,
            errors: List.unmodifiable(attemptErrors),
          );
        }
        rethrow;
      }

      final remaining = _remainingTimeout(
        totalTimeout: totalTimeout,
        stepTimeout: stepTimeout,
        elapsed: _elapsedSinceStart(stopwatch),
      );
      if (remaining == Duration.zero) {
        throw TimeoutException(
          'Retry budget exhausted.',
          minTimeout(totalTimeout, stepTimeout),
        );
      }

      final requestedDelay = _retryDelayFor(
        retryAttempt: retryCount + 1,
        error: error,
      );
      final delay = remaining == null
          ? requestedDelay
          : _minDuration(requestedDelay, remaining);
      if (delay > Duration.zero) {
        final cancelled = await _sleepWithCancellation(
          duration: delay,
          abortSignal: abortSignal,
        );
        if (cancelled) rethrow;
      } else if (abortSignal?.isCancelled ?? false) {
        rethrow;
      }
      onRetry?.call();
      retryCount++;
    }
  }
}

Duration _elapsedSinceStart(Stopwatch stopwatch) {
  return _retryHooks.elapsed?.call() ?? stopwatch.elapsed;
}

Future<bool> _sleepWithCancellation({
  required Duration duration,
  required CancellationToken? abortSignal,
}) async {
  if (abortSignal == null) {
    await _retryHooks.sleep(duration);
    return false;
  }
  if (abortSignal.isCancelled) return true;

  final completer = Completer<bool>();
  var settled = false;
  AbortSignalObservation? observation;

  Future<void> complete(bool cancelled) async {
    if (settled) return;
    settled = true;
    await observation?.dispose();
    completer.complete(cancelled);
  }

  observation = AbortSignalObservation.attach(abortSignal, () {
    complete(true);
  });
  if (settled) {
    unawaited(observation.dispose());
    return completer.future;
  }

  Future.sync(() => _retryHooks.sleep(duration)).then(
    (_) => complete(false),
    onError: (Object error, StackTrace stackTrace) async {
      if (settled) return;
      settled = true;
      await observation?.dispose();
      completer.completeError(error, stackTrace);
    },
  );
  return completer.future;
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
  return false;
}

Duration _retryDelayFor({required int retryAttempt, required Object error}) {
  final retryAfter = _retryAfterDelay(error);
  if (retryAfter != null) return retryAfter;

  final exponentialDelayMs = retryAttempt > 3
      ? _retryMaxDelay.inMilliseconds
      : min(
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
  if (seconds == null || !seconds.isFinite || seconds.isNegative) return null;
  // Keep the bound exactly representable on Dart web, where integers use
  // JavaScript's safe integer range. This is still roughly 285 years.
  const maxRetryAfterMilliseconds =
      0x1fffffffffffff ~/ Duration.microsecondsPerMillisecond;
  final milliseconds = seconds * Duration.millisecondsPerSecond;
  if (!milliseconds.isFinite || milliseconds > maxRetryAfterMilliseconds) {
    return null;
  }
  return Duration(milliseconds: milliseconds.round());
}

Duration? _remainingTimeout({
  required Duration? totalTimeout,
  required Duration? stepTimeout,
  required Duration elapsed,
}) {
  return minTimeout(
    remainingTimeout(timeout: totalTimeout, elapsed: elapsed),
    remainingTimeout(timeout: stepTimeout, elapsed: elapsed),
  );
}

Duration _minDuration(Duration left, Duration right) {
  return left <= right ? left : right;
}
