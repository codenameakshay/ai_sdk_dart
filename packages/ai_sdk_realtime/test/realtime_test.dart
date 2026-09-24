import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

void main() {
  test('rejects invalid GA session controls before sending them', () {
    expect(
      () => const RealtimeFunctionTool(name: '', parameters: {}).toJson(),
      throwsArgumentError,
    );
    expect(
      () => const RealtimeFunctionTool(
        name: 'lookup',
        parameters: {'type': 'array'},
      ).toJson(),
      throwsArgumentError,
    );
    for (final config in [
      const RealtimeServerVad(idleTimeoutMs: -1),
      const RealtimeServerVad(prefixPaddingMs: -1),
      const RealtimeServerVad(silenceDurationMs: -1),
      const RealtimeServerVad(threshold: -0.1),
      const RealtimeServerVad(threshold: 1.1),
    ]) {
      expect(config.toJson, throwsArgumentError);
    }
    expect(
      () => const RealtimeSemanticVad(eagerness: 'immediate').toJson(),
      throwsArgumentError,
    );
    expect(const RealtimeAudioFormat(type: 'audio/pcmu').toJson(), {
      'type': 'audio/pcmu',
    });
  });

  test(
    'types transcript and speech events and keeps unknown events opaque',
    () {
      expect(
        () => RealtimeEvent.fromJson({}),
        throwsA(isA<RealtimeException>()),
      );
      final delta =
          RealtimeEvent.fromJson({
                'type': 'conversation.item.input_audio_transcription.delta',
                'delta': 'hello',
                'item_id': 'item-1',
                'content_index': 2,
                'logprobs': [
                  {'token': 'hello'},
                ],
              })
              as RealtimeTranscriptDelta;
      expect(delta.delta, 'hello');
      expect(delta.itemId, 'item-1');
      expect(delta.contentIndex, 2);
      expect(delta.logprobs, [
        {'token': 'hello'},
      ]);
      final failed =
          RealtimeEvent.fromJson({
                'type': 'conversation.item.input_audio_transcription.failed',
                'error': {'code': 'bad_audio'},
              })
              as RealtimeTranscriptFailed;
      expect(failed.error, {'code': 'bad_audio'});
      final spoken =
          RealtimeEvent.fromJson({
                'type': 'response.output_audio_transcript.done',
                'transcript': 'hello back',
                'response_id': 'response-1',
              })
              as RealtimeOutputTranscriptDone;
      expect(spoken.transcript, 'hello back');
      expect(spoken.responseId, 'response-1');
      expect(
        RealtimeEvent.fromJson({'type': 'input_audio_buffer.speech_started'}),
        isA<RealtimeSpeechEvent>(),
      );
      final unknown = RealtimeEvent.fromJson({
        'type': 'future.event',
        'provider': {'opaque': true},
      });
      expect(unknown, isA<RealtimeUnknownEvent>());
      expect(unknown.raw['provider'], {'opaque': true});
    },
  );

  test('serializes typed GA session tools and turn detection', () {
    const config = RealtimeSessionConfig(
      outputModalities: ['audio', 'text'],
      turnDetection: RealtimeServerVad(
        createResponse: true,
        interruptResponse: true,
        silenceDurationMs: 500,
        threshold: 0.5,
      ),
      tools: [
        RealtimeFunctionTool(
          name: 'lookup',
          description: 'Look up a value.',
          parameters: {'type': 'object', 'properties': {}},
        ),
      ],
    );
    expect(config.toJson(), {
      'type': 'realtime',
      'output_modalities': ['audio', 'text'],
      'audio': {
        'input': {
          'format': {'type': 'audio/pcm', 'rate': 24000},
          'turn_detection': {
            'type': 'server_vad',
            'create_response': true,
            'interrupt_response': true,
            'silence_duration_ms': 500,
            'threshold': 0.5,
          },
        },
        'output': {
          'format': {'type': 'audio/pcm', 'rate': 24000},
        },
      },
      'tools': [
        {
          'type': 'function',
          'name': 'lookup',
          'description': 'Look up a value.',
          'parameters': {'type': 'object', 'properties': {}},
        },
      ],
    });
  });

  test('parses completed transcript and response usage variants', () {
    final transcript =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.completed',
              'item_id': 'item-1',
              'content_index': 0,
              'transcript': 'hello',
              'usage': {
                'type': 'tokens',
                'input_tokens': 4,
                'output_tokens': 2,
                'total_tokens': 6,
                'input_token_details': {'audio_tokens': 4},
              },
            })
            as RealtimeTranscriptCompleted;
    expect(transcript.transcript, 'hello');
    expect(transcript.usage, isA<RealtimeTranscriptTokenUsage>());
    expect((transcript.usage! as RealtimeTranscriptTokenUsage).inputTokens, 4);

    final done =
        RealtimeEvent.fromJson({
              'type': 'response.done',
              'response': {
                'id': 'response-1',
                'usage': {
                  'input_tokens': 10,
                  'output_tokens': 5,
                  'total_tokens': 15,
                  'input_token_details': {
                    'cached_tokens': 3,
                    'cached_tokens_details': {'text_tokens': 3},
                  },
                  'output_token_details': {'audio_tokens': 5},
                },
              },
            })
            as RealtimeResponseDone;
    expect(done.usage?.totalTokens, 15);
    expect(done.usage?.inputTokenDetails?.cachedTokens, 3);
    expect(done.usage?.outputTokenDetails?.audioTokens, 5);
  });

  test('bounded identity history refuses unsafe eviction', () async {
    final transport = _FakeTransport();
    final sessionFuture = RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse('ws://test/realtime'),
      maxRememberedToolCalls: 1,
      maxRememberedCancelledResponses: 1,
      connector: (_, _) async => transport,
    );
    transport.add({
      'type': 'session.created',
      'session': {'id': 's1'},
    });
    final session = await sessionFuture;
    final events = <RealtimeEvent>[];
    final errors = <Object>[];
    final sub = session.events.listen(events.add, onError: errors.add);
    transport.add({
      'type': 'response.function_call_arguments.done',
      'call_id': 'c1',
      'name': 'f',
      'arguments': '{}',
    });
    transport.add({
      'type': 'response.function_call_arguments.done',
      'call_id': 'c2',
      'name': 'f',
      'arguments': '{}',
    });
    transport.add({
      'type': 'response.function_call_arguments.done',
      'call_id': 'c1',
      'name': 'f',
      'arguments': '{}',
    });
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<RealtimeToolCall>().map((call) => call.callId), [
      'c1',
    ]);
    expect(errors, isNotEmpty);
    await session.cancelResponse(responseId: 'r1');
    await expectLater(
      session.cancelResponse(responseId: 'r2'),
      throwsA(isA<RealtimeException>()),
    );
    expect(transport.sent.where((item) => item.contains('r2')), isEmpty);
    await sub.cancel();
    await session.close();
  });

  test('cancel and interrupt target the requested response ID', () async {
    final transport = _FakeTransport();
    final pending = RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse('ws://test/realtime'),
      connector: (_, _) async => transport,
    );
    transport.add({
      'type': 'session.created',
      'session': {'id': 's1'},
    });
    final session = await pending;
    addTearDown(session.close);
    await session.cancelResponse(responseId: 'response-secondary');
    expect(jsonDecode(transport.sent.last), {
      'type': 'response.cancel',
      'response_id': 'response-secondary',
    });
    await session.interrupt(
      itemId: 'item-secondary',
      contentIndex: 0,
      audioEndMs: 100,
      responseId: 'response-secondary',
    );
    expect(jsonDecode(transport.sent[transport.sent.length - 2]), {
      'type': 'response.cancel',
      'response_id': 'response-secondary',
    });
    expect(jsonDecode(transport.sent.last), {
      'type': 'conversation.item.truncate',
      'item_id': 'item-secondary',
      'content_index': 0,
      'audio_end_ms': 100,
    });
    await session.cancelResponse();
    expect(jsonDecode(transport.sent.last), {'type': 'response.cancel'});
  });

  test(
    'waits for session.created, configures, and deduplicates tool calls',
    () async {
      final transport = _FakeTransport();
      final sessionFuture = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        connector: (_, _) async => transport,
      );
      transport.add({
        'type': 'session.created',
        'session': {'id': 's1'},
      });
      final session = await sessionFuture;
      expect(session.state, RealtimeConnectionState.ready);
      expect(jsonDecode(transport.sent.single)['type'], 'session.update');
      final events = <RealtimeEvent>[];
      final sub = session.events.listen(events.add);
      transport.add({
        'type': 'response.function_call_arguments.done',
        'call_id': 'c1',
        'name': 'f',
        'arguments': '{}',
      });
      transport.add({
        'type': 'response.function_call_arguments.done',
        'call_id': 'c1',
        'name': 'f',
        'arguments': '{}',
      });
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<RealtimeToolCall>(), hasLength(1));
      await sub.cancel();
      await session.close();
    },
  );

  test('bounds decoded audio and validates interruption duration', () async {
    final transport = _FakeTransport();
    final future = RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse('ws://test/realtime'),
      maxBufferedAudioBytes: 1,
      connector: (_, _) async => transport,
    );
    transport.add({'type': 'session.created'});
    final session = await future;
    final sub = session.events.listen(
      (_) {},
      onError: expectAsync1((error) {
        expect(error, isA<RealtimeException>());
      }),
    );
    transport.add({
      'type': 'response.output_audio.delta',
      'delta': base64.encode([1, 2]),
    });
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      session.interrupt(itemId: 'i', contentIndex: 0, audioEndMs: -1),
      throwsArgumentError,
    );
    await sub.cancel();
    await session.close();
  });

  test(
    'requires session ids and post-configuration matching updates',
    () async {
      final missingIdTransport = _ControlledTransport(autoUpdate: false);
      final missingId = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        timeout: const Duration(milliseconds: 40),
        connector: (_, _) async => missingIdTransport,
      );
      missingIdTransport.addRaw({'type': 'session.created'});
      await expectLater(missingId, throwsA(isA<RealtimeException>()));

      final earlyUpdateTransport = _ControlledTransport(autoUpdate: false);
      final earlyUpdate = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        timeout: const Duration(milliseconds: 40),
        connector: (_, _) async => earlyUpdateTransport,
      );
      earlyUpdateTransport.addRaw({
        'type': 'session.created',
        'session': {'id': 's1'},
      });
      earlyUpdateTransport.addRaw({
        'type': 'session.updated',
        'session': {'id': 's1'},
      });
      await expectLater(earlyUpdate, throwsA(isA<RealtimeException>()));
    },
  );

  test('matching update wins after a mismatched update', () async {
    late _ControlledTransport transport;
    transport = _ControlledTransport(
      autoUpdate: false,
      onSend: (_) {
        transport.addRaw({
          'type': 'session.updated',
          'session': {'id': 'wrong'},
        });
        transport.addRaw({
          'type': 'session.updated',
          'session': {'id': 's1'},
        });
      },
    );
    final pending = RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse('ws://test/realtime'),
      connector: (_, _) async => transport,
    );
    transport.addRaw({
      'type': 'session.created',
      'session': {'id': 's1'},
    });
    final session = await pending;
    expect(session.state, RealtimeConnectionState.ready);
    await session.close();
  });

  test('speaks the Realtime handshake over a real loopback WebSocket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final configured = Completer<void>();
    String? legacyBetaHeader;
    server.listen((request) async {
      legacyBetaHeader = request.headers.value('openai-beta');
      if (request.headers.value('authorization') != 'Bearer test' ||
          request.uri.queryParameters['model'] != 'gpt-realtime-2.1') {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(
        jsonEncode({
          'type': 'session.created',
          'session': {'id': 'loopback'},
        }),
      );
      socket.listen((value) {
        if (jsonDecode(value as String)['type'] == 'session.update' &&
            !configured.isCompleted) {
          configured.complete();
          socket.add(
            jsonEncode({
              'type': 'session.updated',
              'session': {'id': 'loopback'},
            }),
          );
        }
      });
    });
    final session = await RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse(
        'ws://${server.address.host}:${server.port}?model=gpt-realtime-2.1',
      ),
    );
    await configured.future.timeout(const Duration(seconds: 1));
    expect(session.state, RealtimeConnectionState.ready);
    await session.close();
    expect(
      legacyBetaHeader,
      isNull,
      reason:
          'Current GA wire configuration must not select the legacy beta protocol',
    );
  });

  test(
    'validates response identities and discards late cancelled output',
    () async {
      final transport = _FakeTransport();
      final future = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        connector: (_, _) async => transport,
      );
      transport.add({'type': 'session.created'});
      final session = await future;
      final seen = <RealtimeEvent>[];
      final sub = session.events.listen(seen.add, onError: (_) {});
      await session.interrupt(
        itemId: 'item-1',
        contentIndex: 0,
        audioEndMs: 20,
        responseId: 'r1',
      );
      transport.add({
        'type': 'response.output_text.delta',
        'response_id': 'r1',
        'delta': 'late',
      });
      transport.add({
        'type': 'response.output_text.delta',
        'response_id': 'r2',
        'delta': 'current',
      });
      await Future<void>.delayed(Duration.zero);
      expect(seen.whereType<RealtimeTextDelta>().map((event) => event.delta), [
        'current',
      ]);
      final done = RealtimeEvent.fromJson({
        'type': 'response.done',
        'response': {
          'id': 'r2',
          'status': 'completed',
          'usage': {'total_tokens': 3},
        },
      });
      expect((done as RealtimeResponseDone).responseId, 'r2');
      expect(done.usage?.totalTokens, 3);
      await sub.cancel();
      await session.close();
    },
  );

  test(
    'readiness deadline is total while unknown events keep arriving',
    () async {
      final transport = _ControlledTransport(autoUpdate: false);
      final clock = _ManualClock();
      final pending = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        timeout: const Duration(milliseconds: 40),
        clock: clock,
        connector: (_, _) async => transport,
      );
      Object? failure;
      final outcome = pending.then<void>(
        (_) => fail('startup unexpectedly succeeded'),
        onError: (Object error, StackTrace stack) {
          failure = error;
        },
      );
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 20; i++) {
        transport.add({'type': 'provider.future.event'});
      }
      await Future<void>.delayed(Duration.zero);
      clock.elapsed = const Duration(milliseconds: 40);
      await _fireTimeout(clock);
      await outcome;
      expect(failure, isA<RealtimeException>());
      expect(transport.closeCount, 1);
    },
  );

  test(
    'a hanging configuration send is covered by the startup deadline',
    () async {
      final transport = _ControlledTransport(autoUpdate: false, hangSend: true);
      final clock = _ManualClock();
      final pending = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        timeout: const Duration(milliseconds: 40),
        clock: clock,
        connector: (_, _) async => transport,
      );
      Object? failure;
      final outcome = pending.then<void>(
        (_) => fail('startup unexpectedly succeeded'),
        onError: (Object error, StackTrace stack) {
          failure = error;
        },
      );
      transport.add({'type': 'session.created'});
      await Future<void>.delayed(Duration.zero);
      clock.elapsed = const Duration(milliseconds: 40);
      await _fireTimeout(clock);
      await outcome;
      expect(failure, isA<RealtimeException>());
      expect(transport.sent, hasLength(1));
      expect(transport.closeCount, 1);
    },
  );

  test('close has one bounded shared cleanup future', () async {
    final transport = _ControlledTransport(hangClose: true);
    final clock = _ManualClock();
    final future = RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse('ws://test/realtime'),
      clock: clock,
      connector: (_, _) async => transport,
    );
    transport.add({'type': 'session.created'});
    final session = await future;
    final first = session.close(timeout: const Duration(milliseconds: 20));
    final second = session.close(timeout: const Duration(seconds: 1));
    expect(identical(first, second), isTrue);
    Object? failure;
    final outcome = first.then<void>(
      (_) => fail('close unexpectedly succeeded'),
      onError: (Object error, StackTrace stack) {
        failure = error;
      },
    );
    clock.elapsed = const Duration(milliseconds: 20);
    await _fireTimeout(clock);
    await outcome;
    expect(failure, isA<RealtimeException>());
    expect(session.state, RealtimeConnectionState.closed);
    expect(transport.closeCount, 1);
  });

  test(
    'close preserves a cleanup failure observed before its deadline',
    () async {
      final transport = _ControlledTransport(hangClose: true, failCancel: true);
      final future = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        connector: (_, _) async => transport,
      );
      transport.add({'type': 'session.created'});
      final session = await future;
      await expectLater(
        session.close(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'paused listeners receive a bounded queue and missing listeners drop audio',
    () async {
      final transport = _FakeTransport();
      final future = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        maxBufferedAudioBytes: 1,
        maxBufferedEventBytes: 100,
        maxBufferedEventCount: 2,
        connector: (_, _) async => transport,
      );
      transport.add({'type': 'session.created'});
      final session = await future;
      transport.add({
        'type': 'response.output_audio.delta',
        'delta': base64.encode([1, 2]),
      });
      final errors = <Object>[];
      final sub = session.events.listen((_) {}, onError: errors.add);
      for (var i = 0; i < 10; i++) {
        transport.add({
          'type': 'response.output_audio.delta',
          'delta': base64.encode([1, 2]),
        });
      }
      final seen = <RealtimeEvent>[];
      final paused = session.events.listen(seen.add, onError: (_) {});
      paused.pause();
      for (var i = 0; i < 10; i++) {
        transport.add({'type': 'response.output_text.delta', 'delta': '$i'});
      }
      await Future<void>.delayed(Duration.zero);
      paused.resume();
      await Future<void>.delayed(Duration.zero);
      expect(seen, hasLength(lessThanOrEqualTo(2)));
      expect(errors, hasLength(1));
      await sub.cancel();
      await paused.cancel();
      await session.close();
    },
  );

  test(
    'canceling a paused audio subscriber releases its queued budget',
    () async {
      final transport = _FakeTransport();
      final pending = RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        maxBufferedAudioBytes: 2,
        connector: (_, _) async => transport,
      );
      transport.add({'type': 'session.created'});
      final session = await pending;
      final paused = session.events.listen((_) {}, onError: (_) {});
      paused.pause();
      transport.add({
        'type': 'response.output_audio.delta',
        'delta': base64.encode([1, 2]),
      });
      await Future<void>.delayed(Duration.zero);
      await paused.cancel();

      var audioEvents = 0;
      final errors = <Object>[];
      final active = session.events.listen((event) {
        if (event is RealtimeAudioDelta) audioEvents++;
      }, onError: errors.add);
      transport.add({
        'type': 'response.output_audio.delta',
        'delta': base64.encode([3, 4]),
      });
      await Future<void>.delayed(Duration.zero);
      expect(audioEvents, 1);
      expect(errors, isEmpty);
      await session.acknowledgeAudio(2);
      await active.cancel();
      await session.close();
    },
  );

  test('loopback peer close completes the event stream once', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(
        jsonEncode({
          'type': 'session.created',
          'session': {'id': 'loopback-peer'},
        }),
      );
      socket.listen((value) {
        if (jsonDecode(value as String)['type'] == 'session.update') {
          socket.add(
            jsonEncode({
              'type': 'session.updated',
              'session': {'id': 'loopback-peer'},
            }),
          );
          unawaited(socket.close());
        }
      });
    });
    final session = await RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse(
        'ws://${server.address.host}:${server.port}?model=gpt-realtime-2.1',
      ),
    );
    final done = Completer<void>();
    final sub = session.events.listen(
      (_) {},
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future.timeout(const Duration(seconds: 1));
    expect(session.state, RealtimeConnectionState.closed);
    await sub.cancel();
  });
}

