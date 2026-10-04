import 'package:ai_sdk_mcp/src/listener_reconnect_backoff.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('legacy GET failures back off exponentially and cap at 30 seconds', () {
    fakeAsync((async) {
      final backoff = ListenerReconnectBackoff(const Duration(seconds: 10));
      final firedAt = <Duration>[];
      void retry() => backoff.schedule(() {
        firedAt.add(async.elapsed);
        retry();
      });

      retry();
      for (final elapsed in [
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        const Duration(seconds: 60),
        const Duration(seconds: 90),
      ]) {
        async.elapse(elapsed - async.elapsed);
        expect(firedAt.last, elapsed);
      }
      expect(firedAt, [
        const Duration(seconds: 10),
        const Duration(seconds: 30),
        const Duration(seconds: 60),
        const Duration(seconds: 90),
      ]);
      backoff.cancel();
    });
  });

  test('a delivered event resets the legacy GET backoff sequence', () {
    fakeAsync((async) {
      final backoff = ListenerReconnectBackoff(const Duration(seconds: 10));
      final firedAt = <Duration>[];
      backoff.schedule(() => firedAt.add(async.elapsed));

      async.elapse(const Duration(seconds: 10));
      expect(firedAt, [const Duration(seconds: 10)]);
      backoff.reset(); // The listener delivered an SSE notification.
      backoff.schedule(() => firedAt.add(async.elapsed));
      async.elapse(const Duration(seconds: 10));
      expect(firedAt, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
    });
  });

  test('closing cancels a queued legacy GET reconnect', () {
    fakeAsync((async) {
      final backoff = ListenerReconnectBackoff(const Duration(seconds: 10));
      var attempts = 0;
      backoff.schedule(() => attempts++);
      backoff.cancel(); // The transport is closing.

      async.elapse(const Duration(minutes: 1));
      expect(attempts, 0);
      expect(backoff.isScheduled, isFalse);
    });
  });

  test(
    'an explicitly configured initial delay above 30 seconds is preserved',
    () {
      fakeAsync((async) {
        final backoff = ListenerReconnectBackoff(const Duration(seconds: 40));
        var attempts = 0;
        void retry() => backoff.schedule(() => attempts++);
        retry();

        async.elapse(
          const Duration(seconds: 40) - const Duration(microseconds: 1),
        );
        expect(attempts, 0);
        async.elapse(const Duration(microseconds: 1));
        expect(attempts, 1);
        retry();
        async.elapse(const Duration(seconds: 40));
        expect(attempts, 2);
        backoff.cancel();
      });
    },
  );
}
