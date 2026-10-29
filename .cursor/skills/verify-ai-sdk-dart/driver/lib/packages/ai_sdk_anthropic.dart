// Verification checks for package:ai_sdk_anthropic.
// See features/ai_sdk_anthropic.md.
//
// Fixture checks answer in the Anthropic Messages API wire format (JSON
// bodies and named SSE events). Live checks go to api.anthropic.com through a
// recording Dio and need ANTHROPIC_API_KEY.
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_anthropic';
const _liveBaseUrl = 'https://api.anthropic.com/v1';

/// A provider that talks to the fixture server through an injected client.
AnthropicProvider _provider(
  CheckContext ctx,
  FixtureServer server, {
  String apiKey = 'verify-key',
}) {
  final dio = Dio(BaseOptions(baseUrl: server.url('/v1')));
  ctx.onCleanup(() async => dio.close(force: true));
  return AnthropicProvider(apiKey: apiKey, client: dio);
}

LanguageModelV4 _model(CheckContext ctx, FixtureServer server) =>
    _provider(ctx, server)('claude-verify');

Map<String, Object?> _message({
  required List<Map<String, Object?>> content,
  String? stopReason = 'end_turn',
  String? stopSequence,
  Map<String, Object?>? usage,
}) => {
  'id': 'msg_01VerifyFixture',
  'type': 'message',
  'role': 'assistant',
  'model': 'claude-verify',
  'content': content,
  'stop_reason': stopReason,
  'stop_sequence': stopSequence,
  'usage': usage ?? {'input_tokens': 12, 'output_tokens': 7},
};

Map<String, Object?> _text(String text) => {'type': 'text', 'text': text};

Map<String, Object?> _toolUse(
  String id,
  String name,
  Map<String, Object?> in_,
) => {'type': 'tool_use', 'id': id, 'name': name, 'input': in_};

SseEvent _ev(String type, [Map<String, Object?> fields = const {}]) =>
    SseEvent({'type': type, ...fields}, event: type);

SseEvent _messageStart({Map<String, Object?>? usage}) => _ev('message_start', {
  'message': {
    'id': 'msg_01VerifyStream',
    'type': 'message',
    'role': 'assistant',
    'model': 'claude-verify',
    'content': <Object>[],
    'stop_reason': null,
    'stop_sequence': null,
    'usage': usage ?? {'input_tokens': 25, 'output_tokens': 1},
  },
});

SseEvent _blockStart(int index, Map<String, Object?> block) =>
    _ev('content_block_start', {'index': index, 'content_block': block});

SseEvent _blockDelta(int index, Map<String, Object?> delta) =>
    _ev('content_block_delta', {'index': index, 'delta': delta});

SseEvent _blockStop(int index) => _ev('content_block_stop', {'index': index});

SseEvent _messageDelta(String stopReason, {int outputTokens = 15}) =>
    _ev('message_delta', {
      'delta': {'stop_reason': stopReason, 'stop_sequence': null},
      'usage': {'output_tokens': outputTokens},
    });

List<SseEvent> _textStream(List<String> pieces) => [
  _messageStart(),
  _blockStart(0, {'type': 'text', 'text': ''}),
  _ev('ping'),
  for (final piece in pieces)
    _blockDelta(0, {'type': 'text_delta', 'text': piece}),
  _blockStop(0),
  _messageDelta('end_turn'),
  _ev('message_stop'),
];

final _citySchema = Schema<Map<String, dynamic>>(
  jsonSchema: const {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
    },
    'required': ['city'],
    'additionalProperties': false,
  },
  fromJson: (json) => json,
);

Tool<Map<String, dynamic>, String> _weatherTool(void Function() onRun) =>
    tool<Map<String, dynamic>, String>(
      description: 'Get current weather for a city.',
      inputSchema: _citySchema,
      execute: (input, _) async {
        onRun();
        return 'Sunny, 18C in ${input['city']}';
      },
    );

Map<String, Object?> _errorBody(String type, String message) => {
  'type': 'error',
  'error': {'type': type, 'message': message},
  'request_id': 'req_verify',
};

List<Map<dynamic, dynamic>> _messagesOf(FixtureRequest request) =>
    (request.jsonObject['messages'] as List).cast<Map>();

