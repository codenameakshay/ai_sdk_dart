// Verification checks for package:ai_sdk_google. See features/ai_sdk_google.md.
//
// Fixture checks answer in the Gemini API wire format: generateContent JSON,
// streamGenerateContent?alt=sse chunks (plain `data:` lines, no event names)
// and batchEmbedContents. There is no Google key, so there are no live checks.
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_google';
const _generate = '/v1beta/models/gemini-verify:generateContent';
const _stream = '/v1beta/models/gemini-verify:streamGenerateContent';

GoogleGenerativeAIProvider _provider(
  CheckContext ctx,
  FixtureServer server, {
  String apiKey = 'verify-key',
}) {
  final dio = Dio(BaseOptions(baseUrl: server.url('/v1beta')));
  ctx.onCleanup(() async => dio.close(force: true));
  return GoogleGenerativeAIProvider(apiKey: apiKey, client: dio);
}

LanguageModelV4 _model(
  CheckContext ctx,
  FixtureServer server, {
  String modelId = 'gemini-verify',
}) => _provider(ctx, server)(modelId);

Map<String, Object?> _candidate(
  List<Map<String, Object?>> parts, {
  String? finishReason = 'STOP',
  Map<String, Object?>? extra,
}) => {
  'content': {'role': 'model', 'parts': parts},
  'finishReason': ?finishReason,
  'index': 0,
  ...?extra,
};

Map<String, Object?> _response(
  List<Map<String, Object?>> parts, {
  String? finishReason = 'STOP',
  Map<String, Object?>? usage,
  Map<String, Object?>? candidateExtra,
}) => {
  'candidates': [
    _candidate(parts, finishReason: finishReason, extra: candidateExtra),
  ],
  'usageMetadata':
      usage ??
      {'promptTokenCount': 9, 'candidatesTokenCount': 4, 'totalTokenCount': 13},
  'modelVersion': 'gemini-verify',
  'responseId': 'resp-verify',
};

Map<String, Object?> _text(String text) => {'text': text};

Map<String, Object?> _call(
  String name,
  Map<String, Object?> args, {
  String? id,
}) => {
  'functionCall': {'id': ?id, 'name': name, 'args': args},
};

final _citySchema = Schema<Map<String, dynamic>>(
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
      inputSchema: _citySchema,
      execute: (input, _) async {
        onRun();
        return 'Sunny, 18C in ${input['city']}';
      },
    );

Map<String, Object?> _errorBody(int code, String status, String message) => {
  'error': {'code': code, 'message': message, 'status': status},
};

List<Map<dynamic, dynamic>> _contents(FixtureRequest request) =>
    (request.jsonObject['contents'] as List).cast<Map>();

Map<dynamic, dynamic> _generationConfig(FixtureRequest request) =>
    request.jsonObject['generationConfig'] as Map;

