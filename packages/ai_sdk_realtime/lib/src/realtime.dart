import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'platform_transport.dart';

enum RealtimeConnectionState {
  idle,
  connecting,
  ready,
  closing,
  closed,
  failed,
}

class RealtimeException implements Exception {
  const RealtimeException(this.message);
  final String message;
  @override
  String toString() => 'RealtimeException: $message';
}

class RealtimeEventBufferOverflowException extends RealtimeException {
  const RealtimeEventBufferOverflowException()
    : super('Realtime event buffer overflowed');
}

abstract interface class RealtimeClock {
  Duration get elapsed;
  Timer schedule(Duration duration, void Function() callback);
}

class _SystemRealtimeClock implements RealtimeClock {
  _SystemRealtimeClock() : _stopwatch = Stopwatch()..start();
  final Stopwatch _stopwatch;
  @override
  Duration get elapsed => _stopwatch.elapsed;
  @override
  Timer schedule(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}

class RealtimeAudioFormat {
  const RealtimeAudioFormat({required this.type, this.rate})
    : assert(
        type == 'audio/pcm' || type == 'audio/pcmu' || type == 'audio/pcma',
        'Realtime audio format must be audio/pcm, audio/pcmu, or audio/pcma',
      ),
      assert(
        type == 'audio/pcm' ? rate == null || rate == 24000 : rate == null,
        'PCM must use 24000 Hz and G.711 formats must omit rate',
      );
  final String type;
  final int? rate;
  Map<String, dynamic> toJson() => {
    'type': type,
    if (type == 'audio/pcm') 'rate': rate ?? 24000,
  };
}

/// A function tool advertised in a Realtime session.
class RealtimeFunctionTool {
  const RealtimeFunctionTool({
    required this.name,
    required this.parameters,
    this.description,
  });

  final String name;
  final String? description;
  final Map<String, dynamic> parameters;

  Map<String, dynamic> toJson() {
    if (name.isEmpty) throw ArgumentError.value(name, 'name');
    if (parameters['type'] != null && parameters['type'] != 'object') {
      throw ArgumentError.value(
        parameters,
        'parameters',
        'Realtime function tool parameters must be an object schema',
      );
    }
    return {
      'type': 'function',
      'name': name,
      if (description != null) 'description': description,
      'parameters': parameters,
    };
  }
}

sealed class RealtimeTurnDetection {
  const RealtimeTurnDetection();
  Map<String, dynamic> toJson();
}

class RealtimeServerVad extends RealtimeTurnDetection {
  const RealtimeServerVad({
    this.createResponse,
    this.idleTimeoutMs,
    this.interruptResponse,
    this.prefixPaddingMs,
    this.silenceDurationMs,
    this.threshold,
  });

  final bool? createResponse;
  final int? idleTimeoutMs;
  final bool? interruptResponse;
  final int? prefixPaddingMs;
  final int? silenceDurationMs;
  final double? threshold;

  @override
  Map<String, dynamic> toJson() {
    if (idleTimeoutMs != null && idleTimeoutMs! < 0) {
      throw ArgumentError.value(idleTimeoutMs, 'idleTimeoutMs');
    }
    if (prefixPaddingMs != null && prefixPaddingMs! < 0) {
      throw ArgumentError.value(prefixPaddingMs, 'prefixPaddingMs');
    }
    if (silenceDurationMs != null && silenceDurationMs! < 0) {
      throw ArgumentError.value(silenceDurationMs, 'silenceDurationMs');
    }
    if (threshold != null && (threshold! < 0 || threshold! > 1)) {
      throw ArgumentError.value(threshold, 'threshold');
    }
    return {
      'type': 'server_vad',
      if (createResponse != null) 'create_response': createResponse,
      if (idleTimeoutMs != null) 'idle_timeout_ms': idleTimeoutMs,
      if (interruptResponse != null) 'interrupt_response': interruptResponse,
      if (prefixPaddingMs != null) 'prefix_padding_ms': prefixPaddingMs,
      if (silenceDurationMs != null) 'silence_duration_ms': silenceDurationMs,
      if (threshold != null) 'threshold': threshold,
    };
  }
}

class RealtimeSemanticVad extends RealtimeTurnDetection {
  const RealtimeSemanticVad({
    this.createResponse,
    this.eagerness,
    this.interruptResponse,
  });

  final bool? createResponse;
  final String? eagerness;
  final bool? interruptResponse;

