// Verification checks for package:ai_sdk_groq. See features/ai_sdk_groq.md.
//
// Groq speaks the OpenAI Chat Completions wire format. Each check builds a
// model through the public `GroqProvider`, drives it with the ai_sdk_dart core
// functions, and asserts the request that reached the fixture server and the
// result the caller got.
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_groq/ai_sdk_groq.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_groq';
const _model = 'llama-3.3-70b-versatile';

GroqProvider _provider(
  CheckContext ctx,
  FixtureServer server, {
  String? apiKey = 'verify-key',
}) {
  final provider = GroqProvider(
    apiKey: apiKey,
    baseUrl: server.url('/openai/v1'),
  );
  ctx.onCleanup(() async => provider.dispose());
  return provider;
}

Map<String, Object?> _completion({
  String? content,
  String? reasoning,
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
        'reasoning': ?reasoning,
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
    feature: 'groq-generate',
    description:
        'generateText posts to /chat/completions with the bearer key, model, '
        'messages, seed and max_tokens (not max_completion_tokens), and '
        'returns text, usage and finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'Hello from Groq.')),
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
        '/openai/v1/chat/completions',
        method: 'POST',
      );
      final body = request.jsonObject;
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(body['model'], _model, 'model');
      ctx.expectEquals(body['seed'], 42, 'seed');
      ctx.expectEquals(body['max_tokens'], 64, 'max_tokens');
      ctx.expect(
        !body.containsKey('max_completion_tokens'),
        'max_completion_tokens sent to Groq',
      );
      ctx.expectEquals(body['temperature'], 0.2, 'temperature');
      ctx.expectEquals(
        (body['messages'] as List).map((m) => (m as Map)['role']).toList(),
        ['system', 'user'],
        'message roles',
      );
      ctx.expectEquals(result.text, 'Hello from Groq.', 'text');
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
    feature: 'groq-stream',
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
      final body = ctx
          .singleRequest(server, '/openai/v1/chat/completions')
          .jsonObject;
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
    feature: 'groq-tools',
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
                  'id': 'call_groq_1',
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
      final requests = ctx.requestsTo(server, '/openai/v1/chat/completions');
      ctx.expectEquals(requests.length, 2, 'request count');
      final tools = requests[0].jsonObject['tools'] as List;
      ctx.expectEquals(
        ((tools.single as Map)['function'] as Map)['name'],
        'getWeather',
        'serialized tool name',
      );
      final followUp = (requests[1].jsonObject['messages'] as List).cast<Map>();
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(toolMessage['tool_call_id'], 'call_groq_1', 'call id');
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
    feature: 'groq-structured',
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
      final body = ctx
          .singleRequest(server, '/openai/v1/chat/completions')
          .jsonObject;
      final format = body['response_format'] as Map?;
      ctx.expectEquals(format?['type'], 'json_schema', 'response_format.type');
      ctx.expectEquals(result.output, {
        'capital': 'Tokyo',
        'currency': 'JPY',
      }, 'output');
    },
  ),
  Check(
    id: 'reasoning',
    feature: 'groq-reasoning',
    description:
        'providerOptions["groq"] (reasoning_format) is merged into the body, '
        'and the reasoning field of the reply is returned as reasoning text '
        'apart from the answer, for generateText and streamText.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.jsonObject['stream'] == true) {
          return FixtureResponse.sse([
            _chunk({'role': 'assistant', 'reasoning': 'Think: '}),
            _chunk({'reasoning': 'two plus two.'}),
            _chunk({'content': '4'}),
            _chunk({}, finish: 'stop'),
          ], done: true);
        }
        return FixtureResponse.json(
          _completion(content: '4', reasoning: 'Think: two plus two.'),
        );
      });
      const options = {
        'groq': {'reasoning_format': 'parsed'},
      };
      final model = _provider(ctx, server)('qwen/qwen3-32b');
      final generated = await generateText(
        model: model,
        prompt: '2+2?',
        providerOptions: options,
      );
      final streamed = await streamText(
        model: model,
        prompt: '2+2?',
        providerOptions: options,
      );
      final answer = (await streamed.textStream.toList()).join();
      final streamedReasoning = await streamed.reasoningText;
      ctx.observe('generated', {
        'text': generated.text,
        'reasoning': generated.reasoningText,
      });
      ctx.observe('streamed', {'text': answer, 'reasoning': streamedReasoning});
      final requests = ctx.requestsTo(server, '/openai/v1/chat/completions');
      ctx.expectEquals(requests.length, 2, 'request count');
      for (final r in requests) {
        ctx.expectEquals(
          r.jsonObject['reasoning_format'],
          'parsed',
          'reasoning_format',
        );
      }
      ctx.expectEquals(generated.text, '4', 'generated answer');
      ctx.expectEquals(generated.reasoningText, 'Think: two plus two.', 'r');
      ctx.expectEquals(answer, '4', 'streamed answer');
      ctx.expectEquals(streamedReasoning, 'Think: two plus two.', 'sr');
    },
  ),
  Check(
    id: 'auth-and-client',
    feature: 'groq-provider',
    description:
        'apiKey, an async credentialProvider and a missing key produce the '
        'Bearer header, the resolved key and no Authorization header; an '
        'injected client is used and left open by dispose().',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      final base = server.url('/openai/v1');
      await generateText(model: _provider(ctx, server)('m'), prompt: 'a');
      final dynamicProvider = GroqProvider(
        baseUrl: base,
        credentialProvider: () async => 'dyn-key',
      );
      ctx.onCleanup(() async => dynamicProvider.dispose());
      await generateText(model: dynamicProvider('m'), prompt: 'b');
      final keyless = GroqProvider(baseUrl: base);
      ctx.onCleanup(() async => keyless.dispose());
      await generateText(model: keyless('m'), prompt: 'c');
      final dio = Dio(
        BaseOptions(baseUrl: base, headers: {'x-verify-client': 'injected'}),
      );
      ctx.onCleanup(() async => dio.close(force: true));
      // The base URL must be passed to the provider as well: the OpenAI
      // compatible base builds the endpoint from it, not from the Dio.
      final injected = GroqProvider(
        apiKey: 'inj-key',
        baseUrl: base,
        client: dio,
      );
      await generateText(model: injected('m'), prompt: 'd');
      injected.dispose();
      await generateText(model: injected('m'), prompt: 'e');
      final auth = [
        for (final r in ctx.requestsTo(server, '/openai/v1/chat/completions'))
          r.headers['authorization'],
      ];
      ctx.observe('authHeaders', auth);
      final markers = [
        for (final r in ctx.requestsTo(server, '/openai/v1/chat/completions'))
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
    feature: 'groq-provider',
    description:
        'Without baseUrl the provider targets '
        'https://api.groq.com/openai/v1/chat/completions (recorded and '
        'refused locally, no traffic leaves).',
    run: (ctx) async {
      final seen = <Uri>[];
      final error = await HttpOverrides.runWithHttpOverrides(() async {
        final provider = GroqProvider(apiKey: 'verify-key');
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
      ctx.expectEquals(seen.first.host, 'api.groq.com', 'host');
      ctx.expectEquals(seen.first.scheme, 'https', 'scheme');
      ctx.expectEquals(
        error.url,
        'https://api.groq.com/openai/v1/chat/completions',
        'default endpoint',
      );
    },
  ),
  Check(
    id: 'api-error',
    feature: 'groq-errors',
    description:
        'A 401 JSON error is a non-retryable AiApiCallError with status, '
        'message, type and code; a 429 is retryable; a streamed request '
        'surfaces the same typed error.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final limited = request.index >= 1 && request.index < 2;
        return FixtureResponse.json(
          limited
              ? {
                  'error': {
                    'message': 'Rate limit reached for model.',
                    'type': 'tokens',
                    'code': 'rate_limit_exceeded',
                  },
                }
              : {
                  'error': {
                    'message': 'Invalid API Key',
                    'type': 'invalid_request_error',
                    'code': 'invalid_api_key',
                  },
                },
          status: limited ? 429 : 401,
        );
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
      ctx.observe('unauthorized', {
        'status': unauthorized.statusCode,
        'message': unauthorized.message,
        'type': unauthorized.type,
        'code': unauthorized.code,
        'isRetryable': unauthorized.isRetryable,
      });
      ctx.observe('rateLimited', {
        'status': limited.statusCode,
        'message': limited.message,
        'isRetryable': limited.isRetryable,
      });
      ctx.observe('streamed', {
        'status': streamed.statusCode,
        'message': streamed.message,
      });
      ctx.expectEquals(unauthorized.statusCode, 401, 'status');
      ctx.expectEquals(unauthorized.message, 'Invalid API Key', 'message');
      ctx.expectEquals(unauthorized.type, 'invalid_request_error', 'type');
      ctx.expectEquals(unauthorized.code, 'invalid_api_key', 'code');
      ctx.expect(!unauthorized.isRetryable, '401 must not be retryable');
      ctx.expectEquals(limited.statusCode, 429, 'rate limit status');
      ctx.expect(limited.isRetryable, '429 must be retryable');
      ctx.expectEquals(streamed.statusCode, 401, 'stream status');
      ctx.expectEquals(streamed.message, 'Invalid API Key', 'stream message');
    },
  ),
]);
