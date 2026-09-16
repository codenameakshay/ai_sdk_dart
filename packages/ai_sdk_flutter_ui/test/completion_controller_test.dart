import 'dart:async';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('CompletionController', () {
    test('starts empty and idle', () {
      final controller = CompletionController(agent: textAgent('x'));
      expect(controller.completion, isEmpty);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('complete accumulates text and toggles loading/streaming', () async {
      final controller = CompletionController(agent: textAgent('Hello there'));
      var sawLoading = false;
      var sawStreaming = false;
      controller.addListener(() {
        if (controller.isLoading) sawLoading = true;
        if (controller.isStreaming) sawStreaming = true;
      });

      await controller.complete('Hi');
      await pumpUntil(() => !controller.isLoading);

      expect(sawLoading, isTrue);
      expect(sawStreaming, isTrue);
      expect(controller.completion, 'Hello there');
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('onFinish fires with the full text', () async {
      String? finished;
      final controller = CompletionController(
        agent: textAgent('done'),
        onFinish: (t) => finished = t,
      );
      await controller.complete('go');
      await pumpUntil(() => finished != null);
      expect(finished, 'done');
      controller.dispose();
    });

    test('onError fires and error is set on failure', () async {
      Object? captured;
      final failure = StateError('boom');
      final controller = CompletionController(
        agent: erroringAgent(failure),
        onError: (e) => captured = e,
      );
      await controller.complete('go');
      await pumpUntil(() => controller.error != null);
      expect(controller.error, isNotNull);
      expect(captured, isNotNull);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('async lifecycle callback failures are contained', () async {
      final callbackFailure = StateError('callback failed');
      var finishInvoked = false;
      final finished = CompletionController(
        agent: textAgent('done'),
        onFinish: (_) async {
          finishInvoked = true;
          throw callbackFailure;
        },
      );
      await finished.complete('go');
      await pumpUntil(() => !finished.isLoading);
      await Future<void>.delayed(Duration.zero);
      expect(finishInvoked, isTrue);
      expect(finished.isLoading, isFalse);
      expect(finished.isStreaming, isFalse);
      expect(finished.error, isNull);
      finished.dispose();

      final streamFailure = StateError('stream failed');
      var errorInvoked = false;
      final errored = CompletionController(
        agent: erroringAgent(streamFailure),
        onError: (_) async {
          errorInvoked = true;
          throw callbackFailure;
        },
      );
      await errored.complete('go');
      await pumpUntil(() => errored.error != null);
      await Future<void>.delayed(Duration.zero);
      expect(errorInvoked, isTrue);
      expect(errored.error, same(streamFailure));
      expect(errored.isLoading, isFalse);
      expect(errored.isStreaming, isFalse);
      errored.dispose();
    });

    test('complete resets prior state on a new call', () async {
      final controller = CompletionController(agent: textAgent('first'));
      await controller.complete('a');
      await pumpUntil(() => !controller.isLoading);
      expect(controller.completion, 'first');

      // Second completion reuses the same agent/model -> same text, but the
      // buffer must have been reset (not appended).
      await controller.complete('b');
      await pumpUntil(() => !controller.isLoading);
      expect(controller.completion, 'first');
      controller.dispose();
    });

    test('clear resets all state', () async {
      final controller = CompletionController(agent: textAgent('x'));
      await controller.complete('a');
      await pumpUntil(() => !controller.isLoading);
      controller.clear();
      expect(controller.completion, isEmpty);
      expect(controller.error, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('stop is a safe no-op after completion', () async {
      final controller = CompletionController(agent: textAgent('x'));
      await controller.complete('a');
      await pumpUntil(() => !controller.isLoading);
      await controller.stop();
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('stop cancels an in-flight stream and resets flags', () async {
      final controller = CompletionController(
        agent: ToolLoopAgent(model: HoldingTextModel('partial')),
      );

      // Don't await: the holding model keeps the stream open so stop() runs
      // while a subscription is genuinely active.
      unawaited(controller.complete('q'));
      await pumpUntil(() => controller.completion.isNotEmpty);
      expect(controller.isStreaming, isTrue);

      await controller.stop();
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test(
      'a synchronous failure from agent.stream() is caught and reported',
      () async {
        Object? captured;
        final failure = StateError('sync boom');
        final controller = CompletionController(
          agent: syncThrowingAgent(failure),
          onError: (e) => captured = e,
        );

        await controller.complete('go');
        await pumpUntil(() => controller.error != null);

        expect(controller.error, same(failure));
        expect(captured, same(failure));
        expect(controller.isLoading, isFalse);
        expect(controller.isStreaming, isFalse);
        controller.dispose();
      },
    );

    test('an agent.stream() that throws synchronously is caught', () async {
      Object? captured;
      final failure = StateError('stream() threw');
      final controller = CompletionController(
        agent: ThrowingStreamAgent(failure),
        onError: (e) => captured = e,
      );

      await controller.complete('go');
      await pumpUntil(() => controller.error != null);

      expect(controller.error, same(failure));
      expect(captured, same(failure));
      controller.dispose();
    });

    test('captures the last usage after completing', () async {
      const usage = LanguageModelV4Usage(
        inputTokens: LanguageModelV4InputTokenUsage(total: 3),
        outputTokens: LanguageModelV4OutputTokenUsage(total: 5),
      );
      final controller = CompletionController(
        agent: textAgentWithUsage('done', usage),
      );

      await controller.complete('go');
      await pumpUntil(() => !controller.isStreaming && !controller.isLoading);

      expect(controller.lastUsage?.inputTokens.total, 3);
      expect(controller.lastUsage?.outputTokens.total, 5);
      controller.dispose();
    });

    test('still finishes when usage futures fail', () async {
      final agent = RecordingStreamAgent();
      final controller = CompletionController(agent: agent);

      unawaited(controller.complete('go'));
      await pumpUntil(() => agent.invocations.length == 1);
      await pumpUntil(() => controller.isStreaming);
      final invocation = agent.invocations.single;

      invocation.emitText('done');
      invocation.failUsage(StateError('usage failed'));
      await invocation.finish(finalText: 'done');
      await pumpUntil(() => !controller.isLoading && !controller.isStreaming);

      expect(controller.completion, 'done');
      expect(controller.error, isNull);
      expect(controller.lastUsage, isNull);
      controller.dispose();
    });

    test(
      'forwards full-stream subscription errors to controller error state',
      () async {
        final agent = RecordingStreamAgent();
        final controller = CompletionController(agent: agent);

        unawaited(controller.complete('go'));
        await pumpUntil(() => agent.invocations.length == 1);
        await pumpUntil(() => controller.isStreaming);
        final invocation = agent.invocations.single;

        invocation.emitFullStreamFailure(StateError('full stream failed'));
        await pumpUntil(() => controller.error != null);

        expect(controller.error, isA<StateError>());
        expect(controller.isLoading, isFalse);
        expect(controller.isStreaming, isFalse);
        controller.dispose();
      },
    );

    test(
      'forwards addListener/removeListener/hasListeners to the root listenable',
      () {
        final controller = CompletionController(agent: textAgent('x'));
        void listener() {}

        expect(controller.hasListeners, isFalse);
        controller.addListener(listener);
        expect(controller.hasListeners, isTrue);
        controller.removeListener(listener);
        expect(controller.hasListeners, isFalse);
        controller.dispose();
      },
    );

    test('a second complete supersedes the active request and ignores stale '
        'events from the first request', () async {
      final agent = RecordingStreamAgent();
      final controller = CompletionController(agent: agent);

      unawaited(controller.complete('first'));
      await pumpUntil(() => agent.invocations.length == 1);
      final first = agent.invocations.first;
      first.emitText('old');
      await pumpUntil(() => controller.completion == 'old');

      unawaited(controller.complete('second'));
      await pumpUntil(() => agent.invocations.length == 2);
      final second = agent.invocations.last;

      expect(first.abortSignal, isNotNull);
      expect(first.abortSignal!.isCancelled, isTrue);
      expect(first.textSubscriptionCancelled, isTrue);
      expect(first.fullStreamSubscriptionCancelled, isTrue);

      second.emitText('new');
      await second.finish(finalText: 'new');
      await pumpUntil(
        () => !controller.isLoading && controller.completion == 'new',
      );

      first.emitText(' stale');
      first.emitError(StateError('stale'));
      await first.finish(finalText: 'old stale');
      await Future<void>.delayed(Duration.zero);

      expect(controller.completion, 'new');
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('clear cancels the active request and ignores late events', () async {
      final agent = RecordingStreamAgent();
      final controller = CompletionController(agent: agent);

      unawaited(controller.complete('go'));
      await pumpUntil(() => agent.invocations.length == 1);
      final invocation = agent.invocations.single;
      invocation.emitText('partial');
      await pumpUntil(() => controller.completion == 'partial');

      controller.clear();

      expect(invocation.abortSignal, isNotNull);
      expect(invocation.abortSignal!.isCancelled, isTrue);
      expect(invocation.textSubscriptionCancelled, isTrue);
      expect(invocation.fullStreamSubscriptionCancelled, isTrue);
      expect(controller.completion, isEmpty);
      expect(controller.error, isNull);

      invocation.emitText(' late');
      invocation.emitError(StateError('late'));
      await invocation.finish(finalText: 'late');
      await Future<void>.delayed(Duration.zero);

      expect(controller.completion, isEmpty);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('streaming deltas coalesce per frame and terminal completion flushes '
        'without duplicate notifications', () async {
      final scheduler = FakeFrameNotificationScheduler();
      final agent = RecordingStreamAgent();
      final controller = CompletionController(
        agent: agent,
        notificationScheduler: scheduler,
      );
      var rootNotifications = 0;
      var statusNotifications = 0;
      var contentNotifications = 0;
      controller.addListener(() {
        rootNotifications++;
      });
      controller.statusListenable.addListener(() {
        statusNotifications++;
      });
      controller.contentListenable.addListener(() {
        contentNotifications++;
      });

      unawaited(controller.complete('go'));
      await pumpUntil(() => agent.invocations.length == 1);
      await pumpUntil(() => controller.isStreaming);
      final invocation = agent.invocations.single;

      rootNotifications = 0;
      statusNotifications = 0;
      contentNotifications = 0;

      invocation.emitText('a');
      invocation.emitText('b');
      invocation.emitText('c');
      await pumpUntil(() => controller.completion == 'abc');

      expect(controller.completion, 'abc');
      expect(rootNotifications, 0);
      expect(statusNotifications, 0);
      expect(contentNotifications, 0);
      expect(scheduler.pendingCallbackCount, 2);

      scheduler.flush();

      expect(rootNotifications, 1);
      expect(statusNotifications, 0);
      expect(contentNotifications, 1);

      invocation.emitText('d');
      await pumpUntil(() => controller.completion == 'abcd');
      await invocation.finish(finalText: 'abcd');
      await pumpUntil(() => !controller.isLoading && !controller.isStreaming);

      expect(controller.completion, 'abcd');
      expect(rootNotifications, 2);
      expect(statusNotifications, 1);
      expect(contentNotifications, 2);
      expect(scheduler.pendingCallbackCount, 0);
      controller.dispose();
    });

    test('dispose cancels a queued frame notification', () async {
      final scheduler = FakeFrameNotificationScheduler();
      final agent = RecordingStreamAgent();
      final controller = CompletionController(
        agent: agent,
        notificationScheduler: scheduler,
      );
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });

      unawaited(controller.complete('go'));
      await pumpUntil(() => agent.invocations.length == 1);
      await pumpUntil(() => controller.isStreaming);
      final invocation = agent.invocations.single;

      notifications = 0;
      invocation.emitText('partial');
      await pumpUntil(() => controller.completion == 'partial');
      expect(controller.completion, 'partial');
      expect(scheduler.pendingCallbackCount, 2);

      controller.dispose();
      scheduler.flush();

      expect(notifications, 0);
    });

    test(
      'stop flushes queued content immediately without a next-frame duplicate',
      () async {
        final scheduler = FakeFrameNotificationScheduler();
        final agent = RecordingStreamAgent();
        final controller = CompletionController(
          agent: agent,
          notificationScheduler: scheduler,
        );
        final events = <String>[];
        controller.addListener(() => events.add('root'));
        controller.statusListenable.addListener(() => events.add('status'));
        controller.contentListenable.addListener(() => events.add('content'));

        unawaited(controller.complete('go'));
        await pumpUntil(() => agent.invocations.length == 1);
        await pumpUntil(() => controller.isStreaming);
        final invocation = agent.invocations.single;

        events.clear();
        invocation.emitText('queued');
        await pumpUntil(() => controller.completion == 'queued');
        expect(scheduler.pendingCallbackCount, 2);

        await controller.stop();

        expect(events, ['root', 'status', 'content']);
        expect(scheduler.pendingCallbackCount, 0);

        scheduler.flush();

        expect(events, ['root', 'status', 'content']);
        controller.dispose();
      },
    );

    test('stream error flushes queued content immediately without a next-frame '
        'duplicate', () async {
      final scheduler = FakeFrameNotificationScheduler();
      final agent = RecordingStreamAgent();
      final controller = CompletionController(
        agent: agent,
        notificationScheduler: scheduler,
      );
      final events = <String>[];
      controller.addListener(() => events.add('root'));
      controller.statusListenable.addListener(() => events.add('status'));
      controller.contentListenable.addListener(() => events.add('content'));

      unawaited(controller.complete('go'));
      await pumpUntil(() => agent.invocations.length == 1);
      await pumpUntil(() => controller.isStreaming);
      final invocation = agent.invocations.single;

      events.clear();
      invocation.emitText('queued');
      await pumpUntil(() => controller.completion == 'queued');
      expect(scheduler.pendingCallbackCount, 2);

      invocation.emitError(StateError('boom'));
      await pumpUntil(() => controller.error != null);

      expect(events, ['root', 'status', 'content']);
      expect(scheduler.pendingCallbackCount, 0);

      scheduler.flush();

      expect(events, ['root', 'status', 'content']);
      controller.dispose();
    });
  });
}