  @override
  Map<String, dynamic> toJson() {
    const allowed = {'auto', 'low', 'medium', 'high'};
    if (eagerness != null && !allowed.contains(eagerness)) {
      throw ArgumentError.value(eagerness, 'eagerness');
    }
    return {
      'type': 'semantic_vad',
      if (createResponse != null) 'create_response': createResponse,
      if (eagerness != null) 'eagerness': eagerness,
      if (interruptResponse != null) 'interrupt_response': interruptResponse,
    };
  }
}

class RealtimeSessionConfig {
  const RealtimeSessionConfig({
    this.model,
    this.instructions,
    this.outputModalities = const ['text'],
    this.inputFormat = const RealtimeAudioFormat(
      type: 'audio/pcm',
      rate: 24000,
    ),
    this.outputFormat = const RealtimeAudioFormat(
      type: 'audio/pcm',
      rate: 24000,
    ),
    this.voice,
    this.turnDetection,
    this.tools = const [],
  });
  final String? model;
  final String? instructions;
  final List<String> outputModalities;
  final RealtimeAudioFormat inputFormat;
  final RealtimeAudioFormat outputFormat;
  final String? voice;
  final RealtimeTurnDetection? turnDetection;
  final List<RealtimeFunctionTool> tools;
  Map<String, dynamic> toJson() {
    const allowedModalities = {'text', 'audio'};
    if (outputModalities.isEmpty ||
        outputModalities.any((item) => !allowedModalities.contains(item)) ||
        outputModalities.toSet().length != outputModalities.length) {
      throw ArgumentError.value(outputModalities, 'outputModalities');
    }
    final serializedTools = tools.map((tool) => tool.toJson()).toList();
    return {
      'type': 'realtime',
      if (model != null) 'model': model,
      if (instructions != null) 'instructions': instructions,
      'output_modalities': outputModalities,
      'audio': {
        'input': {
          'format': inputFormat.toJson(),
          if (turnDetection != null) 'turn_detection': turnDetection!.toJson(),
        },
        'output': {
          'format': outputFormat.toJson(),
          if (voice != null) 'voice': voice,
        },
      },
      if (serializedTools.isNotEmpty) 'tools': serializedTools,
    };
  }
}

sealed class RealtimeEvent {
  const RealtimeEvent(this.type, this.raw);
  final String type;
  final Map<String, dynamic> raw;
  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || type.isEmpty) {
      throw const RealtimeException('event type is required');
    }
    switch (type) {
      case 'session.created':
        return RealtimeSessionCreated(json);
      case 'session.updated':
        return RealtimeSessionUpdated(json);
      case 'response.output_text.delta':
        return RealtimeTextDelta(json);
      case 'response.output_audio.delta':
        return RealtimeAudioDelta(json);
      case 'conversation.item.input_audio_transcription.delta':
        return RealtimeTranscriptDelta(json);
      case 'conversation.item.input_audio_transcription.completed':
        return RealtimeTranscriptCompleted(json);
      case 'conversation.item.input_audio_transcription.failed':
        return RealtimeTranscriptFailed(json);
      case 'response.output_audio_transcript.delta':
        return RealtimeOutputTranscriptDelta(json);
      case 'response.output_audio_transcript.done':
        return RealtimeOutputTranscriptDone(json);
      case 'input_audio_buffer.speech_started':
        return RealtimeSpeechEvent(json, true);
      case 'input_audio_buffer.speech_stopped':
        return RealtimeSpeechEvent(json, false);
      case 'response.function_call_arguments.done':
        return RealtimeToolCall(json);
      case 'response.output_item.done':
        if ((json['item'] as Map?)?['type'] == 'function_call') {
          return RealtimeToolCall(json);
        }
        return RealtimeUnknownEvent(json);
      case 'response.done':
        return RealtimeResponseDone(json);
      case 'error':
        return RealtimeProviderError(json);
      default:
        return RealtimeUnknownEvent(json);
    }
  }
}

class RealtimeSessionCreated extends RealtimeEvent {
  RealtimeSessionCreated(Map<String, dynamic> raw)
    : super('session.created', raw);
  String? get sessionId =>
      raw['session'] is Map ? (raw['session'] as Map)['id'] as String? : null;
}

class RealtimeSessionUpdated extends RealtimeEvent {
  RealtimeSessionUpdated(Map<String, dynamic> raw)
    : super('session.updated', raw);
  String? get sessionId =>
      raw['session'] is Map ? (raw['session'] as Map)['id'] as String? : null;
}

class RealtimeTextDelta extends RealtimeEvent {
  RealtimeTextDelta(Map<String, dynamic> raw)
    : super('response.output_text.delta', raw);
  String get delta => raw['delta'] as String? ?? '';
  String? get itemId => raw['item_id'] as String?;
}

class RealtimeAudioDelta extends RealtimeEvent {
  RealtimeAudioDelta(Map<String, dynamic> raw)
    : super('response.output_audio.delta', raw);
  Uint8List get audio =>
      Uint8List.fromList(base64.decode(raw['delta'] as String? ?? ''));
  String? get itemId => raw['item_id'] as String?;
  String? get responseId => raw['response_id'] as String?;
}

class RealtimeTranscriptDelta extends RealtimeEvent {
  RealtimeTranscriptDelta(Map<String, dynamic> raw)
    : super('conversation.item.input_audio_transcription.delta', raw);
  String get delta => raw['delta'] as String? ?? '';
  String? get itemId => raw['item_id'] as String?;
  int? get contentIndex => raw['content_index'] as int?;
  List<Map<String, dynamic>>? get logprobs => _mapsOrNull(raw['logprobs']);
}

class RealtimeTranscriptCompleted extends RealtimeEvent {
  RealtimeTranscriptCompleted(Map<String, dynamic> raw)
    : super('conversation.item.input_audio_transcription.completed', raw);
  String get transcript => raw['transcript'] as String? ?? '';
  String? get itemId => raw['item_id'] as String?;
  int? get contentIndex => raw['content_index'] as int?;
  RealtimeTranscriptUsage? get usage =>
      RealtimeTranscriptUsage.fromJson(raw['usage']);
}

class RealtimeTranscriptFailed extends RealtimeEvent {
  RealtimeTranscriptFailed(Map<String, dynamic> raw)
    : super('conversation.item.input_audio_transcription.failed', raw);
  String? get itemId => raw['item_id'] as String?;
  int? get contentIndex => raw['content_index'] as int?;
  Map<String, dynamic>? get error => _mapOrNull(raw['error']);
}