class _ControlledTransport implements RealtimeTransport {
  _ControlledTransport({
    this.autoUpdate = true,
    this.hangSend = false,
    this.hangClose = false,
    this.onSend,
    bool failCancel = false,
  }) : controller = StreamController<Object?>(
         onCancel: failCancel
             ? () => Future<void>.error(StateError('cancel failed'))
             : null,
       );
  final bool autoUpdate;
  final bool hangSend;
  final bool hangClose;
  final void Function(String text)? onSend;
  final StreamController<Object?> controller;
  final sent = <String>[];
  int closeCount = 0;

  void add(Map<String, dynamic> value) =>
      controller.add(jsonEncode(_withSessionId(value)));
  void addRaw(Map<String, dynamic> value) => controller.add(jsonEncode(value));

  @override
  Stream<Object?> get incoming => controller.stream;

  @override
  Future<void> send(String text) {
    sent.add(text);
    onSend?.call(text);
    if (autoUpdate && jsonDecode(text)['type'] == 'session.update') {
      add({'type': 'session.updated'});
    }
    if (hangSend) return Completer<void>().future;
    return Future<void>.value();
  }

  @override
  Future<void> close([int? code, String? reason]) {
    closeCount++;
    if (hangClose) return Completer<void>().future;
    return controller.close();
  }
}

