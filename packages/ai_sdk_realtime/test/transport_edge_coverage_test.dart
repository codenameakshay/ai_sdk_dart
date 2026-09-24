import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

void main() {
  test('covers optional event payloads and malformed map fields', () {
    final text =
        RealtimeEvent.fromJson({'type': 'response.output_text.delta'})
            as RealtimeTextDelta;
    expect(text.itemId, isNull);
    final input =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.delta',
              'logprobs': 'invalid',
            })
            as RealtimeTranscriptDelta;
    expect(input.logprobs, isNull);
    final failed =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.failed',
              'error': 'invalid',
            })
            as RealtimeTranscriptFailed;
    expect(failed.error, isNull);
    expect(failed.itemId, isNull);
    expect(failed.contentIndex, isNull);
    final output =
        RealtimeEvent.fromJson({
              'type': 'response.output_audio_transcript.delta',
            })
            as RealtimeOutputTranscriptDelta;
    expect(output.delta, isEmpty);
  });

  test(
    'accepts binary JSON frames and surfaces malformed transport frames',
    () async {
      final transport = _Transport();
      final pending = RealtimeSession.connect(
        apiKey: 'fixture',
        endpoint: Uri.parse('ws://fixture/realtime'),
        connector: (_, _) async => transport,
      );
      await transport.listening.future;
      transport.add({
        'type': 'session.created',
        'session': {'id': 's1'},
      });
      final session = await pending;
      final errors = <Object>[];
      final sub = session.events.listen((_) {}, onError: errors.add);
      transport.controller.add(
        Uint8List.fromList(utf8.encode('{"type":"future"}')),
      );
      transport.controller.add(42);
      transport.controller.add('[]');
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(2));
      await sub.cancel();
      await session.close();
    },
  );

  test('transport errors fail a ready session and close it once', () async {
    final transport = _Transport();
    final pending = RealtimeSession.connect(
      apiKey: 'fixture',
      endpoint: Uri.parse('ws://fixture/realtime'),
      connector: (_, _) async => transport,
    );
    await transport.listening.future;
    transport.add({
      'type': 'session.created',
      'session': {'id': 's1'},
    });
    final session = await pending;
    final errors = <Object>[];
    final sub = session.events.listen((_) {}, onError: errors.add);
    transport.controller.addError(StateError('transport failed'));
    await Future<void>.delayed(Duration.zero);
    expect(session.state, RealtimeConnectionState.closed);
    expect(errors, contains(isA<StateError>()));
    expect(transport.closeCount, 1);
    await sub.cancel();
  });

  test('connector errors and provider startup errors are propagated', () async {
    await expectLater(
      RealtimeSession.connect(
        apiKey: 'fixture',
        endpoint: Uri.parse('ws://fixture/realtime'),
        connector: (_, _) async => throw StateError('connect failed'),
      ),
      throwsA(isA<StateError>()),
    );

    final transport = _Transport();
    final pending = RealtimeSession.connect(
      apiKey: 'fixture',
      endpoint: Uri.parse('ws://fixture/realtime'),
      connector: (_, _) async => transport,
    );
    await transport.listening.future;
    transport.add({
      'type': 'error',
      'error': {'message': 'rejected'},
    });
    await expectLater(pending, throwsA(isA<RealtimeException>()));
    expect(transport.closeCount, 1);
  });

  test('validates acknowledged audio and interruption indexes', () async {
    final transport = _Transport();
    final pending = RealtimeSession.connect(
      apiKey: 'fixture',
      endpoint: Uri.parse('ws://fixture/realtime'),
      connector: (_, _) async => transport,
    );
    await transport.listening.future;
    transport.add({
      'type': 'session.created',
      'session': {'id': 's1'},
    });
    final session = await pending;
    await expectLater(session.acknowledgeAudio(1), throwsArgumentError);
    await expectLater(
      session.interrupt(itemId: 'item', contentIndex: -1, audioEndMs: 0),
      throwsArgumentError,
    );
    await session.close();
  });

  test('abort after readiness closes the transport once', () async {
    final transport = _Transport();
    final signal = _Signal();
    final pending = RealtimeSession.connect(
      apiKey: 'fixture',
      endpoint: Uri.parse('ws://fixture/realtime'),
      abortSignal: signal,
      connector: (_, _) async => transport,
    );
    await transport.listening.future;
    transport.add({
      'type': 'session.created',
      'session': {'id': 's1'},
    });
    final session = await pending;
    signal.cancel();
    await transport.closed.future;
    await session.close();
    expect(session.state, RealtimeConnectionState.closed);
    expect(transport.closeCount, 1);
  });
}

class _Signal implements AbortSignal {
  final cancelled = Completer<void>();

  @override
  bool get isCancelled => cancelled.isCompleted;

  @override
  Future<void> get onCancelled => cancelled.future;

  void cancel() => cancelled.complete();
}

class _Transport implements RealtimeTransport {
  final listening = Completer<void>();
  final closed = Completer<void>();
  late final controller = StreamController<Object?>.broadcast(
    sync: true,
    onListen: listening.complete,
  );
  final sent = <String>[];
  int closeCount = 0;

  @override
  Stream<Object?> get incoming => controller.stream;

  @override
  Future<void> send(String text) async {
    sent.add(text);
    if (jsonDecode(text)['type'] == 'session.update') {
      add({
        'type': 'session.updated',
        'session': {'id': 's1'},
      });
    }
  }

  void add(Map<String, dynamic> event) => controller.add(jsonEncode(event));

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount++;
    await controller.close();
    if (!closed.isCompleted) closed.complete();
  }
}
