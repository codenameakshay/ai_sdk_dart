// Verification checks for package:ai_sdk_mistral. See features/ai_sdk_mistral.md.
//
// Mistral speaks the OpenAI Chat Completions wire format. Each check builds a
// model through the public `MistralProvider`, drives it with the ai_sdk_dart core
// functions, and asserts the request that reached the fixture server and the
// result the caller got.
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_mistral/ai_sdk_mistral.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_mistral';
const _model = 'mistral-large-latest';

MistralProvider _provider(
  CheckContext ctx,
  FixtureServer server, {
  String? apiKey = 'verify-key',
}) {
  final provider = MistralProvider(apiKey: apiKey, baseUrl: server.url('/v1'));
  ctx.onCleanup(() async => provider.dispose());
  return provider;
}

Map<String, Object?> _completion({
  String? content,
  List<Map<String, Object?>>? toolCalls,
  String finishReason = 'stop',
}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion',
  'created': 1767225600,
  'model': _model,
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
  'usage': {
    'prompt_tokens': 11,
    'completion_tokens': 7,
    'total_tokens': 18,
    'queue_time': 0.01,
  },
};

Map<String, Object?> _chunk(Map<String, Object?> delta, {String? finish}) => {
  'id': 'chatcmpl-verify',
  'object': 'chat.completion.chunk',
  'created': 1767225600,
  'model': _model,
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

final _weatherSchema = Schema<Map<String, dynamic>>(
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

/// Redirects every new `HttpClient` so connections are recorded and refused.
class _RecordingOverrides extends HttpOverrides {
  _RecordingOverrides(this.seen);
  final List<Uri> seen;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) {
      seen.add(uri);
      throw const SocketException('verify: connection refused on purpose');
    };
    return client;
  }
}

