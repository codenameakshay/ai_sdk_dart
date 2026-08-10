import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('FrameNotifier', () {
    test('coalesces repeated frame notifications into one callback', () {
      final scheduler = FakeFrameNotificationScheduler();
      final notifier = FrameNotifier(scheduler: scheduler);
      var notifications = 0;
      notifier.addListener(() {
        notifications++;
      });

      notifier.notifyInFrame();
      notifier.notifyInFrame();
      notifier.notifyInFrame();

      expect(notifications, 0);
      expect(scheduler.pendingCallbackCount, 1);

      scheduler.flush();

      expect(notifications, 1);
      expect(scheduler.pendingCallbackCount, 0);
      notifier.dispose();
    });

    test(
      'immediate notify flushes a queued frame callback without duplicating',
      () {
        final scheduler = FakeFrameNotificationScheduler();
        final notifier = FrameNotifier(scheduler: scheduler);
        var notifications = 0;
        notifier.addListener(() {
          notifications++;
        });

        notifier.notifyInFrame();
        notifier.notifyImmediately();

        expect(notifications, 1);
        expect(scheduler.pendingCallbackCount, 0);

        scheduler.flush();

        expect(notifications, 1);
        notifier.dispose();
      },
    );

    test('dispose cancels a queued callback', () {
      final scheduler = FakeFrameNotificationScheduler();
      final notifier = FrameNotifier(scheduler: scheduler);
      var notifications = 0;
      notifier.addListener(() {
        notifications++;
      });

      notifier.notifyInFrame();
      notifier.dispose();

      expect(scheduler.pendingCallbackCount, 0);

      scheduler.flush();

      expect(notifications, 0);
    });
  });
}