class RealtimeOutputTranscriptDelta extends RealtimeEvent {
  RealtimeOutputTranscriptDelta(Map<String, dynamic> raw)
    : super('response.output_audio_transcript.delta', raw);
  String get delta => raw['delta'] as String? ?? '';
  String? get itemId => raw['item_id'] as String?;
  String? get responseId => raw['response_id'] as String?;
  int? get contentIndex => raw['content_index'] as int?;
}

class RealtimeOutputTranscriptDone extends RealtimeEvent {
  RealtimeOutputTranscriptDone(Map<String, dynamic> raw)
    : super('response.output_audio_transcript.done', raw);
  String get transcript => raw['transcript'] as String? ?? '';
  String? get itemId => raw['item_id'] as String?;
  String? get responseId => raw['response_id'] as String?;
  int? get contentIndex => raw['content_index'] as int?;
}

sealed class RealtimeTranscriptUsage {
  const RealtimeTranscriptUsage();
  static RealtimeTranscriptUsage? fromJson(Object? value) {
    final map = _mapOrNull(value);
    if (map == null) return null;
    return switch (map['type']) {
      'tokens' => RealtimeTranscriptTokenUsage(
        inputTokens: _intOrNull(map['input_tokens']),
        outputTokens: _intOrNull(map['output_tokens']),
        totalTokens: _intOrNull(map['total_tokens']),
        inputTokenDetails: _mapOrNull(map['input_token_details']),
      ),
      'duration' => RealtimeTranscriptDurationUsage(
        seconds: (map['seconds'] as num?)?.toDouble(),
      ),
      _ => RealtimeTranscriptUnknownUsage(map),
    };
  }
}

class RealtimeTranscriptTokenUsage extends RealtimeTranscriptUsage {
  const RealtimeTranscriptTokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.inputTokenDetails,
  });
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final Map<String, dynamic>? inputTokenDetails;
}

class RealtimeTranscriptDurationUsage extends RealtimeTranscriptUsage {
  const RealtimeTranscriptDurationUsage({this.seconds});
  final double? seconds;
}

class RealtimeTranscriptUnknownUsage extends RealtimeTranscriptUsage {
  const RealtimeTranscriptUnknownUsage(this.raw);
  final Map<String, dynamic> raw;
}

class RealtimeSpeechEvent extends RealtimeEvent {
  RealtimeSpeechEvent(Map<String, dynamic> raw, this.started)
    : super(
        started
            ? 'input_audio_buffer.speech_started'
            : 'input_audio_buffer.speech_stopped',
        raw,
      );
  final bool started;
}

class RealtimeToolCall extends RealtimeEvent {
  RealtimeToolCall(Map<String, dynamic> raw)
    : super(raw['type'] as String, raw) {
    final item = raw['item'] is Map ? raw['item'] as Map : raw;
    Object? parsed;
    try {
      parsed = jsonDecode(arguments);
    } catch (_) {
      throw const RealtimeException('Malformed Realtime tool call');
    }
    if (callId.isEmpty || name.isEmpty || arguments.isEmpty || parsed is! Map) {
      throw const RealtimeException('Malformed Realtime tool call');
    }
    if (raw['item'] is Map && item['type'] != 'function_call') {
      throw const RealtimeException('Malformed Realtime tool call');
    }
  }
  String get callId =>
      (raw['call_id'] ?? (raw['item'] as Map?)?['call_id']) as String? ?? '';
  String get name =>
      (raw['name'] ?? (raw['item'] as Map?)?['name']) as String? ?? '';
  String get arguments =>
      (raw['arguments'] ?? (raw['item'] as Map?)?['arguments']) as String? ??
      '';
}

class RealtimeResponseDone extends RealtimeEvent {
  RealtimeResponseDone(Map<String, dynamic> raw) : super('response.done', raw);
  String? get responseId => raw['response'] is Map
      ? (raw['response'] as Map)['id'] as String?
      : raw['response_id'] as String?;
  String? get status => raw['response'] is Map
      ? (raw['response'] as Map)['status'] as String?
      : null;
  RealtimeResponseUsage? get usage => RealtimeResponseUsage.fromJson(
    raw['response'] is Map ? (raw['response'] as Map)['usage'] : null,
  );
}

class RealtimeResponseUsage {
  const RealtimeResponseUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.inputTokenDetails,
    this.outputTokenDetails,
  });
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final RealtimeInputTokenDetails? inputTokenDetails;
  final RealtimeOutputTokenDetails? outputTokenDetails;

  static RealtimeResponseUsage? fromJson(Object? value) {
    final map = _mapOrNull(value);
    if (map == null) return null;
    return RealtimeResponseUsage(
      inputTokens: _intOrNull(map['input_tokens']),
      outputTokens: _intOrNull(map['output_tokens']),
      totalTokens: _intOrNull(map['total_tokens']),
      inputTokenDetails: RealtimeInputTokenDetails.fromJson(
        map['input_token_details'],
      ),
      outputTokenDetails: RealtimeOutputTokenDetails.fromJson(
        map['output_token_details'],
      ),
    );
  }
}

class RealtimeInputTokenDetails {
  const RealtimeInputTokenDetails({
    this.audioTokens,
    this.cachedTokens,
    this.imageTokens,
    this.textTokens,
    this.cachedTokensDetails,
  });
  final int? audioTokens;
  final int? cachedTokens;
  final int? imageTokens;
  final int? textTokens;
  final RealtimeCachedTokenDetails? cachedTokensDetails;

