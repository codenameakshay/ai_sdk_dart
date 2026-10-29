// Verification checks for package:ai_sdk_dart, text half (generateText,
// streamText, structured output, tools, approvals, agents, cancellation).
// See features/ai_sdk_dart-text.md.
//
// Most checks drive OpenAICompatibleChatLanguageModel over HTTP against a
// fixture that speaks the Chat Completions wire format. A few checks use a
// hand-written LanguageModelV4 where the Chat Completions format cannot
// express the stream shape; each one says why in a ctx.note.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _chatPath = '/v1/chat/completions';

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

OpenAICompatibleChatLanguageModel _model(
  CheckContext ctx,
  FixtureServer server, {
  List<LanguageModelV4Warning> warnings = const [],
}) => _modelAt(ctx, server.origin, warnings: warnings);

OpenAICompatibleChatLanguageModel _modelAt(
  CheckContext ctx,
  String origin, {
  List<LanguageModelV4Warning> warnings = const [],
}) {
  final baseUrl = '$origin/v1';
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  ctx.onCleanup(() async => dio.close(force: true));
  return OpenAICompatibleChatLanguageModel(
    modelId: 'verify-model',
    config: OpenAICompatibleConfig(
      provider: 'verify-compat',
      baseUrl: baseUrl,
      client: dio,
      headers: () => {'Authorization': 'Bearer verify-key'},
      warnings: warnings,
    ),
  );
}

typedef _Call = ({String id, String name, String args});

Map<String, Object?> _completion({
  String? content,
  List<_Call> toolCalls = const [],
  String finishReason = 'stop',
  int promptTokens = 11,
  int completionTokens = 7,
  Map<String, Object?> messageExtras = const {},
}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {
      'index': 0,
      'message': {
        'role': 'assistant',
        'content': content,
        if (toolCalls.isNotEmpty)
          'tool_calls': [
            for (final c in toolCalls)
              {
                'id': c.id,
                'type': 'function',
                'function': {'name': c.name, 'arguments': c.args},
              },
          ],
        ...messageExtras,
      },
      'finish_reason': finishReason,
    },
  ],
  'usage': {
    'prompt_tokens': promptTokens,
    'completion_tokens': completionTokens,
    'total_tokens': promptTokens + completionTokens,
  },
};

FixtureResponse _json(Map<String, Object?> body, {Map<String, String>? h}) =>
    FixtureResponse.json(body, headers: h ?? const {});

FixtureResponse _text(String content, {int p = 11, int c = 7}) =>
    _json(_completion(content: content, promptTokens: p, completionTokens: c));

FixtureResponse _calls(List<_Call> calls, {int p = 10, int c = 5}) => _json(
  _completion(
    toolCalls: calls,
    finishReason: 'tool_calls',
    promptTokens: p,
    completionTokens: c,
  ),
);

FixtureResponse _call(String id, String name, String args) =>
    _calls([(id: id, name: name, args: args)]);

Map<String, Object?> _chunk(Map<String, Object?> delta, {String? finish}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion.chunk',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

Map<String, Object?> _usageChunk(int p, int c) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion.chunk',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': <Object>[],
  'usage': {'prompt_tokens': p, 'completion_tokens': c, 'total_tokens': p + c},
};

List<Object> _sseTextEvents(
  List<String> parts, {
  int p = 5,
  int c = 3,
  bool finish = true,
}) => [
  _chunk({'role': 'assistant', 'content': ''}),
  for (final part in parts) _chunk({'content': part}),
  if (finish) ...[_chunk({}, finish: 'stop'), _usageChunk(p, c)],
];

FixtureResponse _sseText(
  List<String> parts, {
  int p = 5,
  int c = 3,
  bool finish = true,
}) => FixtureResponse.sse(
  _sseTextEvents(parts, p: p, c: c, finish: finish),
  done: true,
);

/// A loopback SSE server that sends one event per [gap], flushes each one to
/// the socket, and reports whether the client closed the connection early.
///
/// FixtureResponse.sse(delay:) cannot do this. The harness fixture server
/// keeps dart:io response buffering on, so a delayed stream reaches the
/// client in one piece when it ends, and dart:io's HttpServer hides a client
/// that hung up. This helper speaks HTTP/1.1 chunked on a raw socket and
/// records the exchange in the check's evidence.
class _PacedSseServer {
  _PacedSseServer._(this._server);

  final ServerSocket _server;
  final List<Socket> _sockets = [];

  /// Events written to the socket so far (including the final [DONE]).
  int sent = 0;

  /// True when the client closed the connection before the stream ended.
  bool clientClosedEarly = false;
  bool _finished = false;
  final Completer<void> closedEarly = Completer<void>();

  String get origin => 'http://127.0.0.1:${_server.port}';

  static Future<_PacedSseServer> start(
    CheckContext ctx,
    List<Object> events,
    Duration gap,
  ) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final paced = _PacedSseServer._(server);
    ctx.onCleanup(() async {
      for (final socket in paced._sockets) {
        socket.destroy();
      }
      await server.close();
    });
    server.listen((socket) {
      paced._sockets.add(socket);
      final received = BytesBuilder();
      var handled = false;
      socket.listen(
        (bytes) {
          if (handled) return;
          received.add(bytes);
          final request = _parseRequest(received.toBytes());
          if (request == null) return;
          handled = true;
          ctx.exchanges.add(request.exchange);
          unawaited(paced._respond(socket, request.exchange, events, gap));
        },
        onDone: () {
          if (!paced._finished && !paced.closedEarly.isCompleted) {
            paced.clientClosedEarly = true;
            paced.closedEarly.complete();
          }
        },
        onError: (Object _) {},
      );
    });
    return paced;
  }

  Future<void> _respond(
    Socket socket,
    Exchange exchange,
    List<Object> events,
    Duration gap,
  ) async {
    exchange
      ..status = 200
      ..responseContentType = 'text/event-stream';
    try {
      socket.add(
        ascii.encode(
          'HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n'
          'cache-control: no-cache\r\ntransfer-encoding: chunked\r\n\r\n',
        ),
      );
      for (final event in [...events, '[DONE]']) {
        await Future<void>.delayed(gap);
        if (clientClosedEarly) break;
        final payload = utf8.encode(SseEvent(event).encode());
        socket.add(ascii.encode('${payload.length.toRadixString(16)}\r\n'));
        socket.add(payload);
        socket.add(ascii.encode('\r\n'));
        await socket.flush();
        sent++;
        exchange.responseBody = '<$sent events written>';
      }
      if (!clientClosedEarly) {
        _finished = true;
        socket.add(ascii.encode('0\r\n\r\n'));
        await socket.flush();
        await socket.close();
      }
    } catch (_) {
      // A write after the client hung up fails; that is the expected end.
    }
    exchange.responseBody =
        '<$sent of ${events.length + 1} events written; client closed early: '
        '$clientClosedEarly>';
  }
}

({Exchange exchange})? _parseRequest(List<int> bytes) {
  final text = latin1.decode(bytes);
  final headerEnd = text.indexOf('\r\n\r\n');
  if (headerEnd < 0) return null;
  final lines = text.substring(0, headerEnd).split('\r\n');
  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final colon = line.indexOf(':');
    if (colon > 0) {
      headers[line.substring(0, colon).trim().toLowerCase()] = line
          .substring(colon + 1)
          .trim();
    }
  }
  final length = int.tryParse(headers['content-length'] ?? '') ?? 0;
  final bodyStart = headerEnd + 4;
  if (bytes.length - bodyStart < length) return null;
  final body = utf8.decode(bytes.sublist(bodyStart, bodyStart + length));
  final parts = lines.first.split(' ');
  return (
    exchange: Exchange(
      source: 'fixture',
      method: parts[0],
      url: parts[1],
      requestHeaders: redactHeaders(headers),
      requestBody: body.isEmpty ? null : jsonDecode(body),
    ),
  );
}

FixtureResponse _sseCall(
  String id,
  String name,
  List<String> argParts, {
  int p = 5,
  int c = 3,
}) => FixtureResponse.sse([
  _chunk({
    'role': 'assistant',
    'tool_calls': [
      {
        'index': 0,
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': ''},
      },
    ],
  }),
  for (final part in argParts)
    _chunk({
      'tool_calls': [
        {
          'index': 0,
          'function': {'arguments': part},
        },
      ],
    }),
  _chunk({}, finish: 'tool_calls'),
  _usageChunk(p, c),
], done: true);

/// Answers request N with responses[N]; the last response repeats.
FixtureHandler _sequence(List<FixtureResponse> responses) =>
    (request) =>
        responses[request.index < responses.length
            ? request.index
            : responses.length - 1];

List<FixtureRequest> _chatRequests(CheckContext ctx, FixtureServer server) =>
    ctx.requestsTo(server, _chatPath, method: 'POST');

List<Map<String, dynamic>> _messages(FixtureRequest request) =>
    (request.jsonObject['messages'] as List).cast<Map<String, dynamic>>();

List<String> _roles(FixtureRequest request) => [
  for (final m in _messages(request)) m['role'] as String,
];

class _Drain<T> {
  _Drain(Stream<T> stream) {
    stream.listen(
      items.add,
      onError: (Object e, StackTrace _) => errors.add(e),
      onDone: _done.complete,
    );
  }
  final List<T> items = [];
  final List<Object> errors = [];
  final Completer<void> _done = Completer<void>();
  Future<void> get done => _done.future;
}

String _eventName(StreamTextEvent event) => '${event.runtimeType}'
    .replaceFirst('StreamText', '')
    .replaceFirst(RegExp(r'Event(<.*>)?$'), '');

String _toolText(LanguageModelV4ToolResultPart part) =>
    (part.output as ToolResultOutputText).text;

// ---------------------------------------------------------------------------
// Tools and schemas
// ---------------------------------------------------------------------------

class _Weather {
  _Weather(this.city);
  factory _Weather.fromJson(Map<String, dynamic> json) =>
      _Weather(json['city'] as String);
  final String city;
}

const _weatherJsonSchema = {
  'type': 'object',
  'properties': {
    'city': {'type': 'string'},
  },
  'required': ['city'],
  'additionalProperties': false,
};

final _weatherSchema = Schema<_Weather>(
  jsonSchema: _weatherJsonSchema,
  fromJson: _Weather.fromJson,
);

Tool<_Weather, String> _weatherTool({
  void Function(_Weather input, ToolExecutionOptions options)? onRun,
  bool? strict,
  ToolNeedsApproval<_Weather>? needsApproval,
  ToolApprovalPolicy? approvalPolicy,
  Duration? delay,
}) => tool<_Weather, String>(
  description: 'Get current weather for a city.',
  inputSchema: _weatherSchema,
  strict: strict,
  needsApproval: needsApproval,
  approvalPolicy: approvalPolicy,
  execute: (input, options) async {
    onRun?.call(input, options);
    if (delay != null) await Future<void>.delayed(delay);
    return 'Sunny, 18C in ${input.city}';
  },
);

// ---------------------------------------------------------------------------
// Hand-written LanguageModelV4 for shapes Chat Completions cannot express
// ---------------------------------------------------------------------------

class _ScriptedModel extends LanguageModelV4 {
  _ScriptedModel({this.generates = const [], this.streams = const []});

  final List<LanguageModelV4GenerateResult> generates;
  final List<List<LanguageModelV4StreamPart>> streams;
  final List<LanguageModelV4CallOptions> calls = [];

  @override
  String get provider => 'verify-scripted';

  @override
  String get modelId => 'scripted-1';

  @override
  Future<LanguageModelV4GenerateResult> doGenerate(
    LanguageModelV4CallOptions options,
  ) async {
    calls.add(options);
    return generates[calls.length - 1];
  }

  @override
  Future<LanguageModelV4StreamResult> doStream(
    LanguageModelV4CallOptions options,
  ) async {
    calls.add(options);
    return LanguageModelV4StreamResult(
      stream: Stream.fromIterable(streams[calls.length - 1]),
    );
  }
}

const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==';

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

