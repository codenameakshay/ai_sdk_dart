// Verification checks for package:ai_sdk_openai. See features/ai_sdk_openai.md.
//
// Fixture checks drive the provider through its public API against an
// in-process server that answers in the real OpenAI wire formats. Live checks
// (OPENAI_API_KEY) repeat the main paths against api.openai.com with tiny
// inputs and a recording Dio.
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_openai';
const _liveBaseUrl = 'https://api.openai.com/v1';

OpenAIProvider _provider(
  CheckContext ctx,
  FixtureServer server, {
  String? apiKey = 'verify-key',
  CredentialProvider? credentialProvider,
}) {
  final provider = OpenAIProvider(
    apiKey: apiKey,
    baseUrl: server.url('/v1'),
    credentialProvider: credentialProvider,
  );
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
  'model': 'gpt-4.1-mini',
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
  'model': 'gpt-4.1-mini',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': finish},
  ],
};

Map<String, Object?> _message(
  String text, {
  List<Object> annotations = const [],
}) => {
  'type': 'message',
  'id': 'msg_verify',
  'status': 'completed',
  'role': 'assistant',
  'content': [
    {'type': 'output_text', 'text': text, 'annotations': annotations},
  ],
};

Map<String, Object?> _response(
  List<Map<String, Object?>> output, {
  Map<String, Object?>? usage,
  String status = 'completed',
}) => {
  'id': 'resp_verify',
  'object': 'response',
  'created_at': 1767225600,
  'status': status,
  'model': 'gpt-4.1-mini',
  'output': output,
  'usage':
      usage ??
      {
        'input_tokens': 12,
        'output_tokens': 8,
        'total_tokens': 20,
        'input_tokens_details': {'cached_tokens': 4},
        'output_tokens_details': {'reasoning_tokens': 3},
      },
};

Map<String, Object?> _functionCall(String callId, String name, String args) => {
  'type': 'function_call',
  'id': 'fc_$callId',
  'call_id': callId,
  'name': name,
  'arguments': args,
  'status': 'completed',
};

Map<String, Object?> _error(String message, String type, String code) => {
  'error': {'message': message, 'type': type, 'code': code, 'param': null},
};

Tool<Map<String, dynamic>, String> _weatherTool(void Function() onExecute) =>
    tool<Map<String, dynamic>, String>(
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
      execute: (input, _) async {
        onExecute();
        return 'Sunny, 18C in ${input['city']}';
      },
    );

Schema<Map<String, dynamic>> _capitalSchema() => Schema<Map<String, dynamic>>(
  jsonSchema: const {
    'type': 'object',
    'properties': {
      'capital': {'type': 'string'},
      'country': {'type': 'string'},
    },
    'required': ['capital', 'country'],
    'additionalProperties': false,
  },
  fromJson: (json) => json,
);

final _png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4, //
]);

String _stringOf(Object? value) => '$value';

OpenAIProvider _liveProvider(CheckContext ctx, {String? apiKey}) {
  final key = apiKey ?? ctx.requireEnv('OPENAI_API_KEY');
  return OpenAIProvider(
    apiKey: key,
    client: ctx.recordingDio(baseUrl: _liveBaseUrl),
  );
}

String _liveModel(CheckContext ctx) =>
    ctx.env('OPENAI_VERIFY_MODEL', 'gpt-4.1-mini');

