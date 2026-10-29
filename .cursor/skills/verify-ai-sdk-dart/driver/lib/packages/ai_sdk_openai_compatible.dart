// Verification checks for package:ai_sdk_openai_compatible.
// See features/ai_sdk_openai_compatible.md.
//
// This is the reference module: each check builds a model the way a provider
// author does, drives it through the public ai_sdk_dart API, and asserts both
// the request that reached the (fixture) server and the result the caller got.
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_openai_compatible';

OpenAICompatibleChatLanguageModel _model(
  CheckContext ctx,
  FixtureServer server, {
  String seedKey = 'seed',
  String maxTokensKey = 'max_completion_tokens',
  Map<String, String>? queryParameters,
  bool supportsTools = true,
}) {
  final baseUrl = server.url('/v1');
  final dio = Dio(BaseOptions(baseUrl: baseUrl));
  ctx.onCleanup(() async => dio.close(force: true));
  return OpenAICompatibleChatLanguageModel(
    modelId: 'verify-model',
    config: OpenAICompatibleConfig(
      provider: 'verify-compat',
      baseUrl: baseUrl,
      client: dio,
      headers: () => {'Authorization': 'Bearer verify-key'},
      seedKey: seedKey,
      maxTokensKey: maxTokensKey,
      queryParameters: queryParameters,
      supportsTools: supportsTools,
    ),
  );
}

Map<String, Object?> _completion({
  String? content,
  List<Map<String, Object?>>? toolCalls,
  String finishReason = 'stop',
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
        'tool_calls': ?toolCalls,
      },
      'finish_reason': finishReason,
    },
  ],
  'usage': {'prompt_tokens': 11, 'completion_tokens': 7, 'total_tokens': 18},
};

