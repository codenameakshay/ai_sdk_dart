import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

void main() {
  test('decodes transcript token usage and nested response usage details', () {
    final transcript =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.completed',
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
    final tokenUsage = transcript.usage! as RealtimeTranscriptTokenUsage;
    expect(tokenUsage.totalTokens, 6);
    expect(tokenUsage.inputTokenDetails, {'audio_tokens': 4});

    final done =
        RealtimeEvent.fromJson({
              'type': 'response.done',
              'response': {
                'id': 'response-1',
                'status': 'completed',
                'usage': {
                  'input_tokens': 10,
                  'output_tokens': 5,
                  'total_tokens': 15,
                  'input_token_details': {
                    'audio_tokens': 5,
                    'cached_tokens': 3,
                    'cached_tokens_details': {'text_tokens': 3},
                  },
                  'output_token_details': {'audio_tokens': 5},
                },
              },
            })
            as RealtimeResponseDone;
    expect(done.responseId, 'response-1');
    expect(done.status, 'completed');
    expect(done.usage?.totalTokens, 15);
    expect(done.usage?.inputTokenDetails?.audioTokens, 5);
    expect(done.usage?.inputTokenDetails?.cachedTokens, 3);
    expect(done.usage?.inputTokenDetails?.cachedTokensDetails?.textTokens, 3);
    expect(done.usage?.outputTokenDetails?.audioTokens, 5);
  });

  test('decodes transcript duration and unknown usage variants', () {
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

  test('keeps provider errors and unknown envelopes opaque', () {
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
  });

  test('decodes event variants and response identity fallbacks', () {
    final created =
        RealtimeEvent.fromJson({
              'type': 'session.created',
              'session': {'id': 'created'},
            })
            as RealtimeSessionCreated;
    final updated =
        RealtimeEvent.fromJson({
              'type': 'session.updated',
              'session': {'id': 'updated'},
            })
            as RealtimeSessionUpdated;
    expect(created.sessionId, 'created');
    expect(updated.sessionId, 'updated');
    expect(
      (RealtimeEvent.fromJson({'type': 'response.output_text.delta'})
              as RealtimeTextDelta)
          .delta,
      '',
    );
    final audio =
        RealtimeEvent.fromJson({
              'type': 'response.output_audio.delta',
              'delta': 'AQ',
              'item_id': 'item',
              'response_id': 'response',
            })
            as RealtimeAudioDelta;
    expect(audio.audio, Uint8List.fromList([1]));
    expect(audio.itemId, 'item');
    expect(audio.responseId, 'response');
    final transcript =
        RealtimeEvent.fromJson({
              'type': 'conversation.item.input_audio_transcription.completed',
              'transcript': 'text',
              'item_id': 'input',
              'content_index': 1,
              'usage': {'type': 'duration', 'seconds': 2},
            })
            as RealtimeTranscriptCompleted;
    expect(transcript.itemId, 'input');
    expect(transcript.contentIndex, 1);
    expect(transcript.transcript, 'text');
    expect(
      (RealtimeEvent.fromJson({
                'type': 'conversation.item.input_audio_transcription.failed',
                'item_id': 'failed',
                'content_index': 2,
                'error': [],
              })
              as RealtimeTranscriptFailed)
          .error,
      isNull,
    );
    final outputDelta =
        RealtimeEvent.fromJson({
              'type': 'response.output_audio_transcript.delta',
              'delta': 'spoken',
              'item_id': 'out',
              'response_id': 'r',
              'content_index': 3,
            })
            as RealtimeOutputTranscriptDelta;
    final outputDone =
        RealtimeEvent.fromJson({
              'type': 'response.output_audio_transcript.done',
              'transcript': 'spoken',
              'item_id': 'out',
              'response_id': 'r',
              'content_index': 3,
            })
            as RealtimeOutputTranscriptDone;
    expect(
      [outputDelta.itemId, outputDelta.responseId, outputDelta.contentIndex],
      ['out', 'r', 3],
    );
    expect(
      [outputDone.itemId, outputDone.responseId, outputDone.contentIndex],
      ['out', 'r', 3],
    );
    expect(
      (RealtimeEvent.fromJson({'type': 'input_audio_buffer.speech_stopped'})
              as RealtimeSpeechEvent)
          .started,
      isFalse,
    );
    expect(
      (RealtimeEvent.fromJson({
        'type': 'response.output_item.done',
        'item': {'type': 'message'},
      })).type,
      'response.output_item.done',
    );
    final fallback =
        RealtimeEvent.fromJson({
              'type': 'response.done',
              'response_id': 'fallback',
            })
            as RealtimeResponseDone;
    expect(fallback.responseId, 'fallback');
    expect(fallback.status, isNull);
    expect(fallback.usage, isNull);
    expect(RealtimeException('bad').toString(), 'RealtimeException: bad');
  });

  test('rejects malformed function calls from both wire event forms', () {
    for (final event in [
      {
        'type': 'response.function_call_arguments.done',
        'call_id': 'c',
        'name': 'tool',
        'arguments': '{',
      },
      {
        'type': 'response.function_call_arguments.done',
        'call_id': '',
        'name': 'tool',
        'arguments': '{}',
      },
      {
        'type': 'response.output_item.done',
        'item': {
          'type': 'function_call',
          'call_id': 'c',
          'name': 'tool',
          'arguments': '[]',
        },
      },
      {
        'type': 'response.output_item.done',
        'item': {
          'type': 'function_call',
          'call_id': 'c',
          'name': 'tool',
          'arguments': '',
        },
      },
    ]) {
      expect(
        () => RealtimeEvent.fromJson(event),
        throwsA(isA<RealtimeException>()),
      );
    }
  });

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