final checks = PackageChecks(_package, [
  Check(
    id: 'generate-text',
    feature: 'mistral-generate',
    description:
        'generateText posts to /chat/completions with the bearer key, model, '
        'messages, random_seed (not seed) and max_tokens (not '
        'max_completion_tokens), and returns text, usage and finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) =>
            FixtureResponse.json(_completion(content: 'Hello from Mistral.')),
      );
      final result = await generateText(
        model: _provider(ctx, server)(_model),
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
      ctx.expectEquals(body['model'], _model, 'model');
      ctx.expectEquals(body['random_seed'], 42, 'random_seed');
      ctx.expect(!body.containsKey('seed'), 'seed key sent to Mistral');
      ctx.expectEquals(body['max_tokens'], 64, 'max_tokens');
      ctx.expect(
        !body.containsKey('max_completion_tokens'),
        'max_completion_tokens sent to Mistral',
      );
      ctx.expectEquals(body['temperature'], 0.2, 'temperature');
      ctx.expectEquals(
        (body['messages'] as List).map((m) => (m as Map)['role']).toList(),
        ['system', 'user'],
        'message roles',
      );
      ctx.expectEquals(result.text, 'Hello from Mistral.', 'text');
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
    feature: 'mistral-stream',
    description:
        'streamText sends stream=true with include_usage and yields the SSE '
        'deltas in order, then usage from the trailing chunk and the finish '
        'reason.',
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
            'model': _model,
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
        model: _provider(ctx, server)(_model),
        prompt: 'Count to three.',
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      final finish = await result.finishReason;
      ctx.observe('deltas', deltas);
      ctx.observe('usage', usage);
      final body = ctx.singleRequest(server, '/v1/chat/completions').jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(body['stream_options'], {
        'include_usage': true,
      }, 'stream_options');
      ctx.expectEquals(deltas.join(), 'One, two, three.', 'streamed text');
      ctx.expect(deltas.length >= 3, 'expected incremental deltas');
      ctx.expectEquals(usage?.inputTokens.total, 5, 'input tokens');
      ctx.expectEquals(usage?.outputTokens.total, 3, 'output tokens');
      ctx.expect('$finish'.contains('stop'), 'finish reason not stop');
    },
  ),
  Check(
    id: 'tool-loop',
    feature: 'mistral-tools',
    description:
        'A tool call in the first response runs the tool once and its result '
        'goes back as a tool message with the same tool_call_id; the second '
        'response is the final text.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _completion(
              finishReason: 'tool_calls',
              toolCalls: [
                {
                  'id': 'call_mistral_1',
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
        model: _provider(ctx, server)(_model),
        prompt: 'Weather in Paris?',
        maxSteps: 3,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: 'Get current weather for a city.',
            inputSchema: _weatherSchema,
            execute: (input, _) async {
              executions++;
              return 'Sunny, 18C in ${input['city']}';
            },
          ),
        },
      );
      ctx.observe('text', result.text);
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, '/v1/chat/completions');
      ctx.expectEquals(requests.length, 2, 'request count');
      final tools = requests[0].jsonObject['tools'] as List;
      ctx.expectEquals(
        ((tools.single as Map)['function'] as Map)['name'],
        'getWeather',
        'serialized tool name',
      );
      final followUp = (requests[1].jsonObject['messages'] as List).cast<Map>();
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(
        toolMessage['tool_call_id'],
        'call_mistral_1',
        'call id',
      );
      ctx.expect(
        '${toolMessage['content']}'.contains('Sunny, 18C in Paris'),
        'tool result missing: ${toolMessage['content']}',
      );
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(result.text, 'It is sunny in Paris.', 'final text');
    },
  ),
  Check(
    id: 'structured-output',
    feature: 'mistral-structured',
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
        model: _provider(ctx, server)(_model),
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
    id: 'provider-options',
    feature: 'mistral-options',
    description:
        'providerOptions["mistral"] (safe_prompt, prompt_mode) is '
        'merged into the chat body next to the standard fields.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      await generateText(
        model: _provider(ctx, server)(_model),
        prompt: 'hi',
        maxOutputTokens: 16,
        providerOptions: const {
          'mistral': {'safe_prompt': true, 'prompt_mode': 'reasoning'},
        },
      );
      final body = ctx.singleRequest(server, '/v1/chat/completions').jsonObject;
      ctx.expectEquals(body['safe_prompt'], true, 'safe_prompt');
      ctx.expectEquals(body['prompt_mode'], 'reasoning', 'prompt_mode');
      ctx.expectEquals(body['max_tokens'], 16, 'max_tokens kept');
    },
  ),
  Check(
    id: 'embed',
    feature: 'mistral-embed',
    description:
        'embed and embedMany post input to /embeddings with the bearer key '
        'and return the vectors in input order, with the prompt token usage.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final input = request.jsonObject['input'] as List;
        return FixtureResponse.json({
          'id': 'embd-verify',
          'object': 'list',
          'model': 'mistral-embed',
          'data': [
            for (var i = 0; i < input.length; i++)
              {
                'object': 'embedding',
                'index': i,
                'embedding': [0.1 * (i + 1), 0.2, 0.3],
              },
          ],
          'usage': {
            'prompt_tokens': 4 * input.length,
            'total_tokens': 4 * input.length,
          },
        });
      });
      final model = _provider(ctx, server).embedding('mistral-embed');
      final one = await embed(model: model, value: 'sunny day');
      final many = await embedMany(
        model: model,
        values: ['alpha', 'beta'],
        providerOptions: const {
          'mistral': {'output_dtype': 'float'},
        },
      );
      ctx.observe('one', one.embedding);
      ctx.observe('many', [for (final e in many.embeddings) e.embedding]);
      ctx.observe('manyUsage', many.usage?.tokens);
      final requests = ctx.requestsTo(server, '/v1/embeddings', method: 'POST');
      ctx.expectEquals(requests.length, 2, 'embed request count');
      ctx.expectEquals(
        requests[0].headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      final first = requests[0].jsonObject;
      ctx.expectEquals(first['model'], 'mistral-embed', 'model');
      ctx.expectEquals(first['input'], ['sunny day'], 'input');
      final second = requests[1].jsonObject;
      ctx.expectEquals(second['input'], ['alpha', 'beta'], 'input (many)');
      ctx.expectEquals(second['output_dtype'], 'float', 'provider option');
      ctx.expectEquals(one.embedding, [0.1, 0.2, 0.3], 'single vector');
      ctx.expectEquals(many.embeddings[1].value, 'beta', 'value order');
      ctx.expectEquals(many.embeddings[1].embedding[0], 0.2, 'vector order');
      ctx.expectEquals(many.usage?.tokens, 8, 'usage tokens');
    },
  ),
  Check(
    id: 'auth-and-client',
    feature: 'mistral-provider',
    description:
        'apiKey, an async credentialProvider and a missing key produce the '
        'Bearer header, the resolved key and no Authorization header; an '
        'injected client is used and left open by dispose().',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      final base = server.url('/v1');
      await generateText(model: _provider(ctx, server)('m'), prompt: 'a');
      final dynamicProvider = MistralProvider(
        baseUrl: base,
        credentialProvider: () async => 'dyn-key',
      );
      ctx.onCleanup(() async => dynamicProvider.dispose());
      await generateText(model: dynamicProvider('m'), prompt: 'b');
      final keyless = MistralProvider(baseUrl: base);
      ctx.onCleanup(() async => keyless.dispose());
      await generateText(model: keyless('m'), prompt: 'c');
      final dio = Dio(
        BaseOptions(baseUrl: base, headers: {'x-verify-client': 'injected'}),
      );
      ctx.onCleanup(() async => dio.close(force: true));
      // The base URL must be passed to the provider as well: the OpenAI
      // compatible base builds the endpoint from it, not from the Dio.
      final injected = MistralProvider(
        apiKey: 'inj-key',
        baseUrl: base,
        client: dio,
      );
      await generateText(model: injected('m'), prompt: 'd');
      injected.dispose();
      await generateText(model: injected('m'), prompt: 'e');
      final auth = [
        for (final r in ctx.requestsTo(server, '/v1/chat/completions'))
          r.headers['authorization'],
      ];
      ctx.observe('authHeaders', auth);
      final markers = [
        for (final r in ctx.requestsTo(server, '/v1/chat/completions'))
          r.headers['x-verify-client'],
      ];
      ctx.observe('clientMarkers', markers);
      ctx.expectEquals(markers.sublist(3), [
        'injected',
        'injected',
      ], 'injected client carried its header');
      ctx.expectEquals(auth, [
        'Bearer verify-key',
        'Bearer dyn-key',
        null,
        'Bearer inj-key',
        'Bearer inj-key',
      ], 'authorization per request');
    },
  ),
  Check(
    id: 'default-base-url',
    feature: 'mistral-provider',
    description:
        'Without baseUrl the provider targets '
        'https://api.mistral.ai/v1/chat/completions (recorded and '
        'refused locally, no traffic leaves).',
    run: (ctx) async {
      final seen = <Uri>[];
      final error = await HttpOverrides.runWithHttpOverrides(() async {
        final provider = MistralProvider(apiKey: 'verify-key');
        try {
          return await ctx.expectThrows<AiApiCallError>(
            () =>
                generateText(model: provider('m'), prompt: 'hi', maxRetries: 0),
            'generateText',
          );
        } finally {
          provider.dispose();
        }
      }, _RecordingOverrides(seen));
      ctx.observe('connectUris', seen.map((u) => '$u').toList());
      ctx.observe('errorUrl', error.url);
      ctx.expect(seen.isNotEmpty, 'no connection attempt recorded');
      ctx.expectEquals(seen.first.host, 'api.mistral.ai', 'host');
      ctx.expectEquals(seen.first.scheme, 'https', 'scheme');
      ctx.expectEquals(
        error.url,
        'https://api.mistral.ai/v1/chat/completions',
        'default endpoint',
      );
    },
  ),
  Check(
    id: 'api-error',
    feature: 'mistral-errors',
    description:
        'Mistral error bodies ({message, request_id} and the {object: error} '
        'shape) become AiApiCallError with status and message for chat, a '
        'streamed request and embeddings; 401 is not retryable and 429 is.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.path == '/v1/embeddings') {
          return FixtureResponse.json({
            'object': 'error',
            'message': 'Invalid model',
            'type': 'invalid_request_error',
            'param': null,
            'code': null,
          }, status: 422);
        }
        if (request.index == 1) {
          return FixtureResponse.json({
            'object': 'error',
            'message': 'Rate limit exceeded',
            'type': 'rate_limited',
            'param': null,
            'code': '1300',
          }, status: 429);
        }
        return FixtureResponse.json({
          'message': 'Unauthorized',
          'request_id': 'req-verify',
        }, status: 401);
      });
      final provider = _provider(ctx, server);
      final unauthorized = await ctx.expectThrows<AiApiCallError>(
        () =>
            generateText(model: provider(_model), prompt: 'hi', maxRetries: 0),
        'generateText',
      );
      final exhausted = await ctx.expectThrows<AiRetryError>(
        () =>
            generateText(model: provider(_model), prompt: 'hi', maxRetries: 0),
        'generateText (429)',
      );
      final limited = exhausted.lastError as AiApiCallError;
      final streamed = await ctx.expectThrows<AiApiCallError>(() async {
        final result = await streamText(
          model: provider(_model),
          prompt: 'hi',
          maxRetries: 0,
        );
        await result.textStream.toList();
      }, 'streamText');
      final embedding = await ctx.expectThrows<AiApiCallError>(
        () => embed(model: provider.embedding('bad'), value: 'x'),
        'embed',
      );
      ctx.observe('unauthorized', {
        'status': unauthorized.statusCode,
        'message': unauthorized.message,
        'isRetryable': unauthorized.isRetryable,
      });
      ctx.observe('rateLimited', {
        'status': limited.statusCode,
        'message': limited.message,
        'code': limited.code,
        'isRetryable': limited.isRetryable,
      });
      ctx.observe('streamed', {
        'status': streamed.statusCode,
        'message': streamed.message,
      });
      ctx.observe('embed', {
        'status': embedding.statusCode,
        'message': embedding.message,
      });
      ctx.expectEquals(unauthorized.statusCode, 401, 'status');
      ctx.expectEquals(unauthorized.message, 'Unauthorized', 'message');
      ctx.expect(!unauthorized.isRetryable, '401 must not be retryable');
      ctx.expectEquals(limited.statusCode, 429, 'rate limit status');
      ctx.expectEquals(limited.message, 'Rate limit exceeded', 'rate msg');
      ctx.expect(limited.isRetryable, '429 must be retryable');
      ctx.expectEquals(streamed.statusCode, 401, 'stream status');
      ctx.expectEquals(streamed.message, 'Unauthorized', 'stream message');
      ctx.expectEquals(embedding.statusCode, 422, 'embed status');
      ctx.expectEquals(embedding.message, 'Invalid model', 'embed message');
    },
  ),
]);
