// Verification checks for package:ai_sdk_realtime. See
// features/ai_sdk_realtime.md.
//
// The package is an experimental OpenAI Realtime WebSocket adapter. Every
// check connects the real `RealtimeSession` (with its default dart:io
// WebSocket connector) to an in-process WebSocket server on loopback that
// speaks the GA Realtime wire format. No check talks to OpenAI.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart' show CancellationToken;
import 'package:ai_sdk_provider/ai_sdk_provider.dart'
    show AiOperationCancelledError;
import 'package:ai_sdk_realtime/ai_sdk_realtime.dart';

import '../harness.dart';

const _package = 'ai_sdk_realtime';

typedef _Json = Map<String, dynamic>;

/// A Realtime server: accepts WebSocket upgrades, records what the client
/// sends, and answers like the GA API (session.created on connect,
/// session.updated after session.update).
class _RealtimeServer {
  _RealtimeServer(this._http);

  final HttpServer _http;

  /// Frames the client sent, decoded.
  final List<_Json> received = [];

  /// Path, query and selected headers of each upgrade request.
  final List<Map<String, Object?>> upgrades = [];
  final List<WebSocket> sockets = [];
  final List<Completer<void>> socketsClosed = [];

  /// Set false to leave the client waiting for session.created.
  bool sendCreated = true;

  /// Set false to leave the client waiting for session.updated.
  bool sendUpdated = true;

  /// Set to an error event to send instead of session.created.
  _Json? startupError;
  void Function(WebSocket socket, _Json frame)? onFrame;

  static Future<_RealtimeServer> start(CheckContext ctx) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _RealtimeServer(http);
    ctx.onCleanup(() async {
      for (final socket in server.sockets) {
        await socket.close().catchError((Object _) {});
      }
      await http.close(force: true);
    });
    http.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      server.upgrades.add({
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'authorization': request.headers.value('authorization'),
      });
      final socket = await WebSocketTransformer.upgrade(request);
      server.sockets.add(socket);
      final closed = Completer<void>();
      server.socketsClosed.add(closed);
      if (server.startupError case final error?) {
        socket.add(jsonEncode(error));
      } else if (server.sendCreated) {
        socket.add(jsonEncode(_sessionEvent('session.created')));
      }
      socket.listen(
        (data) {
          final frame = jsonDecode(data as String) as _Json;
          server.received.add(frame);
          if (frame['type'] == 'session.update' && server.sendUpdated) {
            socket.add(jsonEncode(_sessionEvent('session.updated')));
          }
          server.onFrame?.call(socket, frame);
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
      );
    });
    return server;
  }

  Uri get endpoint => Uri.parse(
    'ws://127.0.0.1:${_http.port}/v1/realtime?model=verify-realtime',
  );

  WebSocket get socket => sockets.last;

  void send(_Json event) => socket.add(jsonEncode(event));

  void sendRaw(String text) => socket.add(text);

  List<String> get receivedTypes => [
    for (final frame in received) frame['type'] as String,
  ];
}

_Json _sessionEvent(String type) => {
  'type': type,
  'event_id': 'event_$type',
  'session': {
    'type': 'realtime',
    'id': 'sess_verify',
    'object': 'realtime.session',
    'model': 'verify-realtime',
  },
};

