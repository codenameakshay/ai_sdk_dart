import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAICompatibleChatLanguageModel', () {
    // ── tool serialization + tool_choice modes ──────────────────────────
    test('serializes tools (strict) and tool_choice modes', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        seenBodies.add((jsonDecode(body) as Map).cast<String, dynamic>());
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 'ok'},
            },
          ],
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);

      Future<void> call(LanguageModelV3ToolChoice toolChoice) {
        return model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: _userPrompt('hi'),
            tools: const [
              LanguageModelV3FunctionTool(
                name: 'weather',
                description: 'Get the weather',
                inputSchema: {'type': 'object'},
                strict: true,
              ),
            ],
            toolChoice: toolChoice,
          ),
        );
      }

      await call(const ToolChoiceAuto());
      await call(const ToolChoiceNone());
      await call(const ToolChoiceRequired());
      await call(const ToolChoiceSpecific(toolName: 'weather'));

      expect(seenBodies[0]['tool_choice'], 'auto');
      expect(seenBodies[1]['tool_choice'], 'none');
      expect(seenBodies[2]['tool_choice'], 'required');
      expect(seenBodies[3]['tool_choice'], {
        'type': 'function',
        'function': {'name': 'weather'},
      });

      final tools = (seenBodies[0]['tools'] as List)
          .cast<Map<String, dynamic>>();
      final fn = tools.single['function'] as Map<String, dynamic>;
      expect(fn['name'], 'weather');
      expect(fn['description'], 'Get the weather');
      expect(fn['strict'], isTrue);
      expect(fn['parameters'], {'type': 'object'});
    });

    test('omits tools when supportsTools is false', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          supportsTools: false,
        ),
      );

      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          tools: const [
            LanguageModelV3FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
        ),
      );

      expect(captured.containsKey('tools'), isFalse);
      expect(captured.containsKey('tool_choice'), isFalse);
    });

    // ── multimodal image part serialization ──────────────────────────────
    test('serializes multimodal image + audio content parts', () async {
      final imageB64 = base64Encode(utf8.encode('img'));
      final audioB64 = base64Encode(utf8.encode('audio'));
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3TextPart(text: 'describe'),
                  LanguageModelV3ImagePart(
                    image: DataContentBytes(
                      Uint8List.fromList(utf8.encode('img')),
                    ),
                    mediaType: 'image/png',
                  ),
                  LanguageModelV3FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('audio')),
                    ),
                    mediaType: 'audio/wav',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final content = (messages.first['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      expect(
        (content[1]['image_url'] as Map)['url'],
        'data:image/png;base64,$imageB64',
      );
      expect(content[2]['type'], 'input_audio');
      expect((content[2]['input_audio'] as Map)['data'], audioB64);
    });

    test('flattens content to text when supportsMultimodal is false', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          supportsMultimodal: false,
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3TextPart(text: 'describe'),
                  LanguageModelV3ImagePart(
                    image: DataContentBytes(
                      Uint8List.fromList(utf8.encode('img')),
                    ),
                    mediaType: 'image/png',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(messages.first['content'], 'describe');
    });

    // ── response_format json_schema ──────────────────────────────────────
    test('serializes response_format json_schema from outputSchema', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('weather'),
          outputSchema: const {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
            'required': ['city'],
          },
        ),
      );

      final rf = captured['response_format'] as Map<String, dynamic>;
      expect(rf['type'], 'json_schema');
      final js = rf['json_schema'] as Map<String, dynamic>;
      expect(js['name'], 'response');
      expect(js['strict'], isTrue);
      expect(js['schema'], isA<Map>());
    });

    test('omits response_format when flag disabled', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          supportsResponseFormatJsonSchema: false,
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          outputSchema: const {'type': 'object'},
        ),
      );

      expect(captured.containsKey('response_format'), isFalse);
    });

    // ── non-streaming tool-call parsing + finish reason + usage ──────────
    test('doGenerate parses tool calls, finish reason, usage', () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'id': 'chatcmpl_1',
          'model': 'm',
          'choices': [
            {
              'finish_reason': 'tool_calls',
              'message': {
                'content': 'checking',
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'weather',
                      'arguments': '{"city":"Paris"}',
                    },
                  },
                ],
              },
            },
          ],
          'usage': {
            'prompt_tokens': 10,
            'completion_tokens': 5,
            'total_tokens': 15,
          },
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('weather')),
      );

      expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
      expect(result.usage?.totalTokens, 15);
      expect(
        result.content.whereType<LanguageModelV3TextPart>().single.text,
        'checking',
      );
      final toolCall = result.content
          .whereType<LanguageModelV3ToolCallPart>()
          .single;
      expect(toolCall.toolName, 'weather');
      expect(toolCall.input, {'city': 'Paris'});
    });

    // ── SSE text + tool-call streaming ───────────────────────────────────
    test('doStream parses text deltas and tool-call deltas', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"choices":[{"delta":{"content":"Hel"}}]}',
          '{"choices":[{"delta":{"content":"lo"}}]}',
          '{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"weather","arguments":"{\\"city\\":\\""}}]}}]}',
          '{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Paris\\"}"}}]}}]}',
          '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );

      final parts = await streamResult.stream.toList();
      expect(parts.whereType<StreamPartTextStart>().length, 1);
      expect(
        parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
        'Hello',
      );
      expect(parts.whereType<StreamPartToolCallStart>().length, 1);
      expect(
        parts.whereType<StreamPartToolCallDelta>().length,
        greaterThanOrEqualTo(1),
      );
      final end = parts.whereType<StreamPartToolCallEnd>().single;
      expect(end.toolName, 'weather');
      expect(end.input, {'city': 'Paris'});
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.toolCalls,
      );
    });

    test('stream finish includes usage and provider metadata', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"id":"chatcmpl_123","model":"m","warnings":["careful"],"choices":[{"delta":{"content":"Hi"}}]}',
          '{"id":"chatcmpl_123","model":"m","usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12},"choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      final finish = (await streamResult.stream.toList())
          .whereType<StreamPartFinish>()
          .single;
      expect(finish.usage?.totalTokens, 12);
      expect(finish.providerMetadata?['test']?['id'], 'chatcmpl_123');
      expect(
        finish.providerMetadata?['test']?['warnings'],
        contains('careful'),
      );
    });

    // ── finish-reason mapping ────────────────────────────────────────────
    test('maps finish reasons', () async {
      Future<LanguageModelV3FinishReason> reasonFor(String? raw) async {
        final server = await _TestServer.start((request) async {
          _writeJson(request, {
            'choices': [
              {
                'finish_reason': raw,
                'message': {'content': 'ok'},
              },
            ],
          });
        });
        addTearDown(server.close);
        final model = _bearerModel(server.baseUrl);
        final result = await model.doGenerate(
          LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
        );
        await server.close();
        return result.finishReason;
      }

      expect(await reasonFor('stop'), LanguageModelV3FinishReason.stop);
      expect(await reasonFor('length'), LanguageModelV3FinishReason.length);
      expect(
        await reasonFor('content_filter'),
        LanguageModelV3FinishReason.contentFilter,
      );
      expect(
        await reasonFor('tool_calls'),
        LanguageModelV3FinishReason.toolCalls,
      );
      expect(await reasonFor(null), LanguageModelV3FinishReason.unknown);
      expect(await reasonFor('weird'), LanguageModelV3FinishReason.other);
    });

    // ── config quirks ────────────────────────────────────────────────────
    test('seed key override (random_seed) + max_tokens key override', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'mistral',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          seedKey: 'random_seed',
          maxTokensKey: 'max_tokens',
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          seed: 42,
          maxOutputTokens: 128,
        ),
      );

      expect(captured['random_seed'], 42);
      expect(captured.containsKey('seed'), isFalse);
      expect(captured['max_tokens'], 128);
      expect(captured.containsKey('max_completion_tokens'), isFalse);
    });

    test('default keys are seed + max_completion_tokens', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          seed: 7,
          maxOutputTokens: 64,
        ),
      );

      expect(captured['seed'], 7);
      expect(captured['max_completion_tokens'], 64);
    });

    test('api-version query parameter is sent (Azure quirk)', () async {
      late String capturedQuery;
      final server = await _TestServer.start((request) async {
        capturedQuery = request.uri.query;
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'dep',
        config: OpenAICompatibleConfig(
          provider: 'azure',
          baseUrl: server.baseUrl,
          headers: () => {'api-key': 'k'},
          queryParameters: const {'api-version': '2024-02-15-preview'},
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );

      expect(capturedQuery, contains('api-version=2024-02-15-preview'));
    });

    test('api-key header vs Bearer auth scheme', () async {
      late HttpHeaders apiKeyHeaders;
      final apiKeyServer = await _TestServer.start((request) async {
        apiKeyHeaders = request.headers;
        _writeOk(request);
      });
      addTearDown(apiKeyServer.close);

      final apiKeyModel = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'azure',
          baseUrl: apiKeyServer.baseUrl,
          headers: () => {'api-key': 'secret-key'},
        ),
      );
      await apiKeyModel.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      expect(apiKeyHeaders.value('api-key'), 'secret-key');
      expect(apiKeyHeaders.value('authorization'), isNull);

      late HttpHeaders bearerHeaders;
      final bearerServer = await _TestServer.start((request) async {
        bearerHeaders = request.headers;
        _writeOk(request);
      });
      addTearDown(bearerServer.close);
      final bearerModel = _bearerModel(bearerServer.baseUrl);
      await bearerModel.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      expect(bearerHeaders.value('authorization'), 'Bearer test-token');
      expect(bearerHeaders.value('api-key'), isNull);
    });

    test('extraBody hook injects provider-specific fields', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'o3-mini',
        config: OpenAICompatibleConfig(
          provider: 'openai',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          extraBody: (options) {
            final po = options.providerOptions?['openai'];
            final effort = po?['reasoning_effort'] ?? po?['reasoningEffort'];
            return {if (effort != null) 'reasoning_effort': effort};
          },
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          providerOptions: const {
            'openai': {'reasoningEffort': 'high'},
          },
        ),
      );

      expect(captured['reasoning_effort'], 'high');
    });

    test('serializes assistant tool calls and tool result messages', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.assistant,
                content: [
                  LanguageModelV3ToolCallPart(
                    toolCallId: 'call_1',
                    toolName: 'weather',
                    input: {'city': 'Paris'},
                  ),
                ],
              ),
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'weather',
                    isError: true,
                    output: ToolResultOutputContent([
                      LanguageModelV3TextPart(text: 'failed'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final assistant = messages.first;
      expect(assistant['role'], 'assistant');
      final toolCalls = (assistant['tool_calls'] as List)
          .cast<Map<String, dynamic>>();
      expect((toolCalls.single['function'] as Map)['name'], 'weather');

      final toolMessage = messages.last;
      expect(toolMessage['role'], 'tool');
      expect(toolMessage['tool_call_id'], 'call_1');
      expect(toolMessage['content'], contains('"isError":true'));
    });
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

OpenAICompatibleChatLanguageModel _bearerModel(String baseUrl) {
  return OpenAICompatibleChatLanguageModel(
    modelId: 'm',
    config: OpenAICompatibleConfig(
      provider: 'test',
      baseUrl: baseUrl,
      headers: () => {'Authorization': 'Bearer test-token'},
    ),
  );
}

LanguageModelV3Prompt _userPrompt(String text) {
  return LanguageModelV3Prompt(
    messages: [
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [LanguageModelV3TextPart(text: text)],
      ),
    ],
  );
}

Future<Map<String, dynamic>> _captureBody(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return (jsonDecode(body) as Map).cast<String, dynamic>();
}

void _writeJson(HttpRequest request, Object payload) {
  request.response.statusCode = 200;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(payload));
  request.response.close();
}

void _writeOk(HttpRequest request) {
  _writeJson(request, {
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': 'ok'},
      },
    ],
  });
}

void _writeSse(HttpRequest request, List<String> events) {
  request.response.statusCode = 200;
  request.response.headers.set('content-type', 'text/event-stream');
  for (final event in events) {
    request.response.write('data: $event\n\n');
  }
  request.response.close();
}

class _TestServer {
  _TestServer._(this._server);

  final HttpServer _server;

  static Future<_TestServer> start(
    FutureOr<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        await handler(request);
      }
    }());
    return _TestServer._(server);
  }

  String get baseUrl => 'http://${_server.address.host}:${_server.port}/v1';

  Future<void> close() => _server.close(force: true);
}
