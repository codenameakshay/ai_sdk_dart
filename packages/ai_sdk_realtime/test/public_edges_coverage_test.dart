import 'dart:typed_data';

import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';
import 'package:test/test.dart';

void main() {
  test('validates audio formats, turn detection and session modalities', () {
    expect(
      () => RealtimeAudioFormat(type: 'audio/unknown'),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => RealtimeAudioFormat(type: 'audio/pcm', rate: 16000),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => RealtimeAudioFormat(type: 'audio/pcma', rate: 24000),
      throwsA(isA<AssertionError>()),
    );
    expect(const RealtimeAudioFormat(type: 'audio/pcm').toJson(), {
      'type': 'audio/pcm',
      'rate': 24000,
    });
    expect(
      const RealtimeSemanticVad(
        createResponse: false,
        eagerness: 'high',
        interruptResponse: false,
      ).toJson(),
      {
        'type': 'semantic_vad',
        'create_response': false,
        'eagerness': 'high',
        'interrupt_response': false,
      },
    );
    for (final modalities in [
      <String>[],
      ['video'],
      ['text', 'text'],
    ]) {
      expect(
        () => RealtimeSessionConfig(outputModalities: modalities).toJson(),
        throwsArgumentError,
      );
    }
    expect(
      const RealtimeSessionConfig(
        model: 'model',
        instructions: 'instructions',
        outputModalities: ['audio'],
        inputFormat: RealtimeAudioFormat(type: 'audio/pcmu'),
        outputFormat: RealtimeAudioFormat(type: 'audio/pcma'),
        voice: 'voice',
        turnDetection: RealtimeSemanticVad(eagerness: 'low'),
      ).toJson(),
      {
        'type': 'realtime',
        'model': 'model',
        'instructions': 'instructions',
        'output_modalities': ['audio'],
        'audio': {
          'input': {
            'format': {'type': 'audio/pcmu'},
            'turn_detection': {'type': 'semantic_vad', 'eagerness': 'low'},
          },
          'output': {
            'format': {'type': 'audio/pcma'},
            'voice': 'voice',
          },
        },
      },
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
    final done =
        RealtimeEvent.fromJson({
              'type': 'response.done',
              'response_id': 'fallback',
            })
            as RealtimeResponseDone;
    expect(done.responseId, 'fallback');
    expect(done.status, isNull);
    expect(done.usage, isNull);
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
}
