import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_dart/test.dart';
import 'package:ai_sdk_flutter_ui/ai_sdk_flutter_ui.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _ControlledObjectStreamInvocation {
  _ControlledObjectStreamInvocation();

  final String _textId = 'object-text';
  bool _started = false;
  bool _ended = false;
  bool cancelled = false;
  final StreamController<LanguageModelV3StreamPart> _controller =
      StreamController<LanguageModelV3StreamPart>(
        onCancel: () {
          // Mark that streamText cancelled the upstream provider stream.
        },
      );

  Stream<LanguageModelV3StreamPart> get stream {
    _controller.onCancel = () {
      cancelled = true;
    };
    return _controller.stream;
  }

  void emitObject(Map<String, dynamic> value) {
    if (!_started) {
      _started = true;
      _controller.add(StreamPartTextStart(id: _textId));
    }
    _controller.add(StreamPartTextDelta(id: _textId, delta: jsonEncode(value)));
    if (!_ended) {
      _ended = true;
      _controller.add(StreamPartTextEnd(id: _textId));
    }
  }

  void emitError(Object error) {
    _controller.addError(error);
  }

  Future<void> finish() async {
    _controller.add(
      const StreamPartFinish(
        finishReason: LanguageModelV3FinishReason.stop,
        rawFinishReason: 'stop',
      ),
    );
    await _controller.close();
  }
}

class _ControlledObjectModel implements LanguageModelV3 {
  final List<_ControlledObjectStreamInvocation> invocations = [];

  @override
  String get provider => 'mock';

  @override
  String get modelId => 'controlled-object';

  @override
  String get specificationVersion => 'v3';

  @override
  Future<LanguageModelV3GenerateResult> doGenerate(
    LanguageModelV3CallOptions options,
  ) async {
    throw UnimplementedError('submit() only exercises doStream');
  }

  @override
  Future<LanguageModelV3StreamResult> doStream(
    LanguageModelV3CallOptions options,
  ) async {
    final invocation = _ControlledObjectStreamInvocation();
    invocations.add(invocation);
    return LanguageModelV3StreamResult(stream: invocation.stream);
  }
}