  static RealtimeInputTokenDetails? fromJson(Object? value) {
    final map = _mapOrNull(value);
    if (map == null) return null;
    return RealtimeInputTokenDetails(
      audioTokens: _intOrNull(map['audio_tokens']),
      cachedTokens: _intOrNull(map['cached_tokens']),
      imageTokens: _intOrNull(map['image_tokens']),
      textTokens: _intOrNull(map['text_tokens']),
      cachedTokensDetails: RealtimeCachedTokenDetails.fromJson(
        map['cached_tokens_details'],
      ),
    );
  }
}

class RealtimeCachedTokenDetails {
  const RealtimeCachedTokenDetails({
    this.audioTokens,
    this.imageTokens,
    this.textTokens,
  });
  final int? audioTokens;
  final int? imageTokens;
  final int? textTokens;

  static RealtimeCachedTokenDetails? fromJson(Object? value) {
    final map = _mapOrNull(value);
    if (map == null) return null;
    return RealtimeCachedTokenDetails(
      audioTokens: _intOrNull(map['audio_tokens']),
      imageTokens: _intOrNull(map['image_tokens']),
      textTokens: _intOrNull(map['text_tokens']),
    );
  }
}

class RealtimeOutputTokenDetails {
  const RealtimeOutputTokenDetails({this.audioTokens, this.textTokens});
  final int? audioTokens;
  final int? textTokens;

  static RealtimeOutputTokenDetails? fromJson(Object? value) {
    final map = _mapOrNull(value);
    if (map == null) return null;
    return RealtimeOutputTokenDetails(
      audioTokens: _intOrNull(map['audio_tokens']),
      textTokens: _intOrNull(map['text_tokens']),
    );
  }
}

class RealtimeProviderError extends RealtimeEvent {
  RealtimeProviderError(Map<String, dynamic> raw) : super('error', raw);
  String get message =>
      (raw['error'] is Map ? (raw['error'] as Map)['message'] : null)
          as String? ??
      'Realtime provider error';
}

class RealtimeUnknownEvent extends RealtimeEvent {
  RealtimeUnknownEvent(Map<String, dynamic> raw)
    : super(raw['type'] as String, raw);
}

