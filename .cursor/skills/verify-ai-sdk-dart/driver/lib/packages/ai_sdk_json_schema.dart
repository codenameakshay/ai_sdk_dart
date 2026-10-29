// Verification checks for package:ai_sdk_json_schema.
// See features/ai_sdk_json_schema.md.
//
// The package turns a JSON Schema into a core `Schema` that validates before
// the decoder runs. Direct checks drive `validatedJsonSchema` and
// `JsonSchemaValidator`. Integration checks drive generateText, generateObject
// and streamObject against a fixture Chat Completions server so the invalid
// value arrives the way a real model would send it.
import 'dart:async';
import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_json_schema/ai_sdk_json_schema.dart';
import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart' show ToolResultOutputText;
import 'package:dio/dio.dart';

import '../harness.dart';

const _package = 'ai_sdk_json_schema';

const _weatherShape = <String, dynamic>{
  'type': 'object',
  'required': ['city', 'days', 'region'],
  'additionalProperties': false,
  'properties': {
    'city': {
      'type': 'string',
      'enum': ['Paris', 'London'],
    },
    'days': {
      'type': 'array',
      'items': {
        'type': 'object',
        'required': ['temperature'],
        'properties': {
          'temperature': {'type': 'number'},
        },
      },
    },
    'region': {
      'type': ['string', 'null'],
    },
  },
};

Schema<Map<String, dynamic>> _weatherSchema([Map<String, dynamic>? extra]) =>
    validatedJsonSchema<Map<String, dynamic>>(
      schema: {..._weatherShape, ...?extra},
      fromJson: (json) => json,
    );

Schema<Map<String, dynamic>> _citySchema() =>
    validatedJsonSchema<Map<String, dynamic>>(
      schema: {
        'type': 'object',
        'required': ['city'],
        'properties': {
          'city': {'type': 'string'},
        },
        'additionalProperties': false,
      },
      fromJson: (json) => json,
    );

