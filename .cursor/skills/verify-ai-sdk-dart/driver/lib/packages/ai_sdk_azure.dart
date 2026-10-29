// Verification checks for package:ai_sdk_azure. See features/ai_sdk_azure.md.
//
// No Azure key is available, so every check drives AzureOpenAIProvider against
// an in-process fixture that answers in the Azure OpenAI wire format.
import 'package:ai_sdk_azure/ai_sdk_azure.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';

import '../harness.dart';

const _package = 'ai_sdk_azure';

AzureOpenAIProvider _provider(
  CheckContext ctx,
  FixtureServer server, {
  String? apiKey = 'azure-verify-key',
  String? endpoint,
  String? apiVersion,
  CredentialProvider? credentialProvider,
}) {
  final provider = apiVersion == null
      ? AzureOpenAIProvider(
          endpoint: endpoint ?? server.origin,
          apiKey: apiKey,
          credentialProvider: credentialProvider,
        )
      : AzureOpenAIProvider(
          endpoint: endpoint ?? server.origin,
          apiKey: apiKey,
          credentialProvider: credentialProvider,
          apiVersion: apiVersion,
        );
  ctx.onCleanup(() async => provider.dispose());
  return provider;
}

Map<String, Object?> _completion({
  String? content,
  List<Map<String, Object?>>? toolCalls,
  String finishReason = 'stop',
}) => {
  'id': 'chatcmpl-azure-verify',
  'object': 'chat.completion',
  'created': 1767225600,
  'model': 'gpt-4o',
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
  'usage': {'prompt_tokens': 9, 'completion_tokens': 4, 'total_tokens': 13},
};