Map<String, dynamic>? _mapOrNull(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>>? _mapsOrNull(Object? value) {
  if (value is! List) return null;
  final maps = <Map<String, dynamic>>[];
  for (final item in value) {
    final map = _mapOrNull(item);
    if (map == null) return null;
    maps.add(map);
  }
  return maps;
}

int? _intOrNull(Object? value) => value is int ? value : null;

abstract interface class RealtimeTransport {
  Stream<Object?> get incoming;
  Future<void> send(String text);
  Future<void> close([int? code, String? reason]);
}

typedef RealtimeTransportConnector =
    Future<RealtimeTransport> Function(Uri uri, Map<String, String> headers);

class WebSocketRealtimeTransport implements RealtimeTransport {
  WebSocketRealtimeTransport(this.channel);
  final WebSocketChannel channel;
  @override
  Stream<Object?> get incoming => channel.stream;
  @override
  Future<void> send(String text) async => channel.sink.add(text);
  @override
  Future<void> close([int? code, String? reason]) =>
      channel.sink.close(code, reason);
  static Future<RealtimeTransport> connect(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final channel = await connectAuthenticatedWebSocket(uri, headers);
    return WebSocketRealtimeTransport(channel);
  }
}

class RealtimeSession {
  RealtimeSession._(
    this._transport,
    this.config,
    this._eventHub,
    this._maxBufferedAudioBytes,
    this._maxFrameBytes,
    this._maxRememberedToolCalls,
    this._maxRememberedCancelledResponses,
    this._clock,
  ) {
    // Both startup futures can be completed by one transport failure before
    // the second phase begins. Keep the unobserved phase from becoming an
    // uncaught asynchronous error.
    unawaited(_created.future.then<void>((_) {}, onError: (_, _) {}));
    unawaited(_updated.future.then<void>((_) {}, onError: (_, _) {}));
  }
  final RealtimeTransport _transport;
  final RealtimeSessionConfig config;
  final _BoundedEventHub _eventHub;
  final int _maxBufferedAudioBytes;
  final int _maxFrameBytes;
  final int _maxRememberedToolCalls;
  final int _maxRememberedCancelledResponses;
  final RealtimeClock _clock;
  StreamSubscription<Object?>? _subscription;
  RealtimeConnectionState state = RealtimeConnectionState.connecting;
  final Set<String> _toolCalls = {};
  final Set<String> _cancelledResponses = {};
  final _created = Completer<RealtimeSessionCreated>();
  final _updated = Completer<void>();
  int _bufferedAudioBytes = 0;
  bool _audioOverflowReported = false;
  bool _terminal = false;
  bool _configurationSent = false;
  String? _sessionId;
  Future<void>? _closeFuture;
  AbortSignalObservation? _abortObservation;

  /// Events are dropped while no listener is attached. Each paused listener
  /// receives a separately bounded queue, so a slow host cannot retain frames
  /// without limit.
  Stream<RealtimeEvent> get events => _eventHub.stream;

  static Future<RealtimeSession> connect({
    required String apiKey,
    String model = 'gpt-realtime-2.1',
    Uri? endpoint,
    RealtimeSessionConfig config = const RealtimeSessionConfig(),
    AbortSignal? abortSignal,
    Duration timeout = const Duration(seconds: 15),
    int maxBufferedAudioBytes = 4 * 1024 * 1024,
    int maxFrameBytes = 1024 * 1024,
    int maxBufferedEventBytes = 4 * 1024 * 1024,
    int maxBufferedEventCount = 256,
    int maxRememberedToolCalls = 8192,
    int maxRememberedCancelledResponses = 8192,
    RealtimeClock? clock,
    RealtimeTransportConnector connector = WebSocketRealtimeTransport.connect,
  }) async {
    if (maxBufferedAudioBytes < 1) {
      throw ArgumentError.value(maxBufferedAudioBytes, 'maxBufferedAudioBytes');
    }
    if (maxFrameBytes < 1) {
      throw ArgumentError.value(maxFrameBytes, 'maxFrameBytes');
    }
    if (maxBufferedEventBytes < 1) {
      throw ArgumentError.value(maxBufferedEventBytes, 'maxBufferedEventBytes');
    }
    if (maxBufferedEventCount < 1) {
      throw ArgumentError.value(maxBufferedEventCount, 'maxBufferedEventCount');
    }
    if (maxRememberedToolCalls < 1) {
      throw ArgumentError.value(
        maxRememberedToolCalls,
        'maxRememberedToolCalls',
      );
    }
    if (maxRememberedCancelledResponses < 1) {
      throw ArgumentError.value(
        maxRememberedCancelledResponses,
        'maxRememberedCancelledResponses',
      );
    }
    if (abortSignal?.isCancelled ?? false) {
      throw const AiOperationCancelledError();
    }
    final uri =
        endpoint ??
        Uri.parse(
          'wss://api.openai.com/v1/realtime?model=${Uri.encodeQueryComponent(model)}',
        );
    final effective = RealtimeSessionConfig(
      model: config.model ?? model,
      instructions: config.instructions,
      outputModalities: config.outputModalities,
      inputFormat: config.inputFormat,
      outputFormat: config.outputFormat,
      voice: config.voice,
      turnDetection: config.turnDetection,
      tools: config.tools,
    );
    final realtimeClock = clock ?? _SystemRealtimeClock();
    final pending = connector(uri, {'Authorization': 'Bearer $apiKey'});
    var settled = false;
    pending.then((lateTransport) {
      if (settled) unawaited(lateTransport.close().catchError((_) {}));
    }, onError: (_, _) {});
    RealtimeTransport transport;
    try {
      transport = await _race(pending, abortSignal, timeout);
    } finally {
      settled = true;
    }
    final eventHub = _BoundedEventHub(
      maxBytes: maxBufferedEventBytes,
      maxCount: maxBufferedEventCount,
    );
    final session = RealtimeSession._(
      transport,
      effective,
      eventHub,
      maxBufferedAudioBytes,
      maxFrameBytes,
      maxRememberedToolCalls,
      maxRememberedCancelledResponses,
      realtimeClock,
    );
    eventHub.onAudioDropped = session._dropQueuedAudio;
    final sub = transport.incoming.listen(
      session._receive,
      onError: (Object? e, StackTrace s) {
        session._transportError(
          e ?? const RealtimeException('transport error'),
          s,
        );
      },
      onDone: session._transportDone,
    );
    session._subscription = sub;
    try {
      await _race(
        session._created.future,
        abortSignal,
        _remaining(realtimeClock, timeout),
        timerFactory: realtimeClock.schedule,
      );
      await _race(
        session._sendConfiguration(effective),
        abortSignal,
        _remaining(realtimeClock, timeout),
        timerFactory: realtimeClock.schedule,
      );
      await _race(
        session._updated.future,
        abortSignal,
        _remaining(realtimeClock, timeout),
        timerFactory: realtimeClock.schedule,
      );
      if (!session._terminal) session.state = RealtimeConnectionState.ready;
      if (abortSignal != null) {
        session._abortObservation = AbortSignalObservation.attach(
          abortSignal,
          () => unawaited(session.close().catchError((_) {})),
        );
      }
      return session;
    } catch (error, stack) {
      // Cleanup is bounded and cannot replace the startup error (including
      // cancellation) with a transport or subscription cleanup failure.
      try {
        await session.close(timeout: _remainingOrZero(realtimeClock, timeout));
      } catch (_) {
        // The operation which caused startup to fail is the useful error.
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _sendConfiguration(RealtimeSessionConfig effective) {
    _configurationSent = true;
    return _send({'type': 'session.update', 'session': effective.toJson()});
  }

  void _receive(Object? value) {
    if (_terminal ||
        (state != RealtimeConnectionState.ready &&
            state != RealtimeConnectionState.connecting)) {
      return;
    }
    late final List<int> frame;
    try {
      if (value is String) {
        final byteLength = _utf8ByteLength(value, _maxFrameBytes);
        if (byteLength == 0 || byteLength > _maxFrameBytes) {
          throw const RealtimeException('Realtime frame exceeds limit');
        }
        frame = utf8.encode(value);
      } else if (value is List<int>) {
        if (value.isEmpty || value.length > _maxFrameBytes) {
          throw const RealtimeException('Realtime frame exceeds limit');
        }
        frame = value;
      } else {
        throw const RealtimeException('Realtime frame exceeds limit');
      }
      final json = jsonDecode(utf8.decode(frame));
      if (json is! Map) {
        throw const RealtimeException('Realtime frame must be an object');
      }
      final event = RealtimeEvent.fromJson(Map<String, dynamic>.from(json));
      if (event is RealtimeSessionCreated && !_created.isCompleted) {
        final sessionId = event.sessionId;
        if (sessionId == null || sessionId.isEmpty) {
          throw const RealtimeException(
            'Realtime session.created id is required',
          );
        }
        _sessionId = sessionId;
        _created.complete(event);
      }
      if (event is RealtimeSessionUpdated &&
          !_updated.isCompleted &&
          _configurationSent &&
          event.sessionId == _sessionId) {
        _updated.complete();
      }
      if (event is RealtimeProviderError) {
        _failStartup(RealtimeException(event.message), StackTrace.current);
      }
      if (_isCancelledResponseEvent(event)) {
        return;
      }
      if (event is RealtimeToolCall) {
        if (_toolCalls.contains(event.callId)) return;
        if (_toolCalls.length >= _maxRememberedToolCalls) {
          _reportIdentityLimit('tool call');
          return;
        }
        _toolCalls.add(event.callId);
      }
      if (event is RealtimeAudioDelta) {
        final encoded = event.raw['delta'];
        if (encoded is! String) {
          throw const RealtimeException('Realtime audio delta is invalid');
        }
        final decodedLength = _base64DecodedLength(encoded);
        if (decodedLength == null) {
          throw const RealtimeException('Realtime audio delta is invalid');
        }
        if (decodedLength > _maxBufferedAudioBytes - _bufferedAudioBytes) {
          _reportAudioOverflow();
          return;
        }
        final audio = event.audio;
        if (audio.length != decodedLength) {
          throw const RealtimeException('Realtime audio delta is invalid');
        }
        final audioBytes = audio.length;
        // Audio is only retained when at least one host can receive it. A
        // missing listener therefore cannot consume the audio budget.
        _bufferedAudioBytes += audioBytes;
        if (!_eventHub.add(
          event,
          frameBytes: frame.length,
          audioBytes: audioBytes,
        )) {
          _bufferedAudioBytes -= audioBytes;
        }
        return;
      }
      _eventHub.add(event, frameBytes: frame.length);
    } catch (e, s) {
      _eventHub.addError(e, s);
    }
  }

  void _reportAudioOverflow() {
    if (_audioOverflowReported) return;
    _audioOverflowReported = true;
    _eventHub.addError(
      const RealtimeException('audio buffer limit exceeded'),
      StackTrace.current,
    );
  }

  Future<void> acknowledgeAudio(int bytes) async {
    if (bytes < 0 || bytes > _bufferedAudioBytes) {
      throw ArgumentError.value(bytes, 'bytes');
    }
    _bufferedAudioBytes -= bytes;
    if (_bufferedAudioBytes < _maxBufferedAudioBytes) {
      _audioOverflowReported = false;
    }
  }

  void _dropQueuedAudio(int bytes) {
    if (bytes <= 0) return;
    _bufferedAudioBytes = (_bufferedAudioBytes - bytes).clamp(
      0,
      _maxBufferedAudioBytes,
    );
    if (_bufferedAudioBytes < _maxBufferedAudioBytes) {
      _audioOverflowReported = false;
    }
  }

  Future<void> sendText(String text) => _send({
    'type': 'conversation.item.create',
    'item': {
      'type': 'message',
      'role': 'user',
      'content': [
        {'type': 'input_text', 'text': text},
      ],
    },
  });
  Future<void> sendAudio(Uint8List bytes) => _send({
    'type': 'input_audio_buffer.append',
    'audio': base64.encode(bytes),
  });
  Future<void> commitAudio({bool createResponseEvent = true}) async {
    await _send({'type': 'input_audio_buffer.commit'});
    if (createResponseEvent) await createResponse();
  }

  Future<void> createResponse() => _send({'type': 'response.create'});
  Future<void> cancelResponse({String? responseId}) {
    if (responseId != null && !_rememberCancelledResponse(responseId)) {
      return Future.error(
        const RealtimeException(
          'Cancelled response history is full; refusing an untracked cancellation.',
        ),
      );
    }
    return _send({'type': 'response.cancel', 'response_id': ?responseId});
  }

  bool _rememberCancelledResponse(String responseId) {
    if (_cancelledResponses.contains(responseId)) return true;
    if (_cancelledResponses.length >= _maxRememberedCancelledResponses) {
      _reportIdentityLimit('cancelled response');
      return false;
    }
    _cancelledResponses.add(responseId);
    return true;
  }

  void _reportIdentityLimit(String identity) {
    _eventHub.addError(
      RealtimeException(
        'Realtime $identity identity history is full; event was not accepted.',
      ),
      StackTrace.current,
    );
  }

  bool _isCancelledResponseEvent(RealtimeEvent event) {
    if (event is RealtimeResponseDone || event is RealtimeProviderError) {
      return false;
    }
    final responseId = event.raw['response_id'];
    return responseId is String && _cancelledResponses.contains(responseId);
  }

  Future<void> clearAudio() => _send({'type': 'input_audio_buffer.clear'});
  Future<void> submitToolResult(String callId, Object output) => _send({
    'type': 'conversation.item.create',
    'item': {
      'type': 'function_call_output',
      'call_id': callId,
      'output': output is String ? output : jsonEncode(output),
    },
  });
  Future<void> interrupt({
    required String itemId,
    required int contentIndex,
    required int audioEndMs,
    String? responseId,
  }) async {
    if (audioEndMs < 0) throw ArgumentError.value(audioEndMs, 'audioEndMs');
    if (contentIndex < 0) {
      throw ArgumentError.value(contentIndex, 'contentIndex');
    }
    await cancelResponse(responseId: responseId);
    await _send({
      'type': 'conversation.item.truncate',
      'item_id': itemId,
      'content_index': contentIndex,
      'audio_end_ms': audioEndMs,
    });
  }

  Future<void> _send(Map<String, dynamic> json) {
    if (state != RealtimeConnectionState.ready &&
        state != RealtimeConnectionState.connecting) {
      return Future.error(
        const RealtimeException('Realtime session is closed'),
      );
    }
    return _transport.send(jsonEncode(json));
  }

  void _transportError(Object error, StackTrace stack) {
    if (_terminal) return;
    final observation = _abortObservation;
    _abortObservation = null;
    unawaited(observation?.dispose());
    state = RealtimeConnectionState.failed;
    _terminal = true;
    _failStartup(error, stack);
    _eventHub.addError(error, stack);
    unawaited(close().catchError((_) {}));
  }

  void _transportDone() {
    if (_terminal) return;
    final observation = _abortObservation;
    _abortObservation = null;
    unawaited(observation?.dispose());
    _subscription = null;
    _terminal = true;
    state = RealtimeConnectionState.closed;
    _failStartup(
      const RealtimeException('Realtime connection closed'),
      StackTrace.current,
    );
    _eventHub.close();
  }

  void _failStartup(Object error, StackTrace stack) {
    if (!_created.isCompleted) _created.completeError(error, stack);
    if (!_updated.isCompleted) _updated.completeError(error, stack);
  }

  Future<void> close({Duration timeout = const Duration(seconds: 5)}) {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closeFuture = _close(timeout);
    return _closeFuture!;
  }

  Future<void> _close(Duration timeout) async {
    if (_terminal && state == RealtimeConnectionState.closed) {
      final observation = _abortObservation;
      _abortObservation = null;
      await observation?.dispose();
      _eventHub.close();
      return;
    }
    state = RealtimeConnectionState.closing;
    _terminal = true;
    _failStartup(
      const RealtimeException('Realtime session closed'),
      StackTrace.current,
    );
    final subscription = _subscription;
    _subscription = null;
    final abortObservation = _abortObservation;
    _abortObservation = null;
    final operations = <Future<_CleanupResult>>[];
    final completed = <_CleanupResult>[];
    Future<void> track(Future<_CleanupResult> operation) async {
      final result = await operation;
      completed.add(result);
    }

    if (subscription != null) {
      operations.add(_captureCleanup(Future<void>.sync(subscription.cancel)));
    }
    operations.add(_captureCleanup(Future<void>.sync(_transport.close)));
    Object? cleanupError;
    StackTrace? cleanupStack;
    try {
      await abortObservation?.dispose();
      final all = Future.wait(operations);
      for (final operation in operations) {
        unawaited(track(operation));
      }
      final result = await _raceCleanup(
        all,
        timeout,
        timerFactory: _clock.schedule,
      );
      for (final item in result) {
        if (item.error != null) {
          cleanupError = item.error;
          cleanupStack = item.stack;
          break;
        }
      }
    } catch (error, stack) {
      for (final item in completed) {
        if (item.error != null) {
          cleanupError = item.error;
          cleanupStack = item.stack;
          break;
        }
      }
      cleanupError ??= error;
      cleanupStack ??= stack;
    } finally {
      state = RealtimeConnectionState.closed;
      _eventHub.close();
    }
    if (cleanupError != null) {
      Error.throwWithStackTrace(cleanupError, cleanupStack ?? StackTrace.empty);
    }
  }
}

Duration _remaining(RealtimeClock clock, Duration timeout) {
  final remaining = timeout - clock.elapsed;
  if (remaining <= Duration.zero) {
    throw const RealtimeException('Realtime operation timed out');
  }
  return remaining;
}

Duration _remainingOrZero(RealtimeClock clock, Duration timeout) {
  final remaining = timeout - clock.elapsed;
  return remaining.isNegative ? Duration.zero : remaining;
}

int _utf8ByteLength(String value, int limit) {
  var length = 0;
  for (var index = 0; index < value.length; index++) {
    final codeUnit = value.codeUnitAt(index);
    if (codeUnit >= 0xd800 && codeUnit <= 0xdbff && index + 1 < value.length) {
      final next = value.codeUnitAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        length += 4;
        index++;
      } else {
        length += 3;
      }
    } else if (codeUnit <= 0x7f) {
      length++;
    } else if (codeUnit <= 0x7ff) {
      length += 2;
    } else {
      length += 3;
    }
    if (length > limit) return length;
  }
  return length;
}

int? _base64DecodedLength(String value) {
  if (value.isEmpty) return 0;
  var padding = 0;
  var sawPadding = false;
  for (var index = 0; index < value.length; index++) {
    final code = value.codeUnitAt(index);
    if (code == 61) {
      sawPadding = true;
      padding++;
      continue;
    }
    if (sawPadding || !_isBase64Code(code)) return null;
  }
  if (padding > 2) return null;
  if (padding != 0 && value.length % 4 != 0) return null;
  if (value.length % 4 == 1) return null;
  if (padding != 0 && padding > value.length) return null;
  return padding == 0
      ? (value.length * 6) ~/ 8
      : (value.length ~/ 4) * 3 - padding;
}

bool _isBase64Code(int code) {
  return code >= 0x41 && code <= 0x5a ||
      code >= 0x61 && code <= 0x7a ||
      code >= 0x30 && code <= 0x39 ||
      code == 0x2b ||
      code == 0x2f;
}

Future<T> _race<T>(
  Future<T> operation,
  AbortSignal? signal,
  Duration timeout, {
  Timer Function(Duration, void Function()) timerFactory = Timer.new,
}) {
  if (signal?.isCancelled ?? false) throw const AiOperationCancelledError();
  return runWithAbortSignal(
    () => _raceWithTimeout(
      operation,
      timeout,
      const RealtimeException('Realtime operation timed out'),
      timerFactory: timerFactory,
    ),
    signal,
  );
}

Future<T> _raceWithTimeout<T>(
  Future<T> operation,
  Duration timeout,
  Object timeoutError, {
  Timer Function(Duration, void Function()) timerFactory = Timer.new,
}) {
  if (timeout <= Duration.zero) return Future<T>.error(timeoutError);
  final state = _RaceState<T>();
  Timer? timer;
  operation.then(
    state.complete,
    onError: (Object error, StackTrace stack) {
      state.completeError(error, stack);
    },
  );
  timer = timerFactory(timeout, () {
    state.completeError(timeoutError);
  });
  return state.future.whenComplete(() => timer?.cancel());
}

class _RaceState<T> {
  final completer = Completer<T>();
  bool settled = false;
  Future<T> get future => completer.future;

  void complete(T value) {
    if (settled) return;
    settled = true;
    completer.complete(value);
  }

  void completeError(Object error, [StackTrace? stack]) {
    if (settled) return;
    settled = true;
    completer.completeError(error, stack ?? StackTrace.empty);
  }
}

class _CleanupResult {
  _CleanupResult(this.error, this.stack);
  final Object? error;
  final StackTrace? stack;
}

Future<_CleanupResult> _captureCleanup(Future<void> operation) async {
  try {
    await operation;
    return _CleanupResult(null, null);
  } catch (error, stack) {
    return _CleanupResult(error, stack);
  }
}

Future<List<_CleanupResult>> _raceCleanup(
  Future<List<_CleanupResult>> operation,
  Duration timeout, {
  Timer Function(Duration, void Function()) timerFactory = Timer.new,
}) async {
  return _raceWithTimeout(
    operation,
    timeout,
    const RealtimeException('Realtime close timed out'),
    timerFactory: timerFactory,
  );
}

class _BoundedEventHub {
  _BoundedEventHub({required this.maxBytes, required this.maxCount}) {
    stream = Stream.multi(_listen, isBroadcast: true);
  }

  final int maxBytes;
  final int maxCount;
  late final Stream<RealtimeEvent> stream;
  final Set<_HubListener> _listeners = {};
  void Function(int bytes)? onAudioDropped;
  bool _closed = false;

  void _listen(MultiStreamController<RealtimeEvent> controller) {
    if (_closed) {
      controller.closeSync();
      return;
    }
    final listener = _HubListener(this, controller);
    _listeners.add(listener);
    controller.onPause = () {};
    controller.onResume = listener.drain;
    controller.onCancel = () {
      listener.cancelled = true;
      onAudioDropped?.call(listener.queuedAudioBytes);
      listener.queue.clear();
      listener.queuedBytes = 0;
      listener.queuedAudioBytes = 0;
      _listeners.remove(listener);
    };
  }

  bool add(RealtimeEvent event, {required int frameBytes, int audioBytes = 0}) {
    if (_closed) return false;
    var accepted = false;
    for (final listener in List<_HubListener>.of(_listeners)) {
      accepted |= listener.add(_HubItem.data(event, frameBytes, audioBytes));
    }
    return accepted;
  }

  void addError(Object error, StackTrace stack) {
    if (_closed) return;
    for (final listener in List<_HubListener>.of(_listeners)) {
      listener.add(_HubItem.error(error, stack));
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final listener in List<_HubListener>.of(_listeners)) {
      listener.closeAfterDrain();
    }
  }
}

class _HubItem {
  _HubItem.data(this.event, this.bytes, this.audioBytes)
    : error = null,
      stack = null;
  _HubItem.error(this.error, this.stack)
    : event = null,
      bytes = 1,
      audioBytes = 0;
  final RealtimeEvent? event;
  final Object? error;
  final StackTrace? stack;
  final int bytes;
  final int audioBytes;
}

class _HubListener {
  _HubListener(this.hub, this.controller);
  final _BoundedEventHub hub;
  final MultiStreamController<RealtimeEvent> controller;
  final List<_HubItem> queue = [];
  int queuedBytes = 0;
  int queuedAudioBytes = 0;
  bool cancelled = false;
  bool closing = false;

  bool add(_HubItem item) {
    if (cancelled || closing || !controller.hasListener) return false;
    if (controller.isPaused) {
      if (queue.length >= hub.maxCount ||
          item.bytes > hub.maxBytes - queuedBytes) {
        overflow();
        return false;
      }
      queue.add(item);
      queuedBytes += item.bytes;
      queuedAudioBytes += item.audioBytes;
      return true;
    }
    if (item.event != null) {
      controller.addSync(item.event!);
    } else {
      controller.addErrorSync(item.error!, item.stack);
    }
    return true;
  }

  void drain() {
    while (!cancelled && !controller.isPaused && queue.isNotEmpty) {
      final item = queue.removeAt(0);
      queuedBytes -= item.bytes;
      queuedAudioBytes -= item.audioBytes;
      if (item.event != null) {
        controller.addSync(item.event!);
      } else {
        controller.addErrorSync(item.error!, item.stack);
      }
    }
    if (!cancelled && closing && !controller.isPaused && queue.isEmpty) {
      controller.closeSync();
    }
  }

  void overflow() {
    if (cancelled || closing) return;
    hub.onAudioDropped?.call(queuedAudioBytes);
    queue.clear();
    queuedBytes = 0;
    queuedAudioBytes = 0;
    closing = true;
    queue.add(
      _HubItem.error(
        const RealtimeEventBufferOverflowException(),
        StackTrace.current,
      ),
    );
    queuedBytes = 1;
  }

  void closeAfterDrain() {
    if (cancelled || closing) return;
    closing = true;
    if (!controller.isPaused && queue.isEmpty) {
      controller.closeSync();
    }
  }
}