OpenAICompatibleChatLanguageModel _model(
  CheckContext ctx,
  FixtureServer server,
) {
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

Map<String, Object?> _toolCall(String arguments) => {
  'id': 'call_verify_1',
  'type': 'function',
  'function': {'name': 'weather', 'arguments': arguments},
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

SchemaValidationException _invalid(
  Schema<Map<String, dynamic>> schema,
  Map<String, dynamic> value,
) {
  try {
    schema.fromJson(value);
  } on SchemaValidationException catch (error) {
    return error;
  }
  throw CheckFailure('value was accepted: ${jsonEncode(value)}');
}

final checks = PackageChecks(_package, [
  Check(
    id: 'accepts-valid-rejects-invalid',
    feature: 'js-validate',
    description:
        'validatedJsonSchema decodes a valid nested value and throws '
        'SchemaValidationException for wrong type, bad enum, missing '
        'required field and extra property.',
    run: (ctx) async {
      final schema = _weatherSchema();
      final valid = schema.fromJson({
        'city': 'Paris',
        'days': [
          {'temperature': 12.5},
        ],
        'region': null,
      });
      ctx.expectEquals(valid['city'], 'Paris', 'decoded city');
      // `format` is an annotation, not an assertion.
      final annotated = validatedJsonSchema<Map<String, dynamic>>(
        schema: {
          'type': 'object',
          'properties': {
            'email': {'type': 'string', 'format': 'email'},
          },
        },
        fromJson: (json) => json,
      );
      ctx.expectEquals(
        annotated.fromJson({'email': 'not-an-email'})['email'],
        'not-an-email',
        'format must not be asserted',
      );
      final invalid = <String, Map<String, dynamic>>{
        'scalar type': {'city': 7, 'days': [], 'region': null},
        'enum': {'city': 'Oslo', 'days': [], 'region': null},
        'array type': {'city': 'Paris', 'days': {}, 'region': null},
        'nested required': {
          'city': 'Paris',
          'days': [<String, dynamic>{}],
          'region': null,
        },
        'missing required': {'city': 'Paris', 'days': []},
        'additional property': {
          'city': 'Paris',
          'days': [],
          'region': null,
          'extra': true,
        },
      };
      for (final entry in invalid.entries) {
        final error = _invalid(schema, entry.value);
        ctx.expect(error.issues.isNotEmpty, '${entry.key}: no issues');
        ctx.observe('${entry.key}.issues', [
          for (final i in error.issues)
            {'path': i.path, 'schemaPath': i.schemaPath, 'message': i.message},
        ]);
      }
    },
  ),
  Check(
    id: 'issue-detail-without-values',
    feature: 'js-errors',
    description:
        'SchemaValidationException.issues carry the instance path, schema '
        'path and message, and toString() omits the rejected input value.',
    run: (ctx) async {
      final schema = _weatherSchema();
      const secret = 'sk-secret-city-value';
      final error = _invalid(schema, {
        'city': secret,
        'days': [
          {'temperature': 'hot'},
        ],
        'region': null,
      });
      final paths = error.issues.map((i) => i.path).toList();
      ctx.observe('paths', paths);
      ctx.observe(
        'schemaPaths',
        error.issues.map((i) => i.schemaPath).toList(),
      );
      ctx.expect(paths.contains('/city'), 'missing /city in $paths');
      ctx.expect(
        paths.contains('/days/0/temperature'),
        'missing /days/0/temperature in $paths',
      );
      ctx.expect(
        error.issues.every((i) => i.schemaPath != null && i.message.isNotEmpty),
        'an issue lacks a schema path or message',
      );
      ctx.expectEquals(
        error.toString(),
        'Schema validation failed (${error.issues.length} issues).',
        'toString',
      );
      ctx.expect(
        !error.toString().contains(secret),
        'toString leaks the rejected value',
      );
      final direct = JsonSchemaValidator(
        _weatherShape,
      ).validate({'city': 'Paris', 'days': [], 'region': null});
      ctx.expectEquals(direct.length, 0, 'valid value has no issues');
    },
  ),
  Check(
    id: 'dialects-and-refs',
    feature: 'js-dialects',
    description:
        'Draft 7 and 2020-12 (the default) validate, local \$ref resolves, '
        'and an unsupported dialect or an external \$ref fails at '
        'construction with no network access.',
    run: (ctx) async {
      for (final dialect in [
        'http://json-schema.org/draft-07/schema#',
        'https://json-schema.org/draft/2020-12/schema',
        null,
      ]) {
        final schema = _weatherSchema({r'$schema': ?dialect});
        schema.fromJson({'city': 'London', 'days': [], 'region': 'UK'});
        _invalid(schema, {'city': 'Oslo', 'days': [], 'region': null});
        ctx.observe('dialect.${dialect ?? 'default'}', 'validated');
      }
      final withRef = validatedJsonSchema<Map<String, dynamic>>(
        schema: {
          r'$defs': {
            'city': {'type': 'string'},
          },
          'properties': {
            'city': {r'$ref': r'#/$defs/city'},
          },
        },
        fromJson: (json) => json,
      );
      withRef.fromJson({'city': 'Paris'});
      final refError = _invalid(withRef, {'city': 7});
      ctx.observe('localRefIssue', refError.issues.first.message);
      final external = await ctx.expectThrows<UnsupportedError>(
        () async => validatedJsonSchema<Map<String, dynamic>>(
          schema: {r'$ref': 'https://fixture.invalid/schema.json'},
          fromJson: (json) => json,
        ),
        'external ref',
      );
      ctx.expect(
        '$external'.contains('External JSON Schema references are disabled'),
        'external ref message: $external',
      );
      final dialect = await ctx.expectThrows<UnsupportedError>(
        () async => validatedJsonSchema<Map<String, dynamic>>(
          schema: {r'$schema': 'https://example.test/future-schema'},
          fromJson: (json) => json,
        ),
        'unsupported dialect',
      );
      ctx.expect(
        '$dialect'.contains('Draft 7 and 2020-12'),
        'dialect message: $dialect',
      );
    },
  ),
  Check(
    id: 'json-bounds',
    feature: 'js-bounds',
    description:
        'maxDepth and maxNodes bound both the schema and the validated '
        'value; non-finite numbers and cyclic schemas are refused; non-'
        'positive limits throw ArgumentError.',
    run: (ctx) async {
      final schema = validatedJsonSchema<Map<String, dynamic>>(
        schema: {'type': 'object'},
        fromJson: (json) => json,
        maxDepth: 3,
        maxNodes: 50,
      );
      schema.fromJson({
        'a': {'b': 1},
      });
      final deep = _invalid(schema, {
        'a': {
          'b': {
            'c': {'d': 1},
          },
        },
      });
      final wide = _invalid(schema, {'list': List<int>.filled(60, 1)});
      final nan = _invalid(schema, {'x': double.nan});
      ctx.observe('deepIssue', deep.issues.single.message);
      ctx.observe('wideIssue', wide.issues.single.message);
      ctx.observe('nanIssue', nan.issues.single.message);
      for (final issue in [deep, wide, nan]) {
        ctx.expect(
          issue.issues.single.message.contains(
            'exceeds configured JSON limits',
          ),
          'unexpected issue: ${issue.issues.single.message}',
        );
      }
      await ctx.expectThrows<ArgumentError>(
        () async => validatedJsonSchema<Map<String, dynamic>>(
          schema: {'type': 'object'},
          fromJson: (json) => json,
          maxDepth: 0,
        ),
        'maxDepth 0',
      );
      await ctx.expectThrows<ArgumentError>(
        () async => validatedJsonSchema<Map<String, dynamic>>(
          schema: {'type': 'object'},
          fromJson: (json) => json,
          maxNodes: 0,
        ),
        'maxNodes 0',
      );
      final cyclic = <String, dynamic>{};
      cyclic['self'] = cyclic;
      await ctx.expectThrows<FormatException>(
        () async => validatedJsonSchema<Map<String, dynamic>>(
          schema: cyclic,
          fromJson: (json) => json,
        ),
        'cyclic schema',
      );
      await ctx.expectThrows<FormatException>(
        () async => validatedJsonSchema<Map<String, dynamic>>(
          schema: {
            'a': {
              'b': {
                'c': {'d': 1},
              },
            },
          },
          fromJson: (json) => json,
          maxDepth: 2,
        ),
        'schema deeper than maxDepth',
      );
    },
  ),
  Check(
    id: 'validate-before-decode-and-snapshot',
    feature: 'js-snapshot',
    description:
        'The decoder never runs for an invalid value, and the compiled '
        'schema and the provider-facing jsonSchema are frozen snapshots of '
        'the input map.',
    run: (ctx) async {
      var decoded = 0;
      final source = <String, dynamic>{
        'type': 'object',
        'required': ['city'],
        'properties': {
          'city': {'type': 'string'},
        },
      };
      final schema = validatedJsonSchema<Map<String, dynamic>>(
        schema: source,
        fromJson: (json) {
          decoded++;
          return json;
        },
      );
      (source['properties'] as Map)['city'] = {'type': 'number'};
      _invalid(schema, {});
      _invalid(schema, {'city': 7});
      ctx.expectEquals(decoded, 0, 'decoder calls for invalid values');
      schema.fromJson({'city': 'Paris'});
      ctx.expectEquals(decoded, 1, 'decoder calls for the valid value');
      ctx.expectEquals(
        schema.jsonSchema['properties'],
        {
          'city': {'type': 'string'},
        },
        'provider-facing schema ignores later source edits',
      );
      await ctx.expectThrows<UnsupportedError>(
        () async => (schema.jsonSchema['properties'] as Map)['city'] = {},
        'mutating jsonSchema',
      );
    },
  ),
  Check(
    id: 'tool-input-rejected',
    feature: 'js-tool-input',
    description:
        'A model tool call with arguments that break the schema never runs '
        'the tool; the error goes back to the model, and a valid call runs '
        'the tool once.',
    run: (ctx) async {
      final server = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _completion(
              finishReason: 'tool_calls',
              toolCalls: [_toolCall('{"unexpected":1}')],
            ),
          );
        }
        return FixtureResponse.json(_completion(content: 'I will retry.'));
      });
      var executions = 0;
      final tools = {
        'weather': tool<Map<String, dynamic>, String>(
          description: 'Weather for a city.',
          inputSchema: _citySchema(),
          execute: (input, _) async {
            executions++;
            return 'Sunny in ${input['city']}';
          },
        ),
      };
      final result = await generateText(
        model: _model(ctx, server),
        prompt: 'Weather?',
        tools: tools,
        maxSteps: 3,
        maxRetries: 0,
      );
      final toolResult = result.steps.first.toolResults.single;
      ctx.observe('executions', executions);
      ctx.observe('toolResultIsError', toolResult.isError);
      final output = toolResult.output;
      final outputText = output is ToolResultOutputText
          ? output.text
          : '$output';
      ctx.observe('toolResultOutput', outputText);
      ctx.expect(
        outputText.contains('Schema validation failed'),
        'tool result text: $outputText',
      );
      ctx.expectEquals(executions, 0, 'tool executions for invalid input');
      ctx.expect(toolResult.isError, 'tool result is not an error');
      final first = ctx.requestsTo(server, '/v1/chat/completions').first;
      final toolDef =
          ((first.jsonObject['tools'] as List).single as Map)['function']
              as Map;
      ctx.expectEquals(toolDef['parameters'], {
        'type': 'object',
        'required': ['city'],
        'properties': {
          'city': {'type': 'string'},
        },
        'additionalProperties': false,
      }, 'schema sent to the provider');
      final followUp =
          (ctx
                      .requestsTo(server, '/v1/chat/completions')[1]
                      .jsonObject['messages']
                  as List)
              .cast<Map>();
      final toolMessage = followUp.lastWhere((m) => m['role'] == 'tool');
      ctx.expectEquals(toolMessage['tool_call_id'], 'call_verify_1', 'id');
      ctx.observe('errorSentToModel', toolMessage['content']);
      ctx.expect(
        !'${toolMessage['content']}'.contains('Sunny'),
        'error message looks like a tool result',
      );
      ctx.expectEquals(result.text, 'I will retry.', 'text after the error');

      // A valid call on the same tool executes exactly once.
      final validServer = await ctx.server((request) {
        if (request.index == 0) {
          return FixtureResponse.json(
            _completion(
              finishReason: 'tool_calls',
              toolCalls: [_toolCall('{"city":"Paris"}')],
            ),
          );
        }
        return FixtureResponse.json(_completion(content: 'Sunny in Paris.'));
      });
      final ok = await generateText(
        model: _model(ctx, validServer),
        prompt: 'Weather?',
        tools: tools,
        maxSteps: 3,
        maxRetries: 0,
      );
      ctx.expectEquals(executions, 1, 'tool executions for valid input');
      ctx.expect(
        !ok.steps.first.toolResults.single.isError,
        'valid call failed',
      );
    },
  ),
  Check(
    id: 'generate-object-output',
    feature: 'js-structured',
    description:
        'generateObject sends the schema as response_format, returns a valid '
        'object, and wraps a schema violation in AiNoObjectGeneratedError '
        'whose cause is SchemaValidationException.',
    run: (ctx) async {
      final good = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: '{"city":"Paris"}')),
      );
      final result = await generateObject(
        model: _model(ctx, good),
        schema: _citySchema(),
        prompt: 'City?',
      );
      ctx.observe('object', result.object);
      final body = ctx.singleRequest(good, '/v1/chat/completions').jsonObject;
      final format = body['response_format'] as Map;
      ctx.expectEquals(format['type'], 'json_schema', 'response_format.type');
      ctx.expectEquals((format['json_schema'] as Map)['schema'], {
        'type': 'object',
        'required': ['city'],
        'properties': {
          'city': {'type': 'string'},
        },
        'additionalProperties': false,
      }, 'schema in response_format');
      ctx.expectEquals(result.object, {'city': 'Paris'}, 'valid object');

      final bad = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: '{"city":7}')),
      );
      final error = await ctx.expectThrows<AiNoObjectGeneratedError>(
        () => generateObject(
          model: _model(ctx, bad),
          schema: _citySchema(),
          prompt: 'City?',
        ),
        'invalid structured output',
      );
      final cause = error.cause;
      ctx.expect(
        cause is SchemaValidationException,
        'cause is ${cause.runtimeType}, not SchemaValidationException',
      );
      ctx.observe('causePaths', [
        for (final i in (cause as SchemaValidationException).issues) i.path,
      ]);
      ctx.expectEquals(
        [for (final i in cause.issues) i.path],
        ['/city'],
        'issue paths',
      );
    },
  ),
  Check(
    id: 'output-object-text',
    feature: 'js-structured',
    description:
        'generateText with Output.object and a validated schema returns the '
        'typed output and rejects a reply that breaks the schema.',
    run: (ctx) async {
      final good = await ctx.server(
        (_) => FixtureResponse.json(_completion(content: '{"city":"Rome"}')),
      );
      final result = await generateText<Map<String, dynamic>>(
        model: _model(ctx, good),
        prompt: 'City?',
        output: Output.object(schema: _citySchema()),
        maxRetries: 0,
      );
      ctx.expectEquals(result.output, {'city': 'Rome'}, 'output');
      final bad = await ctx.server(
        (_) => FixtureResponse.json(
          _completion(content: '{"city":"Rome","extra":1}'),
        ),
      );
      final error = await ctx.expectThrows<Object>(() async {
        final r = await generateText<Map<String, dynamic>>(
          model: _model(ctx, bad),
          prompt: 'City?',
          output: Output.object(schema: _citySchema()),
          maxRetries: 0,
        );
        // Output is parsed lazily in some versions; force it.
        r.output;
      }, 'additionalProperties violation');
      ctx.observe('errorType', '${error.runtimeType}');
      ctx.expect(
        error is AiNoObjectGeneratedError &&
            error.cause is SchemaValidationException,
        'expected AiNoObjectGeneratedError caused by SchemaValidationException, '
        'got ${error.runtimeType}: $error',
      );
    },
  ),
  Check(
    id: 'stream-object-final-validation',
    feature: 'js-stream-object',
    description:
        'streamObject emits unvalidated partial snapshots and validates only '
        'the final object, which fails with a SchemaValidationException '
        'cause when it breaks the schema.',
    run: (ctx) async {
      Future<FixtureServer> serve(List<String> pieces) => ctx.server(
        (_) => FixtureResponse.sse([
          _chunk({'role': 'assistant', 'content': ''}),
          for (final piece in pieces) _chunk({'content': piece}),
          _chunk({}, finish: 'stop'),
        ], done: true),
      );
      final good = await serve(['{"city":', '"Oslo"}']);
      final result = await streamObject(
        model: _model(ctx, good),
        schema: _citySchema(),
        prompt: 'City?',
      );
      final partials = await result.partialObjectStream.toList();
      final object = await result.object;
      ctx.observe('partials', partials);
      ctx.observe('object', object);
      ctx.expectEquals(object, {'city': 'Oslo'}, 'final object');
      ctx.expect(partials.isNotEmpty, 'no partial snapshots');
      final body = ctx.singleRequest(good, '/v1/chat/completions').jsonObject;
      ctx.expectEquals(body['stream'], true, 'stream flag');

      final bad = await serve(['{"city":', '7}']);
      final badResult = await streamObject(
        model: _model(ctx, bad),
        schema: _citySchema(),
        prompt: 'City?',
      );
      final objectOutcome = badResult.object.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      final badPartials = <Map<String, dynamic>>[];
      Object? streamError;
      final streamDone = Completer<void>();
      badResult.partialObjectStream.listen(
        badPartials.add,
        onError: (Object e) => streamError = e,
        onDone: streamDone.complete,
      );
      await streamDone.future;
      final error = await objectOutcome;
      ctx.observe('invalidPartials', badPartials);
      ctx.expect(error != null, 'invalid final object was accepted');
      ctx.expect(
        badPartials.isNotEmpty,
        'partial snapshots must arrive before final validation fails',
      );
      ctx.expect(
        streamError != null,
        'partial stream did not report the final failure',
      );
      ctx.observe('errorType', '${error.runtimeType}');
      ctx.expect(
        error is SchemaValidationException ||
            (error is AiNoObjectGeneratedError &&
                error.cause is SchemaValidationException),
        'expected a schema validation failure, got ${error.runtimeType}: $error',
      );
    },
  ),
]);