void main() {
  group('ObjectStreamController', () {
    test('starts with initial value and idle state', () {
      final controller = ObjectStreamController<Map<String, dynamic>>(
        initialValue: const {'seed': true},
      );
      expect(controller.value, const {'seed': true});
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('bind streams partial values and toggles loading/streaming', () async {
      final controller = ObjectStreamController<int>();
      var sawLoading = false;
      var sawStreaming = false;
      controller.addListener(() {
        if (controller.isLoading) sawLoading = true;
        if (controller.isStreaming) sawStreaming = true;
      });

      await controller.bind(Stream<int>.fromIterable([1, 2, 3]));
      await pumpUntil(() => !controller.isLoading);

      expect(sawLoading, isTrue);
      expect(sawStreaming, isTrue);
      expect(controller.value, 3); // last partial wins
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('bind onFinish fires with the final value', () async {
      int? finished;
      final controller = ObjectStreamController<int>(
        onFinish: (v) => finished = v,
      );
      await controller.bind(Stream<int>.fromIterable([10, 20]));
      await pumpUntil(() => finished != null);
      expect(finished, 20);
      controller.dispose();
    });

    test('bind onError fires and sets error', () async {
      Object? captured;
      final failure = StateError('boom');
      final controller = ObjectStreamController<int>(
        onError: (e) => captured = e,
      );
      await controller.bind(Stream<int>.error(failure));
      await pumpUntil(() => controller.error != null);
      expect(controller.error, same(failure));
      expect(captured, same(failure));
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);
      controller.dispose();
    });

    test('clear / reset wipe value and error', () async {
      final controller = ObjectStreamController<int>();
      await controller.bind(Stream<int>.value(42));
      await pumpUntil(() => controller.value == 42);
      expect(controller.value, 42);

      controller.clear();
      expect(controller.value, isNull);

      await controller.bind(Stream<int>.value(7));
      await pumpUntil(() => controller.value == 7);
      controller.reset();
      expect(controller.value, isNull);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('submit throws StateError when model/schema not provided', () {
      final controller = ObjectStreamController<Map<String, dynamic>>();
      expect(() => controller.submit('hi'), throwsA(isA<StateError>()));
      controller.dispose();
    });

    test(
      'submit runs streamText(output: object) and streams the parsed object',
      () async {
        final controller = ObjectStreamController<Map<String, dynamic>>(
          model: MockLanguageModelV3(response: [mockText('{"title":"Hi"}')]),
          schema: mapSchema,
        );

        await controller.submit('Give me a title');
        await pumpUntil(
          () => !controller.isLoading && controller.value != null,
        );

        expect(controller.value, isNotNull);
        expect(controller.value!['title'], 'Hi');
        expect(controller.isStreaming, isFalse);
        expect(controller.isLoading, isFalse);
        controller.dispose();
      },
    );

    test('stop cancels an in-flight stream and resets flags', () async {
      final controller = ObjectStreamController<int>();
      // A long-lived source so stop() runs while the subscription is active.
      final source = StreamController<int>();
      addTearDown(source.close);

      unawaited(controller.bind(source.stream));
      source.add(1);
      await pumpUntil(() => controller.value == 1);
      expect(controller.isStreaming, isTrue);
      expect(controller.isLoading, isTrue);

      await controller.stop();
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);

      // Further events after stop must not revive the controller (sub cancelled).
      source.add(2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.value, 1);
      controller.dispose();
    });

    test('submit binds via bind() so a later bind still works', () async {
      final controller = ObjectStreamController<Map<String, dynamic>>(
        model: MockLanguageModelV3(response: [mockText('{"title":"A"}')]),
        schema: mapSchema,
      );
      await controller.submit('a');
      await pumpUntil(() => controller.value != null && !controller.isLoading);
      expect(controller.value!['title'], 'A');

      // bind still works independently afterwards.
      await controller.bind(
        Stream<Map<String, dynamic>>.value(const {'title': 'B'}),
      );
      await pumpUntil(() => controller.value?['title'] == 'B');
      expect(controller.value!['title'], 'B');
      controller.dispose();
    });

    test('clear cancels the active bind and ignores late events', () async {
      final source = StreamController<int>();
      addTearDown(source.close);
      final controller = ObjectStreamController<int>();

      unawaited(controller.bind(source.stream));
      source.add(1);
      await pumpUntil(() => controller.value == 1);

      controller.clear();

      expect(controller.value, isNull);
      expect(controller.error, isNull);
      expect(controller.isLoading, isFalse);
      expect(controller.isStreaming, isFalse);

      source.add(2);
      source.addError(StateError('late'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.value, isNull);
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('dispose cancels the active bind and stops notifications', () async {
      final source = StreamController<int>();
      addTearDown(source.close);
      final controller = ObjectStreamController<int>();
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });

      unawaited(controller.bind(source.stream));
      source.add(1);
      await pumpUntil(() => controller.value == 1);
      final beforeDispose = notifications;

      controller.dispose();

      source.add(2);
      source.addError(StateError('late'));
      await Future<void>.delayed(Duration.zero);

      expect(notifications, beforeDispose);
    });

    test('second submit cancels the first upstream stream and ignores stale '
        'first partials, errors, and finish', () async {
      final model = _ControlledObjectModel();
      final controller = ObjectStreamController<Map<String, dynamic>>(
        model: model,
        schema: mapSchema,
      );

      unawaited(controller.submit('first'));
      await pumpUntil(() => model.invocations.length == 1);
      final first = model.invocations.first;

      first.emitObject(const {'title': 'old'});
      await pumpUntil(() => controller.value?['title'] == 'old');
      expect(controller.isStreaming, isTrue);

      unawaited(controller.submit('second'));
      await pumpUntil(() => model.invocations.length == 2);
      await pumpUntil(() => first.cancelled);
      final second = model.invocations.last;

      expect(first.cancelled, isTrue);
      expect(controller.value, isNull);
      expect(controller.error, isNull);

      second.emitObject(const {'title': 'new'});
      await pumpUntil(() => controller.value?['title'] == 'new');

      first.emitObject(const {'title': 'stale'});
      first.emitError(StateError('stale'));
      await first.finish();
      await Future<void>.delayed(Duration.zero);

      expect(controller.value?['title'], 'new');
      expect(controller.error, isNull);
      expect(controller.isLoading, isTrue);

      await second.finish();
      await pumpUntil(() => !controller.isLoading && !controller.isStreaming);

      expect(controller.value?['title'], 'new');
      expect(controller.error, isNull);
      controller.dispose();
    });

    test('content deltas coalesce per frame and completion flushes without '
        'duplicate notifications', () async {
      final scheduler = FakeFrameNotificationScheduler();
      final source = StreamController<int>();
      addTearDown(source.close);
      final controller = ObjectStreamController<int>(
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

      unawaited(controller.bind(source.stream));
      source.add(1);
      await pumpUntil(() => controller.value == 1);

      rootNotifications = 0;
      statusNotifications = 0;
      contentNotifications = 0;

      source.add(2);
      source.add(3);
      await pumpUntil(() => controller.value == 3);

      expect(rootNotifications, 0);
      expect(statusNotifications, 0);
      expect(contentNotifications, 0);
      expect(scheduler.pendingCallbackCount, 2);

      scheduler.flush();

      expect(rootNotifications, 1);
      expect(statusNotifications, 0);
      expect(contentNotifications, 1);

      await source.close();
      await pumpUntil(() => !controller.isLoading && !controller.isStreaming);

      expect(controller.value, 3);
      expect(rootNotifications, 2);
      expect(statusNotifications, 1);
      expect(contentNotifications, 2);
      expect(scheduler.pendingCallbackCount, 0);
      controller.dispose();
    });

    test(
      'stop flushes queued content immediately without a next-frame duplicate',
      () async {
        final scheduler = FakeFrameNotificationScheduler();
        final source = StreamController<int>();
        addTearDown(source.close);
        final controller = ObjectStreamController<int>(
          notificationScheduler: scheduler,
        );
        final events = <String>[];
        controller.addListener(() => events.add('root'));
        controller.statusListenable.addListener(() => events.add('status'));
        controller.contentListenable.addListener(() => events.add('content'));

        unawaited(controller.bind(source.stream));
        source.add(1);
        await pumpUntil(() => controller.value == 1 && controller.isStreaming);

        events.clear();
        source.add(2);
        await pumpUntil(() => controller.value == 2);
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
      final source = StreamController<int>();
      addTearDown(source.close);
      final controller = ObjectStreamController<int>(
        notificationScheduler: scheduler,
      );
      final events = <String>[];
      controller.addListener(() => events.add('root'));
      controller.statusListenable.addListener(() => events.add('status'));
      controller.contentListenable.addListener(() => events.add('content'));

      unawaited(controller.bind(source.stream));
      source.add(1);
      await pumpUntil(() => controller.value == 1 && controller.isStreaming);

      events.clear();
      source.add(2);
      await pumpUntil(() => controller.value == 2);
      expect(scheduler.pendingCallbackCount, 2);

      source.addError(StateError('boom'));
      await pumpUntil(() => controller.error != null);

      expect(events, ['root', 'status', 'content']);
      expect(scheduler.pendingCallbackCount, 0);

      scheduler.flush();

      expect(events, ['root', 'status', 'content']);
      controller.dispose();
    });
  });
}