final checks = PackageChecks(_package, [
  Check(
    id: 'provider-key-url',
    feature: 'google-provider',
    description:
        'The API key travels as the ?key= query parameter, model ids get the '
        'models/ prefix once, custom headers pass through, and a missing key '
        'fails before any request.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_response([_text('ok')])),
      );
      await generateText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxOutputTokens: 16,
        headers: {'x-verify-trace': 'trace-1'},
      );
      await generateText(
        model: _model(ctx, server, modelId: 'models/gemini-verify'),
        prompt: 'hi',
        maxOutputTokens: 16,
      );
      final dio = Dio(BaseOptions(baseUrl: server.url('/v1beta')));
      ctx.onCleanup(() async => dio.close(force: true));
      var resolved = 0;
      await generateText(
        model: GoogleGenerativeAIProvider(
          credentialProvider: () async {
            resolved++;
            return 'lazy-key';
          },
          client: dio,
        )('gemini-verify'),
        prompt: 'hi',
        maxOutputTokens: 16,
      );
      final requests = ctx.requestsTo(server, _generate, method: 'POST');
      ctx.expectEquals(requests.length, 3, 'request count');
      ctx.expectEquals(
        requests[0].uri.queryParameters['key'],
        'verify-key',
        'key',
      );
      ctx.expectEquals(
        requests[0].headers['x-verify-trace'],
        'trace-1',
        'custom header',
      );
      ctx.expect(
        !requests[0].headers.containsKey('authorization'),
        'Gemini key must not be sent as Authorization',
      );
      ctx.expectEquals(
        requests[2].uri.queryParameters['key'],
        'lazy-key',
        'lazy',
      );
      ctx.expectEquals(resolved, 1, 'credentialProvider calls');
      final noKey = GoogleGenerativeAIProvider(apiKey: '', client: dio);
      final before = server.requests.length;
      await ctx.expectThrows<StateError>(
        () => generateText(model: noKey('gemini-verify'), prompt: 'hi'),
        'missing key',
      );
      ctx.expectEquals(
        server.requests.length,
        before,
        'no request without key',
      );
    },
  ),
  Check(
    id: 'provider-base-url-dispose',
    feature: 'google-provider',
    description:
        'baseUrl routes an owned client to a proxy path; dispose() leaves an '
        'injected client usable.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_response([_text('via proxy')])),
      );
      final owned = GoogleGenerativeAIProvider(
        apiKey: 'verify-key',
        baseUrl: server.url('/proxy/v1beta'),
      );
      final result = await generateText(
        model: owned('gemini-verify'),
        prompt: 'hi',
        maxOutputTokens: 16,
      );
      owned.dispose();
      ctx.singleRequest(
        server,
        '/proxy/v1beta/models/gemini-verify:generateContent',
        method: 'POST',
      );
      ctx.expectEquals(result.text, 'via proxy', 'text');
      final injected = Dio(BaseOptions(baseUrl: server.url('/v1beta')));
      ctx.onCleanup(() async => injected.close(force: true));
      GoogleGenerativeAIProvider(apiKey: 'k', client: injected).dispose();
      final after = await injected.get<Object?>('/still-open');
      ctx.expectEquals(after.statusCode, 200, 'injected client after dispose');
    },
  ),
  Check(
    id: 'generate-text',
    feature: 'google-generate',
    description:
        'generateText posts to :generateContent with systemInstruction, '
        'generationConfig and role-mapped contents, and returns text, usage '
        'and the finish reason.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_response([_text('Hello from Gemini.')])),
      );
      final result = await generateText(
        model: _model(ctx, server),
        system: 'Be brief.',
        maxOutputTokens: 64,
        temperature: 0.2,
        topP: 0.9,
        topK: 20,
        stopSequences: ['STOP'],
        messages: [
          const ModelMessage(role: ModelMessageRole.user, content: 'Hi.'),
          const ModelMessage(
            role: ModelMessageRole.assistant,
            content: 'Hello!',
          ),
          const ModelMessage(
            role: ModelMessageRole.user,
            content: 'Say hello.',
          ),
        ],
      );
      ctx.observe('text', result.text);
      ctx.observe('usage', result.usage);
      ctx.observe('finishReason', '${result.finishReason}');
      final request = ctx.singleRequest(server, _generate, method: 'POST');
      final body = request.jsonObject;
      ctx.expectEquals(body['systemInstruction'], {
        'parts': [
          {'text': 'Be brief.'},
        ],
      }, 'systemInstruction');
      final config = _generationConfig(request);
      ctx.expectEquals(config['maxOutputTokens'], 64, 'maxOutputTokens');
      ctx.expectEquals(config['temperature'], 0.2, 'temperature');
      ctx.expectEquals(config['topP'], 0.9, 'topP');
      ctx.expectEquals(config['topK'], 20, 'topK');
      ctx.expectEquals(config['stopSequences'], ['STOP'], 'stopSequences');
      ctx.expectEquals(_contents(request).map((c) => c['role']).toList(), [
        'user',
        'model',
        'user',
      ], 'content roles');
      ctx.expectEquals(_contents(request).last['parts'], [
        {'text': 'Say hello.'},
      ], 'last user parts');
      ctx.expectEquals(result.text, 'Hello from Gemini.', 'text');
      ctx.expectEquals(result.usage?.inputTokens.total, 9, 'input tokens');
      ctx.expectEquals(result.usage?.outputTokens.total, 4, 'output tokens');
      ctx.expectEquals(
        result.finishReason,
        LanguageModelV4FinishReason.stop,
        'finish reason',
      );
      ctx.expectEquals(result.rawFinishReason, 'STOP', 'raw finish reason');
    },
  ),
  Check(
    id: 'stream-text',
    feature: 'google-stream',
    description:
        'streamText posts to :streamGenerateContent?alt=sse and yields the '
        'text of each data chunk in order, with usage from the last chunk.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _response(
            [_text('One, ')],
            finishReason: null,
            usage: {
              'promptTokenCount': 5,
              'candidatesTokenCount': 1,
              'totalTokenCount': 6,
            },
          ),
          _response([_text('two, ')], finishReason: null),
          _response(
            [_text('three.')],
            usage: {
              'promptTokenCount': 5,
              'candidatesTokenCount': 3,
              'totalTokenCount': 8,
            },
          ),
        ]),
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
      final request = ctx.singleRequest(server, _stream, method: 'POST');
      ctx.expectEquals(request.uri.queryParameters['alt'], 'sse', 'alt');
      ctx.expectEquals(request.uri.queryParameters['key'], 'verify-key', 'key');
      ctx.expectEquals(
        _generationConfig(request)['maxOutputTokens'],
        64,
        'max',
      );
      ctx.expectEquals(deltas, ['One, ', 'two, ', 'three.'], 'deltas');
      ctx.expectEquals(usage?.inputTokens.total, 5, 'input tokens');
      ctx.expectEquals(usage?.outputTokens.total, 3, 'output tokens');
      ctx.expectEquals(finish, LanguageModelV4FinishReason.stop, 'finish');
    },
  ),
  Check(
    id: 'tool-loop',
    feature: 'google-tools',
    description:
        'functionDeclarations are sent; a functionCall part is executed and '
        'a functionResponse part goes back in a user turn after the model '
        'turn that holds the call.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _response([
              _call('getWeather', {'city': 'Paris'}),
            ]),
          );
        }
        return FixtureResponse.json(
          _response([_text('It is sunny in Paris.')]),
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
      ctx.observe('executions', executions);
      final requests = ctx.requestsTo(server, _generate);
      ctx.expectEquals(requests.length, 2, 'request count');
      final declarations =
          ((requests[0].jsonObject['tools'] as List).single
                  as Map)['functionDeclarations']
              as List;
      final declaration = declarations.single as Map;
      ctx.expectEquals(declaration['name'], 'getWeather', 'declaration name');
      ctx.expectEquals((declaration['parameters'] as Map)['required'], [
        'city',
      ], 'declaration parameters');
      final followUp = _contents(requests[1]);
      ctx.expectEquals(followUp.map((c) => c['role']).toList(), [
        'user',
        'model',
        'user',
      ], 'follow-up roles');
      final call =
          ((followUp[1]['parts'] as List).single as Map)['functionCall'] as Map;
      ctx.expectEquals(call['name'], 'getWeather', 'echoed call');
      ctx.expectEquals(call['args'], {'city': 'Paris'}, 'echoed args');
      final response =
          ((followUp[2]['parts'] as List).single as Map)['functionResponse']
              as Map;
      ctx.observe('functionResponse', response);
      ctx.expectEquals(response['name'], 'getWeather', 'response name');
      ctx.expect(
        '${response['response']}'.contains('Sunny, 18C in Paris'),
        'tool output missing: ${response['response']}',
      );
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(result.text, 'It is sunny in Paris.', 'final text');
    },
  ),
  Check(
    id: 'parallel-tool-calls',
    feature: 'google-tools',
    description:
        'Two functionCall parts in one candidate run both tools and both '
        'functionResponse parts return in one user turn, keeping call ids.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _response([
              _call('getWeather', {'city': 'Paris'}, id: 'call-a'),
              _call('getWeather', {'city': 'Rome'}, id: 'call-b'),
            ]),
          );
        }
        return FixtureResponse.json(_response([_text('Both are sunny.')]));
      });
      final cities = <String>[];
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather in Paris and Rome?',
        maxOutputTokens: 64,
        maxSteps: 3,
        tools: {
          'getWeather': tool<Map<String, dynamic>, String>(
            description: 'Get current weather for a city.',
            inputSchema: _citySchema,
            execute: (input, _) async {
              cities.add('${input['city']}');
              return 'Sunny in ${input['city']}';
            },
          ),
        },
      );
      ctx.observe('cities', cities);
      final followUp = _contents(ctx.requestsTo(server, _generate)[1]);
      final responses = [
        for (final p in followUp.last['parts'] as List)
          (p as Map)['functionResponse'] as Map,
      ];
      ctx.expectEquals(cities.toSet(), {'Paris', 'Rome'}, 'executed cities');
      ctx.expectEquals(responses.length, 2, 'functionResponse count');
      ctx.expectEquals(responses.map((r) => r['id']).toSet(), {
        'call-a',
        'call-b',
      }, 'response ids');
      ctx.expectEquals(result.text, 'Both are sunny.', 'final text');
    },
  ),
  Check(
    id: 'stream-tool-loop',
    feature: 'google-tools',
    description:
        'A functionCall in a streamed chunk runs the tool once and the '
        'follow-up streamed request carries the functionResponse.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.sse([
            _response([
              _call('getWeather', {'city': 'Lima'}),
            ]),
          ]);
        }
        return FixtureResponse.sse([
          _response([_text('Mild in Lima.')]),
        ]);
      });
      var executions = 0;
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Weather in Lima?',
        maxOutputTokens: 64,
        maxSteps: 3,
        tools: {'getWeather': _weatherTool(() => executions++)},
      );
      final text = (await result.textStream.toList()).join();
      final requests = ctx.requestsTo(server, _stream);
      ctx.expectEquals(requests.length, 2, 'request count');
      final response =
          ((_contents(requests[1]).last['parts'] as List).single
                  as Map)['functionResponse']
              as Map;
      ctx.expectEquals(response['name'], 'getWeather', 'response name');
      ctx.expectEquals(executions, 1, 'tool executions');
      ctx.expectEquals(text, 'Mild in Lima.', 'final text');
      ctx.observe('text', text);
    },
  ),
  Check(
    id: 'tool-choice',
    feature: 'google-tool-choice',
    description:
        'ToolChoice auto, required, none and specific map to '
        'functionCallingConfig AUTO, ANY, NONE and ANY with allowedFunctionNames.',
    run: (ctx) async {
      final server = await ctx.server(
        (request) => FixtureResponse.json(
          request.index == 1 || request.index == 3
              ? _response([
                  _call('getWeather', {'city': 'Rome'}),
                ])
              : _response([_text('ok')]),
        ),
      );
      for (final choice in <LanguageModelV4ToolChoice>[
        const ToolChoiceAuto(),
        const ToolChoiceRequired(),
        const ToolChoiceNone(),
        const ToolChoiceSpecific(toolName: 'getWeather'),
      ]) {
        await generateText(
          model: _model(ctx, server),
          prompt: 'weather?',
          maxOutputTokens: 16,
          toolChoice: choice,
          tools: {'getWeather': _weatherTool(() {})},
        );
      }
      final sent = [
        for (final r in ctx.requestsTo(server, _generate))
          (r.jsonObject['toolConfig'] as Map)['functionCallingConfig'],
      ];
      ctx.observe('functionCallingConfig', sent);
      ctx.expectEquals(sent, [
        {'mode': 'AUTO'},
        {'mode': 'ANY'},
        {'mode': 'NONE'},
        {
          'mode': 'ANY',
          'allowedFunctionNames': ['getWeather'],
        },
      ], 'functionCallingConfig values');
    },
  ),
  Check(
    id: 'structured-output',
    feature: 'google-structured',
    description:
        'Output.object sends responseMimeType application/json with '
        'responseJsonSchema and parses the JSON reply into the typed output.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _response([_text('{"capital":"Tokyo","currency":"JPY"}')]),
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
            },
            fromJson: (json) => json,
          ),
        ),
      );
      ctx.observe('output', result.output);
      final config = _generationConfig(ctx.singleRequest(server, _generate));
      ctx.expectEquals(config['responseMimeType'], 'application/json', 'mime');
      ctx.expectEquals(
        (config['responseJsonSchema'] as Map)['required'],
        ['capital', 'currency'],
        'responseJsonSchema.required',
      );
      ctx.expectEquals(result.output, {
        'capital': 'Tokyo',
        'currency': 'JPY',
      }, 'output');
    },
  ),
  Check(
    id: 'thinking-config',
    feature: 'google-thinking',
    description:
        'providerOptions thinkingConfig lands in generationConfig; thought '
        'parts become reasoning, thoughtsTokenCount is added to output usage, '
        'and thought signatures are replayed in a tool loop.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _response(
              [
                {'text': 'I should call the tool.', 'thought': true},
                {
                  ..._call('getWeather', {'city': 'Oslo'}),
                  'thoughtSignature': 'sig-google-1',
                },
              ],
              usage: {
                'promptTokenCount': 10,
                'candidatesTokenCount': 5,
                'thoughtsTokenCount': 20,
                'totalTokenCount': 35,
              },
            ),
          );
        }
        return FixtureResponse.json(_response([_text('Cold in Oslo.')]));
      });
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather in Oslo?',
        maxOutputTokens: 512,
        maxSteps: 3,
        providerOptions: {
          'google': {
            'thinkingConfig': {'includeThoughts': true, 'thinkingBudget': 1024},
          },
        },
        tools: {'getWeather': _weatherTool(() {})},
      );
      final requests = ctx.requestsTo(server, _generate);
      ctx.expectEquals(requests.length, 2, 'request count');
      for (final r in requests) {
        ctx.expectEquals(
          _generationConfig(r)['thinkingConfig'],
          {'includeThoughts': true, 'thinkingBudget': 1024},
          'thinkingConfig on request ${r.index}',
        );
        ctx.expect(
          !r.jsonObject.containsKey('thinkingConfig'),
          'thinkingConfig leaked to the top level',
        );
      }
      final firstStep = result.steps.first;
      ctx.observe('firstStepUsage', firstStep.usage);
      ctx.observe('firstStepReasoning', firstStep.reasoningText);
      ctx.expectEquals(
        firstStep.usage?.outputTokens.total,
        25,
        'candidates + thoughts',
      );
      ctx.expectEquals(
        firstStep.usage?.outputTokens.reasoning,
        20,
        'reasoning',
      );
      ctx.expectEquals(
        firstStep.reasoningText,
        'I should call the tool.',
        'reasoning text',
      );
      final modelParts = (_contents(requests[1])[1]['parts'] as List)
          .cast<Map>();
      ctx.observe('replayedModelParts', modelParts);
      final replayedCall = modelParts.firstWhere(
        (p) => p.containsKey('functionCall'),
      );
      ctx.expectEquals(
        replayedCall['thoughtSignature'],
        'sig-google-1',
        'replayed thoughtSignature',
      );
      ctx.expectEquals(result.text, 'Cold in Oslo.', 'final text');
    },
  ),
  Check(
    id: 'reasoning-levels',
    feature: 'google-thinking',
    description:
        'The portable reasoning level becomes thinkingBudget for Gemini 2.5, '
        'thinkingLevel for Gemini 3, and a zero budget for none.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_response([_text('ok')])),
      );
      Future<Object?> thinkingFor(
        String modelId,
        LanguageModelV4Reasoning reasoning,
      ) async {
        await generateText(
          model: _model(ctx, server, modelId: modelId),
          prompt: 'hi',
          maxOutputTokens: 1000,
          reasoning: reasoning,
        );
        return _generationConfig(server.requests.last)['thinkingConfig'];
      }

      final budgetHigh = await thinkingFor(
        'gemini-2.5-flash',
        LanguageModelV4Reasoning.high,
      );
      final budgetNone = await thinkingFor(
        'gemini-2.5-flash',
        LanguageModelV4Reasoning.none,
      );
      final levelMedium = await thinkingFor(
        'gemini-3-flash-preview',
        LanguageModelV4Reasoning.medium,
      );
      ctx.observe('levels', [budgetHigh, budgetNone, levelMedium]);
      ctx.expectEquals(budgetHigh, {'thinkingBudget': 600}, '2.5 high (60%)');
      ctx.expectEquals(budgetNone, {'thinkingBudget': 0}, '2.5 none');
      ctx.expectEquals(levelMedium, {'thinkingLevel': 'medium'}, '3 medium');
    },
  ),
  Check(
    id: 'stream-thinking',
    feature: 'google-thinking',
    description:
        'Streamed thought chunks become reasoning start/delta/end parts '
        'separate from the answer text.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.sse([
          _response([
            {'text': 'Thinking about ', 'thought': true},
          ], finishReason: null),
          _response([
            {'text': 'the answer.', 'thought': true},
          ], finishReason: null),
          _response([_text('42')]),
        ]),
      );
      final result = await streamText(
        model: _model(ctx, server),
        prompt: 'Meaning of life?',
        maxOutputTokens: 256,
        providerOptions: {
          'google': {
            'thinkingConfig': {'includeThoughts': true},
          },
        },
      );
      final parts = await result.providerStream.toList();
      final reasoning = parts
          .whereType<StreamPartReasoningDelta>()
          .map((p) => p.delta)
          .join();
      final text = parts
          .whereType<StreamPartTextDelta>()
          .map((p) => p.delta)
          .join();
      ctx.observe('reasoning', reasoning);
      ctx.observe('text', text);
      ctx.expectEquals(reasoning, 'Thinking about the answer.', 'reasoning');
      ctx.expectEquals(text, '42', 'answer text');
      ctx.expect(
        parts.whereType<StreamPartReasoningEnd>().length == 1,
        'expected one reasoning end part',
      );
    },
  ),
  Check(
    id: 'embeddings',
    feature: 'google-embeddings',
    description:
        'google.embedding(text-embedding-004) posts :batchEmbedContents with '
        'one request per value and returns the vectors for embed and embedMany.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        final inputs = (request.jsonObject['requests'] as List).length;
        return FixtureResponse.json({
          'embeddings': [
            for (var i = 0; i < inputs; i++)
              {
                'values': [0.1 * (i + 1), 0.2, 0.3],
              },
          ],
        });
      });
      final model = _provider(ctx, server).embedding('text-embedding-004');
      final one = await embed(model: model, value: 'hello');
      final many = await embedMany(model: model, values: ['a', 'b']);
      ctx.observe('embedding', one.embedding);
      ctx.observe('many', many.embeddings.map((e) => e.embedding).toList());
      const path = '/v1beta/models/text-embedding-004:batchEmbedContents';
      final requests = ctx.requestsTo(server, path, method: 'POST');
      ctx.expectEquals(requests.length, 2, 'request count');
      ctx.expectEquals(
        requests[0].uri.queryParameters['key'],
        'verify-key',
        'key',
      );
      ctx.expectEquals(requests[0].jsonObject['requests'], [
        {
          'model': 'models/text-embedding-004',
          'content': {
            'parts': [
              {'text': 'hello'},
            ],
          },
        },
      ], 'single request body');
      ctx.expectEquals(
        (requests[1].jsonObject['requests'] as List)
            .map((r) => ((r as Map)['content'] as Map)['parts'])
            .toList(),
        [
          [
            {'text': 'a'},
          ],
          [
            {'text': 'b'},
          ],
        ],
        'batch parts',
      );
      ctx.expectEquals(one.embedding, [0.1, 0.2, 0.3], 'vector');
      ctx.expectEquals(many.embeddings.length, 2, 'batch size');
      ctx.expectEquals(many.embeddings[1].embedding[0], 0.2, 'second vector');
      ctx.expectEquals(model.modelId, 'text-embedding-004', 'modelId');
    },
  ),
  Check(
    id: 'safety-settings-options',
    feature: 'google-options',
    description:
        'providerOptions google (safetySettings, cachedContent) are merged '
        'into the request body unchanged.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(_response([_text('ok')])),
      );
      final safety = [
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_ONLY_HIGH',
        },
      ];
      await generateText(
        model: _model(ctx, server),
        prompt: 'hi',
        maxOutputTokens: 16,
        providerOptions: {
          'google': {
            'safetySettings': safety,
            'cachedContent': 'cachedContents/verify-123',
          },
        },
      );
      final body = ctx.singleRequest(server, _generate).jsonObject;
      ctx.expectEquals(body['safetySettings'], safety, 'safetySettings');
      ctx.expectEquals(
        body['cachedContent'],
        'cachedContents/verify-123',
        'cachedContent',
      );
      ctx.expect(!body.containsKey('google'), 'provider options key leaked');
    },
  ),
  Check(
    id: 'safety-blocks',
    feature: 'google-options',
    description:
        'A SAFETY candidate and a candidate-less promptFeedback block both '
        'finish as content-filter results, and the block reason surfaces as a '
        'warning.',
    run: (ctx) async {
      final server = await ctx.server(
        (request) => FixtureResponse.json(
          request.index == 0
              ? _response([_text('')], finishReason: 'SAFETY')
              : {
                  'promptFeedback': {
                    'blockReason': 'PROHIBITED_CONTENT',
                    'safetyRatings': <Object>[],
                  },
                  'usageMetadata': {
                    'promptTokenCount': 4,
                    'totalTokenCount': 4,
                  },
                },
        ),
      );
      final candidate = await generateText(
        model: _model(ctx, server),
        prompt: 'x',
        maxOutputTokens: 16,
      );
      final prompt = await generateText(
        model: _model(ctx, server),
        prompt: 'x',
        maxOutputTokens: 16,
      );
      ctx.observe('candidate', '${candidate.finishReason}');
      ctx.observe('promptBlock', [
        '${prompt.finishReason}',
        prompt.rawFinishReason,
        prompt.warnings.map((w) => '$w').toList(),
      ]);
      ctx.expectEquals(
        candidate.finishReason,
        LanguageModelV4FinishReason.contentFilter,
        'SAFETY candidate',
      );
      ctx.expectEquals(
        prompt.finishReason,
        LanguageModelV4FinishReason.contentFilter,
        'prompt block',
      );
      ctx.expectEquals(prompt.rawFinishReason, 'PROHIBITED_CONTENT', 'raw');
      ctx.expect(prompt.warnings.isNotEmpty, 'block reason warning missing');
    },
  ),
  Check(
    id: 'multimodal-input-output',
    feature: 'google-multimodal',
    description:
        'Image and file parts become inlineData or fileData parts; an '
        'inlineData part in the reply comes back as a file.',
    run: (ctx) async {
      final server = await ctx.server(
        (_) => FixtureResponse.json(
          _response([
            _text('Here is the picture.'),
            {
              'inlineData': {'mimeType': 'image/png', 'data': 'iVBORw0KGgo='},
            },
          ]),
        ),
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
              ),
            ],
          ),
        ],
      );
      final parts =
          (_contents(ctx.singleRequest(server, _generate)).single['parts']
                  as List)
              .cast<Map>();
      ctx.observe('requestParts', parts);
      ctx.expectEquals(parts[0], {'text': 'Describe these.'}, 'text part');
      ctx.expectEquals(parts[1]['inlineData'], {
        'mimeType': 'image/png',
        'data': 'iVBORw0KGgo=',
      }, 'inline image');
      ctx.expectEquals(parts[2]['fileData'], {
        'mimeType': 'image/jpeg',
        'fileUri': 'https://example.com/cat.jpg',
      }, 'url image');
      ctx.expectEquals(parts[3]['inlineData'], {
        'mimeType': 'application/pdf',
        'data': 'JVBERi0xLjQ=',
      }, 'inline pdf');
      ctx.expectEquals(result.files.length, 1, 'returned file count');
      ctx.expectEquals(result.files.single.mediaType, 'image/png', 'file type');
      ctx.expectEquals(result.text, 'Here is the picture.', 'text');
    },
  ),
  Check(
    id: 'grounding-sources',
    feature: 'google-grounding',
    description:
        'A provider-defined google_search tool is sent as googleSearch next '
        'to functionDeclarations; groundingChunks become source parts, for '
        'generate and for stream.',
    run: (ctx) async {
      final grounding = {
        'groundingMetadata': {
          'webSearchQueries': ['dart language'],
          'groundingChunks': [
            {
              'web': {'uri': 'https://dart.dev', 'title': 'Dart'},
            },
          ],
        },
      };
      final server = await ctx.server((request) {
        if (request.path.endsWith(':streamGenerateContent')) {
          return FixtureResponse.sse([
            _response([
              _text('Dart is a language.'),
            ], candidateExtra: grounding),
          ]);
        }
        return FixtureResponse.json(
          _response([_text('Dart is a language.')], candidateExtra: grounding),
        );
      });
      const searchTool = LanguageModelV4ProviderDefinedTool(
        id: 'google.google_search',
        name: 'google_search',
        args: {},
      );
      final generated = await generateText(
        model: _model(ctx, server),
        prompt: 'What is Dart?',
        maxOutputTokens: 64,
        tools: {'getWeather': _weatherTool(() {})},
        providerDefinedTools: const [searchTool],
      );
      final streamed = await streamText(
        model: _model(ctx, server),
        prompt: 'What is Dart?',
        maxOutputTokens: 64,
        providerDefinedTools: const [searchTool],
      );
      await streamed.textStream.toList();
      final streamedSources = await streamed.sources;
      final tools =
          (ctx.singleRequest(server, _generate).jsonObject['tools'] as List)
              .cast<Map>();
      ctx.observe('tools', tools);
      ctx.expectEquals(tools.length, 2, 'tool entries');
      ctx.expect(
        tools.any((t) => t.containsKey('functionDeclarations')),
        'functionDeclarations entry missing',
      );
      ctx.expect(
        tools.any((t) => t.containsKey('googleSearch')),
        'googleSearch entry missing',
      );
      ctx.expectEquals(
        (ctx.singleRequest(server, _stream).jsonObject['tools'] as List).single,
        {'googleSearch': <String, Object?>{}},
        'streamed provider tool',
      );
      for (final (label, sources) in [
        ('generate', generated.sources),
        ('stream', streamedSources),
      ]) {
        ctx.observe('$label.sources', sources);
        ctx.expectEquals(sources.length, 1, '$label source count');
        ctx.expectEquals(sources.single.url, 'https://dart.dev', '$label url');
        ctx.expectEquals(sources.single.title, 'Dart', '$label title');
      }
    },
  ),
  Check(
    id: 'finish-reasons-usage',
    feature: 'google-finish-reasons',
    description:
        'STOP, MAX_TOKENS, SAFETY, RECITATION and OTHER map to stop, length, '
        'content-filter x2 and other; cached tokens split the input usage.',
    run: (ctx) async {
      const reasons = ['STOP', 'MAX_TOKENS', 'SAFETY', 'RECITATION', 'OTHER'];
      final server = await ctx.server(
        (request) => FixtureResponse.json(
          _response(
            [_text('x')],
            finishReason: reasons[request.index],
            usage: {
              'promptTokenCount': 100,
              'cachedContentTokenCount': 60,
              'candidatesTokenCount': 3,
              'totalTokenCount': 103,
            },
          ),
        ),
      );
      final mapping = <String, String>{};
      LanguageModelV4Usage? lastUsage;
      for (final reason in reasons) {
        final result = await generateText(
          model: _model(ctx, server),
          prompt: 'x',
          maxOutputTokens: 16,
        );
        lastUsage = result.usage;
        mapping[reason] = '${result.finishReason}';
        final expected = switch (reason) {
          'STOP' => LanguageModelV4FinishReason.stop,
          'MAX_TOKENS' => LanguageModelV4FinishReason.length,
          'SAFETY' || 'RECITATION' => LanguageModelV4FinishReason.contentFilter,
          _ => LanguageModelV4FinishReason.other,
        };
        ctx.expectEquals(result.finishReason, expected, 'finish for $reason');
        ctx.expectEquals(result.rawFinishReason, reason, 'raw for $reason');
      }
      ctx.observe('mapping', mapping);
      ctx.observe('usage', lastUsage);
      ctx.expectEquals(lastUsage?.inputTokens.total, 100, 'input total');
      ctx.expectEquals(lastUsage?.inputTokens.cacheRead, 60, 'cacheRead');
      ctx.expectEquals(lastUsage?.inputTokens.noCache, 40, 'noCache');
    },
  ),
  Check(
    id: 'api-errors',
    feature: 'google-errors',
    description:
        'Google error JSON (400, 403, 429) becomes a typed AiApiCallError '
        'with status code, google status as type and message; 429 is '
        'retryable and wrapped in AiRetryError, and a retry then succeeds.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        switch (request.index) {
          case 0:
            return FixtureResponse.json(
              _errorBody(400, 'INVALID_ARGUMENT', 'API key not valid.'),
              status: 400,
            );
          case 1:
            return FixtureResponse.json(
              _errorBody(403, 'PERMISSION_DENIED', 'Method not allowed.'),
              status: 403,
            );
          case 2:
          case 3:
            return FixtureResponse.json(
              _errorBody(429, 'RESOURCE_EXHAUSTED', 'Quota exceeded.'),
              status: 429,
            );
          default:
            return FixtureResponse.json(_response([_text('recovered')]));
        }
      });
      Future<T> fail<T extends Object>(String what, {int retries = 0}) =>
          ctx.expectThrows<T>(
            () => generateText(
              model: _model(ctx, server),
              prompt: 'hi',
              maxOutputTokens: 16,
              maxRetries: retries,
            ),
            what,
          );
      final invalid = await fail<AiApiCallError>('400');
      final denied = await fail<AiApiCallError>('403');
      final exhausted = await fail<AiRetryError>('429');
      final quota = exhausted.lastError as AiApiCallError;
      ctx.observe('400', [invalid.statusCode, invalid.type, invalid.message]);
      ctx.observe('429', [quota.statusCode, quota.type]);
      ctx.expectEquals(invalid.statusCode, 400, '400 status');
      ctx.expectEquals(invalid.type, 'INVALID_ARGUMENT', '400 type');
      ctx.expect(
        invalid.message.contains('API key not valid'),
        'provider message lost: ${invalid.message}',
      );
      ctx.expect(!invalid.isRetryable, '400 must not be retryable');
      ctx.expectEquals(denied.type, 'PERMISSION_DENIED', '403 type');
      ctx.expectEquals(quota.statusCode, 429, '429 status');
      ctx.expectEquals(quota.type, 'RESOURCE_EXHAUSTED', '429 type');
      ctx.expect(quota.isRetryable, '429 must be retryable');
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
    feature: 'google-errors',
    description:
        'A non-2xx response on the stream endpoint throws a typed '
        'AiApiCallError with the message from the drained body, and a stream '
        'that ends before finishReason surfaces a truncation error.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _errorBody(400, 'INVALID_ARGUMENT', 'Invalid JSON payload.'),
            status: 400,
          );
        }
        return FixtureResponse.sse([
          _response([_text('cut off')], finishReason: null),
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
      final rejected = await errorOf('rejected stream');
      final truncated = await errorOf('truncated stream');
      ctx.observe('rejected', [
        rejected.statusCode,
        rejected.type,
        rejected.message,
      ]);
      ctx.observe('truncated', truncated.message);
      ctx.expectEquals(rejected.statusCode, 400, 'status');
      ctx.expectEquals(rejected.type, 'INVALID_ARGUMENT', 'type');
      ctx.expect(
        rejected.message.contains('Invalid JSON payload'),
        'streamed error body not drained: ${rejected.message}',
      );
      ctx.expect(
        truncated.message.contains('ended before finishReason'),
        'expected truncation error, got ${truncated.message}',
      );
    },
  ),
]);