Future<void> _until(
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) throw CheckFailure('timed out: $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Connects a session and collects its events and errors.
class _Client {
  _Client(this.session, this.events, this.errors);

  final RealtimeSession session;
  final List<RealtimeEvent> events;
  final List<Object> errors;
  bool done = false;

  static Future<_Client> connect(
    CheckContext ctx,
    _RealtimeServer server, {
    String apiKey = 'rt-test-key',
    RealtimeSessionConfig config = const RealtimeSessionConfig(),
    int maxBufferedAudioBytes = 4 * 1024 * 1024,
    int maxFrameBytes = 1024 * 1024,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final session = await RealtimeSession.connect(
      apiKey: apiKey,
      endpoint: server.endpoint,
      config: config,
      maxBufferedAudioBytes: maxBufferedAudioBytes,
      maxFrameBytes: maxFrameBytes,
      timeout: timeout,
    );
    ctx.onCleanup(() => session.close().catchError((Object _) {}));
    final client = _Client(session, [], []);
    session.events.listen(
      client.events.add,
      onError: client.errors.add,
      onDone: () => client.done = true,
    );
    return client;
  }

  List<String> get eventTypes => [for (final e in events) e.type];

  T only<T extends RealtimeEvent>() => events.whereType<T>().single;
}

void _recordWire(CheckContext ctx, _RealtimeServer server) {
  ctx.observe('clientFrames', server.received);
  ctx.observe('upgrades', server.upgrades);
}

final checks = PackageChecks(_package, [
  Check(
    id: 'connect-handshake',
    feature: 'rt-session',
    description:
        'RealtimeSession.connect upgrades with a Bearer header on the model '
        'URL, waits for session.created, sends session.update with the '
        'default GA session and becomes ready only after session.updated.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(ctx, server);
      _recordWire(ctx, server);
      ctx.expectEquals(
        client.session.state,
        RealtimeConnectionState.ready,
        'state',
      );
      final upgrade = server.upgrades.single;
      ctx.expectEquals(upgrade['path'], '/v1/realtime', 'upgrade path');
      ctx.expectEquals(upgrade['query'], {
        'model': 'verify-realtime',
      }, 'model query');
      ctx.expectEquals(
        upgrade['authorization'],
        'Bearer rt-test-key',
        'authorization header on the upgrade request',
      );
      ctx.expectEquals(server.receivedTypes, ['session.update'], 'frames');
      final session = server.received.single['session'] as _Json;
      ctx.expectEquals(session['type'], 'realtime', 'session.type');
      ctx.expectEquals(session['model'], 'gpt-realtime-2.1', 'default model');
      ctx.expectEquals(session['output_modalities'], ['text'], 'modalities');
      ctx.expectEquals(session['audio'], {
        'input': {
          'format': {'type': 'audio/pcm', 'rate': 24000},
        },
        'output': {
          'format': {'type': 'audio/pcm', 'rate': 24000},
        },
      }, 'default audio formats');
      ctx.expect(!session.containsKey('tools'), 'tools sent without tools');
    },
  ),
  Check(
    id: 'session-config-wire',
    feature: 'rt-config',
    description:
        'RealtimeSessionConfig serializes model, instructions, modalities, '
        'voice, audio formats, server and semantic turn detection and '
        'function tools into the session.update body, and rejects invalid '
        'values before any frame is sent.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final first = await _Client.connect(
        ctx,
        server,
        config: const RealtimeSessionConfig(
          model: 'verify-realtime-custom',
          instructions: 'Be brief.',
          outputModalities: ['audio'],
          voice: 'marin',
          outputFormat: RealtimeAudioFormat(type: 'audio/pcmu'),
          turnDetection: RealtimeServerVad(
            createResponse: true,
            silenceDurationMs: 400,
            threshold: 0.6,
            interruptResponse: false,
          ),
          tools: [
            RealtimeFunctionTool(
              name: 'get_weather',
              description: 'Weather for a city.',
              parameters: {
                'type': 'object',
                'properties': {
                  'city': {'type': 'string'},
                },
                'required': ['city'],
              },
            ),
          ],
        ),
      );
      final session = server.received.first['session'] as _Json;
      ctx.expectEquals(session['model'], 'verify-realtime-custom', 'model');
      ctx.expectEquals(session['instructions'], 'Be brief.', 'instructions');
      ctx.expectEquals(session['output_modalities'], ['audio'], 'modalities');
      final audio = session['audio'] as _Json;
      ctx.expectEquals((audio['output'] as _Json), {
        'format': {'type': 'audio/pcmu'},
        'voice': 'marin',
      }, 'audio.output (G.711 omits rate)');
      ctx.expectEquals((audio['input'] as _Json)['turn_detection'], {
        'type': 'server_vad',
        'create_response': true,
        'interrupt_response': false,
        'silence_duration_ms': 400,
        'threshold': 0.6,
      }, 'server_vad');
      ctx.expectEquals(session['tools'], [
        {
          'type': 'function',
          'name': 'get_weather',
          'description': 'Weather for a city.',
          'parameters': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
            'required': ['city'],
          },
        },
      ], 'tools');
      await first.session.close();

      await _Client.connect(
        ctx,
        server,
        config: const RealtimeSessionConfig(
          turnDetection: RealtimeSemanticVad(
            eagerness: 'high',
            createResponse: true,
          ),
        ),
      );
      final semantic =
          (server.received.last['session'] as _Json)['audio'] as _Json;
      ctx.expectEquals((semantic['input'] as _Json)['turn_detection'], {
        'type': 'semantic_vad',
        'create_response': true,
        'eagerness': 'high',
      }, 'semantic_vad');
      _recordWire(ctx, server);

      final framesBefore = server.received.length;
      final invalid = <String, RealtimeSessionConfig>{
        'unknown modality': const RealtimeSessionConfig(
          outputModalities: ['video'],
        ),
        'duplicate modality': const RealtimeSessionConfig(
          outputModalities: ['text', 'text'],
        ),
        'vad threshold above 1': const RealtimeSessionConfig(
          turnDetection: RealtimeServerVad(threshold: 1.5),
        ),
        'bad eagerness': const RealtimeSessionConfig(
          turnDetection: RealtimeSemanticVad(eagerness: 'frantic'),
        ),
        'tool with array parameters': const RealtimeSessionConfig(
          tools: [
            RealtimeFunctionTool(name: 't', parameters: {'type': 'array'}),
          ],
        ),
      };
      for (final entry in invalid.entries) {
        await ctx.expectThrows<ArgumentError>(
          () => _Client.connect(ctx, server, config: entry.value),
          entry.key,
        );
      }
      ctx.expectEquals(
        server.received.where((f) => f['type'] == 'session.update').length,
        framesBefore,
        'invalid configs must not send a session.update',
      );
    },
  ),
  Check(
    id: 'client-events-wire',
    feature: 'rt-send',
    description:
        'sendText, sendAudio, commitAudio, createResponse, cancelResponse, '
        'clearAudio, submitToolResult and interrupt each send the GA client '
        'event with the documented fields.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(ctx, server);
      final session = client.session;
      await session.sendText('Say hello.');
      await session.sendAudio(Uint8List.fromList([1, 2, 3, 4]));
      await session.commitAudio();
      await session.commitAudio(createResponseEvent: false);
      await session.createResponse();
      await session.cancelResponse(responseId: 'resp_1');
      await session.cancelResponse();
      await session.clearAudio();
      await session.submitToolResult('call_1', 'Sunny');
      await session.submitToolResult('call_2', {'temp': 18});
      await session.interrupt(
        itemId: 'item_1',
        contentIndex: 0,
        audioEndMs: 1500,
        responseId: 'resp_2',
      );
      await _until(
        () => server.received.length >= 14,
        'server to receive all frames',
      );
      _recordWire(ctx, server);
      final frames = server.received.skip(1).toList();
      ctx.expectEquals(
        [for (final f in frames) f['type']],
        [
          'conversation.item.create',
          'input_audio_buffer.append',
          'input_audio_buffer.commit',
          'response.create',
          'input_audio_buffer.commit',
          'response.create',
          'response.cancel',
          'response.cancel',
          'input_audio_buffer.clear',
          'conversation.item.create',
          'conversation.item.create',
          'response.cancel',
          'conversation.item.truncate',
        ],
        'client frame order',
      );
      ctx.expectEquals(frames[0]['item'], {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': 'Say hello.'},
        ],
      }, 'sendText item');
      ctx.expectEquals(
        frames[1]['audio'],
        base64Encode([1, 2, 3, 4]),
        'sendAudio base64',
      );
      ctx.expectEquals(frames[6]['response_id'], 'resp_1', 'cancel id');
      ctx.expect(
        !frames[7].containsKey('response_id'),
        'cancel without id carries a response_id',
      );
      ctx.expectEquals(frames[9]['item'], {
        'type': 'function_call_output',
        'call_id': 'call_1',
        'output': 'Sunny',
      }, 'string tool result');
      ctx.expectEquals(frames[10]['item'], {
        'type': 'function_call_output',
        'call_id': 'call_2',
        'output': '{"temp":18}',
      }, 'JSON tool result is stringified');
      ctx.expectEquals(frames[11]['response_id'], 'resp_2', 'interrupt cancel');
      ctx.expectEquals(frames[12], {
        'type': 'conversation.item.truncate',
        'item_id': 'item_1',
        'content_index': 0,
        'audio_end_ms': 1500,
      }, 'truncate');
      await ctx.expectThrows<ArgumentError>(
        () => session.interrupt(itemId: 'i', contentIndex: 0, audioEndMs: -1),
        'negative audioEndMs',
      );
      await ctx.expectThrows<ArgumentError>(
        () => session.interrupt(itemId: 'i', contentIndex: -1, audioEndMs: 0),
        'negative contentIndex',
      );
    },
  ),
  Check(
    id: 'server-events-typed',
    feature: 'rt-events',
    description:
        'Server events reach session.events as typed classes: text, audio, '
        'input and output transcripts with usage, speech boundaries, '
        'session.updated, response.done with token usage, and unknown types '
        'kept as RealtimeUnknownEvent.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(ctx, server);
      server
        ..send(_sessionEvent('session.updated'))
        ..send({
          'type': 'input_audio_buffer.speech_started',
          'audio_start_ms': 120,
          'item_id': 'item_u',
        })
        ..send({
          'type': 'input_audio_buffer.speech_stopped',
          'item_id': 'item_u',
        })
        ..send({
          'type': 'conversation.item.input_audio_transcription.delta',
          'item_id': 'item_u',
          'content_index': 0,
          'delta': 'Hel',
        })
        ..send({
          'type': 'conversation.item.input_audio_transcription.completed',
          'item_id': 'item_u',
          'content_index': 0,
          'transcript': 'Hello there',
          'usage': {
            'type': 'tokens',
            'input_tokens': 9,
            'output_tokens': 3,
            'total_tokens': 12,
          },
        })
        ..send({
          'type': 'conversation.item.input_audio_transcription.failed',
          'item_id': 'item_x',
          'content_index': 0,
          'error': {'type': 'transcription_error', 'message': 'no speech'},
        })
        ..send({
          'type': 'response.output_text.delta',
          'response_id': 'resp_1',
          'item_id': 'item_a',
          'delta': 'Hi ',
        })
        ..send({
          'type': 'response.output_text.delta',
          'response_id': 'resp_1',
          'item_id': 'item_a',
          'delta': 'there.',
        })
        ..send({
          'type': 'response.output_audio.delta',
          'response_id': 'resp_1',
          'item_id': 'item_a',
          'delta': base64Encode([9, 8, 7, 6, 5]),
        })
        ..send({
          'type': 'response.output_audio_transcript.delta',
          'response_id': 'resp_1',
          'item_id': 'item_a',
          'content_index': 0,
          'delta': 'Hi',
        })
        ..send({
          'type': 'response.output_audio_transcript.done',
          'response_id': 'resp_1',
          'item_id': 'item_a',
          'content_index': 0,
          'transcript': 'Hi there.',
        })
        ..send({'type': 'rate_limits.updated', 'rate_limits': <Object>[]})
        ..send({
          'type': 'response.done',
          'response': {
            'id': 'resp_1',
            'status': 'completed',
            'usage': {
              'input_tokens': 20,
              'output_tokens': 10,
              'total_tokens': 30,
              'input_token_details': {
                'text_tokens': 15,
                'audio_tokens': 5,
                'cached_tokens': 4,
                'cached_tokens_details': {'text_tokens': 4},
              },
              'output_token_details': {'text_tokens': 6, 'audio_tokens': 4},
            },
          },
        });
      await _until(() => client.events.length >= 13, 'all 13 events');
      ctx.observe('eventTypes', client.eventTypes);
      ctx.expectEquals(client.errors.length, 0, 'stream errors');
      ctx.expectEquals(client.eventTypes, [
        'session.updated',
        'input_audio_buffer.speech_started',
        'input_audio_buffer.speech_stopped',
        'conversation.item.input_audio_transcription.delta',
        'conversation.item.input_audio_transcription.completed',
        'conversation.item.input_audio_transcription.failed',
        'response.output_text.delta',
        'response.output_text.delta',
        'response.output_audio.delta',
        'response.output_audio_transcript.delta',
        'response.output_audio_transcript.done',
        'rate_limits.updated',
        'response.done',
      ], 'event order');
      ctx.expectEquals(
        client.events.whereType<RealtimeTextDelta>().map((e) => e.delta).join(),
        'Hi there.',
        'joined text deltas',
      );
      ctx.expectEquals(
        client.events.first.runtimeType,
        RealtimeSessionUpdated,
        'class',
      );
      final started = client.events
          .whereType<RealtimeSpeechEvent>()
          .map((e) => e.started)
          .toList();
      ctx.expectEquals(started, [true, false], 'speech started/stopped');
      ctx.expectEquals(
        client.only<RealtimeTranscriptDelta>().delta,
        'Hel',
        'input transcript delta',
      );
      final completed = client.only<RealtimeTranscriptCompleted>();
      ctx.expectEquals(completed.transcript, 'Hello there', 'transcript');
      final transcriptUsage = completed.usage as RealtimeTranscriptTokenUsage;
      ctx.expectEquals(transcriptUsage.totalTokens, 12, 'transcript usage');
      ctx.expectEquals(
        client.only<RealtimeTranscriptFailed>().error?['message'],
        'no speech',
        'transcript failure',
      );
      final audio = client.only<RealtimeAudioDelta>();
      ctx.expectEquals(audio.audio, [9, 8, 7, 6, 5], 'decoded audio bytes');
      ctx.expectEquals(
        client.only<RealtimeOutputTranscriptDone>().transcript,
        'Hi there.',
        'output transcript',
      );
      final unknown = client.only<RealtimeUnknownEvent>();
      ctx.expectEquals(unknown.type, 'rate_limits.updated', 'unknown type');
      ctx.expectEquals(unknown.raw['rate_limits'], <Object>[], 'unknown raw');
      final done = client.only<RealtimeResponseDone>();
      ctx.expectEquals(done.responseId, 'resp_1', 'response id');
      ctx.expectEquals(done.status, 'completed', 'response status');
      final usage = done.usage!;
      ctx.expectEquals(usage.inputTokens, 20, 'input tokens');
      ctx.expectEquals(usage.outputTokens, 10, 'output tokens');
      ctx.expectEquals(usage.totalTokens, 30, 'total tokens');
      ctx.expectEquals(usage.inputTokenDetails?.audioTokens, 5, 'audio in');
      ctx.expectEquals(usage.inputTokenDetails?.cachedTokens, 4, 'cached');
      ctx.expectEquals(
        usage.inputTokenDetails?.cachedTokensDetails?.textTokens,
        4,
        'cached text',
      );
      ctx.expectEquals(usage.outputTokenDetails?.audioTokens, 4, 'audio out');
      await client.session.acknowledgeAudio(audio.audio.length);
    },
  ),
  Check(
    id: 'tool-call-round-trip',
    feature: 'rt-tools',
    description:
        'A function call from the server surfaces once as RealtimeToolCall '
        '(a repeated call_id is dropped); submitToolResult plus '
        'createResponse sends the output and asks for the next response.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(
        ctx,
        server,
        config: const RealtimeSessionConfig(
          tools: [
            RealtimeFunctionTool(
              name: 'get_weather',
              parameters: {'type': 'object'},
            ),
          ],
        ),
      );
      final call = {
        'type': 'response.function_call_arguments.done',
        'response_id': 'resp_1',
        'item_id': 'item_f',
        'call_id': 'call_weather_1',
        'name': 'get_weather',
        'arguments': '{"city":"Paris"}',
      };
      server
        ..send(call)
        ..send(call)
        ..send({
          'type': 'response.output_item.done',
          'response_id': 'resp_1',
          'item': {
            'type': 'function_call',
            'call_id': 'call_weather_2',
            'name': 'get_weather',
            'arguments': '{"city":"Rome"}',
          },
        });
      await _until(
        () => client.events.whereType<RealtimeToolCall>().length >= 2,
        'two tool calls',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final calls = client.events.whereType<RealtimeToolCall>().toList();
      ctx.observe('toolCalls', [
        for (final c in calls)
          {'callId': c.callId, 'name': c.name, 'args': c.arguments},
      ]);
      ctx.expectEquals(calls.length, 2, 'duplicate call_id must be dropped');
      ctx.expectEquals(calls[0].callId, 'call_weather_1', 'first call id');
      ctx.expectEquals(calls[0].name, 'get_weather', 'name');
      ctx.expectEquals(jsonDecode(calls[0].arguments), {
        'city': 'Paris',
      }, 'arguments');
      ctx.expectEquals(calls[1].callId, 'call_weather_2', 'item-form call id');
      await client.session.submitToolResult(calls[0].callId, {'temp': 18});
      await client.session.createResponse();
      await _until(() => server.received.length >= 3, 'tool output frames');
      _recordWire(ctx, server);
      ctx.expectEquals(server.receivedTypes, [
        'session.update',
        'conversation.item.create',
        'response.create',
      ], 'frames after the call');
      ctx.expectEquals(
        (server.received[1]['item'] as _Json)['call_id'],
        'call_weather_1',
        'output call_id',
      );
    },
  ),
  Check(
    id: 'provider-error-events',
    feature: 'rt-errors',
    description:
        'A server error event after startup arrives as RealtimeProviderError '
        'with its message and the session stays usable; a malformed JSON '
        'frame, an oversize frame, and a malformed tool call arrive as '
        'stream errors without closing the session.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(ctx, server, maxFrameBytes: 2048);
      server.send({
        'type': 'error',
        'event_id': 'event_err',
        'error': {
          'type': 'invalid_request_error',
          'code': 'invalid_value',
          'message': 'Invalid value: bogus.',
        },
      });
      await _until(
        () => client.events.whereType<RealtimeProviderError>().isNotEmpty,
        'error event',
      );
      final error = client.only<RealtimeProviderError>();
      ctx.observe('errorMessage', error.message);
      ctx.expectEquals(error.message, 'Invalid value: bogus.', 'message');
      ctx.expectEquals(error.raw['error'], {
        'type': 'invalid_request_error',
        'code': 'invalid_value',
        'message': 'Invalid value: bogus.',
      }, 'raw error payload');
      server
        ..sendRaw('not json')
        ..sendRaw(jsonEncode({'type': 'x', 'pad': 'a' * 4096}))
        ..sendRaw(
          jsonEncode({
            'type': 'response.function_call_arguments.done',
            'call_id': 'c',
            'name': 'n',
            'arguments': 'not json',
          }),
        );
      await _until(() => client.errors.length >= 3, 'three stream errors');
      ctx.observe('streamErrors', client.errors.map((e) => '$e').toList());
      ctx.expect(
        client.errors.any((e) => '$e'.contains('exceeds limit')),
        'no frame-limit error in ${client.errors}',
      );
      ctx.expect(
        client.errors.any((e) => '$e'.contains('Malformed Realtime tool call')),
        'no malformed tool call error in ${client.errors}',
      );
      ctx.expectEquals(
        client.session.state,
        RealtimeConnectionState.ready,
        'session still ready',
      );
      await client.session.sendText('still works');
      await _until(
        () => server.receivedTypes.contains('conversation.item.create'),
        'send after errors',
      );
    },
  ),
  Check(
    id: 'startup-failures',
    feature: 'rt-errors',
    description:
        'connect fails with a typed error when the server sends an error '
        'instead of session.created, never answers (timeout), is '
        'unreachable, or the abort signal is already cancelled.',
    run: (ctx) async {
      final erroring = await _RealtimeServer.start(ctx);
      erroring.startupError = {
        'type': 'error',
        'error': {'type': 'invalid_request_error', 'message': 'Bad model.'},
      };
      final startupError = await ctx.expectThrows<RealtimeException>(
        () => RealtimeSession.connect(
          apiKey: 'k',
          endpoint: erroring.endpoint,
          timeout: const Duration(seconds: 3),
        ),
        'error before session.created',
      );
      ctx.expectEquals(startupError.message, 'Bad model.', 'startup message');

      final silent = await _RealtimeServer.start(ctx)
        ..sendCreated = false;
      final timeout = await ctx.expectThrows<RealtimeException>(
        () => RealtimeSession.connect(
          apiKey: 'k',
          endpoint: silent.endpoint,
          timeout: const Duration(milliseconds: 250),
        ),
        'no session.created',
      );
      ctx.expect(
        timeout.message.contains('timed out'),
        'timeout message: ${timeout.message}',
      );
      await silent.socketsClosed.single.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw CheckFailure(
          'server socket stayed open after the client timed out',
        ),
      );

      final noUpdate = await _RealtimeServer.start(ctx)
        ..sendUpdated = false;
      await ctx.expectThrows<RealtimeException>(
        () => RealtimeSession.connect(
          apiKey: 'k',
          endpoint: noUpdate.endpoint,
          timeout: const Duration(milliseconds: 250),
        ),
        'no session.updated',
      );
      ctx.expectEquals(noUpdate.receivedTypes, ['session.update'], 'frames');

      // A port that was just released: nothing listens there.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close();
      final unreachable = await ctx.expectThrows<Object>(
        () => RealtimeSession.connect(
          apiKey: 'k',
          endpoint: Uri.parse('ws://127.0.0.1:$deadPort/v1/realtime'),
          timeout: const Duration(seconds: 3),
        ),
        'unreachable endpoint',
      );
      ctx.observe('unreachableErrorType', '${unreachable.runtimeType}');

      final token = CancellationToken()..cancel();
      await ctx.expectThrows<AiOperationCancelledError>(
        () => RealtimeSession.connect(
          apiKey: 'k',
          endpoint: erroring.endpoint,
          abortSignal: token,
        ),
        'pre-cancelled abort signal',
      );
      ctx.expectEquals(
        erroring.upgrades.length,
        1,
        'a cancelled connect must not open a socket',
      );
      await ctx.expectThrows<ArgumentError>(
        () => RealtimeSession.connect(
          apiKey: 'k',
          endpoint: erroring.endpoint,
          maxFrameBytes: 0,
        ),
        'maxFrameBytes 0',
      );
    },
  ),
  Check(
    id: 'audio-backpressure',
    feature: 'rt-audio',
    description:
        'Audio deltas beyond maxBufferedAudioBytes are dropped with one '
        'stream error until the host calls acknowledgeAudio; acknowledging '
        'more than is buffered throws ArgumentError.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(
        ctx,
        server,
        maxBufferedAudioBytes: 8,
      );
      Map<String, Object> delta(List<int> bytes) => {
        'type': 'response.output_audio.delta',
        'response_id': 'resp_1',
        'item_id': 'item_a',
        'delta': base64Encode(bytes),
      };
      server
        ..send(delta([1, 2, 3, 4, 5, 6]))
        ..send(delta([7, 8, 9, 10, 11, 12]));
      await _until(() => client.errors.isNotEmpty, 'audio overflow error');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ctx.observe('errors', client.errors.map((e) => '$e').toList());
      ctx.expectEquals(
        client.events.whereType<RealtimeAudioDelta>().length,
        1,
        'second delta dropped',
      );
      ctx.expect(
        '${client.errors.single}'.contains('audio buffer limit exceeded'),
        'overflow error: ${client.errors}',
      );
      await ctx.expectThrows<ArgumentError>(
        () => client.session.acknowledgeAudio(99),
        'acknowledge more than buffered',
      );
      await client.session.acknowledgeAudio(6);
      server.send(delta([13, 14, 15, 16, 17, 18]));
      await _until(
        () => client.events.whereType<RealtimeAudioDelta>().length == 2,
        'delta accepted after acknowledge',
      );
      ctx.expectEquals(
        client.events.whereType<RealtimeAudioDelta>().last.audio,
        [13, 14, 15, 16, 17, 18],
        'accepted audio bytes',
      );
    },
  ),
  Check(
    id: 'cancelled-response-filtered',
    feature: 'rt-cancel',
    description:
        'After cancelResponse(responseId), late deltas for that response are '
        'dropped, while its response.done and events of other responses '
        'still arrive.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(ctx, server);
      await client.session.cancelResponse(responseId: 'resp_old');
      server
        ..send({
          'type': 'response.output_text.delta',
          'response_id': 'resp_old',
          'delta': 'late',
        })
        ..send({
          'type': 'response.output_text.delta',
          'response_id': 'resp_new',
          'delta': 'fresh',
        })
        ..send({
          'type': 'response.done',
          'response': {'id': 'resp_old', 'status': 'cancelled'},
        });
      await _until(
        () => client.events.whereType<RealtimeResponseDone>().isNotEmpty,
        'response.done',
      );
      _recordWire(ctx, server);
      ctx.expectEquals(
        client.events
            .whereType<RealtimeTextDelta>()
            .map((e) => e.delta)
            .toList(),
        ['fresh'],
        'delivered text deltas',
      );
      ctx.expectEquals(
        client.only<RealtimeResponseDone>().status,
        'cancelled',
        'cancelled response.done is kept',
      );
      ctx.expectEquals(server.received.last, {
        'type': 'response.cancel',
        'response_id': 'resp_old',
      }, 'cancel frame');
    },
  ),
  Check(
    id: 'event-buffer-bounds',
    feature: 'rt-events',
    description:
        'Events sent while nobody listens are dropped; a paused listener '
        'gets a bounded queue, and overflowing maxBufferedEventCount ends '
        'its stream with RealtimeEventBufferOverflowException.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final session = await RealtimeSession.connect(
        apiKey: 'k',
        endpoint: server.endpoint,
        maxBufferedEventCount: 3,
      );
      ctx.onCleanup(() => session.close().catchError((Object _) {}));
      Map<String, Object> delta(String text) => {
        'type': 'response.output_text.delta',
        'delta': text,
      };
      server.send(delta('nobody listening'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final seen = <String>[];
      final errors = <Object>[];
      var done = false;
      final subscription = session.events.listen(
        (event) => seen.add((event as RealtimeTextDelta).delta),
        onError: errors.add,
        onDone: () => done = true,
      );
      server.send(delta('heard'));
      await _until(() => seen.isNotEmpty, 'first delivered event');
      ctx.expectEquals(seen, ['heard'], 'events before the listener are lost');

      subscription.pause();
      for (var i = 0; i < 5; i++) {
        server.send(delta('queued $i'));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      ctx.expectEquals(seen.length, 1, 'paused listener received events');
      subscription.resume();
      await _until(() => done, 'stream to end after overflow');
      ctx.observe('seen', seen);
      ctx.observe('errors', errors.map((e) => '$e').toList());
      ctx.expectEquals(errors.length, 1, 'overflow errors');
      ctx.expect(
        errors.single is RealtimeEventBufferOverflowException,
        'expected RealtimeEventBufferOverflowException, got ${errors.single}',
      );
      ctx.expectEquals(seen, [
        'heard',
      ], 'queued events are dropped on overflow');
    },
  ),
  Check(
    id: 'close-lifecycle',
    feature: 'rt-close',
    description:
        'close() ends the events stream and the socket, is idempotent and '
        'makes later sends fail with RealtimeException; a server-initiated '
        'close moves the session to closed and ends the stream.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final client = await _Client.connect(ctx, server);
      await client.session.close();
      await client.session.close();
      await _until(() => client.done, 'events stream to end');
      ctx.expectEquals(
        client.session.state,
        RealtimeConnectionState.closed,
        'state',
      );
      await server.socketsClosed.single.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw CheckFailure('server never saw the close'),
      );
      final error = await ctx.expectThrows<RealtimeException>(
        () => client.session.sendText('too late'),
        'send after close',
      );
      ctx.expect(error.message.contains('closed'), 'message: ${error.message}');

      final second = await _Client.connect(ctx, server);
      await server.socket.close(WebSocketStatus.goingAway, 'bye');
      await _until(() => second.done, 'stream end after server close');
      ctx.expectEquals(
        second.session.state,
        RealtimeConnectionState.closed,
        'state after server close',
      );
      await ctx.expectThrows<RealtimeException>(
        () => second.session.createResponse(),
        'send after server close',
      );
      await second.session.close();
      _recordWire(ctx, server);
    },
  ),
  Check(
    id: 'abort-signal-closes-session',
    feature: 'rt-close',
    description:
        'Cancelling the abortSignal passed to connect closes a ready '
        'session and its socket.',
    run: (ctx) async {
      final server = await _RealtimeServer.start(ctx);
      final token = CancellationToken();
      final session = await RealtimeSession.connect(
        apiKey: 'k',
        endpoint: server.endpoint,
        abortSignal: token,
      );
      ctx.onCleanup(() => session.close().catchError((Object _) {}));
      ctx.expectEquals(session.state, RealtimeConnectionState.ready, 'state');
      token.cancel();
      await _until(
        () => session.state == RealtimeConnectionState.closed,
        'session to close after cancel',
      );
      await server.socketsClosed.single.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw CheckFailure('socket stayed open after cancel'),
      );
    },
  ),
  Check(
    id: 'custom-transport',
    feature: 'rt-transport',
    description:
        'A host-supplied RealtimeTransportConnector replaces the dart:io '
        'WebSocket: the session sends its frames through it and reads '
        'events from it, with the URI and Authorization header handed to '
        'the connector.',
    run: (ctx) async {
      final transport = _MemoryTransport();
      Uri? seenUri;
      Map<String, String>? seenHeaders;
      final pending = RealtimeSession.connect(
        apiKey: 'browser-ephemeral',
        endpoint: Uri.parse('wss://realtime.example.test/v1/realtime'),
        connector: (uri, headers) async {
          seenUri = uri;
          seenHeaders = headers;
          return transport;
        },
      );
      await transport.listening.future;
      transport.deliver(_sessionEvent('session.created'));
      await _until(() => transport.sent.isNotEmpty, 'session.update');
      transport.deliver(_sessionEvent('session.updated'));
      final session = await pending;
      final events = <RealtimeEvent>[];
      session.events.listen(events.add);
      transport.deliver({
        'type': 'response.output_text.delta',
        'delta': 'via custom transport',
      });
      await session.sendText('hi');
      await _until(() => events.isNotEmpty, 'event from custom transport');
      ctx.observe('connectorUri', '$seenUri');
      ctx.observe('connectorHeaders', seenHeaders);
      ctx.observe('sent', transport.sent);
      ctx.expectEquals(
        '$seenUri',
        'wss://realtime.example.test/v1/realtime',
        'connector uri',
      );
      ctx.expectEquals(seenHeaders, {
        'Authorization': 'Bearer browser-ephemeral',
      }, 'connector headers');
      ctx.expectEquals(
        [for (final f in transport.sent) (jsonDecode(f) as _Json)['type']],
        ['session.update', 'conversation.item.create'],
        'frames through the transport',
      );
      ctx.expectEquals(
        (events.single as RealtimeTextDelta).delta,
        'via custom transport',
        'delivered delta',
      );
      await session.close();
      ctx.expect(transport.closed, 'transport was not closed');
    },
  ),
]);

/// An in-memory [RealtimeTransport] a browser host could provide.
class _MemoryTransport implements RealtimeTransport {
  final _controller = StreamController<Object?>();
  final listening = Completer<void>();
  final List<String> sent = [];
  bool closed = false;

  @override
  Stream<Object?> get incoming {
    if (!listening.isCompleted) listening.complete();
    return _controller.stream;
  }

  void deliver(_Json event) => _controller.add(jsonEncode(event));

  @override
  Future<void> send(String text) async => sent.add(text);

  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
    await _controller.close();
  }
}
