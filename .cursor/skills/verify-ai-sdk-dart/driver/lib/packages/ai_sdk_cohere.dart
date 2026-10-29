// Verification checks for package:ai_sdk_cohere. See features/ai_sdk_cohere.md.
//
// Each check builds a model through the public `CohereProvider`, drives it
// with the ai_sdk_dart core functions, and asserts both the request that
// reached the fixture server and the result the caller got. Fixtures use the
// Cohere v2 wire format (`/chat`, `/embed`, `/rerank`).
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_cohere';

CohereProvider _provider(
  CheckContext ctx,
  FixtureServer server, {
  String? apiKey = 'verify-key',
}) {
  final provider = CohereProvider(apiKey: apiKey, baseUrl: server.url('/v2'));
  ctx.onCleanup(() async => provider.dispose());
  return provider;
}

Map<String, Object?> _chatResponse({
  List<Map<String, Object?>>? content,
  String? toolPlan,
  List<Map<String, Object?>>? toolCalls,
  String finishReason = 'COMPLETE',
}) => {
  'id': 'c14c80c3-18eb-4519-9460-6c92edd8cfb4',
  'finish_reason': finishReason,
  'message': {
    'role': 'assistant',
    'content': ?content,
    'tool_plan': ?toolPlan,
    'tool_calls': ?toolCalls,
  },
  'usage': {
    'billed_units': {'input_tokens': 9, 'output_tokens': 4},
    'tokens': {'input_tokens': 71, 'output_tokens': 13},
  },
};

SseEvent _event(String type, Map<String, Object?> rest) =>
    SseEvent({'type': type, ...rest}, event: type);

SseEvent _textDelta(String text) => _event('content-delta', {
  'index': 0,
  'delta': {
    'message': {
      'content': {'text': text},
    },
  },
});

SseEvent _messageEnd(String reason, {int input = 5, int output = 3}) =>
    _event('message-end', {
      'delta': {
        'finish_reason': reason,
        'usage': {
          'billed_units': {'input_tokens': input, 'output_tokens': output},
          'tokens': {'input_tokens': input, 'output_tokens': output},
        },
      },
    });

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

