import 'dart:async';

import 'package:ai_sdk_dart/src/core/retry_helper.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:test/test.dart';

class _ObservedToken extends CancellationToken {
  _ObservedToken() {
    _events = StreamController<void>.broadcast(
      onListen: () => attaches++,
      onCancel: () => detaches++,
    );
  }

  late final StreamController<void> _events;
  final _cancelled = Completer<void>();
  var cancelled = false;
  var attaches = 0;
  var detaches = 0;

  @override
  bool get isCancelled => cancelled;

  @override
  Future<void> get onCancelled => _cancelled.future;

  @override
  Stream<void> get cancellationEvents => _events.stream;

  @override
  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _cancelled.complete();
    _events
      ..add(null)
      ..close();
  }
}

void main() {
  tearDown(debugResetRetryHooksForTests);

  test('retry backoff detaches observers after repeated completion', () async {
    final token = _ObservedToken();
    addTearDown(token._events.close);
    debugConfigureRetryHooksForTests(
      sleep: (_) async {},
      randomDouble: () => 1,
    );

    for (var index = 0; index < 50; index++) {
      await expectLater(
        withRetry<void>(
          maxRetries: 1,
          totalTimeout: null,
          stepTimeout: null,
          abortSignal: token,
          fn: (_) async {
            throw const AiApiCallError('retry', isRetryable: true);
          },
        ),
        throwsA(isA<AiRetryError>()),
      );
      expect(token._events.hasListener, isFalse);
    }

    expect(token.attaches, greaterThan(50));
    expect(token.detaches, token.attaches);
  });

  test('retry backoff detaches observer when cancellation wins', () async {
    final token = _ObservedToken();
    addTearDown(token._events.close);
    final sleeping = Completer<void>();
    debugConfigureRetryHooksForTests(
      sleep: (_) => sleeping.future,
      randomDouble: () => 1,
    );

    final retry = withRetry<void>(
      maxRetries: 1,
      totalTimeout: null,
      stepTimeout: null,
      abortSignal: token,
      fn: (_) async {
        throw const AiApiCallError('retry', isRetryable: true);
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(token._events.hasListener, isTrue);
    token.cancel();

    await expectLater(retry, throwsA(isA<AiApiCallError>()));
    await Future<void>.delayed(Duration.zero);
    expect(token._events.hasListener, isFalse);
    sleeping.complete();
  });
}
