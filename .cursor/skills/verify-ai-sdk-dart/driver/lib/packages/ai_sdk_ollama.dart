// Verification checks for package:ai_sdk_ollama. See features/ai_sdk_ollama.md.
//
// Ollama is local, has no API key and streams NDJSON from /api/chat. Each
// check builds a model through the public `OllamaProvider`, drives it with the
// ai_sdk_dart core functions, and asserts the request that reached the fixture
// server and the result the caller got.
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_ollama';
const _model = 'llama3.2';

OllamaProvider _provider(CheckContext ctx, FixtureServer server) {
  final provider = OllamaProvider(baseUrl: server.url('/api'));
  ctx.onCleanup(() async => provider.dispose());
  return provider;
}

Map<String, Object?> _reply({
  String content = '',
  List<Map<String, Object?>>? toolCalls,
  bool done = true,
}) => {
  'model': _model,
  'created_at': '2026-01-01T00:00:00.000000Z',
  'message': {
    'role': 'assistant',
    'content': content,
    'tool_calls': ?toolCalls,
  },
  if (done) ...{
    'done_reason': 'stop',
    'done': true,
    'total_duration': 123456789,
    'prompt_eval_count': 26,
    'eval_count': 298,
  } else
    'done': false,
};

final _weatherSchema = Schema<Map<String, dynamic>>(
  jsonSchema: const {
    'type': 'object',
    'properties': {
      'city': {'type': 'string'},
    },
    'required': ['city'],
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
    feature: 'ollama-generate',
    description:
        'generateText posts to /api/chat with stream=false, sampling in the '
        'options object (num_predict, top_p, top_k, seed, stop), no '
        'Authorization header, and returns text, usage and finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_reply(content: 'Hello from Ollama.')),
      );
      final result = await generateText(
        model: _provider(ctx, server)(_model),
        system: 'Be brief.',
        prompt: 'Say hello.',
        maxOutputTokens: 64,
        temperature: 0.2,
        topP: 0.9,
        topK: 40,
        seed: 42,
        stopSequences: const ['END'],
      );
      ctx.observe('text', result.text);
      ctx.observe('finishReason', '${result.finishReason}');
      ctx.observe('usage', result.usage);
      final request = ctx.singleRequest(server, '/api/chat', method: 'POST');
      final body = request.jsonObject;
      ctx.expectEquals(body['model'], _model, 'model');
      ctx.expectEquals(body['stream'], false, 'stream flag');
      ctx.expectEquals(body['options'], {
        'num_predict': 64,
        'temperature': 0.2,
        'top_p': 0.9,
        'top_k': 40,
        'seed': 42,
        'stop': ['END'],
      }, 'options object');
      ctx.expectEquals(
        (body['messages'] as List).map((m) => (m as Map)['role']).toList(),
        ['system', 'user'],
        'message roles',
      );
      ctx.expect(
        !request.headers.containsKey('authorization'),
        'Authorization header sent to local Ollama',
      );
      ctx.expectEquals(result.text, 'Hello from Ollama.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 26, 'input tokens');
      ctx.expectEquals(result.usage?.outputTokens.total, 298, 'output tokens');
      ctx.expect(
        '${result.finishReason}'.contains('stop'),
        'done_reason stop must map to stop',
      );
    },
  ),
  Check(
    id: 'stream-text',
    feature: 'ollama-stream',
    description:
        'streamText sends stream=true and turns the NDJSON lines from '
        '/api/chat into ordered text deltas, then usage and finish reason '
        'from the done:true line.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.ndjson([
          _reply(content: 'One, ', done: false),
          _reply(content: 'two, ', done: false),
          _reply(content: 'three.', done: false),
          _reply(),
        ]),
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
      ctx.observe('finishReason', '$finish');
      final body = ctx.singleRequest(server, '/api/chat').jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(deltas, ['One, ', 'two, ', 'three.'], 'delta order');
      ctx.expectEquals(usage?.inputTokens.total, 26, 'input tokens');
      ctx.expectEquals(usage?.outputTokens.total, 298, 'output tokens');
      ctx.expect('$finish'.contains('stop'), 'finish reason not stop');
    },
  ),
  Check(
    id: 'stream-errors',
    feature: 'ollama-errors',
    description:
        'An {"error": ...} NDJSON line after streaming started, and a stream '
        'that ends without done:true, each surface as a typed AiApiCallError.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.ndjson([
            _reply(content: 'partial', done: false),
            {'error': 'llama runner process has terminated'},
          ]);
        }
        return FixtureResponse.ndjson([
          _reply(content: 'partial', done: false),
        ]);
      });
      final model = _provider(ctx, server)(_model);
      final midStream = await ctx.expectThrows<AiApiCallError>(() async {
        final result = await streamText(model: model, prompt: 'hi');
        await result.textStream.toList();
      }, 'error line');
      final truncated = await ctx.expectThrows<AiApiCallError>(() async {
        final result = await streamText(model: model, prompt: 'hi');
        await result.textStream.toList();
      }, 'truncated stream');
      ctx.observe('midStream', midStream.message);
      ctx.observe('truncated', truncated.message);
      ctx.expectEquals(
        midStream.message,
        'llama runner process has terminated',
        'error line message',
      );
      ctx.expect(
        truncated.message.contains('before done: true'),
        'truncation message missing: ${truncated.message}',
      );
    },
  ),
  Check(
    id: 'tool-loop',
    feature: 'ollama-tools',
    description:
        'A message.tool_calls reply (arguments as a JSON object) runs the '
        'tool once; the follow-up sends the assistant tool_calls and a tool '
        'message with tool_name; the second reply is the final text.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _reply(
              toolCalls: [
                {
                  'function': {
                    'name': 'getWeather',
                    'arguments': {'city': 'Paris'},
                  },
                },
              ],
            ),
          );
        }
        return FixtureResponse.json(_reply(content: 'It is sunny in Paris.'));
      });
      var executions = 0;
      String? seenCity;
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
              seenCity = input['city'] as String?;
              return 'Sunny, 18C in ${input['city']}';
            },
          ),
        },
      );
      ctx.observe('text', result.text);
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, '/api/chat');
      ctx.expectEquals(requests.length, 2, 'request count');
      final tools = requests[0].jsonObject['tools'] as List;
      final fn = (tools.single as Map)['function'] as Map;
      ctx.expectEquals((tools.single as Map)['type'], 'function', 'tool type');
      ctx.expectEquals(fn['name'], 'getWeather', 'tool name');
      final followUp = (requests[1].jsonObject['messages'] as List).cast<Map>();
      final assistant = followUp.lastWhere((m) => m['role'] == 'assistant');
      final call =
          ((assistant['tool_calls'] as List).single as Map)['function'];
      ctx.expectEquals((call as Map)['arguments'], {
        'city': 'Paris',
      }, 'assistant call arguments');
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(toolMessage['tool_name'], 'getWeather', 'tool_name');
      ctx.expect(
        '${toolMessage['content']}'.contains('Sunny, 18C in Paris'),
        'tool result missing: ${toolMessage['content']}',
      );
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(seenCity, 'Paris', 'tool argument');
      ctx.expectEquals(result.text, 'It is sunny in Paris.', 'final text');
      ctx.expect(
        '${result.steps.first.finishReason}'.contains('toolCalls'),
        'first step finish reason: ${result.steps.first.finishReason}',
      );
    },
  ),
  Check(
    id: 'stream-tool-call',
    feature: 'ollama-tools',
    description:
        'A whole tool call inside an NDJSON line becomes one tool call; '
        'streamText runs it once and streams the follow-up answer.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.ndjson([
            _reply(
              done: false,
              toolCalls: [
                {
                  'function': {
                    'name': 'getWeather',
                    'arguments': {'city': 'Rome'},
                  },
                },
              ],
            ),
            _reply(),
          ]);
        }
        return FixtureResponse.ndjson([
          _reply(content: 'Rome is sunny.', done: false),
          _reply(),
        ]);
      });
      var executions = 0;
      final result = await streamText(
        model: _provider(ctx, server)(_model),
        prompt: 'Weather in Rome?',
        maxSteps: 3,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: 'Get current weather for a city.',
            inputSchema: _weatherSchema,
            execute: (input, _) async {
              executions++;
              return 'Sunny in ${input['city']}';
            },
          ),
        },
      );
      final text = (await result.textStream.toList()).join();
      ctx.observe('text', text);
      ctx.observe('executions', executions);
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(text, 'Rome is sunny.', 'final text');
      final requests = ctx.requestsTo(server, '/api/chat');
      ctx.expectEquals(requests.length, 2, 'request count');
      final toolMessage = (requests[1].jsonObject['messages'] as List)
          .cast<Map>()
          .lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(toolMessage['tool_name'], 'getWeather', 'tool_name');
    },
  ),
  Check(
    id: 'image-input',
    feature: 'ollama-multimodal',
    description:
        'An image part is attached to the user message as a raw base64 string '
        'in the images array (no data: prefix).',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_reply(content: 'A red dot.')),
      );
      final result = await generateText(
        model: _provider(ctx, server)('llava'),
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [
              const LanguageModelV4TextPart(text: 'What is this?'),
              LanguageModelV4ImagePart(
                image: DataContentBytes(Uint8List.fromList([137, 80, 78, 71])),
                mediaType: 'image/png',
              ),
            ],
          ),
        ],
      );
      final message =
          (ctx.singleRequest(server, '/api/chat').jsonObject['messages']
                  as List)
              .cast<Map>()
              .singleWhere((m) => m['role'] == 'user');
      ctx.observe('message', message);
      ctx.expectEquals(message['content'], 'What is this?', 'text content');
      ctx.expectEquals(message['images'], ['iVBORw=='], 'images');
      ctx.expectEquals(result.text, 'A red dot.', 'text');
    },
  ),
  Check(
    id: 'embed',
    feature: 'ollama-embed',
    description:
        'embed and embedMany post input to /api/embed with no auth header and '
        'return the vectors in input order; providerOptions["ollama"] is '
        'merged into the body.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final input = request.jsonObject['input'] as List;
        return FixtureResponse.json({
          'model': 'nomic-embed-text',
          'embeddings': [
            for (var i = 0; i < input.length; i++) [0.1 * (i + 1), 0.2, 0.3],
          ],
          'total_duration': 14143917,
          'load_duration': 1019500,
          'prompt_eval_count': 8,
        });
      });
      final model = _provider(ctx, server).embedding('nomic-embed-text');
      final one = await embed(model: model, value: 'sunny day');
      final many = await embedMany(
        model: model,
        values: ['alpha', 'beta'],
        providerOptions: const {
          'ollama': {'truncate': false, 'keep_alive': '5m'},
        },
      );
      ctx.observe('one', one.embedding);
      ctx.observe('many', [for (final e in many.embeddings) e.embedding]);
      final requests = ctx.requestsTo(server, '/api/embed', method: 'POST');
      ctx.expectEquals(requests.length, 2, 'embed request count');
      ctx.expect(
        requests.every((r) => !r.headers.containsKey('authorization')),
        'Authorization header sent to local Ollama',
      );
      final first = requests[0].jsonObject;
      ctx.expectEquals(first['model'], 'nomic-embed-text', 'model');
      ctx.expectEquals(first['input'], ['sunny day'], 'input');
      final second = requests[1].jsonObject;
      ctx.expectEquals(second['input'], ['alpha', 'beta'], 'input (many)');
      ctx.expectEquals(second['truncate'], false, 'truncate');
      ctx.expectEquals(second['keep_alive'], '5m', 'keep_alive');
      ctx.expectEquals(one.embedding, [0.1, 0.2, 0.3], 'single vector');
      ctx.expectEquals(many.embeddings[1].value, 'beta', 'value order');
      ctx.expectEquals(many.embeddings[1].embedding[0], 0.2, 'vector order');
    },
  ),
  Check(
    id: 'provider-options',
    feature: 'ollama-options',
    description:
        'providerOptions["ollama"] entries (num_ctx, repeat_penalty) are '
        'merged into the options object next to the standard sampling keys, '
        'and per-call headers reach the server.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_reply(content: 'ok')),
      );
      await generateText(
        model: _provider(ctx, server)(_model),
        prompt: 'hi',
        temperature: 0.5,
        headers: const {'x-verify-proxy': 'gateway'},
        providerOptions: const {
          'ollama': {'num_ctx': 4096, 'repeat_penalty': 1.1},
        },
      );
      final request = ctx.singleRequest(server, '/api/chat');
      final options = request.jsonObject['options'] as Map;
      ctx.observe('options', options);
      ctx.expectEquals(options['num_ctx'], 4096, 'num_ctx');
      ctx.expectEquals(options['repeat_penalty'], 1.1, 'repeat_penalty');
      ctx.expectEquals(options['temperature'], 0.5, 'temperature kept');
      ctx.expectEquals(request.headers['x-verify-proxy'], 'gateway', 'header');
    },
  ),
  Check(
    id: 'client-lifecycle',
    feature: 'ollama-provider',
    description:
        'An injected Dio is used for requests and left open by dispose(); an '
        'owned client sends requests to the given baseUrl without a key.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_reply(content: 'ok')),
      );
      final owned = _provider(ctx, server);
      await generateText(model: owned(_model), prompt: 'a');
      final dio = Dio(
        BaseOptions(
          baseUrl: server.url('/api'),
          headers: {'x-verify-client': 'injected'},
        ),
      );
      ctx.onCleanup(() async => dio.close(force: true));
      final injected = OllamaProvider(client: dio);
      await generateText(model: injected(_model), prompt: 'b');
      injected.dispose();
      await generateText(model: injected(_model), prompt: 'c');
      final markers = [
        for (final r in ctx.requestsTo(server, '/api/chat'))
          r.headers['x-verify-client'],
      ];
      ctx.observe('clientMarkers', markers);
      ctx.expectEquals(markers, [
        null,
        'injected',
        'injected',
      ], 'which client sent each request');
    },
  ),
  Check(
    id: 'default-base-url',
    feature: 'ollama-provider',
    description:
        'Without baseUrl the provider targets http://localhost:11434/api/chat '
        '(recorded and refused locally) and sends no Authorization header.',
    run: (ctx) async {
      final seen = <Uri>[];
      final error = await HttpOverrides.runWithHttpOverrides(() async {
        final provider = OllamaProvider();
        try {
          return await ctx.expectThrows<AiApiCallError>(
            () => generateText(
              model: provider(_model),
              prompt: 'hi',
              maxRetries: 0,
            ),
            'generateText',
          );
        } finally {
          provider.dispose();
        }
      }, _RecordingOverrides(seen));
      ctx.observe('connectUris', seen.map((u) => '$u').toList());
      ctx.observe('errorUrl', error.url);
      ctx.expect(seen.isNotEmpty, 'no connection attempt recorded');
      ctx.expectEquals(seen.first.host, 'localhost', 'host');
      ctx.expectEquals(seen.first.port, 11434, 'port');
      ctx.expectEquals(seen.first.scheme, 'http', 'scheme');
      ctx.expectEquals(
        error.url,
        'http://localhost:11434/api/chat',
        'default endpoint',
      );
    },
  ),
  Check(
    id: 'api-error',
    feature: 'ollama-errors',
    description:
        'A 404 {"error": "..."} reply becomes AiApiCallError with status and '
        'message for chat, a streamed chat request and embed.',
    run: (ctx) async {
      final server = await ctx.server(
        (request) => FixtureResponse.json({
          'error': request.path == '/api/embed'
              ? 'model "nope-embed" not found, try pulling it first'
              : 'model "llama99" not found, try pulling it first',
        }, status: 404),
      );
      final provider = _provider(ctx, server);
      final chat = await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: provider('llama99'),
          prompt: 'hi',
          maxRetries: 0,
        ),
        'generateText',
      );
      final streamed = await ctx.expectThrows<AiApiCallError>(() async {
        final result = await streamText(
          model: provider('llama99'),
          prompt: 'hi',
          maxRetries: 0,
        );
        await result.textStream.toList();
      }, 'streamText');
      final embedding = await ctx.expectThrows<AiApiCallError>(
        () => embed(model: provider.embedding('nope-embed'), value: 'x'),
        'embed',
      );
      ctx.observe('chat', {'status': chat.statusCode, 'message': chat.message});
      ctx.observe('stream', {
        'status': streamed.statusCode,
        'message': streamed.message,
      });
      ctx.observe('embed', {
        'status': embedding.statusCode,
        'message': embedding.message,
      });
      const chatMessage = 'model "llama99" not found, try pulling it first';
      ctx.expectEquals(chat.statusCode, 404, 'chat status');
      ctx.expectEquals(chat.message, chatMessage, 'chat message');
      ctx.expect(!chat.isRetryable, '404 must not be retryable');
      ctx.expectEquals(streamed.statusCode, 404, 'stream status');
      ctx.expectEquals(streamed.message, chatMessage, 'stream message');
      ctx.expectEquals(embedding.statusCode, 404, 'embed status');
      ctx.expect(
        embedding.message.contains('nope-embed'),
        'embed message: ${embedding.message}',
      );
    },
  ),
]);