class _FakeTransport implements RealtimeTransport {
  final controller = StreamController<Object?>();
  final sent = <String>[];
  void add(Map<String, dynamic> value) =>
      controller.add(jsonEncode(_withSessionId(value)));
  @override
  Stream<Object?> get incoming => controller.stream;
  @override
  Future<void> send(String text) async {
    sent.add(text);
    if (jsonDecode(text)['type'] == 'session.update') {
      add({'type': 'session.updated'});
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async => controller.close();
}

Map<String, dynamic> _withSessionId(Map<String, dynamic> value) {
  if (value['type'] == 'session.created' ||
      value['type'] == 'session.updated') {
    return {
      ...value,
      if (value['session'] is! Map) 'session': {'id': 's1'},
    };
  }
  return value;
}

Future<void> _fireTimeout(_ManualClock clock) async {
  clock.fireAll();
  await Future<void>.delayed(Duration.zero);
  clock.fireAll();
  await Future<void>.delayed(Duration.zero);
}

class _ManualClock implements RealtimeClock {
  @override
  Duration elapsed = Duration.zero;
  final timers = <_ManualTimer>[];

  @override
  Timer schedule(Duration duration, void Function() callback) {
    final timer = _ManualTimer(callback);
    timers.add(timer);
    return timer;
  }

  void fireAll() {
    while (true) {
      final active = timers.where((timer) => timer.isActive).toList();
      if (active.isEmpty) return;
      for (final timer in active) {
        timer.fire();
      }
    }
  }
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