Map<String, Object?> _chunk(Map<String, Object?> delta, {String? finish}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion.chunk',
  'created': 1767225600,
  'model': 'verify-model',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

final _weatherTool = tool<Map<String, dynamic>, String>(
  description: 'Get current weather for a city.',
  inputSchema: Schema(
    jsonSchema: const {
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
      'required': ['city'],
      'additionalProperties': false,
    },
    fromJson: (json) => json,
  ),
  execute: (input, _) async => 'Sunny, 18C in ${input['city']}',
);

final checks = PackageChecks(_package, [
  Check(
    id: 'generate-text',
    feature: 'compat-generate',
    description:
        'generateText sends one Chat Completions request with auth, model, '
        'messages, seed and max tokens, and returns text, usage and finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _completion(content: 'Hello from the fixture.'),
        ),
      );
      final result = await generateText(
        model: _model(ctx, server),
        system: 'Be brief.',
        prompt: 'Say hello.',
        maxOutputTokens: 64,
        seed: 42,
        temperature: 0.2,
      );
      ctx.observe('text', result.text);
      ctx.observe('finishReason', '${result.finishReason}');
      ctx.observe('usage', result.usage);
      final request = ctx.singleRequest(
        server,
        '/v1/chat/completions',
        method: 'POST',
      );
      final body = request.jsonObject;
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(body['model'], 'verify-model', 'model');
      ctx.expectEquals(body['seed'], 42, 'seed');
      ctx.expectEquals(
        body['max_completion_tokens'],
        64,
        'max_completion_tokens',
      );
      ctx.expectEquals(body['temperature'], 0.2, 'temperature');
      ctx.expectEquals(
        (body['messages'] as List).map((m) => (m as Map)['role']).toList(),
        ['system', 'user'],
        'message roles',
      );
      ctx.expect(body['stream'] != true, 'non-streaming call sent stream=true');
      ctx.expectEquals(result.text, 'Hello from the fixture.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 11, 'input tokens');
      ctx.expectEquals(result.usage?.outputTokens.total, 7, 'output tokens');
      ctx.expect(
        '${result.finishReason}'.contains('stop'),
        'finish reason not stop',
      );
    },
  ),
  Check(
    id: 'stream-text',
    feature: 'compat-stream',
    description:
        'streamText sends stream=true with include_usage and yields the SSE '
        'deltas in order, then usage and finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _chunk({'role': 'assistant', 'content': ''}),
          _chunk({'content': 'One, '}),
          _chunk({'content': 'two, '}),
          _chunk({'content': 'three.'}),
          _chunk({}, finish: 'stop'),
          {
            'id': 'chatcmpl-verify',
            'object': 'chat.completion.chunk',
            'created': 1767225600,
            'model': 'verify-model',
            'choices': <Object>[],
            'usage': {
              'prompt_tokens': 5,
              'completion_tokens': 3,
              'total_tokens': 8,
            },
          },
        ], done: true),
      );
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Count to three.',
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      ctx.observe('deltas', deltas);
      ctx.observe('usage', usage);
      final body = ctx.singleRequest(server, '/v1/chat/completions').jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(body['stream_options'], {
        'include_usage': true,
      }, 'stream_options');
      ctx.expectEquals(deltas.join(), 'One, two, three.', 'streamed text');
      ctx.expect(
        deltas.length >= 3,
        'expected incremental deltas, got ${deltas.length}',
      );
      ctx.expectEquals(usage?.outputTokens.total, 3, 'streamed output tokens');
    },
  ),
  Check(
    id: 'tool-loop',
    feature: 'compat-tools',
    description:
        'A tool call in the first response is executed and its result is sent '
        'back as a tool message; the second response becomes the final text.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _completion(
              finishReason: 'tool_calls',
              toolCalls: [
                {
                  'id': 'call_verify_1',
                  'type': 'function',
                  'function': {
                    'name': 'getWeather',
                    'arguments': '{"city":"Paris"}',
                  },
                },
              ],
            ),
          );
        }
        return FixtureResponse.json(
          _completion(content: 'It is sunny in Paris.'),
        );
      });
      var executions = 0;
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather in Paris?',
        maxSteps: 3,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: _weatherTool.description,
            inputSchema: _weatherTool.inputSchema,
            execute: (input, options) async {
              executions++;
              return 'Sunny, 18C in ${input['city']}';
            },
          ),
        },
      );
      ctx.observe('text', result.text);
      ctx.observe('steps', result.steps.length);
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, '/v1/chat/completions');
      ctx.expectEquals(requests.length, 2, 'request count');
      final first = requests[0].jsonObject;
      final tools = first['tools'] as List;
      ctx.expectEquals(
        ((tools.single as Map)['function'] as Map)['name'],
        'getWeather',
        'serialized tool name',
      );
      final followUp = (requests[1].jsonObject['messages'] as List).cast<Map>();
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(
        toolMessage['tool_call_id'],
        'call_verify_1',
        'tool_call_id',
      );
      ctx.expect(
        '${toolMessage['content']}'.contains('Sunny, 18C in Paris'),
        'tool result missing from follow-up: ${toolMessage['content']}',
      );
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(result.text, 'It is sunny in Paris.', 'final text');
    },
  ),
  Check(
    id: 'structured-output',
    feature: 'compat-structured',
    description:
        'Output.object sends response_format json_schema and parses the JSON '
        'reply into the typed output.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _completion(content: '{"capital":"Tokyo","currency":"JPY"}'),
        ),
      );
      final result = await generateText<Map<String, dynamic>>(
        model: _model(ctx, server),
        prompt: 'Capital and currency of Japan.',
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
      final body = ctx.singleRequest(server, '/v1/chat/completions').jsonObject;
      final format = body['response_format'] as Map?;
      ctx.expectEquals(format?['type'], 'json_schema', 'response_format.type');
      ctx.expectEquals(result.output, {
        'capital': 'Tokyo',
        'currency': 'JPY',
      }, 'output');
    },
  ),
  Check(
    id: 'config-quirks',
    feature: 'compat-config',
    description:
        'Config overrides change the wire format: query parameters on the URL, '
        'random_seed and max_tokens body keys, and no tools when unsupported.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      await generateText(
        model: _model(
          ctx,
          server,
          seedKey: 'random_seed',
          maxTokensKey: 'max_tokens',
          queryParameters: {'api-version': '2024-10-21'},
          supportsTools: false,
        ),
        prompt: 'ok?',
        seed: 7,
        maxOutputTokens: 16,
        tools: {'getWeather': _weatherTool},
      );
      final request = ctx.singleRequest(server, '/v1/chat/completions');
      final body = request.jsonObject;
      ctx.observe('query', request.uri.queryParameters);
      ctx.expectEquals(
        request.uri.queryParameters['api-version'],
        '2024-10-21',
        'api-version',
      );
      ctx.expectEquals(body['random_seed'], 7, 'random_seed');
      ctx.expect(
        !body.containsKey('seed'),
        'seed key sent alongside random_seed',
      );
      ctx.expectEquals(body['max_tokens'], 16, 'max_tokens');
      ctx.expect(
        !body.containsKey('max_completion_tokens'),
        'max_completion_tokens sent',
      );
      ctx.expect(
        !body.containsKey('tools'),
        'tools sent although supportsTools=false',
      );
    },
  ),
  Check(
    id: 'api-error',
    feature: 'compat-errors',
    description:
        'A 401 JSON error from the server surfaces as a typed AiApiCallError '
        'with status, message and retryability.',
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
      final error = await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: _model(ctx, server),
          prompt: 'hi',
          maxRetries: 0,
        ),
        'generateText',
      );
      ctx.observe('statusCode', error.statusCode);
      ctx.observe('message', error.message);
      ctx.observe('isRetryable', error.isRetryable);
      ctx.expectEquals(error.statusCode, 401, 'statusCode');
      ctx.expect(
        error.message.contains('Incorrect API key'),
        'provider message lost',
      );
      ctx.expect(!error.isRetryable, '401 must not be retryable');
    },
  ),
]);
