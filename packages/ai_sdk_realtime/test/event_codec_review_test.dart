import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

void main() {
  test('decodes transcript usage variants and malformed optional details', () {
    final tokens =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.completed',
              'transcript': 'recognized',
              'usage': {
                'type': 'tokens',
                'input_tokens': 4,
                'output_tokens': 2,
                'total_tokens': 6,
                'input_token_details': {'audio_tokens': 4},
              },
            })
            as RealtimeTranscriptCompleted;
    expect(tokens.transcript, 'recognized');
    expect(tokens.usage, isA<RealtimeTranscriptTokenUsage>());
    final tokenUsage = tokens.usage! as RealtimeTranscriptTokenUsage;
    expect(tokenUsage.totalTokens, 6);
    expect(tokenUsage.inputTokenDetails, {'audio_tokens': 4});

    final duration =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.completed',
              'usage': {'type': 'duration', 'seconds': 1.5},
            })
            as RealtimeTranscriptCompleted;
    expect((duration.usage as RealtimeTranscriptDurationUsage).seconds, 1.5);
    final future =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.completed',
              'usage': {'type': 'future', 'units': 3},
            })
            as RealtimeTranscriptCompleted;
    expect((future.usage as RealtimeTranscriptUnknownUsage).raw, {
      'type': 'future',
      'units': 3,
    });
    expect(
      (RealtimeEvent.fromJson({
                'type': 'conversation.item.input_audio_transcription.delta',
                'logprobs': [1],
              })
              as RealtimeTranscriptDelta)
          .logprobs,
      isNull,
    );
  });

  test(
    'decodes nested response usage and keeps malformed envelopes opaque',
    () {
      final done =
          RealtimeEvent.fromJson({
                'type': 'response.done',
                'response': {
                  'id': 'r1',
                  'status': 'completed',
                  'usage': {
                    'input_tokens': 8,
                    'output_tokens': 3,
                    'total_tokens': 11,
                    'input_token_details': {
                      'audio_tokens': 5,
                      'cached_tokens_details': {'text_tokens': 2},
                    },
                    'output_token_details': {'audio_tokens': 3},
                  },
                },
              })
              as RealtimeResponseDone;
      expect(done.responseId, 'r1');
      expect(done.status, 'completed');
      expect(done.usage?.inputTokenDetails?.audioTokens, 5);
      expect(done.usage?.inputTokenDetails?.cachedTokensDetails?.textTokens, 2);
      expect(done.usage?.outputTokenDetails?.audioTokens, 3);

      final providerError =
          RealtimeEvent.fromJson({
                'type': 'error',
                'error': {'message': 'rejected'},
              })
              as RealtimeProviderError;
      expect(providerError.message, 'rejected');
      expect(
        (RealtimeEvent.fromJson({'type': 'error'}) as RealtimeProviderError)
            .message,
        'Realtime provider error',
      );

      final unknown =
          RealtimeEvent.fromJson({
                'type': 'future.event',
                'nested': {'kept': true},
              })
              as RealtimeUnknownEvent;
      expect(unknown.raw['nested'], {'kept': true});
      expect(
        () => RealtimeEvent.fromJson({'type': ''}),
        throwsA(isA<RealtimeException>()),
      );
    },
  );

  test('sends public session operations and closes the transport', () async {
    final transport = _CodecTransport();
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

    await session.sendText('hello');
    await session.sendAudio(Uint8List.fromList([1, 2]));
    await session.commitAudio(createResponseEvent: false);
    await session.commitAudio();
    await session.clearAudio();
    await session.createResponse();
    await session.cancelResponse();
    await session.submitToolResult('call-1', {'ok': true});
    await session.interrupt(itemId: 'item-1', contentIndex: 0, audioEndMs: 12);

    final messages = transport.sent.map(jsonDecode).toList();
    expect(messages.map((message) => message['type']), [
      'session.update',
      'conversation.item.create',
      'input_audio_buffer.append',
      'input_audio_buffer.commit',
      'input_audio_buffer.commit',
      'response.create',
      'input_audio_buffer.clear',
      'response.create',
      'response.cancel',
      'conversation.item.create',
      'response.cancel',
      'conversation.item.truncate',
    ]);
    expect(messages[9]['item']['output'], '{"ok":true}');
    await session.close();
    expect(transport.closeCount, 1);
    await expectLater(
      session.sendText('closed'),
      throwsA(isA<RealtimeException>()),
    );
  });

  test('rejects zero-sized session limits before opening transport', () async {
    Future<void> check({
      int audio = 4 * 1024 * 1024,
      int frame = 1024 * 1024,
      int eventBytes = 4 * 1024 * 1024,
      int eventCount = 256,
      int toolCalls = 8192,
      int cancelledResponses = 8192,
    }) => expectLater(
      RealtimeSession.connect(
        apiKey: 'test',
        endpoint: Uri.parse('ws://test/realtime'),
        connector: (_, _) async => _CodecTransport(),
        maxBufferedAudioBytes: audio,
        maxFrameBytes: frame,
        maxBufferedEventBytes: eventBytes,
        maxBufferedEventCount: eventCount,
        maxRememberedToolCalls: toolCalls,
        maxRememberedCancelledResponses: cancelledResponses,
      ),
      throwsArgumentError,
    );

    await check(audio: 0);
    await check(frame: 0);
    await check(eventBytes: 0);
    await check(eventCount: 0);
    await check(toolCalls: 0);
    await check(cancelledResponses: 0);
  });

  test('keeps malformed frames observable and future events opaque', () async {
    final transport = _CodecTransport();
    final pending = RealtimeSession.connect(
      apiKey: 'test',
      endpoint: Uri.parse('ws://test/realtime'),
      maxBufferedAudioBytes: 16,
      connector: (_, _) async => transport,
    );
    transport.add({
      'type': 'session.created',
      'session': {'id': 's1'},
    });
    final session = await pending;
    final events = <RealtimeEvent>[];
    final errors = <Object>[];
    final subscription = session.events.listen(events.add, onError: errors.add);

    transport.addRaw('{');
    transport.addRaw('[]');
    transport.add({'type': 'provider.future.event', 'payload': 'café 東京 😀'});
    for (final encoded in ['0123', '++++', '////', 'AQ']) {
      transport.add({'type': 'response.output_audio.delta', 'delta': encoded});
    }
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(2));
    expect(
      events.whereType<RealtimeUnknownEvent>().single.raw['payload'],
      'café 東京 😀',
    );
    expect(
      events.whereType<RealtimeAudioDelta>().map((event) => event.audio.length),
      [3, 3, 3, 1],
    );
    await session.acknowledgeAudio(10);
    await subscription.cancel();
    await session.close();
  });
}

class _CodecTransport implements RealtimeTransport {
  final incomingController = StreamController<Object?>();
  final sent = <String>[];
  var closeCount = 0;

  @override
  Stream<Object?> get incoming => incomingController.stream;

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

  void add(Map<String, dynamic> event) => addRaw(jsonEncode(event));

  void addRaw(Object? value) => incomingController.add(value);

  @override
  Future<void> close([int? code, String? reason]) async {
    closeCount++;
    await incomingController.close();
  }
}