final checks = PackageChecks(_package, [
  Check(
    id: 'provider-headers',
    feature: 'anthropic-provider',
    description:
        'A request carries x-api-key, anthropic-version and per-call custom '
        'headers; a credentialProvider supplies the key lazily.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_message(content: [_text('ok')])),
      );
      await generateText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxOutputTokens: 16,
        headers: {'x-verify-trace': 'trace-1'},
      );
      final dio = Dio(BaseOptions(baseUrl: server.url('/v1')));
      ctx.onCleanup(() async => dio.close(force: true));
      var resolved = 0;
      final lazy = AnthropicProvider(
        credentialProvider: () async {
          resolved++;
          return 'lazy-key';
        },
        client: dio,
      );
      await generateText(
        model: lazy('claude-verify'),
        prompt: 'hi',
        maxOutputTokens: 16,
      );
      final requests = ctx.requestsTo(server, '/v1/messages', method: 'POST');
      ctx.expectEquals(requests.length, 2, 'request count');
      ctx.expectEquals(requests[0].headers['x-api-key'], 'verify-key', 'key');
      ctx.expectEquals(
        requests[0].headers['anthropic-version'],
        '2023-06-01',
        'anthropic-version',
      );
      ctx.expectEquals(
        requests[0].headers['x-verify-trace'],
        'trace-1',
        'custom header',
      );
      ctx.expect(
        !(requests[0].headers['authorization'] ?? '').startsWith('Bearer'),
        'Anthropic must not use a Bearer token',
      );
      ctx.expectEquals(
        requests[1].headers['x-api-key'],
        'lazy-key',
        'lazy key',
      );
      ctx.expectEquals(resolved, 1, 'credentialProvider calls');
      ctx.observe('requestCount', requests.length);
    },
  ),
  Check(
    id: 'provider-base-url-dispose',
    feature: 'anthropic-provider',
    description:
        'baseUrl routes an owned client to a proxy path; dispose() closes an '
        'owned client but leaves an injected one usable.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_message(content: [_text('via proxy')])),
      );
      final owned = AnthropicProvider(
        apiKey: 'verify-key',
        baseUrl: server.url('/proxy/v1'),
      );
      final result = await generateText(
        model: owned('claude-verify'),
        prompt: 'hi',
        maxOutputTokens: 16,
      );
      owned.dispose();
      final request = ctx.singleRequest(
        server,
        '/proxy/v1/messages',
        method: 'POST',
      );
      ctx.expectEquals(result.text, 'via proxy', 'text');
      ctx.expectEquals(
        request.headers['anthropic-version'],
        '2023-06-01',
        'anthropic-version on owned client',
      );
      final injected = Dio(BaseOptions(baseUrl: server.url('/v1')));
      ctx.onCleanup(() async => injected.close(force: true));
      AnthropicProvider(apiKey: 'k', client: injected).dispose();
      final after = await injected.get<Object?>('/still-open');
      ctx.observe('injectedClientStatusAfterDispose', after.statusCode);
      ctx.expectEquals(after.statusCode, 200, 'injected client after dispose');
    },
  ),
  Check(
    id: 'generate-text',
    feature: 'anthropic-generate',
    description:
        'generateText posts to /messages with model, max_tokens, system and '
        'messages, and returns text, usage, finish reason and response id.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _message(content: [_text('Hello from the fixture.')]),
        ),
      );
      final result = await generateText(
        model: _model(ctx, server),
        system: 'Be brief.',
        prompt: 'Say hello.',
        maxOutputTokens: 64,
        temperature: 0.2,
        topP: 0.9,
        stopSequences: ['STOP'],
      );
      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      ctx.observe('finishReason', '${result.finishReason}');
      final request = ctx.singleRequest(server, '/v1/messages', method: 'POST');
      final body = request.jsonObject;
      ctx.expectEquals(body['model'], 'claude-verify', 'model');
      ctx.expectEquals(body['max_tokens'], 64, 'max_tokens');
      ctx.expectEquals(body['system'], 'Be brief.', 'system prompt');
      ctx.expectEquals(body['temperature'], 0.2, 'temperature');
      ctx.expectEquals(body['top_p'], 0.9, 'top_p');
      ctx.expectEquals(body['stop_sequences'], ['STOP'], 'stop_sequences');
      ctx.expect(body['stream'] != true, 'non-streaming call sent stream=true');
      final messages = _messagesOf(request);
      ctx.expectEquals(messages.length, 1, 'message count');
      ctx.expectEquals(messages.single['role'], 'user', 'role');
      ctx.expectEquals(messages.single['content'], [
        {'type': 'text', 'text': 'Say hello.'},
      ], 'user content blocks');
      ctx.expectEquals(result.text, 'Hello from the fixture.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 12, 'input tokens');
      ctx.expectEquals(result.usage?.outputTokens.total, 7, 'output tokens');
      ctx.expectEquals(
        result.finishReason,
        LanguageModelV4FinishReason.stop,
        'finish reason',
      );
      ctx.expectEquals(result.rawFinishReason, 'end_turn', 'raw finish reason');
    },
  ),
  Check(
    id: 'stream-text',
    feature: 'anthropic-stream',
    description:
        'streamText sends stream=true and turns the named SSE events '
        '(message_start, content_block_*, ping, message_delta, message_stop) '
        'into ordered text deltas, usage and a finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse(_textStream(['One, ', 'two, ', 'three.'])),
      );
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Count to three.',
        maxOutputTokens: 64,
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      final finish = await result.finishReason;
      ctx.observe('deltas', deltas);
      ctx.observe('usage', usage);
      ctx.observe('finishReason', '$finish');
      final body = ctx.singleRequest(server, '/v1/messages').jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(body['max_tokens'], 64, 'max_tokens');
      ctx.expectEquals(deltas.join(), 'One, two, three.', 'streamed text');
      ctx.expectEquals(deltas.length, 3, 'delta count');
      ctx.expectEquals(usage?.inputTokens.total, 25, 'input tokens');
      ctx.expectEquals(usage?.outputTokens.total, 15, 'output tokens');
      ctx.expectEquals(finish, LanguageModelV4FinishReason.stop, 'finish');
    },
  ),
  Check(
    id: 'tool-loop',
    feature: 'anthropic-tools',
    description:
        'A tool_use block is executed and its result goes back as a '
        'tool_result block with the same tool_use_id; the second response is '
        'the final text. Tools are sent with input_schema.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _message(
              stopReason: 'tool_use',
              content: [
                _text('Let me check.'),
                _toolUse('toolu_01Verify', 'getWeather', {'city': 'Paris'}),
              ],
            ),
          );
        }
        return FixtureResponse.json(
          _message(content: [_text('It is sunny in Paris.')]),
        );
      });
      var executions = 0;
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather in Paris?',
        maxOutputTokens: 64,
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(() => executions++)},
      );
      ctx.observe('text', result.text);
      ctx.observe('steps', result.steps.length);
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, '/v1/messages');
      ctx.expectEquals(requests.length, 2, 'request count');
      final tools = (requests[0].jsonObject['tools'] as List).cast<Map>();
      ctx.expectEquals(tools.single['name'], 'getWeather', 'tool name');
      ctx.expectEquals((tools.single['input_schema'] as Map)['required'], [
        'city',
      ], 'input_schema.required');
      final followUp = _messagesOf(requests[1]);
      final assistant = followUp.firstWhere((m) => m['role'] == 'assistant');
      final toolUse = (assistant['content'] as List).cast<Map>().firstWhere(
        (b) => b['type'] == 'tool_use',
      );
      ctx.expectEquals(toolUse['id'], 'toolu_01Verify', 'echoed tool_use id');
      final toolResult = (followUp.last['content'] as List).cast<Map>().single;
      ctx.expectEquals(followUp.last['role'], 'user', 'tool_result role');
      ctx.expectEquals(toolResult['type'], 'tool_result', 'block type');
      ctx.expectEquals(toolResult['tool_use_id'], 'toolu_01Verify', 'id');
      ctx.expectEquals(toolResult['content'], 'Sunny, 18C in Paris', 'content');
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(result.text, 'It is sunny in Paris.', 'final text');
    },
  ),
  Check(
    id: 'stream-tool-loop',
    feature: 'anthropic-tools',
    description:
        'A streamed tool_use block assembled from input_json_delta fragments '
        'runs the tool once and the follow-up request carries its tool_result.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.sse([
            _messageStart(),
            _blockStart(0, {
              'type': 'tool_use',
              'id': 'toolu_01Stream',
              'name': 'getWeather',
              'input': <String, Object?>{},
            }),
            _blockDelta(0, {'type': 'input_json_delta', 'partial_json': ''}),
            _blockDelta(0, {
              'type': 'input_json_delta',
              'partial_json': '{"city": ',
            }),
            _blockDelta(0, {
              'type': 'input_json_delta',
              'partial_json': '"Rome"}',
            }),
            _blockStop(0),
            _messageDelta('tool_use'),
            _ev('message_stop'),
          ]);
        }
        return FixtureResponse.sse(_textStream(['Rome is sunny.']));
      });
      var executions = 0;
      String? seenCity;
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Weather in Rome?',
        maxOutputTokens: 64,
        maxSteps: 3,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: 'Get current weather for a city.',
            inputSchema: _citySchema,
            execute: (input, _) async {
              executions++;
              seenCity = input['city'] as String?;
              return 'Sunny, 20C in ${input['city']}';
            },
          ),
        },
      );
      final text = (await result.textStream.toList()).join();
      ctx.observe('text', text);
      ctx.observe('executions', executions);
      ctx.observe('city', seenCity);
      final requests = ctx.requestsTo(server, '/v1/messages');
      ctx.expectEquals(requests.length, 2, 'request count');
      ctx.expectEquals(requests[0].jsonObject['stream'], true, 'stream flag');
      final toolResult = (_messagesOf(requests[1]).last['content'] as List)
          .cast<Map>()
          .single;
      ctx.expectEquals(toolResult['tool_use_id'], 'toolu_01Stream', 'id');
      ctx.expectEquals(toolResult['content'], 'Sunny, 20C in Rome', 'content');
      ctx.expectEquals(seenCity, 'Rome', 'tool input assembled from fragments');
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(text, 'Rome is sunny.', 'final text');
    },
  ),
  Check(
    id: 'tool-choice',
    feature: 'anthropic-tool-choice',
    description:
        'ToolChoice auto, required, none and specific map to tool_choice '
        'auto, any, none and tool+name.',
    run: (ctx) async {
      final server = await ctx.server(
        (request) => FixtureResponse.json(
          request.index == 1 || request.index == 3
              ? _message(
                  stopReason: 'tool_use',
                  content: [
                    _toolUse('toolu_01Choice', 'getWeather', {'city': 'Rome'}),
                  ],
                )
              : _message(content: [_text('ok')]),
        ),
      );
      final choices = <String, LanguageModelV4ToolChoice>{
        'auto': const ToolChoiceAuto(),
        'required': const ToolChoiceRequired(),
        'none': const ToolChoiceNone(),
        'specific': const ToolChoiceSpecific(toolName: 'getWeather'),
      };
      for (final choice in choices.values) {
        await generateText(
          model: _model(ctx, server),
          prompt: 'weather?',
          maxOutputTokens: 16,
          toolChoice: choice,
          tools: {'getWeather': _weatherTool(() {})},
        );
      }
      final requests = ctx.requestsTo(server, '/v1/messages');
      ctx.expectEquals(requests.length, 4, 'request count');
      final sent = [for (final r in requests) r.jsonObject['tool_choice']];
      ctx.observe('tool_choice', sent);
      ctx.expectEquals(sent, [
        {'type': 'auto'},
        {'type': 'any'},
        {'type': 'none'},
        {'type': 'tool', 'name': 'getWeather'},
      ], 'tool_choice values');
    },
  ),
  Check(
    id: 'structured-output',
    feature: 'anthropic-structured',
    description:
        'Output.object sends output_config.format json_schema and parses the '
        'JSON text reply into the typed output.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _message(content: [_text('{"capital":"Tokyo","currency":"JPY"}')]),
        ),
      );
      final result = await generateText<Map<String, dynamic>>(
        model: _model(ctx, server),
        prompt: 'Capital and currency of Japan.',
        maxOutputTokens: 64,
        output: Output.object(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'capital': {'type': 'string'},
                'currency': {'type': 'string'},
              },
              'required': ['capital', 'currency'],
              'additionalProperties': false,
            },
            fromJson: (json) => json,
          ),
        ),
      );
      ctx.observe('output', result.output);
      final body = ctx.singleRequest(server, '/v1/messages').jsonObject;
      final format = (body['output_config'] as Map?)?['format'] as Map?;
      ctx.expectEquals(format?['type'], 'json_schema', 'format.type');
      ctx.expectEquals((format?['schema'] as Map?)?['required'], [
        'capital',
        'currency',
      ], 'format.schema.required');
      ctx.expectEquals(result.output, {
        'capital': 'Tokyo',
        'currency': 'JPY',
      }, 'output');
    },
  ),
  Check(
    id: 'thinking-generate',
    feature: 'anthropic-thinking',
    description:
        'AnthropicThinkingOptions sends thinking {type: enabled, '
        'budget_tokens}; thinking and redacted_thinking blocks come back as '
        'reasoning parts, with the signature kept.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _message(
            content: [
              {
                'type': 'thinking',
                'thinking': 'Subtract 5, then divide by 3.',
                'signature': 'EqQBCgIYAhIM-verify-signature',
              },
              {'type': 'redacted_thinking', 'data': 'EmwKAhgBEgy-redacted'},
              _text('x = 5'),
            ],
            usage: {'input_tokens': 20, 'output_tokens': 40},
          ),
        ),
      );
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Solve 3x + 5 = 20.',
        maxOutputTokens: 2048,
        providerOptions: {
          'anthropic': const AnthropicThinkingOptions(
            budgetTokens: 1024,
          ).toMap(),
        },
      );
      ctx.observe('reasoning', result.reasoning.map((r) => r.text).toList());
      ctx.observe('text', result.text);
      final body = ctx.singleRequest(server, '/v1/messages').jsonObject;
      ctx.expectEquals(body['thinking'], {
        'type': 'enabled',
        'budget_tokens': 1024,
      }, 'thinking');
      ctx.expectEquals(body['max_tokens'], 2048, 'max_tokens above budget');
      ctx.expect(
        !body.containsKey('anthropic'),
        'provider options leaked into the body',
      );
      ctx.expectEquals(
        result.reasoning.first.text,
        'Subtract 5, then divide by 3.',
        'reasoning text',
      );
      ctx.expectEquals(
        result.reasoning.first.signature,
        'EqQBCgIYAhIM-verify-signature',
        'signature',
      );
      ctx.expect(
        result.content
                .whereType<LanguageModelV4RedactedReasoningPart>()
                .length ==
            1,
        'redacted_thinking block was dropped',
      );
      ctx.expectEquals(result.text, 'x = 5', 'final text');
    },
  ),
  Check(
    id: 'thinking-continuation',
    feature: 'anthropic-thinking',
    description:
        'In a tool loop with thinking, the follow-up request replays the '
        'signed thinking block before tool_use, then the tool_result.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _message(
              stopReason: 'tool_use',
              content: [
                {
                  'type': 'thinking',
                  'thinking': 'I should call the weather tool.',
                  'signature': 'sig-continuation-1',
                },
                _toolUse('toolu_01Think', 'getWeather', {'city': 'Oslo'}),
              ],
            ),
          );
        }
        return FixtureResponse.json(
          _message(content: [_text('Cold in Oslo.')]),
        );
      });
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather in Oslo?',
        maxOutputTokens: 2048,
        maxSteps: 3,
        providerOptions: {
          'anthropic': const AnthropicThinkingOptions(
            budgetTokens: 1024,
          ).toMap(),
        },
        tools: {'getWeather': _weatherTool(() {})},
      );
      final requests = ctx.requestsTo(server, '/v1/messages');
      ctx.expectEquals(requests.length, 2, 'request count');
      for (final r in requests) {
        ctx.expectEquals(r.jsonObject['thinking'], {
          'type': 'enabled',
          'budget_tokens': 1024,
        }, 'thinking on request ${r.index}');
      }
      final messages = _messagesOf(requests[1]);
      final assistant = messages.firstWhere((m) => m['role'] == 'assistant');
      final blocks = (assistant['content'] as List).cast<Map>();
      ctx.observe('assistantBlocks', blocks);
      ctx.expectEquals(blocks.map((b) => b['type']).toList(), [
        'thinking',
        'tool_use',
      ], 'assistant block order');
      ctx.expectEquals(blocks[0]['signature'], 'sig-continuation-1', 'sig');
      ctx.expectEquals(
        blocks[0]['thinking'],
        'I should call the weather tool.',
        'thinking text',
      );
      ctx.expectEquals(
        ((messages.last['content'] as List).cast<Map>().single)['tool_use_id'],
        'toolu_01Think',
        'tool_result id',
      );
      ctx.expectEquals(result.text, 'Cold in Oslo.', 'final text');
    },
  ),
  Check(
    id: 'thinking-stream',
    feature: 'anthropic-thinking',
    description:
        'Streamed thinking_delta and signature_delta events become reasoning '
        'start/delta/end parts whose end carries the joined signature; a '
        'tool loop replays the signed block.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.sse([
            _messageStart(),
            _blockStart(0, {'type': 'thinking', 'thinking': ''}),
            _blockDelta(0, {'type': 'thinking_delta', 'thinking': 'Need the '}),
            _blockDelta(0, {
              'type': 'thinking_delta',
              'thinking': 'weather tool.',
            }),
            _blockDelta(0, {'type': 'signature_delta', 'signature': 'sig-'}),
            _blockDelta(0, {'type': 'signature_delta', 'signature': 'stream'}),
            _blockStop(0),
            _blockStart(1, {
              'type': 'tool_use',
              'id': 'toolu_01StreamThink',
              'name': 'getWeather',
              'input': <String, Object?>{},
            }),
            _blockDelta(1, {
              'type': 'input_json_delta',
              'partial_json': '{"city":"Lima"}',
            }),
            _blockStop(1),
            _messageDelta('tool_use'),
            _ev('message_stop'),
          ]);
        }
        return FixtureResponse.sse(_textStream(['Mild in Lima.']));
      });
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Weather in Lima?',
        maxOutputTokens: 2048,
        maxSteps: 3,
        providerOptions: {
          'anthropic': const AnthropicThinkingOptions(
            budgetTokens: 1024,
          ).toMap(),
        },
        tools: {'getWeather': _weatherTool(() {})},
      );
      final parts = await result.providerStream.toList();
      final reasoningDeltas = parts
          .whereType<StreamPartReasoningDelta>()
          .map((p) => p.delta)
          .toList();
      final ends = parts.whereType<StreamPartReasoningEnd>().toList();
      ctx.observe('reasoningDeltas', reasoningDeltas);
      ctx.observe('reasoningEndSignatures', [
        for (final e in ends) e.signature,
      ]);
      ctx.expectEquals(
        reasoningDeltas.join(),
        'Need the weather tool.',
        'reasoning text',
      );
      ctx.expectEquals(ends.first.signature, 'sig-stream', 'joined signature');
      final requests = ctx.requestsTo(server, '/v1/messages');
      ctx.expectEquals(requests.length, 2, 'request count');
      final assistant = _messagesOf(
        requests[1],
      ).firstWhere((m) => m['role'] == 'assistant');
      final blocks = (assistant['content'] as List).cast<Map>();
      ctx.expectEquals(blocks.map((b) => b['type']).toList(), [
        'thinking',
        'tool_use',
      ], 'assistant block order');
      ctx.expectEquals(blocks[0]['signature'], 'sig-stream', 'replayed sig');
      ctx.expectEquals(
        blocks[0]['thinking'],
        'Need the weather tool.',
        'replayed thinking',
      );
    },
  ),
  Check(
    id: 'reasoning-options',
    feature: 'anthropic-thinking',
    description:
        'Adaptive thinking with effort, speed: fast, and the portable '
        'reasoning level map to the right thinking and output_config fields.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_message(content: [_text('ok')])),
      );
      Future<Map<String, dynamic>> send({
        String modelId = 'claude-verify',
        Map<String, dynamic>? options,
        LanguageModelV4Reasoning reasoning =
            LanguageModelV4Reasoning.providerDefault,
        int? maxOutputTokens = 4096,
      }) async {
        await generateText(
          model: _provider(ctx, server)(modelId),
          prompt: 'hi',
          maxOutputTokens: maxOutputTokens,
          reasoning: reasoning,
          providerOptions: options == null ? null : {'anthropic': options},
        );
        return server.requests.last.jsonObject;
      }

      final adaptive = await send(
        options: const AnthropicLanguageModelOptions(
          thinking: AnthropicThinkingOptions(adaptive: true),
          effort: 'high',
        ).toMap(),
      );
      final fast = await send(
        options: const AnthropicThinkingOptions(
          budgetTokens: 2048,
          speed: 'fast',
        ).toMap(),
      );
      final legacy = await send(
        modelId: 'claude-sonnet-4-5',
        reasoning: LanguageModelV4Reasoning.high,
      );
      final modern = await send(
        modelId: 'claude-opus-4-7',
        reasoning: LanguageModelV4Reasoning.high,
      );
      ctx.observe('adaptive', adaptive['thinking']);
      ctx.observe('fast', fast['thinking']);
      ctx.observe('legacyHigh', legacy['thinking']);
      ctx.observe('modernHigh', [modern['thinking'], modern['output_config']]);
      ctx.expectEquals(adaptive['thinking'], {'type': 'adaptive'}, 'adaptive');
      ctx.expectEquals(
        (adaptive['output_config'] as Map)['effort'],
        'high',
        'effort',
      );
      ctx.expectEquals(fast['thinking'], {'type': 'disabled'}, 'fast');
      ctx.expectEquals(legacy['thinking'], {
        'type': 'enabled',
        'budget_tokens': 2458,
      }, 'legacy high budget (60% of 4096)');
      ctx.expectEquals(modern['thinking'], {'type': 'adaptive'}, 'modern');
      ctx.expectEquals(
        (modern['output_config'] as Map)['effort'],
        'high',
        'modern effort',
      );
    },
  ),
  Check(
    id: 'prompt-cache-control',
    feature: 'anthropic-cache',
    description:
        'AnthropicCacheControlOptions becomes a top-level cache_control with '
        'ttl, and a part-level cacheControl option lands on that content '
        'block.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_message(content: [_text('ok')])),
      );
      await generateText(
        model: _model(ctx, server),
        maxOutputTokens: 16,
        providerOptions: {
          'anthropic': const AnthropicLanguageModelOptions(
            cacheControl: AnthropicCacheControlOptions(ttl: '1h'),
          ).toMap(),
        },
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [
              const LanguageModelV4TextPart(
                text: 'Long, reusable context.',
                providerOptions: {
                  'anthropic': {
                    'cacheControl': {'type': 'ephemeral'},
                  },
                },
              ),
              const LanguageModelV4TextPart(text: 'Question?'),
            ],
          ),
        ],
      );
      final body = ctx.singleRequest(server, '/v1/messages').jsonObject;
      ctx.expectEquals(body['cache_control'], {
        'type': 'ephemeral',
        'ttl': '1h',
      }, 'top-level cache_control');
      final blocks =
          ((body['messages'] as List).single as Map)['content'] as List;
      ctx.observe('blocks', blocks);
      ctx.expectEquals((blocks[0] as Map)['cache_control'], {
        'type': 'ephemeral',
      }, 'block cache_control');
      ctx.expect(
        !(blocks[1] as Map).containsKey('cache_control'),
        'uncached block got cache_control',
      );
    },
  ),
  Check(
    id: 'usage-cache-tokens',
    feature: 'anthropic-usage',
    description:
        'Cache read and cache creation tokens are reported separately and '
        'summed into the input total, for generate and for stream.',
    run: (ctx) async {
      final usage = {
        'input_tokens': 10,
        'cache_creation_input_tokens': 100,
        'cache_read_input_tokens': 200,
        'output_tokens': 5,
      };
      final server = await ctx.server((request) {
        if (request.jsonObject['stream'] == true) {
          return FixtureResponse.sse([
            _messageStart(usage: {...usage, 'output_tokens': 1}),
            _blockStart(0, {'type': 'text', 'text': ''}),
            _blockDelta(0, {'type': 'text_delta', 'text': 'hi'}),
            _blockStop(0),
            _messageDelta('end_turn', outputTokens: 5),
            _ev('message_stop'),
          ]);
        }
        return FixtureResponse.json(
          _message(content: [_text('hi')], usage: usage),
        );
      });
      final generated = await generateText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxOutputTokens: 16,
      );
      final streamed = await streamText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxOutputTokens: 16,
      );
      await streamed.textStream.toList();
      final streamedUsage = await streamed.usage;
      for (final (label, u) in [
        ('generate', generated.usage),
        ('stream', streamedUsage),
      ]) {
        ctx.observe('$label.usage', u);
        ctx.expectEquals(u?.inputTokens.total, 310, '$label input total');
        ctx.expectEquals(u?.inputTokens.noCache, 10, '$label noCache');
        ctx.expectEquals(u?.inputTokens.cacheRead, 200, '$label cacheRead');
        ctx.expectEquals(u?.inputTokens.cacheWrite, 100, '$label cacheWrite');
        ctx.expectEquals(u?.outputTokens.total, 5, '$label output');
      }
    },
  ),
  Check(
    id: 'image-document-input',
    feature: 'anthropic-multimodal',
    description:
        'Image and file parts become image and document blocks with base64 '
        'or url sources, media types and document titles.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_message(content: [_text('A cat.')])),
      );
      final result = await generateText(
        model: _model(ctx, server),
        maxOutputTokens: 16,
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [
              const LanguageModelV4TextPart(text: 'Describe these.'),
              const LanguageModelV4ImagePart(
                image: DataContentBase64('iVBORw0KGgo='),
                mediaType: 'image/png',
              ),
              LanguageModelV4ImagePart(
                image: DataContentUrl(Uri.parse('https://example.com/cat.jpg')),
                mediaType: 'image/jpeg',
              ),
              const LanguageModelV4FilePart(
                data: DataContentBase64('JVBERi0xLjQ='),
                mediaType: 'application/pdf',
                filename: 'report.pdf',
              ),
              LanguageModelV4FilePart(
                data: DataContentUrl(Uri.parse('https://example.com/a.pdf')),
                mediaType: 'application/pdf',
              ),
            ],
          ),
        ],
      );
      final body = ctx.singleRequest(server, '/v1/messages').jsonObject;
      final blocks =
          (((body['messages'] as List).single as Map)['content'] as List)
              .cast<Map>();
      ctx.observe('blocks', blocks);
      ctx.expectEquals(blocks.map((b) => b['type']).toList(), [
        'text',
        'image',
        'image',
        'document',
        'document',
      ], 'block types');
      ctx.expectEquals(blocks[1]['source'], {
        'type': 'base64',
        'media_type': 'image/png',
        'data': 'iVBORw0KGgo=',
      }, 'base64 image source');
      ctx.expectEquals(blocks[2]['source'], {
        'type': 'url',
        'url': 'https://example.com/cat.jpg',
      }, 'url image source');
      ctx.expectEquals(blocks[3]['source'], {
        'type': 'base64',
        'media_type': 'application/pdf',
        'data': 'JVBERi0xLjQ=',
      }, 'base64 document source');
      ctx.expectEquals(blocks[3]['title'], 'report.pdf', 'document title');
      ctx.expectEquals(blocks[4]['source'], {
        'type': 'url',
        'url': 'https://example.com/a.pdf',
      }, 'url document source');
      ctx.expectEquals(result.text, 'A cat.', 'text');
    },
  ),
  Check(
    id: 'provider-defined-tool-citations',
    feature: 'anthropic-provider-tools',
    description:
        'A provider-defined web_search tool is sent by its versioned type '
        'with its args; citations on the answer text become source parts.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _message(
            content: [
              {
                'type': 'server_tool_use',
                'id': 'srvtoolu_01Verify',
                'name': 'web_search',
                'input': {'query': 'dart language'},
              },
              {
                'type': 'web_search_tool_result',
                'tool_use_id': 'srvtoolu_01Verify',
                'content': [
                  {
                    'type': 'web_search_result',
                    'url': 'https://dart.dev',
                    'title': 'Dart',
                    'encrypted_content': 'abc',
                  },
                ],
              },
              {
                'type': 'text',
                'text': 'Dart is a client-optimized language.',
                'citations': [
                  {
                    'type': 'web_search_result_location',
                    'url': 'https://dart.dev',
                    'title': 'Dart programming language',
                    'cited_text': 'Dart is a client-optimized language',
                    'encrypted_index': 'idx',
                  },
                ],
              },
            ],
          ),
        ),
      );
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'What is Dart?',
        maxOutputTokens: 64,
        providerDefinedTools: const [
          LanguageModelV4ProviderDefinedTool(
            id: 'anthropic.web_search_20250305',
            name: 'web_search',
            args: {'max_uses': 2},
          ),
        ],
      );
      final body = ctx.singleRequest(server, '/v1/messages').jsonObject;
      ctx.expectEquals((body['tools'] as List).single, {
        'type': 'web_search_20250305',
        'name': 'web_search',
        'max_uses': 2,
      }, 'serialized provider tool');
      ctx.observe('sources', result.sources);
      ctx.expectEquals(
        result.text,
        'Dart is a client-optimized language.',
        'text',
      );
      ctx.expectEquals(result.sources.length, 1, 'source count');
      ctx.expectEquals(result.sources.single.url, 'https://dart.dev', 'url');
      ctx.expectEquals(
        result.sources.single.title,
        'Dart programming language',
        'title',
      );
    },
  ),
  Check(
    id: 'stop-reasons',
    feature: 'anthropic-finish-reasons',
    description:
        'end_turn, max_tokens, stop_sequence, tool_use and an unknown reason '
        'map to stop, length, stop, toolCalls and other; the raw reason is kept.',
    run: (ctx) async {
      const reasons = [
        'end_turn',
        'max_tokens',
        'stop_sequence',
        'tool_use',
        'refusal',
      ];
      final server = await ctx.server(
        (request) => FixtureResponse.json(
          _message(
            content: [_text('x')],
            stopReason: reasons[request.index],
            stopSequence: reasons[request.index] == 'stop_sequence'
                ? 'STOP'
                : null,
          ),
        ),
      );
      final seen = <String, String>{};
      for (final reason in reasons) {
        final result = await generateText(
          model: _model(ctx, server),
          prompt: 'x',
          maxOutputTokens: 16,
          stopSequences: ['STOP'],
        );
        seen[result.rawFinishReason ?? 'null'] = '${result.finishReason}';
        final expected = switch (reason) {
          'end_turn' || 'stop_sequence' => LanguageModelV4FinishReason.stop,
          'max_tokens' => LanguageModelV4FinishReason.length,
          'tool_use' => LanguageModelV4FinishReason.toolCalls,
          _ => LanguageModelV4FinishReason.other,
        };
        ctx.expectEquals(result.finishReason, expected, 'finish for $reason');
        ctx.expectEquals(result.rawFinishReason, reason, 'raw for $reason');
      }
      ctx.observe('mapping', seen);
    },
  ),
  Check(
    id: 'api-errors',
    feature: 'anthropic-errors',
    description:
        'Anthropic error JSON (401, 400, 529) becomes a typed AiApiCallError '
        'with status, type, message and isRetryable; a retryable 529 is '
        'wrapped in AiRetryError and a retry then succeeds.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        switch (request.index) {
          case 0:
            return FixtureResponse.json(
              _errorBody('authentication_error', 'invalid x-api-key'),
              status: 401,
            );
          case 1:
            return FixtureResponse.json(
              _errorBody('invalid_request_error', 'max_tokens: required'),
              status: 400,
            );
          case 2:
            return FixtureResponse.json(
              _errorBody('overloaded_error', 'Overloaded'),
              status: 529,
            );
          case 3:
            return FixtureResponse.json(
              _errorBody('overloaded_error', 'Overloaded'),
              status: 529,
            );
          default:
            return FixtureResponse.json(
              _message(content: [_text('recovered')]),
            );
        }
      });
      Future<AiApiCallError> fail(String what) =>
          ctx.expectThrows<AiApiCallError>(
            () => generateText(
              model: _model(ctx, server),
              prompt: 'hi',
              maxOutputTokens: 16,
              maxRetries: 0,
            ),
            what,
          );
      final unauthorized = await fail('401');
      final badRequest = await fail('400');
      final exhausted = await ctx.expectThrows<AiRetryError>(
        () => generateText(
          model: _model(ctx, server),
          prompt: 'hi',
          maxOutputTokens: 16,
          maxRetries: 0,
        ),
        '529',
      );
      final overloaded = exhausted.lastError as AiApiCallError;
      ctx.observe('401', [unauthorized.statusCode, unauthorized.type]);
      ctx.observe('529', [overloaded.statusCode, overloaded.type]);
      ctx.expectEquals(unauthorized.statusCode, 401, '401 status');
      ctx.expectEquals(unauthorized.type, 'authentication_error', '401 type');
      ctx.expect(
        unauthorized.message.contains('invalid x-api-key'),
        'provider message lost: ${unauthorized.message}',
      );
      ctx.expect(!unauthorized.isRetryable, '401 must not be retryable');
      ctx.expectEquals(badRequest.type, 'invalid_request_error', '400 type');
      ctx.expect(!badRequest.isRetryable, '400 must not be retryable');
      ctx.expectEquals(overloaded.statusCode, 529, '529 status');
      ctx.expectEquals(overloaded.type, 'overloaded_error', '529 type');
      ctx.expect(overloaded.isRetryable, '529 must be retryable');
      ctx.expectEquals(exhausted.attempts, 1, 'attempts with maxRetries 0');
      final recovered = await generateText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxOutputTokens: 16,
        maxRetries: 1,
      );
      ctx.expectEquals(recovered.text, 'recovered', 'text after retry');
      ctx.expectEquals(server.requests.length, 5, 'total requests');
    },
  ),
  Check(
    id: 'stream-errors',
    feature: 'anthropic-errors',
    description:
        'An SSE error event mid-stream and a stream that ends before '
        'message_delta both surface as typed AiApiCallError stream failures.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.sse([
            _messageStart(),
            _blockStart(0, {'type': 'text', 'text': ''}),
            _blockDelta(0, {'type': 'text_delta', 'text': 'partial'}),
            _ev('error', {
              'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
            }),
          ]);
        }
        return FixtureResponse.sse([
          _messageStart(),
          _blockStart(0, {'type': 'text', 'text': ''}),
          _blockDelta(0, {'type': 'text_delta', 'text': 'cut off'}),
        ]);
      });
      Future<AiApiCallError> errorOf(String what) =>
          ctx.expectThrows<AiApiCallError>(() async {
            final result = await streamText(
              model: _model(ctx, server),
              prompt: 'hi',
              maxOutputTokens: 16,
              maxRetries: 0,
            );
            await result.providerStream.toList();
          }, what);

      final overloaded = await errorOf('error event');
      final truncated = await errorOf('truncated stream');
      ctx.observe('overloaded', [overloaded.type, overloaded.message]);
      ctx.observe('truncated', truncated.message);
      ctx.expectEquals(overloaded.type, 'overloaded_error', 'error type');
      ctx.expect(
        overloaded.message.contains('Overloaded'),
        'provider message lost: ${overloaded.message}',
      );
      ctx.expect(
        truncated.message.contains('ended before message_delta'),
        'expected truncation error, got ${truncated.message}',
      );
    },
  ),
  Check(
    id: 'live-generate',
    feature: 'anthropic-generate',
    mode: CheckMode.live,
    requiresEnv: ['ANTHROPIC_API_KEY'],
    description:
        'Live: a tiny generateText call returns 200 and non-empty text.',
    run: (ctx) async {
      final provider = AnthropicProvider(
        apiKey: ctx.requireEnv('ANTHROPIC_API_KEY'),
        client: ctx.recordingDio(baseUrl: _liveBaseUrl),
      );
      final result = await generateText(
        model: provider(ctx.env('ANTHROPIC_VERIFY_MODEL', 'claude-haiku-5-5')),
        prompt: 'Reply with the single word: pong',
        maxOutputTokens: 32,
        maxRetries: 0,
      );
      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      ctx.expect(ctx.exchanges.single.status == 200, 'expected HTTP 200');
      ctx.expect(result.text.trim().isNotEmpty, 'empty text');
      ctx.expect((result.usage?.outputTokens.total ?? 0) > 0, 'no usage');
    },
  ),
  Check(
    id: 'live-stream',
    feature: 'anthropic-stream',
    mode: CheckMode.live,
    requiresEnv: ['ANTHROPIC_API_KEY'],
    description: 'Live: a tiny streamText call yields text deltas and usage.',
    run: (ctx) async {
      final provider = AnthropicProvider(
        apiKey: ctx.requireEnv('ANTHROPIC_API_KEY'),
        client: ctx.recordingDio(baseUrl: _liveBaseUrl),
      );
      final result = await streamText(
        model: provider(ctx.env('ANTHROPIC_VERIFY_MODEL', 'claude-haiku-5-5')),
        prompt: 'Count from 1 to 5, separated by spaces.',
        maxOutputTokens: 32,
        maxRetries: 0,
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      ctx.observe('deltas', deltas);
      ctx.observe('usage', usage);
      ctx.expect(ctx.exchanges.single.status == 200, 'expected HTTP 200');
      ctx.expect(deltas.join().trim().isNotEmpty, 'no streamed text');
      ctx.expect((usage?.outputTokens.total ?? 0) > 0, 'no streamed usage');
    },
  ),
  Check(
    id: 'live-structured-output',
    feature: 'anthropic-structured',
    mode: CheckMode.live,
    requiresEnv: ['ANTHROPIC_API_KEY'],
    description: 'Live: Output.object returns JSON that matches the schema.',
    run: (ctx) async {
      final provider = AnthropicProvider(
        apiKey: ctx.requireEnv('ANTHROPIC_API_KEY'),
        client: ctx.recordingDio(baseUrl: _liveBaseUrl),
      );
      final result = await generateText<Map<String, dynamic>>(
        model: provider(ctx.env('ANTHROPIC_VERIFY_MODEL', 'claude-haiku-5-5')),
        prompt: 'Give the capital city of France.',
        maxOutputTokens: 64,
        maxRetries: 0,
        output: Output.object(
          schema: Schema<Map<String, dynamic>>(
            jsonSchema: const {
              'type': 'object',
              'properties': {
                'capital': {'type': 'string'},
              },
              'required': ['capital'],
              'additionalProperties': false,
            },
            fromJson: (json) => json,
          ),
        ),
      );
      ctx.observe('output', result.output);
      ctx.expect(ctx.exchanges.single.status == 200, 'expected HTTP 200');
      final capital = result.output['capital'];
      ctx.expect(
        capital is String && capital.trim().isNotEmpty,
        'capital missing from ${result.output}',
      );
    },
  ),
  Check(
    id: 'live-tool-loop',
    feature: 'anthropic-tools',
    mode: CheckMode.live,
    requiresEnv: ['ANTHROPIC_API_KEY'],
    description:
        'Live: the model calls a tool once, gets its result, and answers.',
    run: (ctx) async {
      final provider = AnthropicProvider(
        apiKey: ctx.requireEnv('ANTHROPIC_API_KEY'),
        client: ctx.recordingDio(baseUrl: _liveBaseUrl),
      );
      var executions = 0;
      final result = await generateText(
        model: provider(ctx.env('ANTHROPIC_VERIFY_MODEL', 'claude-haiku-5-5')),
        prompt: 'What is the weather in Paris? Use the tool.',
        maxOutputTokens: 64,
        maxRetries: 0,
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(() => executions++)},
      );
      ctx.observe('text', result.text);
      ctx.observe('executions', executions);
      ctx.observe('steps', result.steps.length);
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expect(result.steps.length >= 2, 'expected two steps');
      ctx.expect(
        ctx.exchanges.every((e) => e.status == 200),
        'a live call was not 200',
      );
      ctx.expect(result.text.trim().isNotEmpty, 'empty final text');
    },
  ),
  Check(
    id: 'live-thinking-tool-loop',
    feature: 'anthropic-thinking',
    mode: CheckMode.live,
    requiresEnv: ['ANTHROPIC_API_KEY'],
    description:
        'Live: a tool loop with adaptive thinking replays the signed thinking '
        'block, so the continuation request is accepted and answered.',
    run: (ctx) async {
      final provider = AnthropicProvider(
        apiKey: ctx.requireEnv('ANTHROPIC_API_KEY'),
        client: ctx.recordingDio(baseUrl: _liveBaseUrl),
      );
      final modelId = ctx.env(
        'ANTHROPIC_VERIFY_REASONING_MODEL',
        ctx.env('ANTHROPIC_VERIFY_MODEL', 'claude-haiku-5-5'),
      );
      var executions = 0;
      final result = await generateText(
        model: provider(modelId),
        prompt: 'What is the weather in Paris? Use the tool, then answer.',
        maxOutputTokens: 1024,
        maxRetries: 0,
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(() => executions++)},
        providerOptions: {
          'anthropic': const AnthropicLanguageModelOptions(
            thinking: AnthropicThinkingOptions(adaptive: true),
            effort: 'high',
          ).toMap(),
        },
      );
      ctx.observe('model', modelId);
      ctx.observe('executions', executions);
      ctx.observe('statuses', [for (final e in ctx.exchanges) e.status]);
      ctx.observe('text', result.text);
      final firstBlocks =
          ((ctx.exchanges.first.responseBody as Map)['content'] as List)
              .map((b) => (b as Map)['type'])
              .toList();
      ctx.observe('firstResponseBlocks', firstBlocks);
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expect(ctx.exchanges.length >= 2, 'no continuation request was sent');
      if (firstBlocks.contains('thinking')) {
        final replayed =
            (ctx.exchanges[1].requestBody as Map)['messages'] as List;
        final assistant =
            replayed.lastWhere((m) => (m as Map)['role'] == 'assistant') as Map;
        final types = [
          for (final b in assistant['content'] as List) (b as Map)['type'],
        ];
        ctx.observe('replayedAssistantBlocks', types);
        ctx.expect(
          types.contains('thinking'),
          'continuation dropped the signed thinking block: $types',
        );
      } else {
        ctx.note('The model chose not to think on the first step.');
      }
      ctx.expect(
        ctx.exchanges.every((e) => e.status == 200),
        'a live call was not 200: ${ctx.exchanges.map((e) => '${e.status} ${e.error ?? ''}').join('; ')}',
      );
      ctx.expect(result.text.trim().isNotEmpty, 'empty final text');
    },
  ),
  Check(
    id: 'live-reasoning',
    feature: 'anthropic-thinking',
    mode: CheckMode.live,
    requiresEnv: ['ANTHROPIC_API_KEY'],
    description:
        'Live: extended thinking (adaptive with effort by default, or a '
        '1,024-token budget) returns reasoning text and a final answer.',
    run: (ctx) async {
      final provider = AnthropicProvider(
        apiKey: ctx.requireEnv('ANTHROPIC_API_KEY'),
        client: ctx.recordingDio(baseUrl: _liveBaseUrl),
      );
      final modelId = ctx.env(
        'ANTHROPIC_VERIFY_REASONING_MODEL',
        ctx.env('ANTHROPIC_VERIFY_MODEL', 'claude-haiku-5-5'),
      );
      // Current Claude models accept only adaptive thinking; older ones take a
      // token budget. ANTHROPIC_VERIFY_THINKING=budget selects the old form.
      final adaptive =
          ctx.env('ANTHROPIC_VERIFY_THINKING', 'adaptive') != 'budget';
      final options = adaptive
          ? const AnthropicLanguageModelOptions(
              thinking: AnthropicThinkingOptions(adaptive: true),
              effort: 'high',
            )
          : const AnthropicLanguageModelOptions(
              thinking: AnthropicThinkingOptions(budgetTokens: 1024),
            );
      final result = await generateText(
        model: provider(modelId),
        prompt:
            'A train leaves at 09:47 and arrives at 14:18 the same day. '
            'How many minutes is the trip? Answer with the number only.',
        maxOutputTokens: 2048,
        maxRetries: 0,
        providerOptions: {'anthropic': options.toMap()},
      );
      ctx.observe('model', modelId);
      ctx.observe('thinkingMode', adaptive ? 'adaptive' : 'budget');
      ctx.observe('reasoningChars', result.reasoningText.length);
      ctx.observe('text', result.text);
      ctx.expect(ctx.exchanges.single.status == 200, 'expected HTTP 200');
      final sent = ctx.exchanges.single.requestBody as Map;
      if (adaptive) {
        ctx.expectEquals(
          (sent['thinking'] as Map)['type'],
          'adaptive',
          'thinking.type',
        );
        ctx.expectEquals(
          (sent['output_config'] as Map?)?['effort'],
          'high',
          'output_config.effort',
        );
      } else {
        ctx.expectEquals(
          (sent['thinking'] as Map)['budget_tokens'],
          1024,
          'budget_tokens',
        );
      }
      // Current models may return a signed thinking block with its text
      // omitted. Prove the package keeps every block, and surfaces the text
      // whenever the API sends some.
      final raw = (ctx.exchanges.single.responseBody as Map)['content'] as List;
      final thinking = [
        for (final b in raw)
          if ((b as Map)['type'] == 'thinking') b,
      ];
      ctx.observe('rawThinkingBlocks', thinking.length);
      ctx.observe('reasoningParts', result.reasoning.length);
      ctx.expect(thinking.isNotEmpty, 'API returned no thinking block');
      ctx.expect(
        thinking.every((b) => '${b['signature'] ?? ''}'.isNotEmpty),
        'thinking block without signature',
      );
      ctx.expectEquals(
        result.reasoning.length,
        thinking.length,
        'reasoning parts',
      );
      final rawText = thinking.map((b) => '${b['thinking'] ?? ''}').join();
      if (rawText.trim().isEmpty) {
        ctx.note('API omitted the thinking text (signature only).');
      } else {
        ctx.expect(
          result.reasoningText.trim().isNotEmpty,
          'thinking text dropped',
        );
      }
      ctx.expect(result.text.contains('271'), 'wrong answer: ${result.text}');
    },
  ),
  Check(
    id: 'live-invalid-key',
    feature: 'anthropic-errors',
    mode: CheckMode.live,
    requiresEnv: ['ANTHROPIC_API_KEY'],
    description: 'Live: a bad key raises a typed 401 authentication_error.',
    run: (ctx) async {
      ctx.requireEnv('ANTHROPIC_API_KEY');
      final provider = AnthropicProvider(
        apiKey: 'sk-ant-invalid-verify-key',
        client: ctx.recordingDio(baseUrl: _liveBaseUrl),
      );
      final error = await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: provider(
            ctx.env('ANTHROPIC_VERIFY_MODEL', 'claude-haiku-5-5'),
          ),
          prompt: 'hi',
          maxOutputTokens: 16,
          maxRetries: 0,
        ),
        'invalid key',
      );
      ctx.observe('statusCode', error.statusCode);
      ctx.observe('type', error.type);
      ctx.expectEquals(error.statusCode, 401, 'statusCode');
      ctx.expectEquals(error.type, 'authentication_error', 'type');
      ctx.expect(!error.isRetryable, '401 must not be retryable');
    },
  ),
]);