/// Runs [body], which must fail with a retryable provider error. generateText
/// wraps that error in [AiRetryError] even with maxRetries 0.
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
  // ---------------------------------------------------------------- provider
  Check(
    id: 'provider-auth',
    feature: 'provider-config',
    description:
        'apiKey becomes a Bearer header, an async credentialProvider is '
        'resolved per request, and an empty key sends no Authorization header.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      await generateText(
        model: _provider(ctx, server, apiKey: 'static-key')('gpt-4.1-mini'),
        prompt: 'hi',
      );
      var rotation = 0;
      final rotating = _provider(
        ctx,
        server,
        credentialProvider: () async => 'rotated-${++rotation}',
      );
      await generateText(model: rotating.chat('gpt-4.1-mini'), prompt: 'a');
      await generateText(model: rotating.chat('gpt-4.1-mini'), prompt: 'b');
      await generateText(
        model: _provider(ctx, server, apiKey: '')('gpt-4.1-mini'),
        prompt: 'no key',
      );
      final auth = [
        for (final r in server.requests) r.headers['authorization'],
      ];
      ctx.observe('authorizationHeaders', auth);
      ctx.expectEquals(auth, [
        'Bearer static-key',
        'Bearer rotated-1',
        'Bearer rotated-2',
        null,
      ], 'authorization header per request');
    },
  ),
  Check(
    id: 'provider-base-url-client',
    feature: 'provider-config',
    description:
        'baseUrl routes chat and Responses requests, and an injected Dio '
        'client (with its own headers) is used and survives dispose().',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.path.endsWith('/responses')) {
          return FixtureResponse.json(_response([_message('responses ok')]));
        }
        return FixtureResponse.json(_completion(content: 'chat ok'));
      });
      final dio = Dio(
        BaseOptions(
          baseUrl: server.url('/proxy/v1'),
          headers: {
            'OpenAI-Organization': 'org-verify',
            'OpenAI-Project': 'proj-verify',
          },
        ),
      );
      ctx.onCleanup(() async => dio.close(force: true));
      final injected = OpenAIProvider(
        apiKey: 'k',
        baseUrl: server.url('/proxy/v1'),
        client: dio,
      );
      final chat = await generateText(
        model: injected('gpt-4.1-mini'),
        prompt: 'hi',
      );
      injected.dispose();
      final responses = await generateText(
        model: injected.responses('gpt-4.1-mini'),
        prompt: 'hi',
      );
      ctx.observe('paths', [for (final r in server.requests) r.path]);
      ctx.expectEquals(chat.text, 'chat ok', 'chat text');
      ctx.expectEquals(
        responses.text,
        'responses ok',
        'responses text after dispose of an injected client',
      );
      ctx.expectEquals(server.requests.map((r) => r.path).toList(), [
        '/proxy/v1/chat/completions',
        '/proxy/v1/responses',
      ], 'request paths under baseUrl');
      for (final r in server.requests) {
        ctx.expectEquals(
          r.headers['openai-organization'],
          'org-verify',
          'organization header from the injected client',
        );
        ctx.expectEquals(
          r.headers['openai-project'],
          'proj-verify',
          'project header from the injected client',
        );
      }
      ctx.note(
        'OpenAIProvider has no organization/project option; those headers '
        'travel through the injected Dio client.',
      );
    },
  ),
  Check(
    id: 'provider-dispose',
    feature: 'provider-config',
    description:
        'dispose() closes the Dio client the provider created, so a later '
        'call fails instead of reaching the server.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      final provider = OpenAIProvider(apiKey: 'k', baseUrl: server.url('/v1'));
      final before = await generateText(
        model: provider('gpt-4.1-mini'),
        prompt: 'hi',
      );
      provider.dispose();
      Object? failure;
      try {
        await generateText(
          model: provider('gpt-4.1-mini'),
          prompt: 'again',
          maxRetries: 0,
        );
      } catch (error) {
        failure = error;
      }
      ctx.observe('beforeDispose', before.text);
      ctx.observe('afterDispose', failure == null ? null : '$failure');
      ctx.expectEquals(before.text, 'ok', 'text before dispose');
      ctx.expect(failure != null, 'a call after dispose() must fail');
      ctx.expectEquals(
        server.requests.length,
        1,
        'requests that reached the server',
      );
    },
  ),

  // -------------------------------------------------------------------- chat
  Check(
    id: 'chat-generate',
    feature: 'chat-generate',
    description:
        'provider(model) sends Chat Completions with Bearer auth, model, '
        'messages and max_completion_tokens, and returns text, usage, finish.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'Hello there.')),
      );
      final result = await generateText(
        model: _provider(ctx, server)('gpt-4.1-mini'),
        system: 'Be brief.',
        prompt: 'Say hello.',
        maxOutputTokens: 32,
        temperature: 0.3,
      );
      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      ctx.observe('finishReason', '${result.finishReason}');
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
      ctx.expectEquals(body['model'], 'gpt-4.1-mini', 'model');
      ctx.expectEquals(body['max_completion_tokens'], 32, 'max tokens key');
      ctx.expectEquals(body['temperature'], 0.3, 'temperature');
      ctx.expectEquals(
        (body['messages'] as List).map((m) => (m as Map)['role']).toList(),
        ['system', 'user'],
        'message roles',
      );
      ctx.expectEquals(result.text, 'Hello there.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 11, 'input tokens');
      ctx.expectEquals(result.usage?.outputTokens.total, 7, 'output tokens');
      ctx.expect(
        _stringOf(result.finishReason).contains('stop'),
        'finish reason is not stop',
      );
      ctx.expect(
        result.warnings.isEmpty,
        'a non gpt-6 model must carry no warnings: ${result.warnings}',
      );
    },
  ),
  Check(
    id: 'chat-stream',
    feature: 'chat-stream',
    description:
        'streamText over chat sends stream=true with include_usage and yields '
        'the SSE deltas in order, then usage.',
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
            'model': 'gpt-4.1-mini',
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
        model: _provider(ctx, server).chat('gpt-4.1-mini'),
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
      ctx.expect(deltas.length >= 3, 'expected incremental deltas');
      ctx.expectEquals(usage?.outputTokens.total, 3, 'output tokens');
    },
  ),
  Check(
    id: 'chat-tool-loop',
    feature: 'chat-tools',
    description:
        'A tool call is executed and its result goes back as a tool message; '
        'the second response becomes the final text.',
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
        return FixtureResponse.json(_completion(content: 'Sunny in Paris.'));
      });
      var executions = 0;
      final result = await generateText(
        model: _provider(ctx, server)('gpt-4.1-mini'),
        prompt: 'Weather in Paris?',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(() => executions++)},
      );
      ctx.observe('text', result.text);
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, '/v1/chat/completions');
      ctx.expectEquals(requests.length, 2, 'request count');
      final tools = requests[0].jsonObject['tools'] as List;
      ctx.expectEquals(
        ((tools.single as Map)['function'] as Map)['name'],
        'getWeather',
        'serialized tool',
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
        'tool result missing from follow-up',
      );
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(result.text, 'Sunny in Paris.', 'final text');
    },
  ),
  Check(
    id: 'chat-structured',
    feature: 'chat-structured',
    description:
        'Output.object sends response_format json_schema and parses the '
        'JSON reply.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _completion(content: '{"capital":"Paris","country":"France"}'),
        ),
      );
      final result = await generateText<Map<String, dynamic>>(
        model: _provider(ctx, server)('gpt-4.1-mini'),
        prompt: 'Capital of France.',
        output: Output.object(schema: _capitalSchema()),
      );
      ctx.observe('output', result.output);
      final body = ctx.singleRequest(server, '/v1/chat/completions').jsonObject;
      final format = body['response_format'] as Map?;
      ctx.expectEquals(format?['type'], 'json_schema', 'response_format.type');
      ctx.expectEquals(result.output, {
        'capital': 'Paris',
        'country': 'France',
      }, 'output');
    },
  ),
  Check(
    id: 'chat-provider-options',
    feature: 'chat-options',
    description:
        'OpenAILanguageModelOptions, snake_case keys, the standard reasoning '
        'enum and pass-through keys all land in the chat request body.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      final model = _provider(ctx, server)('o4-mini');
      await generateText(
        model: model,
        prompt: 'typed',
        providerOptions: {
          'openai': const OpenAILanguageModelOptions(
            reasoningEffort: 'high',
            reasoningSummary: 'concise',
          ).toMap(),
        },
      );
      await generateText(
        model: model,
        prompt: 'camel and pass-through',
        providerOptions: const {
          'openai': {
            'reasoningEffort': 'low',
            'reasoningSummary': 'detailed',
            'user': 'verify-user',
          },
        },
      );
      await generateText(
        model: model,
        prompt: 'standard',
        reasoning: LanguageModelV4Reasoning.medium,
      );
      final bodies = [for (final r in server.requests) r.jsonObject];
      ctx.observe('bodies', [
        for (final b in bodies)
          {
            'reasoning_effort': b['reasoning_effort'],
            'reasoning_summary': b['reasoning_summary'],
            'user': b['user'],
          },
      ]);
      ctx.expectEquals(bodies[0]['reasoning_effort'], 'high', 'typed effort');
      ctx.expectEquals(
        bodies[0]['reasoning_summary'],
        'concise',
        'typed summary',
      );
      ctx.expectEquals(bodies[1]['reasoning_effort'], 'low', 'camelCase');
      ctx.expectEquals(bodies[1]['reasoning_summary'], 'detailed', 'summary');
      ctx.expectEquals(bodies[1]['user'], 'verify-user', 'pass-through key');
      ctx.expect(
        !bodies[1].containsKey('reasoningEffort'),
        'camelCase key must be renamed, not forwarded',
      );
      ctx.expectEquals(
        bodies[2]['reasoning_effort'],
        'medium',
        'standard reasoning enum',
      );
    },
  ),
  Check(
    id: 'chat-gpt6-warning',
    feature: 'chat-gpt6-warning',
    description:
        'A gpt-6 model id on Chat Completions adds a compatibility warning '
        'that points to openai.responses.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: 'ok')),
      );
      final result = await generateText(
        model: _provider(ctx, server)('gpt-6-luna'),
        prompt: 'hi',
      );
      final warnings = result.warnings
          .whereType<LanguageModelV4CompatibilityWarning>()
          .toList();
      ctx.observe('warnings', [
        for (final w in warnings) {'feature': w.feature, 'details': w.details},
      ]);
      ctx.expectEquals(warnings.length, 1, 'compatibility warnings');
      ctx.expectEquals(warnings.single.feature, 'chat-completions', 'feature');
      ctx.expect(
        '${warnings.single.details}'.contains('responses'),
        'warning does not point to responses',
      );
      ctx.expectEquals(
        ctx.singleRequest(server, '/v1/chat/completions').jsonObject['model'],
        'gpt-6-luna',
        'request still sent',
      );
    },
  ),

  // --------------------------------------------------------------- responses
  Check(
    id: 'responses-generate',
    feature: 'responses-generate',
    description:
        'provider.responses sends POST /responses with model, input, '
        'instructions and max_output_tokens, and maps text, usage and finish.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _response([_message('Hello from Responses.')]),
        ),
      );
      final result = await generateText(
        model: _provider(ctx, server).responses('gpt-4.1-mini'),
        system: 'Be brief.',
        prompt: 'Say hello.',
        maxOutputTokens: 32,
        temperature: 0.2,
      );
      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      ctx.observe('finishReason', '${result.finishReason}');
      final request = ctx.singleRequest(
        server,
        '/v1/responses',
        method: 'POST',
      );
      final body = request.jsonObject;
      ctx.expectEquals(
        request.headers['authorization'],
        'Bearer verify-key',
        'auth header',
      );
      ctx.expectEquals(body['model'], 'gpt-4.1-mini', 'model');
      ctx.expectEquals(body['instructions'], 'Be brief.', 'instructions');
      ctx.expectEquals(body['max_output_tokens'], 32, 'max_output_tokens');
      ctx.expectEquals(body['temperature'], 0.2, 'temperature');
      final input = (body['input'] as List).single as Map;
      ctx.expectEquals(input['role'], 'user', 'input role');
      ctx.expectEquals(
        ((input['content'] as List).single as Map)['text'],
        'Say hello.',
        'input text',
      );
      ctx.expect(body['stream'] != true, 'non-streaming call sent stream');
      ctx.expectEquals(result.text, 'Hello from Responses.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 12, 'input tokens');
      ctx.expectEquals(result.usage?.inputTokens.cacheRead, 4, 'cached');
      ctx.expectEquals(result.usage?.outputTokens.total, 8, 'output tokens');
      ctx.expectEquals(result.usage?.outputTokens.reasoning, 3, 'reasoning');
      ctx.expect(
        _stringOf(result.finishReason).contains('stop'),
        'finish reason is not stop',
      );
    },
  ),
  Check(
    id: 'responses-stream',
    feature: 'responses-stream',
    description:
        'Responses SSE events become ordered text deltas, then the terminal '
        'response.completed supplies usage and the finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          SseEvent({
            'type': 'response.created',
            'response': {'id': 'resp_verify', 'model': 'gpt-4.1-mini'},
          }, event: 'response.created'),
          SseEvent({
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': {
              'type': 'message',
              'id': 'msg_verify',
              'role': 'assistant',
              'content': <Object>[],
            },
          }, event: 'response.output_item.added'),
          for (final piece in ['One, ', 'two, ', 'three.'])
            SseEvent({
              'type': 'response.output_text.delta',
              'item_id': 'msg_verify',
              'output_index': 0,
              'content_index': 0,
              'delta': piece,
            }, event: 'response.output_text.delta'),
          SseEvent({
            'type': 'response.output_item.done',
            'output_index': 0,
            'item': _message('One, two, three.'),
          }, event: 'response.output_item.done'),
          SseEvent({
            'type': 'response.completed',
            'response': _response([_message('One, two, three.')]),
          }, event: 'response.completed'),
        ]),
      );
      final result = await streamText(
        model: _provider(ctx, server).responses('gpt-4.1-mini'),
        prompt: 'Count to three.',
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      final finish = await result.finishReason;
      ctx.observe('deltas', deltas);
      ctx.observe('usage', usage);
      ctx.observe('finishReason', '$finish');
      final body = ctx.singleRequest(server, '/v1/responses').jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');
      ctx.expectEquals(deltas, ['One, ', 'two, ', 'three.'], 'deltas');
      ctx.expectEquals(usage?.inputTokens.total, 12, 'input tokens');
      ctx.expectEquals(usage?.outputTokens.total, 8, 'output tokens');
      ctx.expect(_stringOf(finish).contains('stop'), 'finish is not stop');
    },
  ),
  Check(
    id: 'responses-tool-loop',
    feature: 'responses-tools',
    description:
        'A function_call output item runs the tool, and the next request '
        'carries the function_call and its function_call_output by call_id.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _response([
              _functionCall('call_verify_1', 'getWeather', '{"city":"Paris"}'),
            ]),
          );
        }
        return FixtureResponse.json(_response([_message('Sunny in Paris.')]));
      });
      var executions = 0;
      final result = await generateText(
        model: _provider(ctx, server).responses('gpt-4.1-mini'),
        prompt: 'Weather in Paris?',
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(() => executions++)},
      );
      ctx.observe('text', result.text);
      ctx.observe('steps', result.steps.length);
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, '/v1/responses');
      ctx.expectEquals(requests.length, 2, 'request count');
      final firstTools = requests[0].jsonObject['tools'] as List;
      final tool0 = firstTools.single as Map;
      ctx.expectEquals(tool0['type'], 'function', 'tool type');
      ctx.expectEquals(tool0['name'], 'getWeather', 'tool name');
      ctx.expect(tool0['parameters'] is Map, 'tool parameters missing');
      final input = (requests[1].jsonObject['input'] as List).cast<Map>();
      final call = input.firstWhere((i) => i['type'] == 'function_call');
      final output = input.firstWhere(
        (i) => i['type'] == 'function_call_output',
      );
      ctx.expectEquals(call['call_id'], 'call_verify_1', 'call id');
      ctx.expectEquals(output['call_id'], 'call_verify_1', 'output call id');
      ctx.expect(
        '${output['output']}'.contains('Sunny, 18C in Paris'),
        'tool result missing: ${output['output']}',
      );
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(result.text, 'Sunny in Paris.', 'final text');
    },
  ),
  Check(
    id: 'responses-stream-tool-call',
    feature: 'responses-tools',
    description:
        'A streamed function call emits tool-input start/delta/end and one '
        'tool call, and the finish reason is tool-calls.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          SseEvent({
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': {
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_stream_1',
              'name': 'getWeather',
              'arguments': '',
            },
          }),
          SseEvent({
            'type': 'response.function_call_arguments.delta',
            'item_id': 'fc_1',
            'output_index': 0,
            'delta': '{"city":',
          }),
          SseEvent({
            'type': 'response.function_call_arguments.delta',
            'item_id': 'fc_1',
            'output_index': 0,
            'delta': '"Rome"}',
          }),
          SseEvent({
            'type': 'response.function_call_arguments.done',
            'item_id': 'fc_1',
            'output_index': 0,
            'arguments': '{"city":"Rome"}',
          }),
          SseEvent({
            'type': 'response.output_item.done',
            'output_index': 0,
            'item': _functionCall(
              'call_stream_1',
              'getWeather',
              '{"city":"Rome"}',
            )..['id'] = 'fc_1',
          }),
          SseEvent({
            'type': 'response.completed',
            'response': _response([
              _functionCall('call_stream_1', 'getWeather', '{"city":"Rome"}')
                ..['id'] = 'fc_1',
            ]),
          }),
        ]),
      );
      final model = _provider(ctx, server).responses('gpt-4.1-mini');
      final stream = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: const LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'Weather in Rome?')],
              ),
            ],
          ),
        ),
      );
      final parts = await stream.stream.toList();
      final kinds = [for (final p in parts) p.runtimeType.toString()];
      ctx.observe('partKinds', kinds);
      final calls = parts.whereType<StreamPartToolCall>().toList();
      final deltas = parts
          .whereType<StreamPartToolInputDelta>()
          .map((p) => p.delta)
          .join();
      final finish = parts.whereType<StreamPartFinish>().single;
      ctx.observe('toolInput', deltas);
      ctx.observe('finishReason', '${finish.finishReason}');
      ctx.expectEquals(deltas, '{"city":"Rome"}', 'streamed arguments');
      ctx.expectEquals(calls.length, 1, 'tool calls');
      ctx.expectEquals(calls.single.toolCall.toolCallId, 'call_stream_1', 'id');
      ctx.expectEquals(calls.single.toolCall.toolName, 'getWeather', 'name');
      ctx.expectEquals(calls.single.toolCall.input, {'city': 'Rome'}, 'input');
      ctx.expectEquals(
        finish.finishReason,
        LanguageModelV4FinishReason.toolCalls,
        'finish reason',
      );
      ctx.expect(
        ctx.singleRequest(server, '/v1/responses').jsonObject['stream'] == true,
        'stream flag not sent',
      );
    },
  ),
  Check(
    id: 'responses-structured',
    feature: 'responses-structured',
    description:
        'Output.object sends text.format json_schema (strict) and parses '
        'the JSON text of the reply.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _response([_message('{"capital":"Paris","country":"France"}')]),
        ),
      );
      final result = await generateText<Map<String, dynamic>>(
        model: _provider(ctx, server).responses('gpt-4.1-mini'),
        prompt: 'Capital of France.',
        output: Output.object(schema: _capitalSchema()),
      );
      ctx.observe('output', result.output);
      final body = ctx.singleRequest(server, '/v1/responses').jsonObject;
      final format = (body['text'] as Map)['format'] as Map;
      ctx.observe('format', format);
      ctx.expectEquals(format['type'], 'json_schema', 'format type');
      ctx.expectEquals(format['strict'], true, 'strict');
      ctx.expect(format['schema'] is Map, 'schema missing');
      ctx.expectEquals(result.output, {
        'capital': 'Paris',
        'country': 'France',
      }, 'output');
    },
  ),
  Check(
    id: 'responses-reasoning',
    feature: 'responses-reasoning',
    description:
        'reasoning effort and summary go into the reasoning object, and a '
        'reasoning output item surfaces as reasoning text with its tokens.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _response([
            {
              'type': 'reasoning',
              'id': 'rs_verify',
              'summary': [
                {'type': 'summary_text', 'text': 'Weighed two options.'},
              ],
            },
            _message('Answer: 4.'),
          ]),
        ),
      );
      final result = await generateText(
        model: _provider(ctx, server).responses('o4-mini'),
        prompt: '2+2?',
        reasoning: LanguageModelV4Reasoning.low,
        providerOptions: {
          'openai': const OpenAILanguageModelOptions(
            reasoningEffort: 'high',
            reasoningSummary: 'detailed',
          ).toMap(),
        },
      );
      ctx.observe('reasoningText', result.reasoningText);
      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      final body = ctx.singleRequest(server, '/v1/responses').jsonObject;
      ctx.expectEquals(body['reasoning'], {
        'effort': 'high',
        'summary': 'detailed',
      }, 'reasoning object');
      ctx.expect(
        !body.containsKey('reasoning_effort'),
        'reasoning_effort must be folded into reasoning',
      );
      ctx.expectEquals(
        result.reasoningText,
        'Weighed two options.',
        'reasoning text',
      );
      ctx.expectEquals(result.text, 'Answer: 4.', 'text');
      ctx.expectEquals(result.usage?.outputTokens.reasoning, 3, 'tokens');
    },
  ),
  Check(
    id: 'responses-hosted-tools',
    feature: 'responses-hosted-tools',
    description:
        'OpenAIWebSearchTool, OpenAIFileSearchTool, OpenAICodeInterpreterTool, '
        'OpenAIImageGenerationTool and OpenAIMcpTool serialize as typed tools; '
        'a web_search_call plus url_citation comes back as a provider-executed '
        'call, result and sources.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _response([
            {
              'type': 'web_search_call',
              'id': 'ws_verify',
              'status': 'completed',
              'action': {'type': 'search', 'query': 'dart sdk'},
            },
            _message(
              'Dart is a language.',
              annotations: [
                {
                  'type': 'url_citation',
                  'url': 'https://dart.dev',
                  'title': 'Dart',
                  'start_index': 0,
                  'end_index': 4,
                },
              ],
            ),
          ]),
        ),
      );
      final result = await generateText(
        model: _provider(ctx, server).responses('gpt-4.1-mini'),
        prompt: 'What is Dart?',
        providerDefinedTools: [
          OpenAIWebSearchTool(userLocation: 'Paris', searchContextSize: 'low'),
          OpenAIFileSearchTool(
            vectorStoreIds: const ['vs_verify'],
            maxNumResults: 3,
          ),
          OpenAICodeInterpreterTool(container: const {'type': 'auto'}),
          OpenAIImageGenerationTool(args: const {'size': '1024x1024'}),
          OpenAIMcpTool(
            serverLabel: 'docs',
            serverUrl: 'https://mcp.example.com/sse',
            allowedTools: const ['search'],
            requireApproval: 'never',
          ),
        ],
      );
      final tools =
          (ctx.singleRequest(server, '/v1/responses').jsonObject['tools']
                  as List)
              .cast<Map>();
      ctx.observe('tools', tools);
      ctx.expectEquals(tools.map((t) => t['type']).toList(), [
        'web_search_preview',
        'file_search',
        'code_interpreter',
        'image_generation',
        'mcp',
      ], 'tool types');
      ctx.expectEquals(tools[0]['search_context_size'], 'low', 'context size');
      ctx.expectEquals(
        (tools[0]['user_location'] as Map)['city'],
        'Paris',
        'user location',
      );
      ctx.expectEquals(tools[1]['vector_store_ids'], ['vs_verify'], 'stores');
      ctx.expectEquals(tools[1]['max_num_results'], 3, 'max results');
      ctx.expectEquals(tools[2]['container'], {'type': 'auto'}, 'container');
      ctx.expectEquals(tools[3]['size'], '1024x1024', 'image args');
      ctx.expectEquals(tools[4]['server_label'], 'docs', 'mcp label');
      ctx.expectEquals(
        tools[4]['server_url'],
        'https://mcp.example.com/sse',
        'mcp url',
      );
      ctx.expectEquals(tools[4]['allowed_tools'], ['search'], 'allowed tools');
      ctx.expectEquals(tools[4]['require_approval'], 'never', 'approval');
      final calls = result.content
          .whereType<LanguageModelV4ToolCallPart>()
          .toList();
      ctx.observe('toolCalls', [
        for (final c in calls)
          {'name': c.toolName, 'providerExecuted': c.providerExecuted},
      ]);
      ctx.expectEquals(calls.length, 1, 'hosted tool calls');
      ctx.expectEquals(calls.single.toolName, 'web_search_preview', 'name');
      ctx.expect(
        calls.single.providerExecuted,
        'call must be provider executed',
      );
      ctx.expectEquals(
        result.content.whereType<LanguageModelV4ToolResultPart>().length,
        1,
        'hosted tool results',
      );
      ctx.expectEquals(result.sources.map((s) => s.url).toList(), [
        'https://dart.dev',
      ], 'sources');
      ctx.expectEquals(result.text, 'Dart is a language.', 'text');
    },
  ),
  Check(
    id: 'responses-previous-response',
    feature: 'responses-state',
    description:
        'previous_response_id and store pass through provider options to the '
        'request body, and the response id is reported back.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_response([_message('continued')])),
      );
      final result = await generateText(
        model: _provider(ctx, server).responses('gpt-4.1-mini'),
        prompt: 'Continue.',
        providerOptions: const {
          'openai': {'previous_response_id': 'resp_previous', 'store': true},
        },
      );
      final body = ctx.singleRequest(server, '/v1/responses').jsonObject;
      ctx.observe('responseId', result.response?.response?.id);
      ctx.expectEquals(body['previous_response_id'], 'resp_previous', 'prev');
      ctx.expectEquals(body['store'], true, 'store');
      ctx.expectEquals(result.response?.response?.id, 'resp_verify', 'id');
      ctx.expectEquals(result.text, 'continued', 'text');
    },
  ),
  Check(
    id: 'responses-errors',
    feature: 'responses-errors',
    description:
        'Responses maps an HTTP 401, a 429, a status=failed body and an SSE '
        'error event to typed AiApiCallError / stream errors.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final mode = request.jsonObject['input'].toString();
        if (mode.contains('unauthorized')) {
          return FixtureResponse.json(
            _error(
              'Incorrect API key provided.',
              'invalid_request_error',
              'invalid_api_key',
            ),
            status: 401,
          );
        }
        if (mode.contains('limited')) {
          return FixtureResponse.json(
            _error('Rate limit reached.', 'requests', 'rate_limit_exceeded'),
            status: 429,
          );
        }
        if (mode.contains('failed')) {
          return FixtureResponse.json({
            'id': 'resp_failed',
            'status': 'failed',
            'error': {'message': 'The model failed.', 'code': 'server_error'},
            'output': <Object>[],
          });
        }
        return FixtureResponse.sse([
          SseEvent({
            'type': 'error',
            'message': 'Stream broke.',
            'code': 'server_error',
          }),
        ]);
      });
      final model = _provider(ctx, server).responses('gpt-4.1-mini');
      Future<void> run(String word) async {
        await generateText(model: model, prompt: word, maxRetries: 0);
      }

      final unauthorized = await ctx.expectThrows<AiApiCallError>(
        () => run('unauthorized'),
        '401',
      );
      final limited = await _retryableFailure(ctx, () => run('limited'), '429');
      final failed = await ctx.expectThrows<AiApiCallError>(
        () => run('failed'),
        'status failed',
      );
      final stream = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: const LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'streamed')],
              ),
            ],
          ),
        ),
      );
      final parts = await stream.stream.toList();
      final streamError = parts.whereType<StreamPartError>().single.error;
      final finish = parts.whereType<StreamPartFinish>().single;
      ctx.observe('streamError', '$streamError');
      ctx.expectEquals(unauthorized.statusCode, 401, '401 status');
      ctx.expectEquals(unauthorized.code, 'invalid_api_key', '401 code');
      ctx.expect(!unauthorized.isRetryable, '401 must not be retryable');
      ctx.expectEquals(limited.statusCode, 429, '429 status');
      ctx.expect(limited.isRetryable, '429 must be retryable');
      ctx.expect(
        failed.message.contains('The model failed.'),
        'failed message: ${failed.message}',
      );
      ctx.expect(streamError is AiApiCallError, 'stream error type');
      ctx.expect(
        '$streamError'.contains('Stream broke.'),
        'stream error message',
      );
      ctx.expectEquals(
        finish.finishReason,
        LanguageModelV4FinishReason.error,
        'stream finish reason',
      );
    },
  ),
  Check(
    id: 'responses-abort',
    feature: 'responses-abort',
    description:
        'Cancelling the abortSignal during a slow Responses call stops the '
        'call with a cancellation error instead of waiting for the server.',
    run: (ctx) async {
      final server = await ctx.server((_) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return FixtureResponse.json(_response([_message('late')]));
      });
      final token = CancellationToken();
      final started = DateTime.now();
      Future<void>.delayed(const Duration(milliseconds: 200), token.cancel);
      Object? failure;
      try {
        await generateText(
          model: _provider(ctx, server).responses('gpt-4.1-mini'),
          prompt: 'slow',
          maxRetries: 0,
          abortSignal: token,
        );
      } catch (error) {
        failure = error;
      }
      final elapsed = DateTime.now().difference(started);
      ctx.observe('failure', failure == null ? null : '${failure.runtimeType}');
      ctx.observe('elapsedMs', elapsed.inMilliseconds);
      ctx.expect(failure != null, 'the call must fail after cancel');
      ctx.expect(
        elapsed < const Duration(seconds: 2),
        'cancel did not stop the call early: $elapsed',
      );
    },
  ),

  // ------------------------------------------------------------ other models
  Check(
    id: 'embeddings',
    feature: 'embeddings',
    description:
        'embed and embedMany send POST /embeddings with model and input, '
        'order vectors by index and report token usage.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final input = request.jsonObject['input'] as List;
        return FixtureResponse.json({
          'object': 'list',
          'model': 'text-embedding-3-small',
          'data': [
            for (var i = input.length - 1; i >= 0; i--)
              {
                'object': 'embedding',
                'index': i,
                'embedding': [i + 0.5, i + 1.5],
              },
          ],
          'usage': {'prompt_tokens': 5, 'total_tokens': 5},
        });
      });
      final model = _provider(ctx, server).embedding('text-embedding-3-small');
      final one = await embed(model: model, value: 'alpha');
      final many = await embedMany(model: model, values: ['a', 'b', 'c']);
      ctx.observe('single', one.embedding);
      ctx.observe('many', [for (final e in many.embeddings) e.embedding]);
      ctx.observe('usage', many.usage?.tokens);
      final requests = ctx.requestsTo(server, '/v1/embeddings', method: 'POST');
      ctx.expectEquals(requests.length, 2, 'embedding requests');
      ctx.expectEquals(
        requests[0].headers['authorization'],
        'Bearer verify-key',
        'auth',
      );
      ctx.expectEquals(
        requests[0].jsonObject['model'],
        'text-embedding-3-small',
        'model',
      );
      ctx.expectEquals(requests[0].jsonObject['input'], ['alpha'], 'input');
      ctx.expectEquals(requests[1].jsonObject['input'], [
        'a',
        'b',
        'c',
      ], 'many');
      ctx.expectEquals(one.embedding, [0.5, 1.5], 'single vector');
      ctx.expectEquals(
        [for (final e in many.embeddings) e.embedding],
        [
          [0.5, 1.5],
          [1.5, 2.5],
          [2.5, 3.5],
        ],
        'vectors restored to input order',
      );
      ctx.expectEquals(many.usage?.tokens, 5, 'usage tokens');
    },
  ),
  Check(
    id: 'image-generation',
    feature: 'images',
    description:
        'generateImage sends POST /images/generations with prompt, n, size '
        'and response_format b64_json (omitted for gpt-image-1) and decodes '
        'the bytes.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json({
          'created': 1767225600,
          'data': [
            {'b64_json': base64Encode(_png)},
          ],
        }),
      );
      final provider = _provider(ctx, server);
      final dalle = await generateImage(
        model: provider.image('dall-e-2'),
        prompt: 'A red square',
        n: 1,
        size: '256x256',
      );
      await generateImage(model: provider.image('gpt-image-1'), prompt: 'cat');
      final requests = ctx.requestsTo(server, '/v1/images/generations');
      final first = requests[0].jsonObject;
      ctx.observe('bytes', dalle.image.bytes.length);
      ctx.observe('mediaType', dalle.image.mediaType);
      ctx.expectEquals(requests.length, 2, 'requests');
      ctx.expectEquals(first['model'], 'dall-e-2', 'model');
      ctx.expectEquals(first['prompt'], 'A red square', 'prompt');
      ctx.expectEquals(first['n'], 1, 'n');
      ctx.expectEquals(first['size'], '256x256', 'size');
      ctx.expectEquals(first['response_format'], 'b64_json', 'format');
      ctx.expect(
        !requests[1].jsonObject.containsKey('response_format'),
        'gpt-image-1 must not receive response_format',
      );
      ctx.expectEquals(dalle.image.bytes, _png, 'decoded bytes');
      ctx.expectEquals(dalle.image.mediaType, 'image/png', 'media type');
      ctx.expectEquals(dalle.usage?.imagesGenerated, 1, 'images generated');
    },
  ),
  Check(
    id: 'speech',
    feature: 'speech',
    description:
        'generateSpeech sends POST /audio/speech with model, input, voice, '
        'format and speed, and returns the audio bytes with their media type.',
    run: (ctx) async {
      final audio = List<int>.generate(32, (i) => i);
      final server = await ctx.server(
        (_) => FixtureResponse.bytes(audio, contentType: 'audio/mpeg'),
      );
      final result = await generateSpeech(
        model: _provider(ctx, server).speech('tts-1'),
        text: 'The quick brown fox.',
        voice: 'alloy',
        format: 'mp3',
        speed: 1.25,
      );
      ctx.observe('bytes', result.audio.length);
      ctx.observe('mediaType', result.mediaType);
      final body = ctx.singleRequest(server, '/v1/audio/speech').jsonObject;
      ctx.expectEquals(body['model'], 'tts-1', 'model');
      ctx.expectEquals(body['input'], 'The quick brown fox.', 'input');
      ctx.expectEquals(body['voice'], 'alloy', 'voice');
      ctx.expectEquals(body['response_format'], 'mp3', 'format');
      ctx.expectEquals(body['speed'], 1.25, 'speed');
      ctx.expectEquals(result.audio, audio, 'audio bytes');
      ctx.expectEquals(result.mediaType, 'audio/mpeg', 'media type');
    },
  ),
  Check(
    id: 'transcription',
    feature: 'transcription',
    description:
        'transcribe sends a multipart POST /audio/transcriptions with the '
        'file, model, response_format, language and prompt, and returns text.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json({'text': 'The quick brown fox.'}),
      );
      final result = await transcribe(
        model: _provider(ctx, server).transcription('whisper-1'),
        audio: Uint8List.fromList(List<int>.generate(16, (i) => i + 65)),
        audioMediaType: 'audio/wav',
        language: 'en',
        prompt: 'fox',
      );
      final request = ctx.singleRequest(server, '/v1/audio/transcriptions');
      final text = request.bodyText;
      ctx.observe('text', result.text);
      ctx.observe('contentType', request.headers['content-type']);
      ctx.expect(
        '${request.headers['content-type']}'.startsWith('multipart/form-data'),
        'request is not multipart',
      );
      for (final (name, value) in const [
        ('model', 'whisper-1'),
        ('response_format', 'json'),
        ('language', 'en'),
        ('prompt', 'fox'),
      ]) {
        ctx.expect(
          RegExp('name="$name"\\r\\n\\r\\n$value\\r\\n').hasMatch(text),
          'multipart field $name=$value missing',
        );
      }
      ctx.expect(
        RegExp('name="file"; filename="audio\\.wav"').hasMatch(text),
        'file part with audio.wav missing',
      );
      ctx.expect(text.contains('audio/wav'), 'file content type missing');
      ctx.expectEquals(result.text, 'The quick brown fox.', 'transcript');
    },
  ),

  // ------------------------------------------------------------------- files
  Check(
    id: 'files-lifecycle',
    feature: 'files',
    description:
        'files() uploads multipart with purpose and expiry, retrieves '
        'metadata, streams the content and deletes, with a typed reference.',
    run: (ctx) async {
      Map<String, Object?> fileJson({String id = 'file-verify'}) => {
        'id': id,
        'object': 'file',
        'bytes': 5,
        'created_at': 1767225600,
        'expires_at': 1767312000,
        'filename': 'notes.txt',
        'purpose': 'user_data',
        'status': 'processed',
      };
      final server = await ctx.server((request) {
        if (request.method == 'POST' && request.path == '/v1/files') {
          return FixtureResponse.json(fileJson());
        }
        if (request.method == 'GET' && request.path.endsWith('/content')) {
          return FixtureResponse.bytes(
            utf8.encode('hello'),
            contentType: 'text/plain',
          );
        }
        if (request.method == 'GET') return FixtureResponse.json(fileJson());
        return FixtureResponse.json({
          'id': 'file-verify',
          'object': 'file',
          'deleted': true,
        });
      });
      final files = _provider(ctx, server).files();
      final uploaded = await files.upload(
        OpenAIFileUpload(
          filename: 'notes.txt',
          purpose: 'user_data',
          bytes: Uint8List.fromList(utf8.encode('hello')),
          mediaType: 'text/plain',
          expiresAfter: const OpenAIFileExpiry(seconds: 86400),
        ),
      );
      final retrieved = await files.retrieve(uploaded.id);
      final content = <int>[];
      await for (final chunk in await files.download(uploaded.id)) {
        content.addAll(chunk);
      }
      await files.delete(uploaded.id);
      ctx.observe('uploadedId', uploaded.id.id);
      ctx.observe('namespace', uploaded.id.namespace);
      ctx.observe('content', utf8.decode(content));
      final upload = ctx.requestsTo(server, '/v1/files', method: 'POST').single;
      final form = upload.bodyText;
      ctx.expectEquals(
        upload.headers['authorization'],
        'Bearer verify-key',
        'auth',
      );
      for (final (name, value) in const [
        ('purpose', 'user_data'),
        ('expires_after[anchor]', 'created_at'),
        ('expires_after[seconds]', '86400'),
      ]) {
        ctx.expect(
          form.contains('name="$name"\r\n\r\n$value\r\n'),
          'multipart field $name=$value missing',
        );
      }
      ctx.expect(
        form.contains('filename="notes.txt"') && form.contains('hello'),
        'file part missing',
      );
      ctx.expectEquals(uploaded.id.namespace, 'openai', 'reference namespace');
      ctx.expectEquals(uploaded.id.id, 'file-verify', 'file id');
      ctx.expectEquals(uploaded.bytes, 5, 'bytes');
      ctx.expectEquals(uploaded.purpose, 'user_data', 'purpose');
      ctx.expectEquals(uploaded.filename, 'notes.txt', 'filename');
      ctx.expect(uploaded.expiresAt != null, 'expiresAt missing');
      ctx.expectEquals(retrieved.id.id, 'file-verify', 'retrieved id');
      ctx.expectEquals(utf8.decode(content), 'hello', 'downloaded content');
      ctx.expectEquals(
        server.requests.map((r) => '${r.method} ${r.path}').toList(),
        [
          'POST /v1/files',
          'GET /v1/files/file-verify',
          'GET /v1/files/file-verify/content',
          'DELETE /v1/files/file-verify',
        ],
        'request sequence',
      );
    },
  ),
  Check(
    id: 'files-validation',
    feature: 'files',
    description:
        'Bad uploads and foreign references are rejected before any request: '
        'OpenAIFileException for empty names and bad expiry, ArgumentError '
        'for a non-openai reference.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json({'unexpected': true}),
      );
      final files = _provider(ctx, server).files();
      final emptyName = await ctx.expectThrows<OpenAIFileException>(
        () => files.upload(
          OpenAIFileUpload(
            filename: ' ',
            purpose: 'batch',
            bytes: Uint8List(1),
          ),
        ),
        'empty filename',
      );
      final badExpiry = await ctx.expectThrows<OpenAIFileException>(
        () => files.upload(
          OpenAIFileUpload(
            filename: 'a.txt',
            purpose: 'batch',
            bytes: Uint8List(1),
            expiresAfter: const OpenAIFileExpiry(seconds: 5000000),
          ),
        ),
        'bad expiry',
      );
      await ctx.expectThrows<ArgumentError>(
        () => files.retrieve(
          const DataContentProviderReference(namespace: 'other', id: 'x'),
        ),
        'foreign reference',
      );
      ctx.expect(
        emptyName.message.contains('filename'),
        'empty filename message: ${emptyName.message}',
      );
      ctx.expect(
        badExpiry.message.contains('2592000'),
        'expiry message: ${badExpiry.message}',
      );
      ctx.expectEquals(server.requests.length, 0, 'requests that were sent');
    },
  ),
  Check(
    id: 'files-timeout-abort',
    feature: 'request-scope',
    description:
        'A timeout raises OpenAIFileTimeoutException and a cancelled '
        'abortSignal raises AiOperationCancelledError, both well before the '
        'slow server answers.',
    run: (ctx) async {
      final server = await ctx.server((_) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        return FixtureResponse.json({
          'id': 'file-verify',
          'bytes': 1,
          'created_at': 1,
          'filename': 'a',
          'purpose': 'batch',
        });
      });
      final files = _provider(ctx, server).files();
      const ref = DataContentProviderReference(
        namespace: 'openai',
        id: 'file-verify',
      );
      final started = DateTime.now();
      await ctx.expectThrows<OpenAIFileTimeoutException>(
        () => files.retrieve(ref, timeout: const Duration(milliseconds: 150)),
        'timeout',
      );
      final token = CancellationToken();
      Future<void>.delayed(const Duration(milliseconds: 150), token.cancel);
      await ctx.expectThrows<AiOperationCancelledError>(
        () => files.retrieve(ref, abortSignal: token),
        'abort',
      );
      final elapsed = DateTime.now().difference(started);
      ctx.observe('elapsedMs', elapsed.inMilliseconds);
      ctx.expect(
        elapsed < const Duration(seconds: 2),
        'calls waited for the slow server: $elapsed',
      );
    },
  ),

  // ----------------------------------------------------------------- batches
  Check(
    id: 'batches-lifecycle',
    feature: 'batches',
    description:
        'batches() uploads a JSONL input file, creates the batch, then gets, '
        'lists (with paging) and cancels it; result lines parse into '
        'OpenAIBatchResult.',
    run: (ctx) async {
      Map<String, Object?> batchJson(String id, String status) => {
        'id': id,
        'object': 'batch',
        'status': status,
        'endpoint': '/v1/responses',
        'input_file_id': 'file-in',
        'output_file_id': status == 'completed' ? 'file-out' : null,
        'request_counts': {'total': 2, 'completed': 2, 'failed': 0},
      };
      final server = await ctx.server((request) {
        if (request.path == '/v1/files') {
          return FixtureResponse.json({
            'id': 'file-in',
            'bytes': 100,
            'created_at': 1767225600,
            'filename': 'batch.jsonl',
            'purpose': 'batch',
          });
        }
        if (request.method == 'POST' && request.path == '/v1/batches') {
          return FixtureResponse.json(batchJson('batch_1', 'validating'));
        }
        if (request.path == '/v1/batches/batch_1/cancel') {
          return FixtureResponse.json(batchJson('batch_1', 'cancelling'));
        }
        if (request.path == '/v1/batches/batch_1') {
          return FixtureResponse.json(batchJson('batch_1', 'completed'));
        }
        if (request.path == '/v1/batches') {
          return FixtureResponse.json({
            'object': 'list',
            'data': [
              batchJson('batch_1', 'completed'),
              batchJson('batch_2', 'in_progress'),
            ],
            'has_more': true,
            'last_id': 'batch_2',
          });
        }
        if (request.path == '/v1/files/file-out/content') {
          return FixtureResponse.text(
            '${jsonEncode({
              'id': 'batch_req_1',
              'custom_id': 'a',
              'response': {
                'status_code': 200,
                'request_id': 'req_1',
                'body': {'id': 'resp_a'},
              },
              'error': null,
            })}\n${jsonEncode({
              'id': 'batch_req_2',
              'custom_id': 'b',
              'response': null,
              'error': {'code': 'server_error', 'message': 'boom'},
            })}\n',
            contentType: 'application/jsonl',
          );
        }
        return FixtureResponse.json(
          _error('unexpected', 'x', 'y'),
          status: 404,
        );
      });
      final provider = _provider(ctx, server);
      final batches = provider.batches();
      final created = await batches.create(
        const [
          OpenAIBatchInput(
            customId: 'a',
            model: 'gpt-4.1-mini',
            input: 'hello',
            options: {'max_output_tokens': 16},
          ),
          OpenAIBatchInput(
            customId: 'b',
            model: 'gpt-4.1-mini',
            input: 'world',
          ),
        ],
        metadata: {'source': 'verify'},
      );
      final fetched = await batches.get('batch_1');
      final page = await batches.list(limit: 2, after: 'batch_0');
      final cancelled = await batches.cancel('batch_1');
      final results = <OpenAIBatchResult>[];
      final out = StringBuffer();
      await for (final chunk in await provider.files().download(
        fetched.outputFileId!,
      )) {
        out.write(utf8.decode(chunk));
      }
      for (final line in const LineSplitter().convert(out.toString())) {
        results.add(
          OpenAIBatchResult.fromJson(jsonDecode(line) as Map<String, dynamic>),
        );
      }
      ctx.observe('created', created.rawStatus);
      ctx.observe('page', [for (final b in page) b.id]);
      ctx.observe('results', [
        for (final r in results) {'id': r.customId, 'status': r.statusCode},
      ]);
      final upload = ctx.requestsTo(server, '/v1/files', method: 'POST').single;
      ctx.expect(
        upload.bodyText.contains('name="purpose"\r\n\r\nbatch\r\n'),
        'upload purpose is not batch',
      );
      final lines = const LineSplitter()
          .convert(
            upload.bodyText
                .split('\r\n')
                .where((l) => l.startsWith('{"custom_id"'))
                .join('\n'),
          )
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      ctx.expectEquals(lines.length, 2, 'JSONL rows');
      ctx.expectEquals(lines[0]['custom_id'], 'a', 'custom id');
      ctx.expectEquals(lines[0]['method'], 'POST', 'method');
      ctx.expectEquals(lines[0]['url'], '/v1/responses', 'url');
      ctx.expectEquals(lines[0]['body'], {
        'model': 'gpt-4.1-mini',
        'input': 'hello',
        'max_output_tokens': 16,
      }, 'row body');
      final create = ctx
          .requestsTo(server, '/v1/batches', method: 'POST')
          .single
          .jsonObject;
      ctx.expectEquals(create['input_file_id'], 'file-in', 'input file');
      ctx.expectEquals(create['endpoint'], '/v1/responses', 'endpoint');
      ctx.expectEquals(create['completion_window'], '24h', 'window');
      ctx.expectEquals(create['metadata'], {'source': 'verify'}, 'metadata');
      ctx.expectEquals(created.status, OpenAIBatchStatus.validating, 'status');
      ctx.expectEquals(created.inputFileId?.id, 'file-in', 'input ref');
      ctx.expectEquals(fetched.status, OpenAIBatchStatus.completed, 'get');
      ctx.expectEquals(fetched.outputFileId?.id, 'file-out', 'output ref');
      ctx.expectEquals(fetched.totalRequests, 2, 'total');
      final listRequest = ctx
          .requestsTo(server, '/v1/batches', method: 'GET')
          .single;
      ctx.expectEquals(listRequest.uri.queryParameters, {
        'limit': '2',
        'after': 'batch_0',
      }, 'list query');
      ctx.expectEquals(page.map((b) => b.id).toList(), [
        'batch_1',
        'batch_2',
      ], 'page items');
      ctx.expectEquals(page.hasMore, true, 'hasMore');
      ctx.expectEquals(page.lastId, 'batch_2', 'lastId');
      ctx.expectEquals(
        cancelled.status,
        OpenAIBatchStatus.cancelling,
        'cancel',
      );
      ctx.expectEquals(results.map((r) => r.customId).toList(), [
        'a',
        'b',
      ], 'ids');
      ctx.expectEquals(results[0].statusCode, 200, 'result status');
      ctx.expectEquals(results[0].requestId, 'req_1', 'request id');
      ctx.expectEquals(results[1].error?['code'], 'server_error', 'error');
    },
  ),
  Check(
    id: 'batches-validation',
    feature: 'batches',
    description:
        'Duplicate custom ids, an empty batch and an out-of-range list limit '
        'raise OpenAIBatchException before any request.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json({'unexpected': true}),
      );
      final batches = _provider(ctx, server).batches();
      final duplicate = await ctx.expectThrows<OpenAIBatchException>(
        () => batches.create(const [
          OpenAIBatchInput(customId: 'a', model: 'm', input: 'x'),
          OpenAIBatchInput(customId: 'a', model: 'm', input: 'y'),
        ]),
        'duplicate custom ids',
      );
      await ctx.expectThrows<OpenAIBatchException>(
        () => batches.create(const []),
        'empty batch',
      );
      await ctx.expectThrows<OpenAIBatchException>(
        () => batches.list(limit: 101),
        'limit over 100',
      );
      ctx.observe('duplicateMessage', duplicate.message);
      ctx.expectEquals(server.requests.length, 0, 'requests that were sent');
      ctx.expectEquals(
        OpenAIBatchStatus.parse('in_progress'),
        OpenAIBatchStatus.inProgress,
        'known status',
      );
      ctx.expectEquals(
        OpenAIBatchStatus.parse('brand_new'),
        OpenAIBatchStatus.unknown,
        'unknown status',
      );
    },
  ),

  // ------------------------------------------------------------------ errors
  Check(
    id: 'errors-chat',
    feature: 'errors',
    description:
        'Chat 401 and 429 JSON errors surface as AiApiCallError with status, '
        'code, type and provider message; 429 is retryable, 401 is not.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final limited = '${request.jsonObject['messages']}'.contains('limited');
        return limited
            ? FixtureResponse.json(
                _error(
                  'Rate limit reached.',
                  'requests',
                  'rate_limit_exceeded',
                ),
                status: 429,
                headers: {'retry-after': '1'},
              )
            : FixtureResponse.json(
                _error(
                  'Incorrect API key provided.',
                  'invalid_request_error',
                  'invalid_api_key',
                ),
                status: 401,
              );
      });
      final model = _provider(ctx, server)('gpt-4.1-mini');
      final unauthorized = await ctx.expectThrows<AiApiCallError>(
        () => generateText(model: model, prompt: 'hi', maxRetries: 0),
        '401',
      );
      final limited = await _retryableFailure(
        ctx,
        () => generateText(model: model, prompt: 'limited', maxRetries: 0),
        '429',
      );
      ctx.observe('401', {
        'status': unauthorized.statusCode,
        'code': unauthorized.code,
        'type': unauthorized.type,
        'retryable': unauthorized.isRetryable,
      });
      ctx.observe('429', {
        'status': limited.statusCode,
        'code': limited.code,
        'retryable': limited.isRetryable,
      });
      ctx.expectEquals(unauthorized.statusCode, 401, '401 status');
      ctx.expectEquals(unauthorized.code, 'invalid_api_key', '401 code');
      ctx.expectEquals(unauthorized.type, 'invalid_request_error', '401 type');
      ctx.expect(
        unauthorized.message.contains('Incorrect API key'),
        'provider message lost: ${unauthorized.message}',
      );
      ctx.expect(!unauthorized.isRetryable, '401 must not be retryable');
      ctx.expectEquals(limited.statusCode, 429, '429 status');
      ctx.expect(limited.isRetryable, '429 must be retryable');
    },
  ),
  Check(
    id: 'errors-media-endpoints',
    feature: 'errors',
    description:
        'Embeddings, image, speech, transcription, files and batches raise '
        'AiApiCallError with the provider message and status on non-2xx, and '
        'a 2xx with a malformed body is an invalid-response AiApiCallError.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.path == '/v1/embeddings' &&
            '${request.jsonObject['input']}'.contains('malformed')) {
          return FixtureResponse.json({
            'data': [
              {
                'index': 0,
                'embedding': ['not-a-number'],
              },
            ],
          });
        }
        return FixtureResponse.json(
          _error(
            'Bad request for ${request.path}.',
            'invalid_request_error',
            'bad_request',
          ),
          status: 400,
        );
      });
      final provider = _provider(ctx, server);
      final seen = <String, int?>{};
      Future<void> expectApiError(
        String name,
        Future<Object?> Function() call,
        String path,
      ) async {
        final error = await ctx.expectThrows<AiApiCallError>(
          () async => call(),
          name,
        );
        seen[name] = error.statusCode;
        ctx.expectEquals(error.statusCode, 400, '$name status');
        ctx.expect(
          error.message.contains(path),
          '$name message lost: ${error.message}',
        );
      }

      await expectApiError(
        'embeddings',
        () => provider
            .embedding('m')
            .doEmbed(const EmbeddingModelV2CallOptions(values: ['x'])),
        '/v1/embeddings',
      );
      await expectApiError(
        'image',
        () => provider
            .image('m')
            .doGenerate(const ImageModelV3CallOptions(prompt: 'x')),
        '/v1/images/generations',
      );
      await expectApiError(
        'speech',
        () => provider
            .speech('m')
            .doGenerate(const SpeechModelV1CallOptions(text: 'x')),
        '/v1/audio/speech',
      );
      await expectApiError(
        'transcription',
        () => provider
            .transcription('m')
            .doGenerate(TranscriptionModelV1CallOptions(audio: Uint8List(4))),
        '/v1/audio/transcriptions',
      );
      await expectApiError(
        'files',
        () => provider.files().retrieve(
          const DataContentProviderReference(namespace: 'openai', id: 'f1'),
        ),
        '/v1/files/f1',
      );
      await expectApiError(
        'batches',
        () => provider.batches().get('b1'),
        '/v1/batches/b1',
      );
      final malformed = await ctx.expectThrows<AiApiCallError>(
        () => provider
            .embedding('m')
            .doEmbed(const EmbeddingModelV2CallOptions(values: ['malformed'])),
        'malformed 2xx',
      );
      ctx.observe('statuses', seen);
      ctx.observe('malformed', malformed.message);
      ctx.expectEquals(malformed.statusCode, 200, 'malformed status');
      ctx.expect(
        malformed.message.contains('invalid 2xx response body'),
        'malformed message: ${malformed.message}',
      );
    },
  ),

  // -------------------------------------------------------------------- live
  Check(
    id: 'live-chat-generate',
    feature: 'chat-generate',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description: 'Real Chat Completions call returns non-empty text and usage.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      final result = await generateText(
        model: provider(_liveModel(ctx)),
        prompt: 'Reply with the single word: pong.',
        maxOutputTokens: 16,
      );
      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      ctx.expect(result.text.trim().isNotEmpty, 'empty text');
      ctx.expect(
        (result.usage?.outputTokens.total ?? 0) > 0,
        'no output tokens reported',
      );
      ctx.expectEquals(ctx.exchanges.single.status, 200, 'HTTP status');
    },
  ),
  Check(
    id: 'live-chat-stream',
    feature: 'chat-stream',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description:
        'Real Chat Completions stream yields several deltas and usage.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      final result = await streamText(
        model: provider(_liveModel(ctx)),
        prompt: 'Count from 1 to 5, separated by spaces.',
        maxOutputTokens: 32,
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      ctx.observe('deltas', deltas.length);
      ctx.observe('text', deltas.join());
      ctx.observe('usage', usage);
      ctx.expect(deltas.length >= 2, 'expected incremental deltas');
      ctx.expect(deltas.join().trim().isNotEmpty, 'empty streamed text');
      ctx.expect((usage?.outputTokens.total ?? 0) > 0, 'no usage in stream');
      ctx.expectEquals(ctx.exchanges.single.status, 200, 'HTTP status');
    },
  ),
  Check(
    id: 'live-responses-generate',
    feature: 'responses-generate',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description: 'Real Responses call returns text, usage and a response id.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      final result = await generateText(
        model: provider.responses(_liveModel(ctx)),
        prompt: 'Reply with the single word: pong.',
        maxOutputTokens: 32,
      );
      ctx.observe('text', result.text);
      ctx.observe('responseId', result.response?.response?.id);
      ctx.expect(result.text.trim().isNotEmpty, 'empty text');
      ctx.expect(
        '${result.response?.response?.id}'.startsWith('resp_'),
        'missing response id',
      );
      ctx.expect(
        (result.usage?.inputTokens.total ?? 0) > 0,
        'no input tokens reported',
      );
      ctx.expectEquals(ctx.exchanges.single.status, 200, 'HTTP status');
    },
  ),
  Check(
    id: 'live-responses-stream',
    feature: 'responses-stream',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description: 'Real Responses stream yields deltas and a stop finish.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      final result = await streamText(
        model: provider.responses(_liveModel(ctx)),
        prompt: 'Count from 1 to 5, separated by spaces.',
        maxOutputTokens: 48,
      );
      final deltas = await result.textStream.toList();
      final usage = await result.usage;
      final finish = await result.finishReason;
      ctx.observe('deltas', deltas.length);
      ctx.observe('text', deltas.join());
      ctx.observe('finishReason', '$finish');
      ctx.expect(deltas.length >= 2, 'expected incremental deltas');
      ctx.expect((usage?.outputTokens.total ?? 0) > 0, 'no usage in stream');
      ctx.expect(_stringOf(finish).contains('stop'), 'finish is not stop');
      ctx.expectEquals(ctx.exchanges.single.status, 200, 'HTTP status');
    },
  ),
  Check(
    id: 'live-structured-output',
    feature: 'responses-structured',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description:
        'Real Responses call with a JSON schema returns an object that has '
        'the schema keys.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      final result = await generateText<Map<String, dynamic>>(
        model: provider.responses(_liveModel(ctx)),
        prompt: 'What is the capital of France? Give capital and country.',
        output: Output.object(schema: _capitalSchema()),
        maxOutputTokens: 64,
      );
      ctx.observe('output', result.output);
      ctx.expect(
        result.output['capital'] is String &&
            '${result.output['capital']}'.isNotEmpty,
        'capital missing',
      );
      ctx.expect(result.output['country'] is String, 'country missing');
      final body = ctx.exchanges.single.requestBody as Map;
      ctx.expectEquals(
        ((body['text'] as Map)['format'] as Map)['type'],
        'json_schema',
        'request format',
      );
    },
  ),
  Check(
    id: 'live-tool-loop',
    feature: 'chat-tools',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description:
        'Real two-step tool loop: the model calls getWeather once, the result '
        'goes back, and the final answer is non-empty.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      var executions = 0;
      final result = await generateText(
        model: provider(_liveModel(ctx)),
        prompt:
            'Use the getWeather tool for Paris, then answer in one short sentence.',
        maxSteps: 3,
        maxOutputTokens: 64,
        tools: {'getWeather': _weatherTool(() => executions++)},
      );
      ctx.observe('text', result.text);
      ctx.observe('executions', executions);
      ctx.observe('steps', result.steps.length);
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expect(result.steps.length >= 2, 'expected at least two steps');
      ctx.expect(result.text.trim().isNotEmpty, 'empty final text');
      ctx.expectEquals(ctx.exchanges.length, 2, 'HTTP exchanges');
      for (final e in ctx.exchanges) {
        ctx.expectEquals(e.status, 200, 'HTTP status');
      }
    },
  ),
  Check(
    id: 'live-embeddings',
    feature: 'embeddings',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description: 'Real embeddings call returns one non-empty vector per input.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      final model = provider.embedding(
        ctx.env('OPENAI_VERIFY_EMBEDDING_MODEL', 'text-embedding-3-small'),
      );
      final result = await embedMany(model: model, values: ['cat', 'dog']);
      ctx.observe('count', result.embeddings.length);
      ctx.observe('dimensions', result.embeddings.first.embedding.length);
      ctx.observe('tokens', result.usage?.tokens);
      ctx.expectEquals(result.embeddings.length, 2, 'vectors');
      ctx.expect(
        result.embeddings.first.embedding.length > 100,
        'vector too short',
      );
      ctx.expectEquals(
        result.embeddings[1].embedding.length,
        result.embeddings[0].embedding.length,
        'equal dimensions',
      );
      ctx.expectEquals(ctx.exchanges.single.status, 200, 'HTTP status');
    },
  ),
  Check(
    id: 'live-speech-transcription',
    feature: 'speech',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    timeout: const Duration(seconds: 90),
    description:
        'tts-1 speaks a short phrase, whisper-1 transcribes the returned '
        'audio, and the transcript contains the key word.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      final speech = await generateSpeech(
        model: provider.speech(ctx.env('OPENAI_VERIFY_SPEECH_MODEL', 'tts-1')),
        text: 'The quick brown fox jumps.',
        voice: 'alloy',
        format: 'mp3',
      );
      ctx.observe('audioBytes', speech.audio.length);
      ctx.observe('mediaType', speech.mediaType);
      ctx.expect(speech.audio.length > 1000, 'audio too small');
      final transcript = await transcribe(
        model: provider.transcription(
          ctx.env('OPENAI_VERIFY_TRANSCRIPTION_MODEL', 'whisper-1'),
        ),
        audio: speech.audio,
        audioMediaType: speech.mediaType,
        language: 'en',
      );
      ctx.observe('transcript', transcript.text);
      ctx.expect(
        transcript.text.toLowerCase().contains('fox'),
        'transcript lost the key word: ${transcript.text}',
      );
      ctx.expectEquals(ctx.exchanges.length, 2, 'HTTP exchanges');
      for (final e in ctx.exchanges) {
        ctx.expectEquals(e.status, 200, 'HTTP status');
      }
    },
  ),
  Check(
    id: 'live-image',
    feature: 'images',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    timeout: const Duration(seconds: 90),
    description:
        'Real image generation at the cheapest setting returns PNG bytes.',
    run: (ctx) async {
      final provider = _liveProvider(ctx);
      // gpt-image-1-mini at low quality is the cheapest current option. The
      // dall-e models are retired: the API rejects the response_format field
      // that the adapter adds for non-gpt-image models (see Gotchas).
      final modelId = ctx.env('OPENAI_VERIFY_IMAGE_MODEL', 'gpt-image-1-mini');
      final gptImage = modelId.startsWith('gpt-image');
      final result = await generateImage(
        model: provider.image(modelId),
        prompt: 'A plain red circle on white.',
        n: 1,
        size: ctx.env(
          'OPENAI_VERIFY_IMAGE_SIZE',
          gptImage ? '1024x1024' : '256x256',
        ),
        providerOptions: gptImage
            ? {
                'openai': {'quality': 'low'},
              }
            : null,
      );
      ctx.observe('model', modelId);
      final bytes = result.image.bytes;
      ctx.observe('bytes', bytes.length);
      ctx.observe('mediaType', result.image.mediaType);
      ctx.expect(bytes.length > 1000, 'image too small');
      ctx.expectEquals(bytes.sublist(1, 4), [0x50, 0x4e, 0x47], 'PNG magic');
      ctx.expectEquals(ctx.exchanges.single.status, 200, 'HTTP status');
    },
  ),
  Check(
    id: 'live-invalid-key',
    feature: 'errors',
    mode: CheckMode.live,
    requiresEnv: const ['OPENAI_API_KEY'],
    description:
        'A fake API key against the real API raises a typed 401 '
        'AiApiCallError that is not retryable.',
    run: (ctx) async {
      final provider = _liveProvider(ctx, apiKey: 'sk-invalid-verify-key');
      final error = await ctx.expectThrows<AiApiCallError>(
        () => generateText(
          model: provider(_liveModel(ctx)),
          prompt: 'hi',
          maxOutputTokens: 16,
          maxRetries: 0,
        ),
        'generateText',
      );
      ctx.observe('statusCode', error.statusCode);
      ctx.observe('code', error.code);
      ctx.observe('message', error.message);
      ctx.expectEquals(error.statusCode, 401, 'statusCode');
      ctx.expect(error.message.isNotEmpty, 'empty provider message');
      ctx.expect(!error.isRetryable, '401 must not be retryable');
    },
  ),
]);