Tool<Map<String, dynamic>, String> _weatherTool(void Function() onRun) =>
    tool<Map<String, dynamic>, String>(
      description: 'Get current weather for a city.',
      inputSchema: _weatherSchema,
      execute: (input, _) async {
        onRun();
        return 'Sunny, 18C in ${input['city']}';
      },
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
    feature: 'cohere-generate',
    description:
        'generateText posts to /chat with the bearer key, model, messages and '
        'Cohere sampling keys (p, k, max_tokens, stop_sequences), and returns '
        'text, usage and finish reason from the v2 response.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _chatResponse(
            content: [
              {'type': 'text', 'text': 'Hello from Cohere.'},
            ],
          ),
        ),
      );
      final result = await generateText(
        model: _provider(ctx, server)('command-a-03-2025'),
        system: 'Be brief.',
        prompt: 'Say hello.',
        maxOutputTokens: 64,
        temperature: 0.3,
        topP: 0.9,
        topK: 40,
        seed: 7,
        stopSequences: const ['END'],
      );
      ctx.observe('text', result.text);
      ctx.observe('finishReason', '${result.finishReason}');
      ctx.observe('usage', result.usage);
      final request = ctx.singleRequest(server, '/v2/chat', method: 'POST');
      final body = request.jsonObject;
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(body['model'], 'command-a-03-2025', 'model');
      ctx.expectEquals(body['max_tokens'], 64, 'max_tokens');
      ctx.expectEquals(body['temperature'], 0.3, 'temperature');
      ctx.expectEquals(body['p'], 0.9, 'p (topP)');
      ctx.expectEquals(body['k'], 40, 'k (topK)');
      ctx.expectEquals(body['seed'], 7, 'seed');
      ctx.expectEquals(body['stop_sequences'], ['END'], 'stop_sequences');
      ctx.expectEquals(
        (body['messages'] as List).map((m) => (m as Map)['role']).toList(),
        ['system', 'user'],
        'message roles',
      );
      ctx.expect(body['stream'] != true, 'non-streaming call sent stream=true');
      ctx.expectEquals(result.text, 'Hello from Cohere.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 71, 'input tokens');
      ctx.expectEquals(result.usage?.outputTokens.total, 13, 'output tokens');
      ctx.expect(
        '${result.finishReason}'.contains('stop'),
        'COMPLETE must map to stop',
      );
    },
  ),
  Check(
    id: 'stream-text',
    feature: 'cohere-stream',
    description:
        'streamText sends stream=true and turns the v2 SSE events '
        '(message-start, content-delta, message-end) into ordered text '
        'deltas, usage and a stop finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _event('message-start', {
            'id': 'msg-verify',
            'delta': {
              'message': {'role': 'assistant', 'content': <Object>[]},
            },
          }),
          _event('content-start', {
            'index': 0,
            'delta': {
              'message': {
                'content': {'type': 'text', 'text': ''},
              },
            },
          }),
          _textDelta('One, '),
          _textDelta('two, '),
          _textDelta('three.'),
          _event('content-end', {'index': 0}),
          _messageEnd('COMPLETE', input: 12, output: 6),
        ]),
      );
      final result = await streamText(
        model: _provider(ctx, server)('command-a-03-2025'),
        prompt: 'Count to three.',
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      final finish = await result.finishReason;
      ctx.observe('deltas', deltas);
      ctx.observe('usage', usage);
      ctx.observe('finishReason', '$finish');
      final body = ctx.singleRequest(server, '/v2/chat').jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(deltas, ['One, ', 'two, ', 'three.'], 'delta order');
      ctx.expectEquals(usage?.inputTokens.total, 12, 'input tokens');
      ctx.expectEquals(usage?.outputTokens.total, 6, 'output tokens');
      ctx.expect('$finish'.contains('stop'), 'finish reason not stop');
    },
  ),
  Check(
    id: 'stream-truncated',
    feature: 'cohere-errors',
    description:
        'A stream that ends before message-end surfaces a typed '
        'AiApiCallError event instead of finishing silently.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([_textDelta('partial')]),
      );
      final result = await streamText(
        model: _provider(ctx, server)('command-a-03-2025'),
        prompt: 'hi',
      );
      final error = await ctx.expectThrows<AiApiCallError>(
        () => result.textStream.toList(),
        'textStream',
      );
      ctx.observe('error', '$error');
      ctx.expect(
        error.message.contains('before message-end'),
        'truncation message missing: ${error.message}',
      );
    },
  ),
  Check(
    id: 'tool-loop',
    feature: 'cohere-tools',
    description:
        'A v2 tool_calls reply (with tool_plan) runs the tool once and sends '
        'back an assistant tool_calls message plus a tool message with the '
        'same tool_call_id; the second reply is the final text.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _chatResponse(
              toolPlan: 'I will look up the weather in Paris.',
              toolCalls: [
                {
                  'id': 'getWeather_k1',
                  'type': 'function',
                  'function': {
                    'name': 'getWeather',
                    'arguments': '{"city":"Paris"}',
                  },
                },
              ],
              finishReason: 'TOOL_CALL',
            ),
          );
        }
        return FixtureResponse.json(
          _chatResponse(
            content: [
              {'type': 'text', 'text': 'It is sunny in Paris.'},
            ],
          ),
        );
      });
      var executions = 0;
      final result = await generateText(
        model: _provider(ctx, server)('command-a-03-2025'),
        prompt: 'Weather in Paris?',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(() => executions++)},
      );
      ctx.observe('text', result.text);
      ctx.observe('steps', result.steps.length);
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, '/v2/chat');
      ctx.expectEquals(requests.length, 2, 'request count');
      final tools = requests[0].jsonObject['tools'] as List;
      final fn = (tools.single as Map)['function'] as Map;
      ctx.expectEquals((tools.single as Map)['type'], 'function', 'tool type');
      ctx.expectEquals(fn['name'], 'getWeather', 'tool name');
      ctx.expectEquals((fn['parameters'] as Map)['required'], [
        'city',
      ], 'tool parameters schema');
      final followUp = (requests[1].jsonObject['messages'] as List).cast<Map>();
      final assistant = followUp.lastWhere((m) => m['role'] == 'assistant');
      final calls = assistant['tool_calls'] as List;
      ctx.expectEquals((calls.single as Map)['id'], 'getWeather_k1', 'call id');
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(
        toolMessage['tool_call_id'],
        'getWeather_k1',
        'tool_call_id',
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
    id: 'stream-tool-call',
    feature: 'cohere-tools',
    description:
        'The SSE events tool-call-start, tool-call-delta and tool-call-end '
        'assemble one complete tool call; streamText runs it once and streams '
        'the follow-up answer.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.sse([
            _event('tool-plan-delta', {
              'delta': {
                'message': {'tool_plan': 'Looking it up.'},
              },
            }),
            _event('tool-call-start', {
              'index': 0,
              'delta': {
                'message': {
                  'tool_calls': {
                    'id': 'getWeather_s1',
                    'type': 'function',
                    'function': {'name': 'getWeather', 'arguments': ''},
                  },
                },
              },
            }),
            _event('tool-call-delta', {
              'index': 0,
              'delta': {
                'message': {
                  'tool_calls': {
                    'function': {'arguments': '{"city":'},
                  },
                },
              },
            }),
            _event('tool-call-delta', {
              'index': 0,
              'delta': {
                'message': {
                  'tool_calls': {
                    'function': {'arguments': '"Rome"}'},
                  },
                },
              },
            }),
            _event('tool-call-end', {'index': 0}),
            _messageEnd('TOOL_CALL'),
          ]);
        }
        return FixtureResponse.sse([
          _textDelta('Rome is sunny.'),
          _messageEnd('COMPLETE'),
        ]);
      });
      var executions = 0;
      String? seenCity;
      final result = await streamText(
        model: _provider(ctx, server)('command-a-03-2025'),
        prompt: 'Weather in Rome?',
        maxSteps: 3,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: 'Get current weather for a city.',
            inputSchema: _weatherSchema,
            execute: (input, _) async {
              executions++;
              seenCity = input['city'] as String?;
              return 'Sunny in ${input['city']}';
            },
          ),
        },
      );
      final text = (await result.textStream.toList()).join();
      final toolCalls = await result.steps.then(
        (s) => s.expand((step) => step.toolCalls).toList(),
      );
      ctx.observe('text', text);
      ctx.observe('executions', executions);
      ctx.observe('city', seenCity);
      ctx.observe('toolCallCount', toolCalls.length);
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(seenCity, 'Rome', 'assembled tool arguments');
      ctx.expectEquals(toolCalls.single.toolCallId, 'getWeather_s1', 'call id');
      ctx.expectEquals(text, 'Rome is sunny.', 'final text');
      final requests = ctx.requestsTo(server, '/v2/chat');
      ctx.expectEquals(requests.length, 2, 'request count');
      final toolMessage = (requests[1].jsonObject['messages'] as List)
          .cast<Map>()
          .lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(toolMessage['tool_call_id'], 'getWeather_s1', 'id');
    },
  ),
  Check(
    id: 'tool-choice-and-options',
    feature: 'cohere-tools',
    description:
        'ToolChoiceRequired maps to tool_choice REQUIRED, ToolChoiceNone to '
        'NONE, auto omits the field, and providerOptions["cohere"] is merged '
        'into the request body.',
    run: (ctx) async {
      final server = await ctx.server(
        (request) => FixtureResponse.json(
          request.jsonObject['tool_choice'] == 'REQUIRED'
              ? _chatResponse(
                  toolCalls: [
                    {
                      'id': 'getWeather_r1',
                      'type': 'function',
                      'function': {
                        'name': 'getWeather',
                        'arguments': '{"city":"Oslo"}',
                      },
                    },
                  ],
                  finishReason: 'TOOL_CALL',
                )
              : _chatResponse(
                  content: [
                    {'type': 'text', 'text': 'ok'},
                  ],
                ),
        ),
      );
      final model = _provider(ctx, server)('command-a-03-2025');
      final tools = {'getWeather': _weatherTool(() {})};
      await generateText(
        model: model,
        prompt: 'a',
        tools: tools,
        toolChoice: const ToolChoiceRequired(),
        providerOptions: const {
          'cohere': {'safety_mode': 'STRICT', 'frequency_penalty': 0.5},
        },
      );
      await generateText(
        model: model,
        prompt: 'b',
        tools: tools,
        toolChoice: const ToolChoiceNone(),
      );
      await generateText(
        model: model,
        prompt: 'c',
        tools: tools,
        toolChoice: const ToolChoiceAuto(),
      );
      final requests = ctx.requestsTo(server, '/v2/chat');
      ctx.expectEquals(requests.length, 3, 'request count');
      final bodies = requests.map((r) => r.jsonObject).toList();
      ctx.observe('toolChoices', [for (final b in bodies) b['tool_choice']]);
      ctx.expectEquals(bodies[0]['tool_choice'], 'REQUIRED', 'required');
      ctx.expectEquals(bodies[1]['tool_choice'], 'NONE', 'none');
      ctx.expect(!bodies[2].containsKey('tool_choice'), 'auto sent a value');
      ctx.expectEquals(bodies[0]['safety_mode'], 'STRICT', 'safety_mode');
      ctx.expectEquals(bodies[0]['frequency_penalty'], 0.5, 'penalty');
    },
  ),
  Check(
    id: 'image-input',
    feature: 'cohere-multimodal',
    description:
        'An image part is sent as a content array with a text item and an '
        'image_url item holding a base64 data URI.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _chatResponse(
            content: [
              {'type': 'text', 'text': 'A red dot.'},
            ],
          ),
        ),
      );
      final bytes = Uint8List.fromList([137, 80, 78, 71]);
      final result = await generateText(
        model: _provider(ctx, server)('command-a-vision-07-2025'),
        messages: [
          ModelMessage.parts(
            role: ModelMessageRole.user,
            parts: [
              const LanguageModelV4TextPart(text: 'What is this?'),
              LanguageModelV4ImagePart(
                image: DataContentBytes(bytes),
                mediaType: 'image/png',
              ),
            ],
          ),
        ],
      );
      final message =
          (ctx.singleRequest(server, '/v2/chat').jsonObject['messages'] as List)
              .cast<Map>()
              .singleWhere((m) => m['role'] == 'user');
      final parts = (message['content'] as List).cast<Map>();
      ctx.observe('contentTypes', [for (final p in parts) p['type']]);
      ctx.expectEquals(parts.map((p) => p['type']).toList(), [
        'text',
        'image_url',
      ], 'content part types');
      ctx.expectEquals(
        (parts[1]['image_url'] as Map)['url'],
        'data:image/png;base64,iVBORw==',
        'image data URI',
      );
      ctx.expectEquals(result.text, 'A red dot.', 'text');
    },
  ),
  Check(
    id: 'embed',
    feature: 'cohere-embed',
    description:
        'embed and embedMany post texts to /embed with embedding_types float '
        'and the default input_type, honor an input_type override, and return '
        'the vectors in input order.',
    run: (ctx) async {
      final server = await ctx.server(
        (request) => FixtureResponse.json({
          'id': 'embed-verify',
          'texts': (request.jsonObject['texts'] as List),
          'embeddings': {
            'float': [
              for (
                var i = 0;
                i < (request.jsonObject['texts'] as List).length;
                i++
              )
                [0.1 * (i + 1), 0.2, 0.3],
            ],
          },
          'meta': {
            'billed_units': {'input_tokens': 4},
          },
        }),
      );
      final model = _provider(ctx, server).embedding('embed-english-v3.0');
      final one = await embed(model: model, value: 'sunny day');
      final many = await embedMany(
        model: model,
        values: ['alpha', 'beta'],
        providerOptions: const {
          'cohere': {'input_type': 'search_query'},
        },
      );
      ctx.observe('one', one.embedding);
      ctx.observe('many', [for (final e in many.embeddings) e.embedding]);
      final requests = ctx.requestsTo(server, '/v2/embed', method: 'POST');
      ctx.expectEquals(requests.length, 2, 'embed request count');
      final first = requests[0].jsonObject;
      ctx.expectEquals(
        requests[0].headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(first['model'], 'embed-english-v3.0', 'model');
      ctx.expectEquals(first['texts'], ['sunny day'], 'texts');
      ctx.expectEquals(first['input_type'], 'search_document', 'input_type');
      ctx.expectEquals(first['embedding_types'], ['float'], 'types');
      final second = requests[1].jsonObject;
      ctx.expectEquals(second['texts'], ['alpha', 'beta'], 'texts (many)');
      ctx.expectEquals(second['input_type'], 'search_query', 'override');
      ctx.expectEquals(one.embedding, [0.1, 0.2, 0.3], 'single vector');
      ctx.expectEquals(many.embeddings.length, 2, 'many vectors');
      ctx.expectEquals(many.embeddings[1].value, 'beta', 'value order');
      ctx.expectEquals(many.embeddings[1].embedding[0], 0.2, 'vector order');
    },
  ),
  Check(
    id: 'rerank',
    feature: 'cohere-rerank',
    description:
        'rerank posts query, documents and top_n to /rerank and returns '
        'documents in the order and with the scores Cohere sent, each linked '
        'to its original index and text.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json({
          'id': 'rerank-verify',
          'results': [
            {'index': 2, 'relevance_score': 0.92},
            {'index': 0, 'relevance_score': 0.31},
          ],
          'meta': {
            'billed_units': {'search_units': 1},
          },
        }),
      );
      final result = await rerank(
        model: _provider(ctx, server).rerank('rerank-v3.5'),
        query: 'capital of France',
        documents: [
          'Berlin is in Germany.',
          'Cats purr.',
          'Paris is the capital.',
        ],
        topN: 2,
      );
      ctx.observe('ranked', [
        for (final d in result.documents)
          {'index': d.index, 'score': d.relevanceScore, 'text': d.document},
      ]);
      final request = ctx.singleRequest(server, '/v2/rerank', method: 'POST');
      final body = request.jsonObject;
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(body['model'], 'rerank-v3.5', 'model');
      ctx.expectEquals(body['query'], 'capital of France', 'query');
      ctx.expectEquals((body['documents'] as List).length, 3, 'documents');
      ctx.expectEquals(body['top_n'], 2, 'top_n');
      ctx.expectEquals(result.documents.length, 2, 'ranked count');
      ctx.expectEquals(result.document.index, 2, 'top index');
      ctx.expectEquals(
        result.document.document,
        'Paris is the capital.',
        'top',
      );
      ctx.expectEquals(result.document.relevanceScore, 0.92, 'top score');
      ctx.expectEquals(result.documents[1].index, 0, 'second index');
    },
  ),
  Check(
    id: 'auth-and-client',
    feature: 'cohere-provider',
    description:
        'apiKey, an async credentialProvider and a missing key produce the '
        'Bearer header, the resolved key and no Authorization header; an '
        'injected client is used and left open by dispose().',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _chatResponse(
            content: [
              {'type': 'text', 'text': 'ok'},
            ],
          ),
        ),
      );
      final base = server.url('/v2');
      await generateText(model: _provider(ctx, server)('m'), prompt: 'a');
      final dynamicProvider = CohereProvider(
        baseUrl: base,
        credentialProvider: () async => 'dyn-key',
      );
      ctx.onCleanup(() async => dynamicProvider.dispose());
      await generateText(model: dynamicProvider('m'), prompt: 'b');
      final keyless = CohereProvider(baseUrl: base);
      ctx.onCleanup(() async => keyless.dispose());
      await generateText(model: keyless('m'), prompt: 'c');
      final dio = Dio(
        BaseOptions(baseUrl: base, headers: {'x-verify-client': 'injected'}),
      );
      ctx.onCleanup(() async => dio.close(force: true));
      final injected = CohereProvider(apiKey: 'inj-key', client: dio);
      await generateText(model: injected('m'), prompt: 'd');
      injected.dispose();
      await generateText(model: injected('m'), prompt: 'e');
      final auth = [
        for (final r in ctx.requestsTo(server, '/v2/chat'))
          r.headers['authorization'],
      ];
      ctx.observe('authHeaders', auth);
      final markers = [
        for (final r in ctx.requestsTo(server, '/v2/chat'))
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
    feature: 'cohere-provider',
    description:
        'Without baseUrl the provider connects to api.cohere.com over TLS '
        'port 443 (recorded and refused locally, no traffic leaves).',
    run: (ctx) async {
      final seen = <Uri>[];
      final error = await HttpOverrides.runWithHttpOverrides(() async {
        final provider = CohereProvider(apiKey: 'verify-key');
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
      ctx.expectEquals(seen.first.host, 'api.cohere.com', 'host');
      ctx.expectEquals(seen.first.scheme, 'https', 'scheme');
      ctx.expectEquals(
        error.url,
        'https://api.cohere.com/v2/chat',
        'default endpoint',
      );
    },
  ),
  Check(
    id: 'api-error',
    feature: 'cohere-errors',
    description:
        'Non-2xx replies with Cohere\'s {message} body become AiApiCallError '
        'with status and message for chat, a streamed chat request, embed and '
        'rerank; 401 is not retryable.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final (status, message) = switch (request.path) {
          '/v2/embed' => (400, 'invalid embedding model'),
          '/v2/rerank' => (422, 'unknown rerank model'),
          _ => (401, 'invalid api token'),
        };
        return FixtureResponse.json({'message': message}, status: status);
      });
      final provider = _provider(ctx, server);
      final chat = await ctx.expectThrows<AiApiCallError>(
        () => generateText(model: provider('m'), prompt: 'hi', maxRetries: 0),
        'generateText',
      );
      final streamed = await ctx.expectThrows<AiApiCallError>(() async {
        final result = await streamText(
          model: provider('m'),
          prompt: 'hi',
          maxRetries: 0,
        );
        await result.textStream.toList();
      }, 'streamText');
      final embedding = await ctx.expectThrows<AiApiCallError>(
        () => embed(model: provider.embedding('e'), value: 'x'),
        'embed',
      );
      final reranking = await ctx.expectThrows<AiApiCallError>(
        () => rerank(model: provider.rerank('r'), query: 'q', documents: ['a']),
        'rerank',
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
      ctx.observe('rerank', {
        'status': reranking.statusCode,
        'message': reranking.message,
      });
      ctx.expectEquals(chat.statusCode, 401, 'chat status');
      ctx.expectEquals(chat.message, 'invalid api token', 'chat message');
      ctx.expect(!chat.isRetryable, '401 must not be retryable');
      ctx.expectEquals(streamed.statusCode, 401, 'stream status');
      ctx.expectEquals(streamed.message, 'invalid api token', 'stream msg');
      ctx.expectEquals(embedding.statusCode, 400, 'embed status');
      ctx.expectEquals(embedding.message, 'invalid embedding model', 'embed');
      ctx.expectEquals(reranking.statusCode, 422, 'rerank status');
      ctx.expectEquals(reranking.message, 'unknown rerank model', 'rerank');
    },
  ),
]);