final List<Check> textChecks = [
  // ----- generateText: result envelope -----------------------------------
  Check(
    id: 'generate-text-envelope',
    feature: 'text-generate',
    description:
        'generateText sends the sampling settings and headers on the wire and '
        'returns text, content, steps, usage, finish reason, request and '
        'response metadata.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _json(
          _completion(content: 'Hello from the fixture.'),
          h: {'x-request-id': 'req-77'},
        ),
      );
      final result = await generateText(
        model: _model(ctx, server),
        system: 'Be brief.',
        prompt: 'Say hello.',
        maxOutputTokens: 64,
        temperature: 0.2,
        topP: 0.9,
        presencePenalty: 0.1,
        frequencyPenalty: 0.2,
        stopSequences: const ['END'],
        seed: 42,
        headers: const {'x-verify-trace': 'trace-1'},
      );
      final request = ctx.singleRequest(server, _chatPath, method: 'POST');
      final body = request.jsonObject;
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(
        request.headers['x-verify-trace'],
        'trace-1',
        'per-call header',
      );
      ctx.expectEquals(body['model'], 'verify-model', 'model');
      ctx.expectEquals(body['max_completion_tokens'], 64, 'max tokens');
      ctx.expectEquals(body['temperature'], 0.2, 'temperature');
      ctx.expectEquals(body['top_p'], 0.9, 'top_p');
      ctx.expectEquals(body['presence_penalty'], 0.1, 'presence_penalty');
      ctx.expectEquals(body['frequency_penalty'], 0.2, 'frequency_penalty');
      ctx.expectEquals(body['stop'], ['END'], 'stop');
      ctx.expectEquals(body['seed'], 42, 'seed');
      ctx.expectEquals(_roles(request), ['system', 'user'], 'roles');

      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      ctx.observe('finishReason', result.finishReason);
      ctx.expectEquals(result.text, 'Hello from the fixture.', 'text');
      ctx.expectEquals(result.content.length, 1, 'content parts');
      ctx.expect(
        result.content.single is LanguageModelV4TextPart,
        'content is not a text part',
      );
      ctx.expectEquals(result.steps.length, 1, 'steps');
      ctx.expectEquals(result.finalStep.text, result.text, 'finalStep.text');
      ctx.expectEquals(result.usage?.inputTokens.total, 11, 'usage input');
      ctx.expectEquals(result.usage?.outputTokens.total, 7, 'usage output');
      ctx.expectEquals(result.totalUsage?.inputTokens.total, 11, 'total in');
      ctx.expectEquals(
        result.finishReason,
        LanguageModelV4FinishReason.stop,
        'finish',
      );
      ctx.expectEquals(result.rawFinishReason, 'stop', 'raw finish reason');
      ctx.expectEquals(
        result.responseInfo.metadata?.id,
        'chatcmpl-verify',
        'response id',
      );
      ctx.expectEquals(
        result.responseInfo.metadata?.modelId,
        'verify-model',
        'response model',
      );
      ctx.expectEquals(
        result.responseInfo.metadata?.headers?['x-request-id'],
        'req-77',
        'response header',
      );
      ctx.expectEquals(result.request.system, 'Be brief.', 'request.system');
      ctx.expectEquals(result.requestMessages.length, 1, 'requestMessages');
      ctx.expectEquals(result.responseMessages.length, 1, 'responseMessages');
      ctx.expectEquals(
        result.responseMessages.single.role,
        LanguageModelV4Role.assistant,
        'response message role',
      );
      ctx.expectEquals(result.warnings, <Object>[], 'warnings');
      ctx.expectEquals(result.toolCalls, <Object>[], 'toolCalls');
    },
  ),
  Check(
    id: 'generate-body-inclusion',
    feature: 'text-generate',
    description:
        'Request and response bodies are omitted by default and retained '
        'only when BodyInclusionPolicy asks for them.',
    run: (ctx) async {
      final server = await ctx.server((_) => _text('ok'));
      final model = _model(ctx, server);
      final omitted = await generateText(model: model, prompt: 'hi');
      ctx.expect(omitted.request.body == null, 'request body kept by default');
      ctx.expect(
        omitted.responseInfo.body == null,
        'response body kept by default',
      );
      ctx.expect(
        omitted.response?.response?.body == null,
        'metadata body kept by default',
      );
      final kept = await generateText(
        model: model,
        prompt: 'hi',
        bodyInclusion: const BodyInclusionPolicy.all(),
      );
      final requestBody = kept.request.body as Map?;
      final responseBody = kept.responseInfo.body as Map?;
      ctx.observe('requestBody', requestBody);
      ctx.observe('responseBody', responseBody);
      ctx.expectEquals(
        requestBody?['model'],
        'verify-model',
        'request body model',
      );
      ctx.expectEquals(
        responseBody?['id'],
        'chatcmpl-verify',
        'response body id',
      );
      ctx.expectEquals(_chatRequests(ctx, server).length, 2, 'request count');
    },
  ),
  Check(
    id: 'generate-finish-reasons',
    feature: 'text-generate',
    description:
        'length, content_filter and unknown finish reasons surface as typed '
        'finish reasons with the raw provider value kept.',
    run: (ctx) async {
      final raw = ['length', 'content_filter', 'vendor_specific'];
      final server = await ctx.server(
        _sequence([
          for (final r in raw)
            _json(_completion(content: 'partial', finishReason: r)),
        ]),
      );
      final model = _model(ctx, server);
      final seen = <String, Object?>{};
      for (final r in raw) {
        final result = await generateText(model: model, prompt: 'go');
        seen[r] = '${result.finishReason}';
        ctx.expectEquals(result.rawFinishReason, r, 'raw finish reason');
      }
      ctx.observe('finishReasons', seen);
      ctx.expect(
        seen['length'] == '${LanguageModelV4FinishReason.length}',
        'length not mapped',
      );
      ctx.expect(
        seen['content_filter'] ==
            '${LanguageModelV4FinishReason.contentFilter}',
        'content_filter not mapped',
      );
      ctx.expect(
        seen['vendor_specific'] == '${LanguageModelV4FinishReason.other}',
        'unknown reason not mapped to other',
      );
    },
  ),

  // ----- instructions and messages ---------------------------------------
  Check(
    id: 'instructions-precedence',
    feature: 'text-instructions',
    description:
        'instructions beats the deprecated system parameter, system-role '
        'messages are rejected unless allowSystemInMessages is set.',
    run: (ctx) async {
      final server = await ctx.server((_) => _text('ok'));
      final model = _model(ctx, server);
      await generateText(
        model: model,
        instructions: 'Use instructions.',
        system: 'Ignored system.',
        prompt: 'hi',
      );
      await generateText(model: model, system: 'Legacy system.', prompt: 'hi');
      final rejected = await ctx.expectThrows<ArgumentError>(
        () => generateText(
          model: model,
          messages: const [
            ModelMessage(role: ModelMessageRole.system, content: 'sneaky'),
            ModelMessage(role: ModelMessageRole.user, content: 'hi'),
          ],
        ),
        'system-role message',
      );
      ctx.expect(
        '${rejected.message}'.contains('allowSystemInMessages'),
        'rejection does not name allowSystemInMessages',
      );
      await generateText(
        model: model,
        allowSystemInMessages: true,
        messages: const [
          ModelMessage(role: ModelMessageRole.system, content: 'trusted'),
          ModelMessage(role: ModelMessageRole.user, content: 'hi'),
        ],
      );
      final requests = _chatRequests(ctx, server);
      ctx.expectEquals(
        requests.length,
        3,
        'requests (rejected call sends none)',
      );
      ctx.expectEquals(
        _messages(requests[0]).first['content'],
        'Use instructions.',
        'instructions win',
      );
      ctx.expectEquals(
        _messages(requests[1]).first['content'],
        'Legacy system.',
        'system fallback',
      );
      ctx.expectEquals(_roles(requests[2]), [
        'system',
        'user',
      ], 'allowed system message');
      ctx.expectEquals(
        '${_messages(requests[2]).first['content']}'.contains('trusted'),
        true,
        'allowed system text',
      );
    },
  ),
  Check(
    id: 'message-roles',
    feature: 'text-messages',
    description:
        'user, assistant and tool ModelMessages (text and parts) reach the '
        'wire as the matching Chat Completions roles, and ModelMessage.text '
        'joins the text parts.',
    run: (ctx) async {
      final server = await ctx.server((_) => _text('ok'));
      const toolCall = LanguageModelV4ToolCallPart(
        toolCallId: 'call_hist_1',
        toolName: 'getWeather',
        input: {'city': 'Oslo'},
      );
      final messages = [
        const ModelMessage(role: ModelMessageRole.user, content: 'Hi'),
        const ModelMessage(role: ModelMessageRole.assistant, content: 'Hello!'),
        const ModelMessage(role: ModelMessageRole.user, content: 'Weather?'),
        ModelMessage.parts(
          role: ModelMessageRole.assistant,
          parts: const [toolCall],
        ),
        ModelMessage.parts(
          role: ModelMessageRole.tool,
          parts: const [
            LanguageModelV4ToolResultPart(
              toolCallId: 'call_hist_1',
              toolName: 'getWeather',
              output: ToolResultOutputText('Snow, -3C'),
            ),
          ],
        ),
        const ModelMessage(role: ModelMessageRole.user, content: 'Thanks'),
      ];
      await generateText(model: _model(ctx, server), messages: messages);
      final request = ctx.singleRequest(server, _chatPath);
      final wire = _messages(request);
      ctx.observe('roles', _roles(request));
      ctx.expectEquals(_roles(request), [
        'user',
        'assistant',
        'user',
        'assistant',
        'tool',
        'user',
      ], 'wire roles');
      final assistantCall = (wire[3]['tool_calls'] as List).single as Map;
      ctx.expectEquals(assistantCall['id'], 'call_hist_1', 'replayed call id');
      ctx.expectEquals(
        jsonDecode((assistantCall['function'] as Map)['arguments'] as String),
        {'city': 'Oslo'},
        'replayed call arguments',
      );
      ctx.expectEquals(wire[4]['tool_call_id'], 'call_hist_1', 'tool_call_id');
      ctx.expectEquals(wire[4]['content'], 'Snow, -3C', 'tool content');
      ctx.expectEquals(messages[0].text, 'Hi', 'text of content message');
      final mixed = ModelMessage.parts(
        role: ModelMessageRole.user,
        parts: [
          const LanguageModelV4TextPart(text: 'one '),
          LanguageModelV4ImagePart(
            image: DataContentUrl(Uri.parse('https://example.com/a.png')),
          ),
          const LanguageModelV4TextPart(text: 'two'),
        ],
      );
      ctx.expectEquals(mixed.text, 'one two', 'text joins text parts only');
      ctx.expectEquals(messages[3].text, '', 'tool-call message has no text');
    },
  ),
  Check(
    id: 'multimodal-image',
    feature: 'text-multimodal',
    description:
        'A user message with text, image bytes and an image URL is sent as '
        'Chat Completions content parts.',
    run: (ctx) async {
      final server = await ctx.server((_) => _text('A pixel.'));
      final result = await generateText(
        model: _model(ctx, server),
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [
              const LanguageModelV4TextPart(text: 'Describe these.'),
              LanguageModelV4ImagePart(
                image: DataContentBytes(base64Decode(_onePixelPng)),
                mediaType: 'image/png',
              ),
              LanguageModelV4ImagePart(
                image: DataContentUrl(Uri.parse('https://example.com/cat.jpg')),
              ),
            ],
          ),
        ],
      );
      final content =
          (_messages(ctx.singleRequest(server, _chatPath)).single['content']
                  as List)
              .cast<Map<String, dynamic>>();
      ctx.observe('contentTypes', [for (final p in content) p['type']]);
      ctx.expectEquals(
        [for (final p in content) p['type']],
        ['text', 'image_url', 'image_url'],
        'content part types',
      );
      ctx.expectEquals(content[0]['text'], 'Describe these.', 'text part');
      ctx.expectEquals(
        (content[1]['image_url'] as Map)['url'],
        'data:image/png;base64,$_onePixelPng',
        'image bytes as data URI',
      );
      ctx.expectEquals(
        (content[2]['image_url'] as Map)['url'],
        'https://example.com/cat.jpg',
        'image URL',
      );
      ctx.expectEquals(result.text, 'A pixel.', 'text');
    },
  ),

  // ----- reasoning, sources, files, metadata -----------------------------
  Check(
    id: 'generate-reasoning',
    feature: 'text-content',
    description:
        'reasoning_content in a Chat Completions reply is surfaced as '
        'reasoning parts and reasoningText, ahead of the text.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _json(
          _completion(
            content: '42.',
            messageExtras: {'reasoning_content': 'Add six and seven first.'},
          ),
        ),
      );
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Six times seven?',
        reasoning: LanguageModelV4Reasoning.high,
      );
      ctx.observe('reasoningText', result.reasoningText);
      ctx.expectEquals(
        result.reasoningText,
        'Add six and seven first.',
        'reasoningText',
      );
      ctx.expectEquals(result.reasoning.length, 1, 'reasoning parts');
      ctx.expectEquals(result.text, '42.', 'text excludes reasoning');
      ctx.expect(
        result.content.first is LanguageModelV4ReasoningPart,
        'reasoning is not first',
      );
      ctx.expectEquals(
        result.finalStep.reasoningText,
        'Add six and seven first.',
        'step reasoningText',
      );
    },
  ),
  Check(
    id: 'generate-result-parts',
    feature: 'text-content',
    description:
        'Sources, document sources, files, reasoning files, warnings, '
        'provider metadata and call options travel unchanged between the '
        'model and the generateText result.',
    run: (ctx) async {
      ctx.note(
        'Hand-written LanguageModelV4: the Chat Completions adapter maps '
        'annotations itself and returns no provider metadata, so it cannot '
        'isolate the core aggregation of these parts.',
      );
      final model = _ScriptedModel(
        generates: [
          LanguageModelV4GenerateResult(
            content: const [
              LanguageModelV4ReasoningPart(text: 'Plan.', signature: 'sig-1'),
              LanguageModelV4TextPart(text: 'Final answer.'),
              LanguageModelV4SourcePart(
                id: 'src-1',
                url: 'https://example.com/a',
                title: 'Example A',
              ),
              LanguageModelV4DocumentSourcePart(
                id: 'doc-1',
                mediaType: 'application/pdf',
                title: 'Manual',
                filename: 'manual.pdf',
              ),
              LanguageModelV4FilePart(
                data: DataContentBase64('QQ=='),
                mediaType: 'text/plain',
                filename: 'a.txt',
              ),
              LanguageModelV4ReasoningFilePart(
                data: DataContentBase64('Qg=='),
                mediaType: 'image/png',
              ),
            ],
            finishReason: LanguageModelV4FinishReason.stop,
            rawFinishReason: 'end_turn',
            usage: const LanguageModelV4Usage(
              inputTokens: LanguageModelV4InputTokenUsage(total: 3),
              outputTokens: LanguageModelV4OutputTokenUsage(total: 4),
            ),
            warnings: const [
              LanguageModelV4UnsupportedWarning(
                feature: 'topK',
                details: 'ignored',
              ),
            ],
            request: const LanguageModelV4RequestMetadata(body: {'sent': true}),
            response: LanguageModelV4ResponseMetadata(
              id: 'resp-9',
              modelId: 'scripted-1',
              timestamp: DateTime.utc(2026, 1, 2),
              headers: const {'x-h': '1'},
              body: const {'raw': 1},
            ),
            providerMetadata: const {
              'verify': {'cache': 'hit'},
            },
          ),
        ],
      );
      final result = await generateText(
        model: model,
        instructions: 'Rules.',
        prompt: 'hi',
        reasoning: LanguageModelV4Reasoning.high,
        topK: 5,
        providerOptions: const {
          'verify': {'mode': 'x'},
        },
        bodyInclusion: const BodyInclusionPolicy.all(),
      );
      final options = model.calls.single;
      ctx.expectEquals(
        options.reasoning,
        LanguageModelV4Reasoning.high,
        'reasoning option',
      );
      ctx.expectEquals(options.topK, 5, 'topK option');
      ctx.expectEquals(options.providerOptions, {
        'verify': {'mode': 'x'},
      }, 'providerOptions');
      ctx.expectEquals(options.prompt.system, 'Rules.', 'system');
      ctx.expectEquals(result.text, 'Final answer.', 'text');
      ctx.expectEquals(
        result.reasoning.single.signature,
        'sig-1',
        'reasoning signature',
      );
      ctx.expectEquals(
        result.sources.single.url,
        'https://example.com/a',
        'source url',
      );
      ctx.expectEquals(
        result.sources.single.title,
        'Example A',
        'source title',
      );
      ctx.expectEquals(
        result.documentSources.single.filename,
        'manual.pdf',
        'document source',
      );
      ctx.expectEquals(result.files.single.filename, 'a.txt', 'file');
      ctx.expectEquals(
        result.reasoningFiles.single.mediaType,
        'image/png',
        'reasoning file',
      );
      ctx.expectEquals(result.rawFinishReason, 'end_turn', 'raw finish reason');
      ctx.expectEquals(
        result.warnings.single.type,
        'unsupported',
        'warning type',
      );
      ctx.expectEquals(result.providerMetadata, {
        'verify': {'cache': 'hit'},
      }, 'providerMetadata');
      ctx.expectEquals(
        result.finalStep.providerMetadata,
        result.providerMetadata,
        'step providerMetadata',
      );
      ctx.expectEquals(
        result.responseInfo.metadata?.id,
        'resp-9',
        'response id',
      );
      ctx.expectEquals(result.response?.request?.body, {
        'sent': true,
      }, 'request metadata body');
      ctx.observe(
        'content',
        result.content.map((p) => p.runtimeType.toString()).toList(),
      );
    },
  ),
  Check(
    id: 'generate-warnings',
    feature: 'text-content',
    description:
        'Warnings configured on the model adapter are returned on the '
        'generateText result and on each step.',
    run: (ctx) async {
      final server = await ctx.server((_) => _text('ok'));
      final result = await generateText(
        model: _model(
          ctx,
          server,
          warnings: const [
            LanguageModelV4CompatibilityWarning(
              feature: 'verify-feature',
              details: 'not qualified',
            ),
          ],
        ),
        prompt: 'hi',
      );
      ctx.observe('warnings', result.warnings.map((w) => w.type).toList());
      ctx.expectEquals(result.warnings.length, 1, 'warnings');
      final warning =
          result.warnings.single as LanguageModelV4CompatibilityWarning;
      ctx.expectEquals(warning.feature, 'verify-feature', 'warning feature');
      ctx.expectEquals(result.steps.single.warnings.length, 1, 'step warnings');
    },
  ),

  // ----- streamText ------------------------------------------------------
  Check(
    id: 'stream-text-basic',
    feature: 'text-stream',
    description:
        'streamText sends stream=true, yields text deltas in order, and the '
        'result futures resolve text, usage, finish reason, steps and '
        'response metadata.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _sseText(['One, ', 'two, ', 'three.'], p: 5, c: 3),
      );
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Count to three.',
        maxOutputTokens: 32,
      );
      final deltas = _Drain(result.textStream);
      final text = await result.text;
      await deltas.done;
      final body = ctx.singleRequest(server, _chatPath).jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(body['stream_options'], {
        'include_usage': true,
      }, 'stream_options');
      ctx.expectEquals(body['max_completion_tokens'], 32, 'max tokens');
      ctx.observe('deltas', deltas.items);
      ctx.expectEquals(deltas.items, [
        'One, ',
        'two, ',
        'three.',
      ], 'text deltas');
      ctx.expectEquals(text, 'One, two, three.', 'text future');
      final usage = await result.usage;
      ctx.expectEquals(usage?.inputTokens.total, 5, 'usage input');
      ctx.expectEquals(
        (await result.totalUsage)?.outputTokens.total,
        3,
        'totalUsage output',
      );
      ctx.expectEquals(
        await result.finishReason,
        LanguageModelV4FinishReason.stop,
        'finish reason',
      );
      ctx.expectEquals(
        await result.rawFinishReason,
        'stop',
        'raw finish reason',
      );
      ctx.expectEquals((await result.steps).length, 1, 'steps');
      ctx.expectEquals((await result.finalStep).text, text, 'finalStep text');
      ctx.expectEquals(
        (await result.content).whereType<LanguageModelV4TextPart>().single.text,
        text,
        'content',
      );
      ctx.expectEquals(
        (await result.response).metadata?.id,
        'chatcmpl-verify',
        'response id',
      );
      ctx.expectEquals(
        (await result.response).messages.length,
        1,
        'response messages',
      );
      ctx.expectEquals(
        (await result.request).messages.length,
        1,
        'request messages',
      );
      ctx.expectEquals(await result.warnings, <Object>[], 'warnings');
      ctx.expectEquals(await result.output, text, 'output');
      final providerMetadata = await result.providerMetadata;
      ctx.observe('providerMetadata', providerMetadata);
      ctx.expectEquals(
        (providerMetadata?['verify-compat'] as Map?)?['id'],
        'chatcmpl-verify',
        'provider metadata id',
      );
    },
  ),
  Check(
    id: 'stream-event-taxonomy',
    feature: 'text-stream',
    description:
        'result.stream emits the typed lifecycle events in order, '
        'providerStream emits provider parts, and fullStream is the same '
        'stream as stream.',
    run: (ctx) async {
      final server = await ctx.server((_) => _sseText(['Hel', 'lo']));
      final result = await streamText(model: _model(ctx, server), prompt: 'hi');
      final events = _Drain(result.stream);
      final provider = _Drain(result.providerStream);
      // ignore: deprecated_member_use
      final alias = result.fullStream;
      ctx.expect(identical(result.stream, alias), 'fullStream is not stream');
      await result.text;
      await events.done;
      await provider.done;
      final names = events.items.map(_eventName).toList();
      ctx.observe('events', names);
      ctx.observe(
        'providerParts',
        provider.items.map((p) => '${p.runtimeType}').toList(),
      );
      ctx.expectEquals(names, [
        'Start',
        'StartStep',
        'TextStart',
        'TextDelta',
        'TextDelta',
        'TextEnd',
        'Usage',
        'FinishStep',
        'Finish',
      ], 'event order');
      final finish = events.items.last as StreamTextFinishEvent;
      ctx.expectEquals(finish.text, 'Hello', 'finish text');
      ctx.expectEquals(
        finish.finishReason,
        LanguageModelV4FinishReason.stop,
        'finish reason',
      );
      ctx.expectEquals(finish.steps.length, 1, 'finish steps');
      ctx.expectEquals(finish.finalStep.text, 'Hello', 'finish finalStep');
      final deltas = events.items
          .whereType<StreamTextTextDeltaEvent>()
          .map((e) => e.delta)
          .toList();
      ctx.expectEquals(deltas, ['Hel', 'lo'], 'delta payloads');
      final partNames = provider.items.map((p) => '${p.runtimeType}').toSet();
      ctx.expect(
        partNames.contains('StreamPartTextDelta'),
        'providerStream lacks text deltas',
      );
      ctx.expect(
        partNames.contains('StreamPartFinish'),
        'providerStream lacks finish',
      );
    },
  ),
  Check(
    id: 'stream-raw-chunks',
    feature: 'text-stream',
    description:
        'Raw provider chunks reach the stream only when includeRawChunks '
        'is set.',
    run: (ctx) async {
      final server = await ctx.server((_) => _sseText(['a', 'b']));
      final model = _model(ctx, server);
      final plain = await streamText(model: model, prompt: 'hi');
      final plainEvents = _Drain(plain.stream);
      await plain.text;
      await plainEvents.done;
      final raw = await streamText(
        model: model,
        prompt: 'hi',
        includeRawChunks: true,
      );
      final rawEvents = _Drain(raw.stream);
      await raw.text;
      await rawEvents.done;
      final rawValues = rawEvents.items
          .whereType<StreamTextRawEvent>()
          .toList();
      ctx.observe('rawChunkCount', rawValues.length);
      ctx.expectEquals(
        plainEvents.items.whereType<StreamTextRawEvent>().length,
        0,
        'raw events by default',
      );
      ctx.expect(
        rawValues.length >= 4,
        'expected one raw event per SSE chunk, got ${rawValues.length}',
      );
      ctx.expectEquals(
        (rawValues.first.rawValue as Map)['object'],
        'chat.completion.chunk',
        'raw chunk payload',
      );
    },
  ),
  Check(
    id: 'stream-reasoning',
    feature: 'text-content',
    description:
        'Streamed reasoning_content becomes reasoning start, delta and end '
        'events before the text, and the reasoning futures resolve.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _chunk({'role': 'assistant', 'content': ''}),
          _chunk({'reasoning_content': 'Think '}),
          _chunk({'reasoning_content': 'hard.'}),
          _chunk({'content': 'Done.'}),
          _chunk({}, finish: 'stop'),
          _usageChunk(4, 6),
        ], done: true),
      );
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'hi',
        reasoning: LanguageModelV4Reasoning.medium,
      );
      final events = _Drain(result.stream);
      await result.text;
      await events.done;
      final names = events.items.map(_eventName).toList();
      ctx.observe('events', names);
      final firstText = names.indexOf('TextStart');
      ctx.expect(
        names.contains('ReasoningStart') &&
            names.indexOf('ReasoningStart') < firstText,
        'reasoning does not precede text',
      );
      ctx.expectEquals(
        names.where((n) => n == 'ReasoningDelta').length,
        2,
        'reasoning deltas',
      );
      ctx.expect(names.contains('ReasoningEnd'), 'no reasoning end');
      ctx.expectEquals(
        await result.reasoningText,
        'Think hard.',
        'reasoningText',
      );
      ctx.expectEquals((await result.reasoning).length, 1, 'reasoning parts');
      ctx.expectEquals(await result.text, 'Done.', 'text');
    },
  ),
  Check(
    id: 'stream-result-parts',
    feature: 'text-content',
    description:
        'Sources, document sources, files, reasoning files, warnings, raw '
        'finish reason and provider metadata from a stream resolve on the '
        'result futures and as typed events.',
    run: (ctx) async {
      ctx.note(
        'Hand-written LanguageModelV4: Chat Completions streams cannot carry '
        'document sources, reasoning files or provider metadata.',
      );
      final model = _ScriptedModel(
        streams: [
          [
            const StreamPartStreamStart(
              warnings: [
                LanguageModelV4OtherWarning(message: 'stream-warning'),
              ],
            ),
            const StreamPartReasoningStart(id: 'r1'),
            const StreamPartReasoningDelta(id: 'r1', delta: 'Why. '),
            const StreamPartReasoningEnd(id: 'r1', signature: 'sig-s'),
            const StreamPartTextStart(id: 't1'),
            const StreamPartTextDelta(id: 't1', delta: 'Answer.'),
            const StreamPartTextEnd(id: 't1'),
            const StreamPartSource(
              source: LanguageModelV4SourcePart(
                id: 's1',
                url: 'https://example.com/s',
                title: 'S',
              ),
            ),
            const StreamPartDocumentSource(
              source: LanguageModelV4DocumentSourcePart(
                id: 'd1',
                mediaType: 'application/pdf',
                title: 'Doc',
              ),
            ),
            const StreamPartFile(
              file: LanguageModelV4FilePart(
                data: DataContentBase64('QQ=='),
                mediaType: 'text/plain',
                filename: 'f.txt',
              ),
            ),
            const StreamPartReasoningFile(
              file: LanguageModelV4ReasoningFilePart(
                data: DataContentBase64('Qg=='),
                mediaType: 'image/png',
              ),
            ),
            StreamPartResponseMetadata(
              metadata: LanguageModelV4ResponseMetadata(
                id: 'resp-s1',
                modelId: 'scripted-1',
              ),
            ),
            const StreamPartFinish(
              finishReason: LanguageModelV4FinishReason.stop,
              rawFinishReason: 'end_turn',
              usage: LanguageModelV4Usage(
                inputTokens: LanguageModelV4InputTokenUsage(total: 8),
                outputTokens: LanguageModelV4OutputTokenUsage(total: 2),
              ),
              providerMetadata: {
                'verify': {'cache': 'miss'},
              },
            ),
          ],
        ],
      );
      final result = await streamText(model: model, prompt: 'hi');
      final events = _Drain(result.stream);
      await result.text;
      await events.done;
      final names = events.items.map(_eventName).toSet();
      for (final expected in [
        'Source',
        'DocumentSource',
        'File',
        'ReasoningFile',
      ]) {
        ctx.expect(names.contains(expected), 'missing $expected event');
      }
      ctx.expectEquals(
        (await result.sources).single.url,
        'https://example.com/s',
        'sources',
      );
      ctx.expectEquals(
        (await result.documentSources).single.title,
        'Doc',
        'documentSources',
      );
      ctx.expectEquals((await result.files).single.filename, 'f.txt', 'files');
      ctx.expectEquals(
        (await result.reasoningFiles).single.mediaType,
        'image/png',
        'reasoningFiles',
      );
      ctx.expectEquals(
        (await result.reasoning).single.signature,
        'sig-s',
        'reasoning signature',
      );
      ctx.expectEquals(await result.reasoningText, 'Why. ', 'reasoningText');
      ctx.expectEquals(
        await result.rawFinishReason,
        'end_turn',
        'rawFinishReason',
      );
      ctx.expectEquals(
        (await result.warnings).single.type,
        'other',
        'warnings',
      );
      ctx.expectEquals(await result.providerMetadata, {
        'verify': {'cache': 'miss'},
      }, 'providerMetadata');
      ctx.expectEquals(
        (await result.response).metadata?.id,
        'resp-s1',
        'response metadata',
      );
      ctx.expectEquals((await result.usage)?.inputTokens.total, 8, 'usage');
    },
  ),
  Check(
    id: 'smooth-stream',
    feature: 'text-smooth',
    description:
        'smoothStream splits a long delta into fixed-size chunks and '
        'delayInMs spaces them out; the final text is unchanged.',
    run: (ctx) async {
      final server = await ctx.server((_) => _sseText(['abcdefghijkl']));
      final model = _model(ctx, server);
      final smooth = await streamText(
        model: model,
        prompt: 'hi',
        experimentalTransform: smoothStream(chunkSize: 4),
      );
      final pieces = _Drain(smooth.textStream);
      final smoothText = await smooth.text;
      await pieces.done;
      ctx.observe('chunks', pieces.items);
      ctx.expectEquals(pieces.items, [
        'abcd',
        'efgh',
        'ijkl',
      ], 'smoothed chunks');
      ctx.expectEquals(smoothText, 'abcdefghijkl', 'smoothed text');

      final watch = Stopwatch()..start();
      final slow = await streamText(
        model: model,
        prompt: 'hi',
        experimentalTransform: smoothStream(chunkSize: 3, delayInMs: 40),
      );
      final slowText = await slow.text;
      watch.stop();
      ctx.observe('delayedElapsedMs', watch.elapsedMilliseconds);
      ctx.expectEquals(slowText, 'abcdefghijkl', 'delayed text');
      ctx.expect(
        watch.elapsedMilliseconds >= 120,
        'three gaps of 40 ms expected, elapsed ${watch.elapsedMilliseconds} ms',
      );
    },
  ),
  Check(
    id: 'generate-callbacks',
    feature: 'text-callbacks',
    description:
        'generateText fires onStart, onStepStart, onToolExecutionStart, '
        'onToolExecutionEnd, onStepEnd and onEnd in order; onStepFinish and '
        'onFinish still work as fallbacks.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_1', 'getWeather', '{"city":"Rome"}'),
          _text('Sunny in Rome.'),
        ]),
      );
      final order = <String>[];
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather in Rome?',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool()},
        onStart: (e) => order.add('start:${e.prompt}'),
        onStepStart: (e) => order.add('stepStart:${e.stepNumber}'),
        onToolExecutionStart: (e) =>
            order.add('toolStart:${e.toolCall.toolName}'),
        onToolExecutionEnd: (e) =>
            order.add('toolEnd:${e.success}:${e.output}'),
        onStepEnd: (e) =>
            order.add('stepEnd:${e.stepNumber}:${e.finishReason.name}'),
        onEnd: (e) => order.add('end:${e.text}:${e.steps.length}'),
      );
      ctx.observe('order', order);
      ctx.expectEquals(order, [
        'start:Weather in Rome?',
        'stepStart:0',
        'toolStart:getWeather',
        'toolEnd:true:Sunny, 18C in Rome',
        'stepEnd:0:toolCalls',
        'stepStart:1',
        'stepEnd:1:stop',
        'end:Sunny in Rome.:2',
      ], 'callback order');
      ctx.expectEquals(result.steps.length, 2, 'steps');

      final fallback = <String>[];
      await generateText(
        model: _model(ctx, server),
        prompt: 'again',
        onStepFinish: (e) => fallback.add('step:${e.stepNumber}'),
        onFinish: (e) => fallback.add('finish:${e.steps.length}'),
      );
      ctx.expectEquals(fallback, ['step:0', 'finish:1'], 'fallback callbacks');
    },
  ),
  Check(
    id: 'stream-callbacks',
    feature: 'text-callbacks',
    description:
        'streamText fires onStart, onStepStart, onToolExecutionStart/End, '
        'onStepEnd, onEnd and onChunk with typed chunks across a tool loop.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _sseCall('call_1', 'getWeather', ['{"city":', '"Rome"}']),
          _sseText(['Sunny ', 'in Rome.']),
        ]),
      );
      final order = <String>[];
      final chunkTypes = <String>[];
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Weather in Rome?',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool()},
        onStart: (e) => order.add('start'),
        onStepStart: (e) => order.add('stepStart:${e.stepNumber}'),
        onToolExecutionStart: (e) =>
            order.add('toolStart:${e.toolCall.toolCallId}'),
        onToolExecutionEnd: (e) => order.add('toolEnd:${e.success}'),
        onStepEnd: (e) => order.add('stepEnd:${e.stepNumber}'),
        onEnd: (e) => order.add('end:${e.text}'),
        onChunk: (chunk) => chunkTypes.add(
          '${chunk.runtimeType}'.replaceFirst('StreamText', ''),
        ),
      );
      await result.text;
      ctx.observe('order', order);
      ctx.observe('chunkTypes', chunkTypes);
      ctx.expectEquals(order, [
        'start',
        'stepStart:0',
        'toolStart:call_1',
        'toolEnd:true',
        'stepEnd:0',
        'stepStart:1',
        'stepEnd:1',
        'end:Sunny in Rome.',
      ], 'callback order');
      for (final expected in [
        'ToolInputStartChunk',
        'ToolInputDeltaChunk',
        'ToolCallChunk',
        'ToolResultChunk',
        'TextChunk',
        'UsageChunk',
      ]) {
        ctx.expect(
          chunkTypes.contains(expected),
          'onChunk never saw $expected',
        );
      }
      ctx.expectEquals(_chatRequests(ctx, server).length, 2, 'requests');
    },
  ),
  Check(
    id: 'stream-http-error',
    feature: 'text-stream-errors',
    description:
        'A 401 on a streaming call fires onError, emits an error event, and '
        'rejects the result futures with AiApiCallError.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json({
          'error': {
            'message': 'Incorrect API key provided.',
            'type': 'invalid_request_error',
            'code': 'invalid_api_key',
          },
        }, status: 401),
      );
      Object? onErrorSeen;
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxRetries: 0,
        onError: (e) => onErrorSeen = e,
      );
      final events = _Drain(result.stream);
      final error = await ctx.expectThrows<AiApiCallError>(
        () => result.text,
        'result.text',
      );
      await events.done;
      ctx.observe('statusCode', error.statusCode);
      ctx.expectEquals(error.statusCode, 401, 'statusCode');
      ctx.expect(
        error.message.contains('Incorrect API key'),
        'provider message lost',
      );
      ctx.expect(
        onErrorSeen is AiApiCallError,
        'onError not called with AiApiCallError',
      );
      ctx.expect(
        events.items.whereType<StreamTextErrorEvent>().isNotEmpty,
        'no error event on stream',
      );
      await ctx.expectThrows<AiApiCallError>(
        () => result.usage,
        'result.usage',
      );
      await ctx.expectThrows<AiApiCallError>(
        () => result.steps,
        'result.steps',
      );
      ctx.expectEquals(
        _chatRequests(ctx, server).length,
        1,
        'no retry with maxRetries 0',
      );
    },
  ),
  Check(
    id: 'stream-truncated',
    feature: 'text-stream-errors',
    description:
        'An SSE stream that ends without a finish reason surfaces as an '
        'error instead of a silent partial result.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _sseText(['partial '], finish: false),
      );
      Object? onErrorSeen;
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxRetries: 0,
        onError: (e) => onErrorSeen = e,
      );
      final deltas = _Drain(result.textStream);
      final error = await ctx.expectThrows<AiApiCallError>(
        () => result.text,
        'result.text',
      );
      await deltas.done;
      ctx.observe('message', error.message);
      ctx.expect(
        error.message.contains('finish reason'),
        'unexpected error: ${error.message}',
      );
      ctx.expectEquals(deltas.items, [
        'partial ',
      ], 'delta delivered before the failure');
      ctx.expect(onErrorSeen != null, 'onError not called');
    },
  ),

  // ----- multi-step ------------------------------------------------------
  Check(
    id: 'multi-step-max-steps',
    feature: 'text-multistep',
    description:
        'maxSteps bounds the tool loop: the default of 1 stops after the '
        'first tool step, maxSteps 3 stops after three requests.',
    run: (ctx) async {
      final always = _call('call_n', 'getWeather', '{"city":"Rome"}');
      final single = await ctx.server((_) => always);
      var runs = 0;
      final first = await generateText(
        model: _model(ctx, single),
        prompt: 'go',
        tools: {'getWeather': _weatherTool(onRun: (_, _) => runs++)},
      );
      ctx.expectEquals(
        _chatRequests(ctx, single).length,
        1,
        'requests with default maxSteps',
      );
      ctx.expectEquals(first.steps.length, 1, 'steps with default maxSteps');
      ctx.expectEquals(
        first.finishReason,
        LanguageModelV4FinishReason.toolCalls,
        'finish reason',
      );
      ctx.expectEquals(first.toolResults.length, 1, 'tool still ran once');

      final capped = await ctx.server((_) => always);
      final second = await generateText(
        model: _model(ctx, capped),
        prompt: 'go',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(onRun: (_, _) => runs++)},
      );
      ctx.observe('steps', second.steps.length);
      ctx.expectEquals(
        _chatRequests(ctx, capped).length,
        3,
        'requests with maxSteps 3',
      );
      ctx.expectEquals(second.steps.length, 3, 'steps');
      ctx.expectEquals(second.toolCalls.length, 3, 'aggregate toolCalls');
      ctx.expectEquals(second.toolResults.length, 3, 'aggregate toolResults');
      ctx.expectEquals(
        second.totalUsage?.inputTokens.total,
        30,
        'summed input usage',
      );
      ctx.expectEquals(runs, 4, 'tool executions');
    },
  ),
  Check(
    id: 'prepare-step',
    feature: 'text-multistep',
    description:
        'prepareStep overrides instructions and toolChoice per step and sees '
        'the step number and prior steps.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_1', 'getWeather', '{"city":"Rome"}'),
          _text('Done.'),
        ]),
      );
      final seen = <String>[];
      await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool()},
        prepareStep: (context) {
          seen.add('${context.stepNumber}:${context.steps.length}');
          return context.stepNumber == 0
              ? const GenerateTextPrepareStepResult(
                  instructions: 'Step zero rules.',
                  toolChoice: ToolChoiceRequired(),
                )
              : const GenerateTextPrepareStepResult(
                  instructions: 'Step one rules.',
                  toolChoice: ToolChoiceNone(),
                );
        },
      );
      ctx.observe('prepareStepCalls', seen);
      ctx.expectEquals(seen, ['0:0', '1:1'], 'prepareStep context');
      final requests = _chatRequests(ctx, server);
      ctx.expectEquals(
        _messages(requests[0]).first['content'],
        'Step zero rules.',
        'step 0 system',
      );
      ctx.expectEquals(
        requests[0].jsonObject['tool_choice'],
        'required',
        'step 0 tool_choice',
      );
      ctx.expectEquals(
        _messages(requests[1]).first['content'],
        'Step one rules.',
        'step 1 system',
      );
      ctx.expectEquals(
        requests[1].jsonObject['tool_choice'],
        'none',
        'step 1 tool_choice',
      );
    },
  ),
  Check(
    id: 'stop-conditions',
    feature: 'text-multistep',
    description:
        'stopWhen governs the loop (stepCountIs, hasToolCall, '
        'stopWhenAll) and may exceed maxSteps; stopConditions adds a custom '
        'predicate.',
    run: (ctx) async {
      Future<int> run(
        FixtureHandler handler, {
        Object? stopWhen,
        List<StopCondition> stopConditions = const [],
        int maxSteps = 1,
        Map<String, Tool<dynamic, dynamic>>? extraTools,
      }) async {
        final server = await ctx.server(handler);
        await generateText(
          model: _model(ctx, server),
          prompt: 'go',
          maxSteps: maxSteps,
          stopWhen: stopWhen,
          stopConditions: stopConditions,
          tools: {'getWeather': _weatherTool(), ...?extraTools},
        );
        return _chatRequests(ctx, server).length;
      }

      final loop = _call('call_n', 'getWeather', '{"city":"Rome"}');
      final counts = <String, int>{};
      counts['stepCountIs(2) ignoring maxSteps 1'] = await run(
        (_) => loop,
        stopWhen: stepCountIs(2),
      );
      counts['stopWhenAll'] = await run(
        (_) => loop,
        stopWhen: stopWhenAll([
          stepCountIs(4),
          hasFinishReason(LanguageModelV4FinishReason.toolCalls),
        ]),
      );
      counts['stopConditions'] = await run(
        (_) => loop,
        maxSteps: 10,
        stopConditions: [(snapshot) => snapshot.stepCount >= 3],
      );
      counts['hasToolCall'] = await run(
        _sequence([
          loop,
          _call('call_f', 'finish', '{"city":"x"}'),
          _text('unreached'),
        ]),
        stopWhen: hasToolCall('finish'),
        extraTools: {'finish': _weatherTool()},
      );
      ctx.observe('requestCounts', counts);
      ctx.expectEquals(
        counts['stepCountIs(2) ignoring maxSteps 1'],
        2,
        'stepCountIs',
      );
      ctx.expectEquals(counts['stopWhenAll'], 4, 'stopWhenAll');
      ctx.expectEquals(counts['stopConditions'], 3, 'stopConditions');
      ctx.expectEquals(counts['hasToolCall'], 2, 'hasToolCall');
    },
  ),
  Check(
    id: 'active-tools',
    feature: 'text-multistep',
    description:
        'activeToolNames and prepareStep.activeTools limit which tools are '
        'sent to the provider.',
    run: (ctx) async {
      final server = await ctx.server((_) => _text('ok'));
      final tools = {
        'alpha': _weatherTool(),
        'beta': _weatherTool(),
        'gamma': _weatherTool(),
      };
      List<String> names(FixtureRequest r) => [
        for (final t in (r.jsonObject['tools'] as List? ?? const []))
          ((t as Map)['function'] as Map)['name'] as String,
      ];
      await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        tools: tools,
      );
      await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        tools: tools,
        activeToolNames: const ['beta'],
      );
      await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        tools: tools,
        prepareStep: (_) => const GenerateTextPrepareStepResult(
          activeTools: ['gamma', 'alpha'],
        ),
      );
      final requests = _chatRequests(ctx, server);
      ctx.observe('toolNames', [for (final r in requests) names(r)]);
      ctx.expectEquals(names(requests[0])..sort(), [
        'alpha',
        'beta',
        'gamma',
      ], 'all tools');
      ctx.expectEquals(names(requests[1]), ['beta'], 'activeToolNames');
      ctx.expectEquals(names(requests[2])..sort(), [
        'alpha',
        'gamma',
      ], 'prepareStep activeTools');
    },
  ),

  // ----- structured output -----------------------------------------------
  Check(
    id: 'output-object',
    feature: 'text-structured',
    description:
        'Output.object sends a named json_schema response format and '
        'returns a typed Dart object.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _text('{"name":"Soup","minutes":25}'),
      );
      final result = await generateText<_Recipe>(
        model: _model(ctx, server),
        prompt: 'A quick recipe.',
        output: Output.object(
          schema: _recipeSchema,
          name: 'recipe',
          description: 'One recipe.',
        ),
      );
      final body = ctx.singleRequest(server, _chatPath).jsonObject;
      final format = body['response_format'] as Map;
      ctx.observe('responseFormat', format);
      ctx.expectEquals(format['type'], 'json_schema', 'response_format.type');
      final schema = format['json_schema'] as Map;
      ctx.expectEquals(schema['name'], 'recipe', 'schema name');
      ctx.expectEquals(
        schema['description'],
        'One recipe.',
        'schema description',
      );
      ctx.expectEquals(schema['schema'], _recipeJsonSchema, 'schema body');
      ctx.expect(
        '${_messages(ctx.singleRequest(server, _chatPath)).first['content']}'
            .contains('"minutes"'),
        'system message does not carry the schema',
      );
      ctx.expectEquals(result.output.name, 'Soup', 'typed output name');
      ctx.expectEquals(result.output.minutes, 25, 'typed output minutes');
      ctx.expectEquals(
        result.text,
        '{"name":"Soup","minutes":25}',
        'raw text kept',
      );
    },
  ),
  Check(
    id: 'output-array-choice-json',
    feature: 'text-structured',
    description:
        'Output.array, Output.choice and Output.json send the matching '
        'response format and parse the reply.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _text('[{"name":"Soup","minutes":25},{"name":"Stew","minutes":90}]'),
          _text('positive'),
          _text('{"anything":[1,2,3]}'),
        ]),
      );
      final model = _model(ctx, server);
      final array = await generateText<List<_Recipe>>(
        model: model,
        prompt: 'Two recipes.',
        output: Output.array(element: _recipeSchema),
      );
      final choice = await generateText<String>(
        model: model,
        prompt: 'Sentiment?',
        output: Output.choice(options: const ['positive', 'negative']),
      );
      final json = await generateText<Object?>(
        model: model,
        prompt: 'Any JSON.',
        output: Output.json(),
      );
      final requests = _chatRequests(ctx, server);
      final arrayFormat = requests[0].jsonObject['response_format'] as Map;
      final choiceFormat = requests[1].jsonObject['response_format'] as Map;
      final jsonFormat = requests[2].jsonObject['response_format'] as Map;
      ctx.observe('formats', [arrayFormat, choiceFormat, jsonFormat]);
      ctx.expectEquals(
        ((arrayFormat['json_schema'] as Map)['schema'] as Map)['type'],
        'array',
        'array schema',
      );
      ctx.expectEquals(
        ((arrayFormat['json_schema'] as Map)['schema'] as Map)['items'],
        _recipeJsonSchema,
        'array items',
      );
      ctx.expectEquals(
        ((choiceFormat['json_schema'] as Map)['schema'] as Map)['enum'],
        ['positive', 'negative'],
        'choice enum',
      );
      ctx.expectEquals(
        jsonFormat['type'],
        'json_object',
        'json response_format',
      );
      ctx.expectEquals(array.output.map((r) => r.name).toList(), [
        'Soup',
        'Stew',
      ], 'array output');
      ctx.expectEquals(choice.output, 'positive', 'choice output');
      ctx.expectEquals(json.output, {
        'anything': [1, 2, 3],
      }, 'json output');
    },
  ),
  Check(
    id: 'output-no-object-error',
    feature: 'text-structured',
    description:
        'Invalid, truncated and schema-mismatched JSON all throw '
        'AiNoObjectGeneratedError carrying the text, usage and response; a '
        'complete fenced JSON block still parses.',
    run: (ctx) async {
      final replies = [
        'this is not json at all',
        '{"name":"Soup","minutes":',
        '{"name":"Soup"}',
      ];
      const fenced = '```json\n{"name":"Soup","minutes":25}\n```';
      final server = await ctx.server(
        _sequence([
          for (final r in [...replies, fenced]) _text(r),
        ]),
      );
      final model = _model(ctx, server);
      for (final reply in replies) {
        final error = await ctx.expectThrows<AiNoObjectGeneratedError>(
          () => generateText<_Recipe>(
            model: model,
            prompt: 'recipe',
            output: Output.object(schema: _recipeSchema),
          ),
          'generateText(${jsonEncode(reply).substring(0, 12)}...)',
        );
        ctx.expectEquals(error.text, reply, 'error.text');
        ctx.expectEquals(error.usage?.inputTokens.total, 11, 'error.usage');
        ctx.expectEquals(
          error.response?.id,
          'chatcmpl-verify',
          'error.response',
        );
        ctx.expect(error.cause != null, 'error.cause missing');
      }
      final parsed = await generateText<_Recipe>(
        model: model,
        prompt: 'recipe',
        output: Output.object(schema: _recipeSchema),
      );
      ctx.expectEquals(parsed.output.minutes, 25, 'fenced JSON output');
      ctx.expectEquals(_chatRequests(ctx, server).length, 4, 'requests');
    },
  ),
  Check(
    id: 'stream-partial-output',
    feature: 'text-structured',
    description:
        'partialOutputStream yields growing partial objects while the JSON '
        'streams in, and output resolves to the typed final object.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _sseText([
          '{"name":"A',
          ' long soup',
          ' name for ',
          'testing pa',
          'rtial outp',
          'ut","minut',
          'es":25}',
        ]),
      );
      final result = await streamText<_Recipe>(
        model: _model(ctx, server),
        prompt: 'recipe',
        output: Output.object(schema: _recipeSchema),
      );
      final partials = _Drain(result.partialOutputStream);
      final output = await result.output;
      await partials.done;
      ctx.observe('partials', partials.items);
      ctx.expect(
        partials.items.length >= 2,
        'expected several partials, got ${partials.items.length}',
      );
      const fullName = 'A long soup name for testing partial output';
      var previous = 0;
      for (final partial in partials.items) {
        final name = (partial as Map)['name'] as String;
        ctx.expect(
          fullName.startsWith(name) && name.length >= previous,
          'partial name "$name" does not grow toward the final name',
        );
        previous = name.length;
      }
      ctx.expectEquals(output.name, fullName, 'final output name');
      ctx.expectEquals(output.minutes, 25, 'final output minutes');
    },
  ),
  Check(
    id: 'stream-element-stream',
    feature: 'text-structured',
    description:
        'With Output.array, elementStream emits each completed element once '
        'as soon as it closes and output resolves to the full list.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _sseText([
          '[{"name":"A","minutes":1},{"na',
          'me":"B","minutes":2},',
          '{"name":"C","minutes":3}]',
        ]),
      );
      final result = await streamText<List<_Recipe>>(
        model: _model(ctx, server),
        prompt: 'three recipes',
        output: Output.array(element: _recipeSchema),
      );
      final elements = _Drain(result.elementStream);
      final partials = _Drain(result.partialOutputStream);
      final output = await result.output;
      await elements.done;
      await partials.done;
      final names = elements.items.map((e) => (e as _Recipe).name).toList();
      ctx.observe('elements', names);
      ctx.observe(
        'partialLengths',
        partials.items.map((p) => (p as List).length).toList(),
      );
      ctx.expectEquals(names, ['A', 'B', 'C'], 'element order');
      ctx.expectEquals(output.map((r) => r.minutes).toList(), [
        1,
        2,
        3,
      ], 'final list');
      ctx.expectEquals(
        (partials.items.last as List).length,
        3,
        'last partial list',
      );
    },
  ),

  Check(
    id: 'generate-object',
    feature: 'text-object',
    description:
        'generateObject sends a json_schema response format and returns the '
        'typed object, the raw JSON and the response; unparseable output '
        'throws AiNoObjectGeneratedError.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([_text('{"name":"Soup","minutes":25}'), _text('not json')]),
      );
      final model = _model(ctx, server);
      final result = await generateObject<_Recipe>(
        model: model,
        schema: _recipeSchema,
        instructions: 'You are a chef.',
        prompt: 'A quick recipe.',
        maxOutputTokens: 48,
      );
      final body = _chatRequests(ctx, server)[0].jsonObject;
      final format = body['response_format'] as Map;
      ctx.observe('responseFormat', format);
      ctx.expectEquals(format['type'], 'json_schema', 'response_format.type');
      ctx.expectEquals(
        (format['json_schema'] as Map)['schema'],
        _recipeJsonSchema,
        'schema',
      );
      ctx.expectEquals(body['max_completion_tokens'], 48, 'max tokens');
      ctx.expectEquals(
        '${_messages(_chatRequests(ctx, server)[0]).first['content']}'
            .startsWith('You are a chef.'),
        true,
        'instructions first in the system message',
      );
      ctx.expectEquals(result.object.name, 'Soup', 'typed object');
      ctx.expectEquals(result.object.minutes, 25, 'typed object minutes');
      ctx.expectEquals(result.rawJson, {
        'name': 'Soup',
        'minutes': 25,
      }, 'rawJson');
      ctx.expectEquals(result.response.usage.inputTokens.total, 11, 'usage');
      final error = await ctx.expectThrows<AiNoObjectGeneratedError>(
        () => generateObject<_Recipe>(
          model: model,
          schema: _recipeSchema,
          prompt: 'again',
        ),
        'invalid reply',
      );
      ctx.expectEquals(error.text, 'not json', 'error.text');
    },
  ),
  Check(
    id: 'stream-object',
    feature: 'text-object',
    description:
        'streamObject yields growing partial objects, JSON patch '
        'operations, raw text and the final typed object.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _sseText([
          '{"name":"A',
          ' long soup',
          ' name for ',
          'testing pa',
          'rtial outp',
          'ut","minut',
          'es":25}',
        ]),
      );
      final result = await streamObject<_Recipe>(
        model: _model(ctx, server),
        schema: _recipeSchema,
        prompt: 'recipe',
      );
      final partials = _Drain(result.partialObjectStream);
      final patches = _Drain(result.patchStream);
      final text = _Drain(result.textStream);
      final finals = _Drain(result.stream);
      final object = await result.object;
      await partials.done;
      await patches.done;
      await text.done;
      await finals.done;
      ctx.observe('partials', partials.items);
      ctx.observe(
        'patches',
        patches.items
            .map((ops) => [for (final o in ops) '${o.op} ${o.path}'])
            .toList(),
      );
      final body = ctx.singleRequest(server, _chatPath).jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(
        (body['response_format'] as Map)['type'],
        'json_schema',
        'response_format',
      );
      ctx.expect(partials.items.length >= 2, 'expected several partials');
      ctx.expectEquals(patches.items.length, partials.items.length, 'patches');
      final lastOps = [for (final o in patches.items.last) '${o.op} ${o.path}'];
      ctx.expect(
        lastOps.contains('add /minutes'),
        'last patch lacks "add /minutes": $lastOps',
      );
      ctx.expectEquals(
        text.items.join(),
        '{"name":"A long soup name for testing partial output","minutes":25}',
        'raw text',
      );
      ctx.expectEquals(object.minutes, 25, 'object future');
      ctx.expectEquals(finals.items.length, 1, 'stream emits the final object');
      ctx.expectEquals(finals.items.single.minutes, 25, 'stream object');
    },
  ),

  // ----- tools -----------------------------------------------------------
  Check(
    id: 'tool-typed-loop',
    feature: 'text-tools',
    description:
        'A typed tool is serialized with its schema and strict flag, runs '
        'with the decoded input, and its result goes back as a tool message; '
        'steps and usage aggregate.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_1', 'getWeather', '{"city":"Paris"}'),
          _text('It is sunny in Paris.', p: 20, c: 8),
        ]),
      );
      String? seenCallId;
      _Weather? seenInput;
      int? seenMessages;
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather in Paris?',
        maxSteps: 3,
        tools: {
          'getWeather': _weatherTool(
            strict: true,
            onRun: (input, options) {
              seenInput = input;
              seenCallId = options.toolCallId;
              seenMessages = options.messages?.length;
            },
          ),
        },
      );
      final requests = _chatRequests(ctx, server);
      final fn =
          ((requests[0].jsonObject['tools'] as List).single as Map)['function']
              as Map;
      ctx.observe('toolFunction', fn);
      ctx.expectEquals(fn['name'], 'getWeather', 'tool name');
      ctx.expectEquals(
        fn['description'],
        'Get current weather for a city.',
        'description',
      );
      ctx.expectEquals(fn['parameters'], _weatherJsonSchema, 'parameters');
      ctx.expectEquals(fn['strict'], true, 'strict');
      final followUp = _messages(requests[1]);
      ctx.expectEquals(_roles(requests[1]), [
        'user',
        'assistant',
        'tool',
      ], 'follow-up roles');
      ctx.expectEquals(followUp[2]['tool_call_id'], 'call_1', 'tool_call_id');
      ctx.expectEquals(
        followUp[2]['content'],
        'Sunny, 18C in Paris',
        'tool message',
      );
      ctx.expectEquals(seenInput?.city, 'Paris', 'decoded input');
      ctx.expectEquals(seenCallId, 'call_1', 'options.toolCallId');
      ctx.expect((seenMessages ?? 0) >= 2, 'options.messages missing');
      ctx.expectEquals(result.text, 'It is sunny in Paris.', 'final text');
      ctx.expectEquals(result.steps.length, 2, 'steps');
      ctx.expectEquals(
        result.steps[0].toolCalls.single.toolName,
        'getWeather',
        'step 0 tool call',
      );
      ctx.expectEquals(result.toolCalls.length, 1, 'aggregate toolCalls');
      ctx.expectEquals(
        _toolText(result.toolResults.single),
        'Sunny, 18C in Paris',
        'aggregate toolResults',
      );
      ctx.expectEquals(
        result.totalUsage?.inputTokens.total,
        30,
        'summed input tokens',
      );
      ctx.expectEquals(
        result.totalUsage?.outputTokens.total,
        13,
        'summed output tokens',
      );
      ctx.expectEquals(
        result.usage?.inputTokens.total,
        30,
        'usage aggregates steps',
      );
      ctx.expectEquals(
        result.responseMessages.map((m) => m.role.name).toList(),
        ['assistant', 'tool', 'assistant'],
        'responseMessages',
      );
    },
  ),
  Check(
    id: 'tool-dynamic',
    feature: 'text-tools',
    description:
        'dynamicTool accepts any JSON object input and is advertised with a '
        'plain object schema.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_d', 'lookup', '{"q":"dart","limit":3}'),
          _text('found'),
        ]),
      );
      Object? seen;
      await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        maxSteps: 2,
        tools: {
          'lookup': dynamicTool<String>(
            description: 'Look something up.',
            execute: (input, _) async {
              seen = input;
              return 'result for ${(input as Map)['q']}';
            },
          ),
        },
      );
      final requests = _chatRequests(ctx, server);
      final fn =
          ((requests[0].jsonObject['tools'] as List).single as Map)['function']
              as Map;
      ctx.expectEquals(fn['parameters'], {'type': 'object'}, 'dynamic schema');
      ctx.expectEquals(seen, {
        'q': 'dart',
        'limit': 3,
      }, 'input as sent by the model');
      ctx.expectEquals(
        _messages(requests[1]).last['content'],
        'result for dart',
        'tool message',
      );
    },
  ),
  Check(
    id: 'tool-choice',
    feature: 'text-tools',
    description:
        'toolChoice auto, required, none and a specific tool map to the '
        'Chat Completions tool_choice field; a reply that ignores a required '
        'choice is rejected.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _text('ok'),
          _text('ok'),
          _call('c_req', 'getWeather', '{"city":"A"}'),
          _text('ok'),
          _call('c_spec', 'other', '{"city":"B"}'),
          _text('no tool call'),
        ]),
      );
      final model = _model(ctx, server);
      final tools = {'getWeather': _weatherTool(), 'other': _weatherTool()};
      for (final choice in <LanguageModelV4ToolChoice?>[
        null,
        const ToolChoiceAuto(),
        const ToolChoiceRequired(),
        const ToolChoiceNone(),
        const ToolChoiceSpecific(toolName: 'other'),
      ]) {
        await generateText(
          model: model,
          prompt: 'go',
          tools: tools,
          toolChoice: choice,
        );
      }
      final wire = [
        for (final r in _chatRequests(ctx, server))
          r.jsonObject.containsKey('tool_choice')
              ? r.jsonObject['tool_choice']
              : '<absent>',
      ];
      ctx.observe('toolChoice', wire);
      ctx.expectEquals(wire[1], 'auto', 'auto');
      ctx.expectEquals(wire[2], 'required', 'required');
      ctx.expectEquals(wire[3], 'none', 'none');
      ctx.expectEquals(wire[4], {
        'type': 'function',
        'function': {'name': 'other'},
      }, 'specific');
      ctx.expect(
        wire[0] == '<absent>' || wire[0] == 'auto',
        'unset toolChoice sent ${wire[0]}',
      );
      final violation = await ctx.expectThrows<AiSdkError>(
        () => generateText(
          model: model,
          prompt: 'go',
          tools: tools,
          toolChoice: const ToolChoiceRequired(),
        ),
        'required choice answered with text only',
      );
      ctx.expect(
        violation.message.contains('toolChoice'),
        'violation does not name toolChoice: ${violation.message}',
      );
    },
  ),
  Check(
    id: 'tool-error-returned',
    feature: 'text-tools',
    description:
        'A tool that throws does not fail the call: the error is sent back '
        'to the model as an error tool result, and streamText emits a tool '
        'error event.',
    run: (ctx) async {
      Tool<_Weather, String> failing() => tool<_Weather, String>(
        description: 'Always fails.',
        inputSchema: _weatherSchema,
        execute: (input, _) async => throw StateError('boom'),
      );
      final server = await ctx.server(
        _sequence([
          _call('call_e', 'getWeather', '{"city":"Rome"}'),
          _text('I could not check.'),
        ]),
      );
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        maxSteps: 3,
        tools: {'getWeather': failing()},
      );
      final toolMessage = _messages(_chatRequests(ctx, server)[1]).last;
      final payload = jsonDecode(toolMessage['content'] as String) as Map;
      ctx.observe('toolMessage', payload);
      ctx.expectEquals(toolMessage['role'], 'tool', 'role');
      ctx.expectEquals(payload['isError'], true, 'isError');
      ctx.expect(
        '${(payload['output'] as Map)['text']}'.contains('boom'),
        'error text lost',
      );
      ctx.expectEquals(result.text, 'I could not check.', 'model recovers');
      ctx.expectEquals(
        result.toolResults.single.isError,
        true,
        'result isError',
      );

      final streamServer = await ctx.server(
        _sequence([
          _sseCall('call_e', 'getWeather', ['{"city":"Rome"}']),
          _sseText(['Recovered.']),
        ]),
      );
      final streamed = await streamText(
        model: _model(ctx, streamServer),
        prompt: 'go',
        maxSteps: 3,
        tools: {'getWeather': failing()},
      );
      final events = _Drain(streamed.stream);
      await streamed.text;
      await events.done;
      final toolErrors = events.items
          .whereType<StreamTextToolErrorEvent>()
          .toList();
      ctx.expectEquals(toolErrors.length, 1, 'tool error events');
      ctx.expectEquals(
        toolErrors.single.toolCallId,
        'call_e',
        'tool error call id',
      );
      ctx.expect(
        '${toolErrors.single.error}'.contains('boom'),
        'tool error payload',
      );
    },
  ),
  Check(
    id: 'tool-invalid-input',
    feature: 'text-tools',
    description:
        'Model arguments that fail the tool schema decoder never reach the '
        'executor; an error result goes back to the model.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_bad', 'getWeather', '{"town":"Rome"}'),
          _text('Sorry.'),
        ]),
      );
      var executions = 0;
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(onRun: (_, _) => executions++)},
      );
      final toolMessage = _messages(_chatRequests(ctx, server)[1]).last;
      ctx.observe('toolMessage', toolMessage['content']);
      ctx.expectEquals(executions, 0, 'executor runs');
      ctx.expectEquals(result.toolResults.single.isError, true, 'error result');
      ctx.expectEquals(toolMessage['role'], 'tool', 'tool message role');
      ctx.expect(
        '${toolMessage['content']}'.contains('"isError":true'),
        'error not marked on the wire',
      );
      ctx.expectEquals(result.text, 'Sorry.', 'text');
    },
  ),
  Check(
    id: 'tool-input-hooks',
    feature: 'text-tools',
    description:
        'onInputStart, onInputDelta and onInputAvailable fire while the '
        'tool arguments stream in, before the tool executes.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _sseCall('call_h', 'getWeather', ['{"ci', 'ty":"Ber', 'lin"}']),
          _sseText(['ok']),
        ]),
      );
      final log = <String>[];
      final buffers = <String>[];
      Object? availableInput;
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'go',
        maxSteps: 2,
        tools: {
          'getWeather': _weatherTool(onRun: (_, _) => log.add('execute')),
        },
        onInputStart: (e) => log.add('inputStart:${e.toolName}'),
        onInputDelta: (e) {
          log.add('inputDelta');
          buffers.add(e.inputBuffer);
        },
        onInputAvailable: (e) {
          log.add('inputAvailable');
          availableInput = e.input;
        },
      );
      await result.text;
      ctx.observe('log', log);
      ctx.observe('buffers', buffers);
      ctx.expectEquals(log, [
        'inputStart:getWeather',
        'inputDelta',
        'inputDelta',
        'inputDelta',
        'inputAvailable',
        'execute',
      ], 'hook order');
      ctx.expectEquals(buffers, [
        '{"ci',
        '{"city":"Ber',
        '{"city":"Berlin"}',
      ], 'growing input buffer');
      ctx.expectEquals(availableInput, {'city': 'Berlin'}, 'parsed input');
    },
  ),
  Check(
    id: 'tool-concurrency',
    feature: 'text-tools',
    description:
        'Parallel tool calls run one at a time by default and up to '
        'maxToolConcurrency at once; results keep call order; a value below '
        '1 is rejected.',
    run: (ctx) async {
      final parallel = _calls([
        (id: 'c1', name: 'getWeather', args: '{"city":"A"}'),
        (id: 'c2', name: 'getWeather', args: '{"city":"B"}'),
        (id: 'c3', name: 'getWeather', args: '{"city":"C"}'),
      ]);
      Future<int> maxRunning(int concurrency, FixtureServer server) async {
        var running = 0;
        var peak = 0;
        await generateText(
          model: _model(ctx, server),
          prompt: 'go',
          maxSteps: 2,
          maxToolConcurrency: concurrency,
          tools: {
            'getWeather': _weatherTool(
              delay: const Duration(milliseconds: 60),
              onRun: (_, _) {
                running++;
                if (running > peak) peak = running;
                Timer(const Duration(milliseconds: 55), () => running--);
              },
            ),
          },
        );
        return peak;
      }

      final serial = await ctx.server(_sequence([parallel, _text('done')]));
      final wide = await ctx.server(_sequence([parallel, _text('done')]));
      final serialPeak = await maxRunning(1, serial);
      final widePeak = await maxRunning(3, wide);
      ctx.observe('serialPeak', serialPeak);
      ctx.observe('widePeak', widePeak);
      ctx.expectEquals(serialPeak, 1, 'default concurrency peak');
      ctx.expectEquals(widePeak, 3, 'maxToolConcurrency 3 peak');
      final followUp = _messages(_chatRequests(ctx, wide)[1]);
      ctx.expectEquals(
        [
          for (final m in followUp.where((m) => m['role'] == 'tool'))
            m['tool_call_id'],
        ],
        ['c1', 'c2', 'c3'],
        'tool results keep call order',
      );
      await ctx.expectThrows<ArgumentError>(
        () => generateText(
          model: _model(ctx, wide),
          prompt: 'go',
          maxToolConcurrency: 0,
        ),
        'maxToolConcurrency 0',
      );
    },
  ),
  Check(
    id: 'tool-context',
    feature: 'text-tools',
    description:
        'toolWithContext hands a bound application value to the executor '
        'and keeps it out of the provider request; runtimeContext reaches '
        'ToolExecutionOptions.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_c', 'getWeather', '{"city":"Rome"}'),
          _text('ok'),
        ]),
      );
      String? boundValue;
      Object? runtime;
      await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        maxSteps: 2,
        runtimeContext: const {'tenant': 'acme'},
        tools: {
          'getWeather': toolWithContext<_Weather, String, String>(
            inputSchema: _weatherSchema,
            context: 'secret-db-handle',
            description: 'Weather.',
            execute: (input, context, options) async {
              boundValue = context;
              runtime = options.runtimeContext;
              return 'ok ${input.city}';
            },
          ),
        },
      );
      ctx.observe('boundValue', boundValue);
      ctx.expectEquals(boundValue, 'secret-db-handle', 'bound context');
      ctx.expectEquals(runtime, {'tenant': 'acme'}, 'runtimeContext');
      for (final request in _chatRequests(ctx, server)) {
        ctx.expect(
          !request.bodyText.contains('secret-db-handle'),
          'tool context leaked to the provider',
        );
        ctx.expect(
          !request.bodyText.contains('acme'),
          'runtime context leaked to the provider',
        );
      }
    },
  ),

  Check(
    id: 'tool-definition-options',
    feature: 'text-tools',
    description:
        'Tool input examples, strict and descriptions reach the model call '
        'options, and providerDefinedTools are serialized next to function '
        'tools on the wire.',
    run: (ctx) async {
      ctx.note(
        'The Chat Completions adapter drops inputExamples, so that half '
        'reads the call options through a hand-written LanguageModelV4.',
      );
      final model = _ScriptedModel(
        generates: [
          const LanguageModelV4GenerateResult(
            content: [LanguageModelV4TextPart(text: 'ok')],
          ),
        ],
      );
      await generateText(
        model: model,
        prompt: 'go',
        tools: {
          'getWeather': tool<_Weather, String>(
            description: 'Weather lookup.',
            inputSchema: _weatherSchema,
            strict: true,
            inputExamples: const [
              ToolInputExample(input: {'city': 'Lima'}),
            ],
            execute: (input, _) async => 'x',
          ),
        },
      );
      final sent =
          model.calls.single.tools.single as LanguageModelV4FunctionTool;
      ctx.expectEquals(sent.name, 'getWeather', 'tool name');
      ctx.expectEquals(sent.description, 'Weather lookup.', 'description');
      ctx.expectEquals(sent.strict, true, 'strict');
      ctx.expectEquals(sent.inputSchema, _weatherJsonSchema, 'inputSchema');
      ctx.expectEquals(sent.inputExamples, [
        {'city': 'Lima'},
      ], 'inputExamples');

      final server = await ctx.server((_) => _text('ok'));
      await generateText(
        model: _model(ctx, server),
        prompt: 'go',
        tools: {'getWeather': _weatherTool()},
        providerDefinedTools: const [
          LanguageModelV4ProviderDefinedTool(
            id: 'web_search_preview',
            name: 'web_search',
            args: {'search_context_size': 'low'},
          ),
        ],
      );
      final tools =
          (ctx.singleRequest(server, _chatPath).jsonObject['tools'] as List)
              .cast<Map<String, dynamic>>();
      ctx.observe('tools', tools);
      ctx.expectEquals(tools.length, 2, 'tool count');
      ctx.expectEquals(tools[0]['type'], 'function', 'function tool type');
      ctx.expectEquals(tools[1], {
        'type': 'web_search_preview',
        'name': 'web_search',
        'search_context_size': 'low',
      }, 'provider-defined tool');
    },
  ),

  // ----- approvals -------------------------------------------------------
  Check(
    id: 'approval-generate',
    feature: 'text-approval',
    description:
        'needsApproval pauses the loop with an approval request and no '
        'execution; an approved response runs the tool, a denied one sends '
        'the reason back as an error result.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_a', 'getWeather', '{"city":"Rome"}'),
          _call('call_a', 'getWeather', '{"city":"Rome"}'),
          _text('Approved and done.'),
          _call('call_a', 'getWeather', '{"city":"Rome"}'),
          _text('Understood, skipping.'),
        ]),
      );
      var executions = 0;
      Map<String, Tool<dynamic, dynamic>> tools() => {
        'getWeather': _weatherTool(
          needsApproval: (_, _) => true,
          onRun: (_, _) => executions++,
        ),
      };
      final model = _model(ctx, server);
      final paused = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: tools(),
      );
      final request = paused.toolApprovalRequests.single;
      ctx.observe('approvalRequest', {
        'approvalId': request.approvalId,
        'toolCallId': request.toolCall.toolCallId,
        'policyRevision': request.policyRevision,
        'argumentsFingerprint': request.argumentsFingerprint,
      });
      ctx.expectEquals(executions, 0, 'executions while pending');
      ctx.expectEquals(paused.steps.length, 1, 'loop stops at the request');
      ctx.expectEquals(
        paused.steps.single.toolApprovalRequests.length,
        1,
        'step approval requests',
      );
      ctx.expectEquals(
        paused.finishReason,
        LanguageModelV4FinishReason.toolCalls,
        'finish reason',
      );
      ctx.expectEquals(
        _chatRequests(ctx, server).length,
        1,
        'requests while pending',
      );

      final approved = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: tools(),
        toolApprovalResponses: [
          LanguageModelV4ToolApprovalResponse(
            approvalId: request.approvalId,
            approved: true,
            toolCallId: request.toolCall.toolCallId,
            toolName: request.toolCall.toolName,
            argumentsFingerprint: request.argumentsFingerprint,
            policyRevision: request.policyRevision,
          ),
        ],
      );
      ctx.expectEquals(executions, 1, 'executions after approval');
      ctx.expectEquals(approved.text, 'Approved and done.', 'approved text');
      ctx.expectEquals(
        _messages(_chatRequests(ctx, server)[2]).last['content'],
        'Sunny, 18C in Rome',
        'approved tool result on the wire',
      );

      final denied = await generateText(
        model: model,
        prompt: 'go',
        maxSteps: 3,
        tools: tools(),
        toolApprovalResponses: [
          LanguageModelV4ToolApprovalResponse(
            approvalId: request.approvalId,
            approved: false,
            reason: 'User said no.',
            toolCallId: request.toolCall.toolCallId,
            toolName: request.toolCall.toolName,
            argumentsFingerprint: request.argumentsFingerprint,
            policyRevision: request.policyRevision,
          ),
        ],
      );
      ctx.expectEquals(executions, 1, 'executions after denial');
      ctx.expectEquals(
        denied.toolResults.single.isError,
        true,
        'denied result isError',
      );
      ctx.expect(
        '${_messages(_chatRequests(ctx, server)[4]).last['content']}'.contains(
          'User said no.',
        ),
        'denial reason missing on the wire',
      );
      ctx.expectEquals(denied.text, 'Understood, skipping.', 'denied text');
    },
  ),
  Check(
    id: 'approval-policy',
    feature: 'text-approval',
    description:
        'approvalPolicy forces approval, approvalPolicyFor picks per tool, '
        'and a response bound to an old policy revision asks again.',
    run: (ctx) async {
      var safeRuns = 0;
      var dangerRuns = 0;
      final tools = {
        'safe': _weatherTool(onRun: (_, _) => safeRuns++),
        'danger': _weatherTool(onRun: (_, _) => dangerRuns++),
      };
      final both = _calls([
        (id: 'c_safe', name: 'safe', args: '{"city":"A"}'),
        (id: 'c_danger', name: 'danger', args: '{"city":"B"}'),
      ]);

      final forced = await ctx.server(
        (_) => _call('c1', 'safe', '{"city":"A"}'),
      );
      final always = await generateText(
        model: _model(ctx, forced),
        prompt: 'go',
        maxSteps: 2,
        tools: tools,
        approvalPolicy: ToolApprovalPolicy.always,
      );
      ctx.expectEquals(
        always.toolApprovalRequests.length,
        1,
        'approvalPolicy.always requests',
      );
      ctx.expectEquals(safeRuns, 0, 'safe ran despite approvalPolicy.always');

      final selective = await ctx.server((_) => both);
      final mixed = await generateText(
        model: _model(ctx, selective),
        prompt: 'go',
        maxSteps: 2,
        tools: tools,
        approvalPolicyFor: (name, _) => name == 'danger'
            ? ToolApprovalPolicy.always
            : ToolApprovalPolicy.never,
      );
      ctx.expectEquals(safeRuns, 1, 'safe runs under approvalPolicyFor');
      ctx.expectEquals(dangerRuns, 0, 'danger waits under approvalPolicyFor');
      ctx.expectEquals(
        mixed.toolApprovalRequests.single.toolCall.toolName,
        'danger',
        'approval request tool',
      );

      final stale = await ctx.server(
        (_) => _call('c1', 'danger', '{"city":"B"}'),
      );
      final renewed = await generateText(
        model: _model(ctx, stale),
        prompt: 'go',
        maxSteps: 2,
        tools: tools,
        approvalPolicy: ToolApprovalPolicy.always,
        approvalPolicyRevision: 'v2',
        toolApprovalResponses: const [
          LanguageModelV4ToolApprovalResponse(
            approvalId: 'approval_c1',
            approved: true,
            toolCallId: 'c1',
            toolName: 'danger',
            argumentsFingerprint: '{"city":"B"}',
            policyRevision: 'v1',
          ),
        ],
      );
      ctx.observe(
        'renewedRevision',
        renewed.toolApprovalRequests.single.policyRevision,
      );
      ctx.expectEquals(dangerRuns, 0, 'stale approval executed the tool');
      ctx.expectEquals(
        renewed.toolApprovalRequests.single.policyRevision,
        'v2',
        'renewed request revision',
      );
    },
  ),
  Check(
    id: 'approval-agent-resume',
    feature: 'text-approval',
    description:
        'ToolLoopAgent.stream pauses on an approval request; resume runs '
        'the approved call under its original id and continues the turn.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _sseCall('call_r', 'getWeather', ['{"city":"Rome"}']),
          _sseText(['Resumed ', 'answer.']),
        ]),
      );
      var executions = 0;
      final agent = ToolLoopAgent(
        model: _model(ctx, server),
        maxSteps: 3,
        tools: {
          'getWeather': _weatherTool(
            needsApproval: (_, _) => true,
            onRun: (_, _) => executions++,
          ),
        },
      );
      final first = await agent.stream(prompt: 'Weather in Rome?');
      final steps = await first.steps;
      final request = steps.single.toolApprovalRequests.single;
      ctx.expectEquals(executions, 0, 'executions while paused');
      ctx.expectEquals(
        _chatRequests(ctx, server).length,
        1,
        'requests while paused',
      );

      final resumed = await agent.resume(
        replay: ToolApprovalReplay(
          messages: [
            const ModelMessage(
              role: ModelMessageRole.user,
              content: 'Weather in Rome?',
            ),
            ModelMessage.parts(
              role: ModelMessageRole.assistant,
              parts: [request.toolCall],
            ),
          ],
          requests: [request],
        ),
        toolApprovalResponses: [
          LanguageModelV4ToolApprovalResponse(
            approvalId: request.approvalId,
            approved: true,
            toolCallId: request.toolCall.toolCallId,
            toolName: request.toolCall.toolName,
            argumentsFingerprint: request.argumentsFingerprint,
            policyRevision: request.policyRevision,
          ),
        ],
      );
      final text = await resumed.text;
      final requests = _chatRequests(ctx, server);
      ctx.observe('resumeRoles', _roles(requests[1]));
      ctx.expectEquals(executions, 1, 'executions after resume');
      ctx.expectEquals(text, 'Resumed answer.', 'resumed text');
      ctx.expectEquals(_roles(requests[1]), [
        'user',
        'assistant',
        'tool',
      ], 'resume wire roles');
      final wire = _messages(requests[1]);
      ctx.expectEquals(
        ((wire[1]['tool_calls'] as List).single as Map)['id'],
        'call_r',
        'replayed call id',
      );
      ctx.expectEquals(wire[2]['tool_call_id'], 'call_r', 'tool_call_id');
      ctx.expectEquals(wire[2]['content'], 'Sunny, 18C in Rome', 'tool result');
    },
  ),

  // ----- agents ----------------------------------------------------------
  Check(
    id: 'agent-generate',
    feature: 'text-agent',
    description:
        'ToolLoopAgent.generate sends its instructions, runs the tool loop '
        'up to maxSteps and fires per-call callbacks.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _call('call_1', 'getWeather', '{"city":"Oslo"}'),
          _text('Cold in Oslo.'),
        ]),
      );
      final agent = ToolLoopAgent(
        model: _model(ctx, server),
        instructions: 'You are a weather agent.',
        maxSteps: 4,
        tools: {'getWeather': _weatherTool()},
      );
      final ends = <String>[];
      final result = await agent.generate(
        prompt: 'Weather in Oslo?',
        onStepEnd: (e) => ends.add('step${e.stepNumber}'),
        onEnd: (e) => ends.add('end'),
      );
      final requests = _chatRequests(ctx, server);
      ctx.expectEquals(
        _messages(requests[0]).first['content'],
        'You are a weather agent.',
        'instructions on the wire',
      );
      ctx.expectEquals(
        _messages(requests[1]).first['content'],
        'You are a weather agent.',
        'instructions kept in step 2',
      );
      ctx.expectEquals(result.text, 'Cold in Oslo.', 'text');
      ctx.expectEquals(result.steps.length, 2, 'steps');
      ctx.expectEquals(ends, ['step0', 'step1', 'end'], 'callbacks');
    },
  ),
  Check(
    id: 'agent-stream',
    feature: 'text-agent',
    description:
        'ToolLoopAgent.stream streams text from a tool loop and reports the '
        'finish through onEnd.',
    run: (ctx) async {
      final server = await ctx.server(
        _sequence([
          _sseCall('call_1', 'getWeather', ['{"city":"Oslo"}']),
          _sseText(['Cold ', 'in Oslo.']),
        ]),
      );
      final agent = ToolLoopAgent(
        model: _model(ctx, server),
        instructions: 'Weather agent.',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool()},
      );
      String? endText;
      final result = await agent.stream(
        prompt: 'Weather in Oslo?',
        onEnd: (e) => endText = e.text,
      );
      final deltas = _Drain(result.textStream);
      final text = await result.text;
      await deltas.done;
      ctx.observe('deltas', deltas.items);
      ctx.expectEquals(deltas.items, ['Cold ', 'in Oslo.'], 'streamed deltas');
      ctx.expectEquals(text, 'Cold in Oslo.', 'text');
      ctx.expectEquals(endText, 'Cold in Oslo.', 'onEnd text');
      ctx.expectEquals((await result.steps).length, 2, 'steps');
      ctx.expectEquals(
        _messages(_chatRequests(ctx, server)[0]).first['content'],
        'Weather agent.',
        'instructions',
      );
    },
  ),

  // ----- cancellation ----------------------------------------------------
  Check(
    id: 'cancel-generate',
    feature: 'text-cancel',
    description:
        'A token cancelled before the call sends nothing; one cancelled '
        'while the request is in flight rejects with AiOperationCancelledError '
        'long before the server answers.',
    run: (ctx) async {
      final server = await ctx.server((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        return _text('too late');
      });
      final model = _model(ctx, server);
      final before = CancellationToken()..cancel();
      await ctx.expectThrows<AiOperationCancelledError>(
        () => generateText(model: model, prompt: 'hi', abortSignal: before),
        'pre-cancelled',
      );
      ctx.expectEquals(
        _chatRequests(ctx, server).length,
        0,
        'requests after pre-cancel',
      );

      final token = CancellationToken();
      final watch = Stopwatch()..start();
      Timer(const Duration(milliseconds: 100), token.cancel);
      await ctx.expectThrows<AiOperationCancelledError>(
        () => generateText(
          model: model,
          prompt: 'hi',
          abortSignal: token,
          maxRetries: 0,
        ),
        'in-flight',
      );
      watch.stop();
      ctx.observe('cancelElapsedMs', watch.elapsedMilliseconds);
      ctx.expect(
        watch.elapsedMilliseconds < 1000,
        'cancel took ${watch.elapsedMilliseconds} ms',
      );
      ctx.expectEquals(
        _chatRequests(ctx, server).length,
        1,
        'in-flight request reached the server',
      );
    },
  ),
  Check(
    id: 'cancel-stream',
    feature: 'text-cancel',
    description:
        'Cancelling during a streamed response fires onAbort, stops the '
        'text deltas and rejects the result futures.',
    run: (ctx) async {
      ctx.note(
        'Uses a paced loopback SSE server (see _PacedSseServer): the harness '
        'fixture server buffers delayed chunks until the response ends.',
      );
      final server = await _PacedSseServer.start(
        ctx,
        _sseTextEvents([for (var i = 0; i < 12; i++) 'w$i ']),
        const Duration(milliseconds: 100),
      );
      final token = CancellationToken();
      var aborts = 0;
      final result = await streamText(
        model: _modelAt(ctx, server.origin),
        prompt: 'long answer',
        abortSignal: token,
        maxRetries: 0,
        onAbort: () => aborts++,
      );
      final deltas = <String>[];
      final errors = <Object>[];
      final done = Completer<void>();
      final watch = Stopwatch()..start();
      result.textStream.listen(
        (delta) {
          deltas.add(delta);
          if (deltas.length == 2) token.cancel();
        },
        onError: (Object e, StackTrace _) => errors.add(e),
        onDone: done.complete,
      );
      await ctx.expectThrows<AiOperationCancelledError>(
        () => result.text,
        'result.text',
      );
      final rejectedAtMs = watch.elapsedMilliseconds;
      await done.future;
      watch.stop();
      ctx.observe('deltas', deltas);
      ctx.observe('textRejectedAtMs', rejectedAtMs);
      ctx.observe('textStreamClosedAtMs', watch.elapsedMilliseconds);
      ctx.observe('elapsedMs', watch.elapsedMilliseconds);
      await server.closedEarly.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      ctx.observe('serverEventsWritten', server.sent);
      ctx.observe('clientClosedConnection', server.clientClosedEarly);
      ctx.expect(
        server.clientClosedEarly,
        'the client kept the connection open after cancel',
      );
      ctx.expectEquals(aborts, 1, 'onAbort calls');
      ctx.expect(
        deltas.length >= 2 && deltas.length < 12,
        'expected a partial stream, got ${deltas.length} deltas',
      );
      ctx.expect(
        rejectedAtMs < 600,
        'result.text rejected after $rejectedAtMs ms',
      );
      ctx.expect(server.sent < 10, 'server wrote ${server.sent} events');
    },
  ),
  Check(
    id: 'cancel-tool-signal',
    feature: 'text-cancel',
    description:
        'The abort signal reaches a running tool through ToolExecutionOptions, '
        'and cancelling rejects the call without waiting for the tool.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => _call('call_s', 'getWeather', '{"city":"Rome"}'),
      );
      final token = CancellationToken();
      var toolSawCancel = false;
      var signalPassed = false;
      final slow = tool<_Weather, String>(
        inputSchema: _weatherSchema,
        execute: (input, options) async {
          signalPassed = options.abortSignal != null;
          unawaited(
            options.abortSignal!.onCancelled.then((_) => toolSawCancel = true),
          );
          await Future<void>.delayed(const Duration(seconds: 3));
          return 'late';
        },
      );
      Timer(const Duration(milliseconds: 150), token.cancel);
      final watch = Stopwatch()..start();
      await ctx.expectThrows<AiOperationCancelledError>(
        () => generateText(
          model: _model(ctx, server),
          prompt: 'go',
          maxSteps: 2,
          abortSignal: token,
          tools: {'getWeather': slow},
        ),
        'generateText',
      );
      watch.stop();
      ctx.observe('elapsedMs', watch.elapsedMilliseconds);
      ctx.expect(signalPassed, 'tool did not receive an abort signal');
      ctx.expect(toolSawCancel, 'tool did not observe the cancellation');
      ctx.expect(
        watch.elapsedMilliseconds < 2000,
        'call waited ${watch.elapsedMilliseconds} ms for the tool',
      );
    },
  ),

  // ----- timeouts --------------------------------------------------------
  Check(
    id: 'timeout-total',
    feature: 'text-timeout',
    description:
        'TimeoutConfiguration.total and .step end a slow generateText call '
        'with a TimeoutException.',
    run: (ctx) async {
      final server = await ctx.server((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        return _text('too late');
      });
      final model = _model(ctx, server);
      for (final (label, config) in <(String, TimeoutConfiguration)>[
        (
          'total',
          const TimeoutConfiguration(total: Duration(milliseconds: 150)),
        ),
        ('step', const TimeoutConfiguration(step: Duration(milliseconds: 150))),
      ]) {
        final watch = Stopwatch()..start();
        await ctx.expectThrows<TimeoutException>(
          () => generateText(
            model: model,
            prompt: 'hi',
            maxRetries: 0,
            timeout: config,
          ),
          'timeout.$label',
        );
        watch.stop();
        ctx.observe('${label}ElapsedMs', watch.elapsedMilliseconds);
        ctx.expect(
          watch.elapsedMilliseconds < 1200,
          '$label timeout took ${watch.elapsedMilliseconds} ms',
        );
      }
    },
  ),
  Check(
    id: 'timeout-stream-chunk',
    feature: 'text-timeout',
    description:
        'TimeoutConfiguration.chunk ends a stream whose next chunk is too '
        'late and firstChunk ends one that never starts; deltas received '
        'before the timeout are still delivered, and the connection is closed.',
    run: (ctx) async {
      ctx.note(
        'Uses a paced loopback SSE server (see _PacedSseServer): the harness '
        'fixture server buffers delayed chunks until the response ends.',
      );
      final server = await _PacedSseServer.start(
        ctx,
        _sseTextEvents(['a ', 'b ', 'c ']),
        const Duration(milliseconds: 400),
      );
      final result = await streamText(
        model: _modelAt(ctx, server.origin),
        prompt: 'hi',
        maxRetries: 0,
        timeout: const TimeoutConfiguration(
          firstChunk: Duration(seconds: 2),
          chunk: Duration(milliseconds: 150),
        ),
      );
      final deltas = _Drain(result.textStream);
      final error = await ctx.expectThrows<TimeoutException>(
        () => result.text,
        'result.text',
      );
      await deltas.done;
      ctx.observe('message', error.message);
      ctx.observe('deltas', deltas.items);
      ctx.expect(
        deltas.items.length < 3,
        'stream completed despite the chunk timeout',
      );
      await server.closedEarly.future.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      );
      ctx.expect(
        server.clientClosedEarly,
        'the client kept the connection open after the timeout',
      );

      final late = await _PacedSseServer.start(
        ctx,
        _sseTextEvents(['x ']),
        const Duration(milliseconds: 500),
      );
      final first = await streamText(
        model: _modelAt(ctx, late.origin),
        prompt: 'hi',
        maxRetries: 0,
        timeout: const TimeoutConfiguration(
          firstChunk: Duration(milliseconds: 150),
        ),
      );
      final firstDeltas = _Drain(first.textStream);
      await ctx.expectThrows<TimeoutException>(
        () => first.text,
        'firstChunk timeout',
      );
      await firstDeltas.done;
      ctx.expectEquals(
        firstDeltas.items,
        <String>[],
        'no delta before firstChunk',
      );
    },
  ),
  Check(
    id: 'timeout-tool',
    feature: 'text-timeout',
    description:
        'TimeoutConfiguration.tools gives one tool its own deadline and '
        'TimeoutConfiguration.tool is the default for the others.',
    run: (ctx) async {
      Future<TimeoutException> run(TimeoutConfiguration config) async {
        final server = await ctx.server(
          (_) => _call('call_t', 'getWeather', '{"city":"Rome"}'),
        );
        return ctx.expectThrows<TimeoutException>(
          () => generateText(
            model: _model(ctx, server),
            prompt: 'go',
            maxSteps: 2,
            timeout: config,
            tools: {
              'getWeather': _weatherTool(delay: const Duration(seconds: 3)),
            },
          ),
          'tool timeout',
        );
      }

      final watch = Stopwatch()..start();
      final perTool = await run(
        const TimeoutConfiguration(
          tools: {'getWeather': Duration(milliseconds: 120)},
        ),
      );
      final fallback = await run(
        const TimeoutConfiguration(tool: Duration(milliseconds: 120)),
      );
      watch.stop();
      ctx.observe('perToolMessage', perTool.message);
      ctx.observe('fallbackMessage', fallback.message);
      ctx.expect(
        '${perTool.message}'.contains('getWeather'),
        'per-tool timeout does not name the tool',
      );
      ctx.expect(
        watch.elapsedMilliseconds < 2500,
        'tool timeouts took ${watch.elapsedMilliseconds} ms',
      );
    },
  ),
];

// ---------------------------------------------------------------------------
// Typed structured-output fixture
// ---------------------------------------------------------------------------

class _Recipe {
  _Recipe(this.name, this.minutes);
  factory _Recipe.fromJson(Map<String, dynamic> json) =>
      _Recipe(json['name'] as String, json['minutes'] as int);
  final String name;
  final int minutes;
}

const _recipeJsonSchema = {
  'type': 'object',
  'properties': {
    'name': {'type': 'string'},
    'minutes': {'type': 'integer'},
  },
  'required': ['name', 'minutes'],
  'additionalProperties': false,
};

final _recipeSchema = Schema<_Recipe>(
  jsonSchema: _recipeJsonSchema,
  fromJson: _Recipe.fromJson,
);
