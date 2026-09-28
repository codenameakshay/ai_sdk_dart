import 'dart:async';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

import 'support/fake_abort_signal.dart';

void main() {
  test('late transport cleanup cannot leak a second error', () async {
    final escaped = <Object>[];
    await runZonedGuarded<Future<void>>(() async {
      final connected = Completer<RealtimeTransport>();
      final signal = FakeAbortSignal();
      final pending = RealtimeSession.connect(
        apiKey: 'fixture',
        abortSignal: signal,
        connector: (_, _) => connected.future,
      );
      final failed = expectLater(
        pending,
        throwsA(isA<AiOperationCancelledError>()),
      );
      signal.cancel();
      await failed;
      connected.complete(_Transport(failClose: true));
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => escaped.add(error));
    expect(escaped, isEmpty);
  });

  test('cancelled startup closes a late transport exactly once', () async {
    final connected = Completer<RealtimeTransport>();
    final signal = FakeAbortSignal();
    final transport = _Transport();
    final pending = RealtimeSession.connect(
      apiKey: 'fixture',
      abortSignal: signal,
      connector: (_, _) => connected.future,
    );
    final failed = expectLater(
      pending,
      throwsA(isA<AiOperationCancelledError>()),
    );
    signal.cancel();
    await failed;
    connected.complete(transport);
    await Future<void>.delayed(Duration.zero);
    expect(transport.closeCount, 1);
    expect(transport.sent, isEmpty);
  });
}

class _Transport implements RealtimeTransport {
  _Transport({this.failClose = false});
  final bool failClose;
  int closeCount = 0;
  final sent = <String>[];
  @override
  Stream<Object?> get incoming => const Stream.empty();
  @override
  Future<void> send(String text) async => sent.add(text);
  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount++;
    if (failClose) throw StateError('cleanup failed');
  }
}