Map<String, Object?> _chunk(Map<String, Object?> delta, {String? finish}) => {
  'id': 'chatcmpl-azure-verify',
  'object': 'chat.completion.chunk',
  'created': 1767225600,
  'model': 'gpt-4o',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

Map<String, Object?> _responsesBody(String text) => {
  'id': 'resp_azure_verify',
  'object': 'response',
  'created_at': 1767225600,
  'status': 'completed',
  'model': 'gpt-4o',
  'output': [
    {
      'type': 'message',
      'id': 'msg_azure',
      'status': 'completed',
      'role': 'assistant',
      'content': [
        {'type': 'output_text', 'text': text, 'annotations': <Object>[]},
      ],
    },
  ],
  'usage': {'input_tokens': 6, 'output_tokens': 3, 'total_tokens': 9},
};

Map<String, Object?> _azureError(String message, String code) => {
  'error': {'code': code, 'message': message},
};

/// generateText wraps a retryable provider error in [AiRetryError] even with
/// maxRetries 0; this unwraps it.
Future<AiApiCallError> _retryableFailure(
  CheckContext ctx,
  Future<void> Function() body,
  String what,
) async {
  final retry = await ctx.expectThrows<AiRetryError>(body, what);
  final last = retry.lastError;
  ctx.expect(last is AiApiCallError, '$what: last error is $last');
  return last as AiApiCallError;
}

final checks = PackageChecks(_package, [
  Check(
    id: 'chat-url-and-api-key',
    feature: 'azure-url',
    description:
        'provider(deployment) posts to '
        '<endpoint>/openai/deployments/<id>/chat/completions with the '
        'api-key header and no Authorization header.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'Hello from Azure.')),
      );
      final result = await generateText(
        model: _provider(ctx, server)('my-gpt4o'),
        prompt: 'Say hello.',
        maxOutputTokens: 32,
      );
      final request = ctx.singleRequest(
        server,
        '/openai/deployments/my-gpt4o/chat/completions',
        method: 'POST',
      );
      ctx.observe('text', result.text);
      ctx.observe('path', request.path);
      ctx.observe('query', request.uri.queryParameters);
      ctx.expectEquals(
        request.headers['api-key'],
        'azure-verify-key',
        'api-key header',
      );
      ctx.expect(
        !request.headers.containsKey('authorization'),
        'Azure must not receive an Authorization header',
      );
      ctx.expectEquals(result.text, 'Hello from Azure.', 'text');
    },
  ),
  Check(
    id: 'endpoint-trailing-slash',
    feature: 'azure-url',
    description:
        'A trailing slash on the endpoint does not produce a double slash '
        'in the chat, Responses or embeddings URLs.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.path.endsWith('/embeddings')) {
          return FixtureResponse.json({
            'data': [
              {
                'index': 0,
                'embedding': [0.1, 0.2],
              },
            ],
            'usage': {'prompt_tokens': 1, 'total_tokens': 1},
          });
        }
        if (request.path.endsWith('/responses')) {
          return FixtureResponse.json(_responsesBody('r'));
        }
        return FixtureResponse.json(_completion(content: 'c'));
      });
      final provider = _provider(ctx, server, endpoint: '${server.origin}/');
      await generateText(model: provider('dep'), prompt: 'a');
      await generateText(model: provider.responses('dep'), prompt: 'b');
      await embed(model: provider.embedding('dep'), value: 'c');
      final paths = [for (final r in server.requests) r.path];
      ctx.observe('paths', paths);
      ctx.expectEquals(paths, [
        '/openai/deployments/dep/chat/completions',
        '/openai/v1/responses',
        '/openai/deployments/dep/embeddings',
      ], 'request paths');
    },
  ),
  Check(
    id: 'api-version',
    feature: 'azure-api-version',
    description:
        'Chat and embeddings send the default api-version query parameter, '
        'a custom apiVersion replaces it, and Responses sends none.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.path.endsWith('/embeddings')) {
          return FixtureResponse.json({
            'data': [
              {
                'index': 0,
                'embedding': [1.0],
              },
            ],
          });
        }
        if (request.path.endsWith('/responses')) {
          return FixtureResponse.json(_responsesBody('r'));
        }
        return FixtureResponse.json(_completion(content: 'c'));
      });
      final defaults = _provider(ctx, server);
      final custom = _provider(ctx, server, apiVersion: '2025-03-01-preview');
      await generateText(model: defaults('dep'), prompt: 'a');
      await embed(model: defaults.embedding('dep'), value: 'b');
      await generateText(model: custom('dep'), prompt: 'c');
      await embed(model: custom.embedding('dep'), value: 'd');
      await generateText(model: custom.responses('dep'), prompt: 'e');
      final versions = [
        for (final r in server.requests) r.uri.queryParameters['api-version'],
      ];
      ctx.observe('apiVersions', versions);
      ctx.expectEquals(defaults.apiVersion, '2024-02-15-preview', 'default');
      ctx.expectEquals(versions, [
        '2024-02-15-preview',
        '2024-02-15-preview',
        '2025-03-01-preview',
        '2025-03-01-preview',
        null,
      ], 'api-version per request');
    },
  ),
  Check(
    id: 'credential-provider',
    feature: 'azure-auth',
    description:
        'An async credentialProvider replaces apiKey and is resolved on each '
        'request; a null key sends no api-key header.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      var rotation = 0;
      final rotating = _provider(
        ctx,
        server,
        apiKey: 'ignored-static-key',
        credentialProvider: () async => 'rotated-${++rotation}',
      );
      await generateText(model: rotating('dep'), prompt: 'a');
      await generateText(model: rotating('dep'), prompt: 'b');
      await generateText(
        model: _provider(ctx, server, apiKey: null)('dep'),
        prompt: 'no key',
      );
      final keys = [for (final r in server.requests) r.headers['api-key']];
      ctx.observe('apiKeyHeaders', keys);
      ctx.expectEquals(keys, ['rotated-1', 'rotated-2', null], 'api-key');
    },
  ),
  Check(
    id: 'chat-generate',
    feature: 'azure-chat',
    description:
        'Chat sends the deployment as model, max_tokens (not '
        'max_completion_tokens) and messages, and returns text, usage and '
        'finish reason; chat() is the same as call syntax.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'Bonjour.')),
      );
      final provider = _provider(ctx, server);
      final result = await generateText(
        model: provider.chat('my-gpt4o'),
        system: 'Be brief.',
        prompt: 'Say hello in French.',
        maxOutputTokens: 24,
        temperature: 0.1,
      );
      final request = ctx.singleRequest(
        server,
        '/openai/deployments/my-gpt4o/chat/completions',
      );
      final body = request.jsonObject;
      ctx.observe('usage', result.usage);
      ctx.observe('finishReason', '${result.finishReason}');
      ctx.expectEquals(body['model'], 'my-gpt4o', 'model');
      ctx.expectEquals(body['max_tokens'], 24, 'max_tokens');
      ctx.expect(
        !body.containsKey('max_completion_tokens'),
        'max_completion_tokens must not be sent to Azure',
      );
      ctx.expectEquals(body['temperature'], 0.1, 'temperature');
      ctx.expectEquals(
        (body['messages'] as List).map((m) => (m as Map)['role']).toList(),
        ['system', 'user'],
        'message roles',
      );
      ctx.expectEquals(provider('x').modelId, 'x', 'modelId');
      ctx.expectEquals(provider('x').provider, 'azure', 'provider name');
      ctx.expectEquals(result.text, 'Bonjour.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 9, 'input tokens');
      ctx.expectEquals(result.usage?.outputTokens.total, 4, 'output tokens');
      ctx.expect(
        '${result.finishReason}'.contains('stop'),
        'finish reason is not stop',
      );
    },
  ),
  Check(
    id: 'chat-stream',
    feature: 'azure-chat',
    description:
        'streamText over an Azure deployment sends stream=true and yields '
        'the SSE deltas in order with usage.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _chunk({'role': 'assistant', 'content': ''}),
          _chunk({'content': 'Az'}),
          _chunk({'content': 'ure '}),
          _chunk({'content': 'stream.'}),
          _chunk({}, finish: 'stop'),
          {
            'id': 'chatcmpl-azure-verify',
            'object': 'chat.completion.chunk',
            'created': 1767225600,
            'model': 'gpt-4o',
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
        model: _provider(ctx, server)('my-gpt4o'),
        prompt: 'Stream.',
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      ctx.observe('deltas', deltas);
      ctx.observe('usage', usage);
      final request = ctx.singleRequest(
        server,
        '/openai/deployments/my-gpt4o/chat/completions',
      );
      ctx.expectEquals(request.jsonObject['stream'], true, 'stream flag');
      ctx.expectEquals(
        request.uri.queryParameters['api-version'],
        '2024-02-15-preview',
        'api-version on stream',
      );
      ctx.expectEquals(deltas.join(), 'Azure stream.', 'streamed text');
      ctx.expect(deltas.length >= 3, 'expected incremental deltas');
      ctx.expectEquals(usage?.outputTokens.total, 3, 'output tokens');
    },
  ),
  Check(
    id: 'chat-tool-loop',
    feature: 'azure-chat',
    description:
        'A tool call from an Azure deployment is executed and its result is '
        'sent back as a tool message to the same deployment URL.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _completion(
              finishReason: 'tool_calls',
              toolCalls: [
                {
                  'id': 'call_azure_1',
                  'type': 'function',
                  'function': {
                    'name': 'getWeather',
                    'arguments': '{"city":"Oslo"}',
                  },
                },
              ],
            ),
          );
        }
        return FixtureResponse.json(_completion(content: 'Cold in Oslo.'));
      });
      var executions = 0;
      final result = await generateText(
        model: _provider(ctx, server)('my-gpt4o'),
        prompt: 'Weather in Oslo?',
        maxSteps: 3,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: 'Get current weather for a city.',
            inputSchema: Schema(
              jsonSchema: const {
                'type': 'object',
                'properties': {
                  'city': {'type': 'string'},
                },
                'required': ['city'],
              },
              fromJson: (json) => json,
            ),
            execute: (input, _) async {
              executions++;
              return 'Snow, -2C in ${input['city']}';
            },
          ),
        },
      );
      final requests = ctx.requestsTo(
        server,
        '/openai/deployments/my-gpt4o/chat/completions',
      );
      ctx.observe('text', result.text);
      ctx.observe('executions', executions);
      ctx.expectEquals(requests.length, 2, 'request count');
      final tools = requests[0].jsonObject['tools'] as List;
      ctx.expectEquals(
        ((tools.single as Map)['function'] as Map)['name'],
        'getWeather',
        'serialized tool',
      );
      final followUp = (requests[1].jsonObject['messages'] as List).cast<Map>();
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(toolMessage['tool_call_id'], 'call_azure_1', 'call id');
      ctx.expect(
        '${toolMessage['content']}'.contains('Snow, -2C in Oslo'),
        'tool result missing from follow-up',
      );
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(result.text, 'Cold in Oslo.', 'final text');
    },
  ),
  Check(
    id: 'chat-provider-options',
    feature: 'azure-chat',
    description:
        'providerOptions under the azure key are merged into the chat body, '
        'for example Azure data-source style extras.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      await generateText(
        model: _provider(ctx, server)('my-gpt4o'),
        prompt: 'hi',
        providerOptions: const {
          'azure': {
            'user': 'verify-user',
            'data_sources': [
              {'type': 'azure_search'},
            ],
          },
        },
      );
      final body = ctx
          .singleRequest(
            server,
            '/openai/deployments/my-gpt4o/chat/completions',
          )
          .jsonObject;
      ctx.observe('body', {
        'user': body['user'],
        'data_sources': body['data_sources'],
      });
      ctx.expectEquals(body['user'], 'verify-user', 'user');
      ctx.expectEquals(body['data_sources'], [
        {'type': 'azure_search'},
      ], 'data_sources');
    },
  ),
  Check(
    id: 'responses-v1',
    feature: 'azure-responses',
    description:
        'provider.responses posts to /openai/v1/responses with the api-key '
        'header, the deployment as model and no api-version query.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_responsesBody('Responses on Azure.')),
      );
      final result = await generateText(
        model: _provider(ctx, server).responses('my-gpt4o'),
        system: 'Be brief.',
        prompt: 'Hello.',
        maxOutputTokens: 20,
      );
      final request = ctx.singleRequest(
        server,
        '/openai/v1/responses',
        method: 'POST',
      );
      final body = request.jsonObject;
      ctx.observe('text', result.text);
      ctx.observe('query', request.uri.queryParameters);
      ctx.expectEquals(request.headers['api-key'], 'azure-verify-key', 'key');
      ctx.expect(
        !request.headers.containsKey('authorization'),
        'Azure must not receive an Authorization header',
      );
      ctx.expect(request.uri.query.isEmpty, 'Responses must send no query');
      ctx.expectEquals(body['model'], 'my-gpt4o', 'deployment as model');
      ctx.expectEquals(body['instructions'], 'Be brief.', 'instructions');
      ctx.expectEquals(body['max_output_tokens'], 20, 'max_output_tokens');
      ctx.expectEquals(result.text, 'Responses on Azure.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 6, 'input tokens');
    },
  ),
  Check(
    id: 'embeddings',
    feature: 'azure-embeddings',
    description:
        'embed and embedMany post to the deployment embeddings URL with '
        'api-key and api-version, order vectors by index and report usage.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final input = request.jsonObject['input'] as List;
        return FixtureResponse.json({
          'object': 'list',
          'model': 'text-embedding-ada-002',
          'data': [
            for (var i = input.length - 1; i >= 0; i--)
              {
                'object': 'embedding',
                'index': i,
                'embedding': [i + 0.25, i + 0.75],
              },
          ],
          'usage': {'prompt_tokens': 6, 'total_tokens': 6},
        });
      });
      final model = _provider(ctx, server).embedding('my-ada');
      final one = await embed(model: model, value: 'alpha');
      final many = await embedMany(model: model, values: ['a', 'b']);
      final requests = ctx.requestsTo(
        server,
        '/openai/deployments/my-ada/embeddings',
        method: 'POST',
      );
      ctx.observe('single', one.embedding);
      ctx.observe('many', [for (final e in many.embeddings) e.embedding]);
      ctx.expectEquals(requests.length, 2, 'embedding requests');
      ctx.expectEquals(
        requests[0].headers['api-key'],
        'azure-verify-key',
        'key',
      );
      ctx.expectEquals(
        requests[0].uri.queryParameters['api-version'],
        '2024-02-15-preview',
        'api-version',
      );
      ctx.expectEquals(requests[0].jsonObject['input'], ['alpha'], 'input');
      ctx.expectEquals(requests[0].jsonObject['model'], 'my-ada', 'model');
      ctx.expectEquals(requests[1].jsonObject['input'], ['a', 'b'], 'many');
      ctx.expectEquals(one.embedding, [0.25, 0.75], 'single vector');
      ctx.expectEquals(
        [for (final e in many.embeddings) e.embedding],
        [
          [0.25, 0.75],
          [1.25, 1.75],
        ],
        'vectors restored to input order',
      );
      ctx.expectEquals(many.usage?.tokens, 6, 'usage tokens');
      ctx.expectEquals(model.provider, 'azure', 'provider name');
      ctx.expectEquals(model.modelId, 'my-ada', 'modelId');
    },
  ),
  Check(
    id: 'errors',
    feature: 'azure-errors',
    description:
        'Azure 401 and 429 JSON errors surface as AiApiCallError from chat, '
        'Responses and embeddings, with status and message; a malformed 2xx '
        'embeddings body is an invalid-response AiApiCallError.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.path.endsWith('/embeddings')) {
          if ('${request.jsonObject['input']}'.contains('malformed')) {
            return FixtureResponse.json({
              'data': [
                {
                  'index': 0,
                  'embedding': ['x'],
                },
              ],
            });
          }
          return FixtureResponse.json(
            _azureError(
              'Access denied due to invalid subscription key.',
              '401',
            ),
            status: 401,
          );
        }
        if (request.path.endsWith('/responses')) {
          return FixtureResponse.json(
            _azureError(
              'Requests to the Responses API are rate limited.',
              '429',
            ),
            status: 429,
          );
        }
        return FixtureResponse.json(
          _azureError('Access denied due to invalid subscription key.', '401'),
          status: 401,
        );
      });
      final provider = _provider(ctx, server);
      final chat = await ctx.expectThrows<AiApiCallError>(
        () => generateText(model: provider('dep'), prompt: 'hi', maxRetries: 0),
        'chat 401',
      );
      final responses = await _retryableFailure(
        ctx,
        () => generateText(
          model: provider.responses('dep'),
          prompt: 'hi',
          maxRetries: 0,
        ),
        'responses 429',
      );
      final embedding = await ctx.expectThrows<AiApiCallError>(
        () => embed(model: provider.embedding('dep'), value: 'x'),
        'embedding 401',
      );
      final malformed = await ctx.expectThrows<AiApiCallError>(
        () => embed(model: provider.embedding('dep'), value: 'malformed'),
        'embedding malformed',
      );
      ctx.observe('statuses', {
        'chat': chat.statusCode,
        'responses': responses.statusCode,
        'embedding': embedding.statusCode,
        'malformed': malformed.statusCode,
      });
      ctx.expectEquals(chat.statusCode, 401, 'chat status');
      ctx.expect(
        chat.message.contains('invalid subscription key'),
        'chat message lost: ${chat.message}',
      );
      ctx.expect(!chat.isRetryable, 'chat 401 must not be retryable');
      ctx.expectEquals(responses.statusCode, 429, 'responses status');
      ctx.expect(responses.isRetryable, 'responses 429 must be retryable');
      ctx.expectEquals(embedding.statusCode, 401, 'embedding status');
      ctx.expect(
        embedding.message.contains('invalid subscription key'),
        'embedding message lost: ${embedding.message}',
      );
      ctx.expect(
        malformed.message.contains('invalid 2xx response body'),
        'malformed message: ${malformed.message}',
      );
    },
  ),
  Check(
    id: 'dispose',
    feature: 'azure-provider',
    description:
        'dispose() closes the Dio client the provider created, so a later '
        'call fails instead of reaching the server.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      final provider = AzureOpenAIProvider(
        endpoint: server.origin,
        apiKey: 'k',
      );
      await generateText(model: provider('dep'), prompt: 'hi');
      provider.dispose();
      Object? failure;
      try {
        await generateText(
          model: provider('dep'),
          prompt: 'again',
          maxRetries: 0,
        );
      } catch (error) {
        failure = error;
      }
      ctx.observe('afterDispose', failure == null ? null : '$failure');
      ctx.expect(failure != null, 'a call after dispose() must fail');
      ctx.expectEquals(server.requests.length, 1, 'requests at the server');
    },
  ),
]);
