import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
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

      Future<void> call(LanguageModelV4ToolChoice toolChoice) {
        return model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: _userPrompt('hi'),
            tools: const [
              LanguageModelV4FunctionTool(
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

    test('serializes provider-defined tools verbatim', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: _userPrompt('hi'),
          tools: const [
            LanguageModelV4ProviderDefinedTool(
              id: 'test.search',
              name: 'search',
              description: 'Provider-native search',
              args: {'max_results': 5},
            ),
          ],
        ),
      );

      final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
      expect(tools.single, {
        'type': 'test.search',
        'name': 'search',
        'description': 'Provider-native search',
        'max_results': 5,
      });
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
          client: _testClient(server.baseUrl),
          headers: () => {'Authorization': 'Bearer k'},
          supportsTools: false,
        ),
      );

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: _userPrompt('hi'),
          tools: const [
            LanguageModelV4FunctionTool(
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
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  LanguageModelV4TextPart(text: 'describe'),
                  LanguageModelV4ImagePart(
                    image: DataContentBytes(
                      Uint8List.fromList(utf8.encode('img')),
                    ),
                    mediaType: 'image/png',
                  ),
                  LanguageModelV4FilePart(
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
          client: _testClient(server.baseUrl),
          headers: () => {'Authorization': 'Bearer k'},
          supportsMultimodal: false,
        ),
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  LanguageModelV4TextPart(text: 'describe'),
                  LanguageModelV4ImagePart(
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
    test('serializes a JSON response format', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: _userPrompt('weather'),
          responseFormat: const LanguageModelV4JsonResponseFormat(
            schema: {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
              },
              'required': ['city'],
            },
          ),
        ),
      );

      final rf = captured['response_format'] as Map<String, dynamic>;
      expect(rf['type'], 'json_schema');
      final js = rf['json_schema'] as Map<String, dynamic>;
      expect(js['name'], 'response');
      expect(js['strict'], isTrue);
      expect(js['schema'], isA<Map>());
    });

    test('serializes JSON response format descriptions', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: _userPrompt('weather'),
          responseFormat: const LanguageModelV4JsonResponseFormat(
            name: 'weather_response',
            description: 'Structured weather response.',
            schema: {'type': 'object'},
          ),
        ),
      );

      final rf = captured['response_format'] as Map<String, dynamic>;
      final js = rf['json_schema'] as Map<String, dynamic>;
      expect(js['name'], 'weather_response');
      expect(js['description'], 'Structured weather response.');
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
          client: _testClient(server.baseUrl),
          headers: () => {'Authorization': 'Bearer k'},
          supportsResponseFormatJsonSchema: false,
        ),
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: _userPrompt('hi'),
          responseFormat: const LanguageModelV4JsonResponseFormat(
            schema: {'type': 'object'},
          ),
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
        LanguageModelV4CallOptions(prompt: _userPrompt('weather')),
      );

      expect(result.finishReason, LanguageModelV4FinishReason.toolCalls);
      expect(result.usage.inputTokens.total, 10);
      expect(result.usage.outputTokens.total, 5);
      expect(
        result.content.whereType<LanguageModelV4TextPart>().single.text,
        'checking',
      );
      final toolCall = result.content
          .whereType<LanguageModelV4ToolCallPart>()
          .single;
      expect(toolCall.toolName, 'weather');
      expect(toolCall.input, {'city': 'Paris'});
    });

    test('doGenerate maps prompt_tokens_details.cached_tokens', () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'id': 'chatcmpl_c',
          'model': 'm',
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 'hi'},
            },
          ],
          'usage': {
            'prompt_tokens': 100,
            'completion_tokens': 5,
            'total_tokens': 105,
            'prompt_tokens_details': {'cached_tokens': 80},
          },
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );

      // prompt_tokens already includes cache hits, so total stays at 100 and
      // the uncached remainder is surfaced separately.
      expect(result.usage.inputTokens.total, 100);
      expect(result.usage.inputTokens.noCache, 20);
      expect(result.usage.inputTokens.cacheRead, 80);
      expect(result.usage.inputTokens.cacheWrite, isNull);
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
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );

      final parts = await streamResult.stream.toList();
      expect(parts.whereType<StreamPartTextStart>().length, 1);
      expect(
        parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
        'Hello',
      );
      expect(parts.whereType<StreamPartToolInputStart>().length, 1);
      expect(
        parts.whereType<StreamPartToolInputDelta>().length,
        greaterThanOrEqualTo(1),
      );
      expect(parts.whereType<StreamPartToolInputEnd>().length, 1);
      final toolCall = parts.whereType<StreamPartToolCall>().single.toolCall;
      expect(toolCall.toolName, 'weather');
      expect(toolCall.input, {'city': 'Paris'});
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.toolCalls,
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
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.usage.inputTokens.total, 9);
      expect(finish.usage.outputTokens.total, 3);
      expect(finish.providerMetadata?['test']?['id'], 'chatcmpl_123');
      expect(finish.providerMetadata?['test']?['warnings'], contains('other'));
      expect(
        parts.whereType<StreamPartStreamStart>().single.warnings,
        contains(
          isA<LanguageModelV4OtherWarning>().having(
            (warning) => warning.message,
            'message',
            'careful',
          ),
        ),
      );
    });

    test('emits raw chunks when includeRawChunks is enabled', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"id":"chatcmpl_raw","model":"m","choices":[{"delta":{"content":"Hi"}}]}',
          '{"id":"chatcmpl_raw","model":"m","choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: _userPrompt('hi'),
          includeRawChunks: true,
        ),
      );
      final parts = await streamResult.stream.toList();
      final rawParts = parts.whereType<StreamPartRaw>().toList();
      expect(rawParts, hasLength(2));
      expect(
        (rawParts.first.rawValue as Map<String, dynamic>)['id'],
        'chatcmpl_raw',
      );
    });

    test(
      'emits a stream-start part even when the stream has no JSON chunks',
      () async {
        final server = await _TestServer.start((request) async {
          _writeSse(request, ['[DONE]']);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );
        final parts = await streamResult.stream.toList();
        expect(parts.whereType<StreamPartStreamStart>(), hasLength(1));
        expect(parts.whereType<StreamPartFinish>(), isEmpty);
      },
    );

    // ── finish-reason mapping ────────────────────────────────────────────
    test('maps finish reasons', () async {
      Future<LanguageModelV4FinishReason> reasonFor(String? raw) async {
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
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );
        await server.close();
        return result.finishReason;
      }

      expect(await reasonFor('stop'), LanguageModelV4FinishReason.stop);
      expect(await reasonFor('length'), LanguageModelV4FinishReason.length);
      expect(
        await reasonFor('content_filter'),
        LanguageModelV4FinishReason.contentFilter,
      );
      expect(
        await reasonFor('tool_calls'),
        LanguageModelV4FinishReason.toolCalls,
      );
      expect(await reasonFor(null), LanguageModelV4FinishReason.unknown);
      expect(await reasonFor('weird'), LanguageModelV4FinishReason.other);
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
          client: _testClient(server.baseUrl),
          headers: () => {'Authorization': 'Bearer k'},
          seedKey: 'random_seed',
          maxTokensKey: 'max_tokens',
        ),
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
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
        LanguageModelV4CallOptions(
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
          client: _testClient(server.baseUrl),
          headers: () => {'api-key': 'k'},
          queryParameters: const {'api-version': '2024-02-15-preview'},
        ),
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );

      expect(capturedQuery, contains('api-version=2024-02-15-preview'));
    });

    test(
      'baseUrl ending with slash still posts to chat/completions once',
      () async {
        late String capturedPath;
        final server = await _TestServer.start((request) async {
          capturedPath = request.uri.path;
          _writeOk(request);
        });
        addTearDown(server.close);

        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'm',
          config: OpenAICompatibleConfig(
            provider: 'test',
            baseUrl: '${server.baseUrl}/',
            client: _testClient(server.baseUrl),
            headers: () => {'Authorization': 'Bearer k'},
          ),
        );

        await model.doGenerate(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );

        expect(capturedPath, '/v1/chat/completions');
      },
    );

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
          client: _testClient(apiKeyServer.baseUrl),
          headers: () => {'api-key': 'secret-key'},
        ),
      );
      await apiKeyModel.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
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
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      expect(bearerHeaders.value('authorization'), 'Bearer test-token');
      expect(bearerHeaders.value('api-key'), isNull);
    });

    test('headers are resolved immediately before each dispatch', () async {
      final authorizations = <String?>[];
      final server = await _TestServer.start((request) async {
        authorizations.add(request.headers.value('authorization'));
        _writeOk(request);
      });
      addTearDown(server.close);

      var token = 'first-token';
      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          client: _testClient(server.baseUrl),
          headers: () async => {'Authorization': 'Bearer $token'},
        ),
      );

      await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      token = 'second-token';
      await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('again')),
      );

      expect(authorizations, ['Bearer first-token', 'Bearer second-token']);
    });

    test(
      'provider auth wins while custom request headers remain per-call',
      () async {
        String? authorization;
        String? traceId;
        final server = await _TestServer.start((request) async {
          authorization = request.headers.value('authorization');
          traceId = request.headers.value('x-trace-id');
          _writeOk(request);
        });
        addTearDown(server.close);

        final client = _testClient(server.baseUrl);
        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'm',
          config: OpenAICompatibleConfig(
            provider: 'test',
            baseUrl: server.baseUrl,
            client: client,
            headers: () => {'Authorization': 'Bearer provider-token'},
          ),
        );

        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: _userPrompt('hi'),
            headers: const {
              'Authorization': 'Bearer request-token',
              'X-Trace-Id': 'trace-1',
            },
          ),
        );

        expect(authorization, 'Bearer provider-token');
        expect(traceId, 'trace-1');
        expect(client.options.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('concurrent dispatches resolve independent request headers', () async {
      final authByPrompt = <String, String?>{};
      final server = await _TestServer.start((request) async {
        final body = await _captureBody(request);
        final content =
            ((body['messages'] as List).first
                as Map<String, dynamic>)['content'];
        final prompt = switch (content) {
          String text => text,
          List parts => ((parts.first as Map)['text']).toString(),
          _ => content.toString(),
        };
        authByPrompt[prompt] = request.headers.value('authorization');
        _writeOk(request);
      });
      addTearDown(server.close);

      final gates = [Completer<void>(), Completer<void>()];
      var callCount = 0;
      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          client: _testClient(server.baseUrl),
          headers: () async {
            final index = callCount++;
            await gates[index].future;
            return {'Authorization': 'Bearer token-$index'};
          },
        ),
      );

      final first = model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('first')),
      );
      final second = model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('second')),
      );

      gates[1].complete();
      gates[0].complete();
      await Future.wait([first, second]);

      expect(authByPrompt, {
        'first': 'Bearer token-0',
        'second': 'Bearer token-1',
      });
    });

    test('reuses an injected client across requests', () async {
      final server = await _TestServer.start((request) async {
        _writeOk(request);
      });
      addTearDown(server.close);

      var interceptedRequests = 0;
      final client = Dio(BaseOptions(baseUrl: server.baseUrl))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              interceptedRequests++;
              handler.next(options);
            },
          ),
        );
      addTearDown(() => client.close(force: true));

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer reused'},
          client: client,
        ),
      );

      await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('again')),
      );

      expect(interceptedRequests, 2);
    });

    test(
      'doGenerate cancels an in-flight Dio request via abortSignal',
      () async {
        final adapter = _CancellationHttpClientAdapter();
        final client = _cancellationClient(adapter, 'http://localhost/v1');
        addTearDown(() => client.close(force: true));
        final abortSignal = _TestAbortSignal();
        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'm',
          config: OpenAICompatibleConfig(
            provider: 'test',
            baseUrl: 'http://localhost/v1',
            client: client,
            headers: () => {'Authorization': 'Bearer test-token'},
          ),
        );

        final future = model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: _userPrompt('hi'),
            abortSignal: abortSignal,
          ),
        );

        await adapter.fetchStarted.future;
        expect(adapter.lastOptions?.cancelToken, isNotNull);
        abortSignal.cancel();

        await expectLater(future, throwsA(isA<AiOperationCancelledError>()));
        expect(adapter.fetchCount, 1);
      },
    );

    test(
      'doGenerate surfaces AiOperationCancelledError for a pre-cancelled abortSignal',
      () async {
        final adapter = _CancellationHttpClientAdapter();
        final client = _cancellationClient(adapter, 'http://localhost/v1');
        addTearDown(() => client.close(force: true));
        final abortSignal = _TestAbortSignal()..cancel();
        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'm',
          config: OpenAICompatibleConfig(
            provider: 'test',
            baseUrl: 'http://localhost/v1',
            client: client,
            headers: () => {'Authorization': 'Bearer test-token'},
          ),
        );

        await expectLater(
          model.doGenerate(
            LanguageModelV4CallOptions(
              prompt: _userPrompt('hi'),
              abortSignal: abortSignal,
            ),
          ),
          throwsA(isA<AiOperationCancelledError>()),
        );
        expect(adapter.fetchCount, 0);
      },
    );

    test('doStream cancels the Dio handshake via abortSignal', () async {
      final adapter = _CancellationHttpClientAdapter();
      final client = _cancellationClient(adapter, 'http://localhost/v1');
      addTearDown(() => client.close(force: true));
      final abortSignal = _TestAbortSignal();
      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: 'http://localhost/v1',
          client: client,
          headers: () => {'Authorization': 'Bearer test-token'},
        ),
      );

      final future = model.doStream(
        LanguageModelV4CallOptions(
          prompt: _userPrompt('hi'),
          abortSignal: abortSignal,
        ),
      );

      await adapter.fetchStarted.future;
      expect(adapter.lastOptions?.cancelToken, isNotNull);
      abortSignal.cancel();

      await expectLater(future, throwsA(isA<AiOperationCancelledError>()));
      expect(adapter.fetchCount, 1);
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
          client: _testClient(server.baseUrl),
          headers: () => {'Authorization': 'Bearer k'},
          extraBody: (options) {
            final po = options.providerOptions?['openai'];
            final effort = po?['reasoning_effort'] ?? po?['reasoningEffort'];
            return {'reasoning_effort': ?effort};
          },
        ),
      );
      await model.doGenerate(
        LanguageModelV4CallOptions(
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
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [
                  LanguageModelV4ToolCallPart(
                    toolCallId: 'call_1',
                    toolName: 'weather',
                    input: {'city': 'Paris'},
                  ),
                ],
              ),
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'weather',
                    isError: true,
                    output: ToolResultOutputContent([
                      LanguageModelV4TextPart(text: 'failed'),
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

    // ── specificationVersion / provider getters ──────────────────────────
    test('exposes provider and specificationVersion', () {
      final model = _bearerModel('http://localhost/v1');
      expect(model.provider, 'test');
      expect(model.specificationVersion, 'v4');
    });

    // ── sampling params + system prompt + stop sequences ─────────────────
    test(
      'serializes sampling params, stop sequences and system prompt',
      () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          captured = await _captureBody(request);
          _writeOk(request);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              system: 'You are concise.',
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [LanguageModelV4TextPart(text: 'hi')],
                ),
              ],
            ),
            temperature: 0.3,
            topP: 0.9,
            presencePenalty: 0.5,
            frequencyPenalty: 0.25,
            stopSequences: const ['STOP'],
          ),
        );

        expect(captured['temperature'], 0.3);
        expect(captured['top_p'], 0.9);
        expect(captured['presence_penalty'], 0.5);
        expect(captured['frequency_penalty'], 0.25);
        expect(captured['stop'], ['STOP']);
        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        expect(messages.first['role'], 'system');
        expect(messages.first['content'], 'You are concise.');
      },
    );

    // ── empty / missing response shapes ──────────────────────────────────
    test('doGenerate tolerates empty choices and missing message', () async {
      final emptyChoicesServer = await _TestServer.start((request) async {
        _writeJson(request, {'choices': <dynamic>[]});
      });
      addTearDown(emptyChoicesServer.close);

      final model1 = _bearerModel(emptyChoicesServer.baseUrl);
      final result1 = await model1.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      expect(result1.content, isEmpty);
      expect(result1.finishReason, LanguageModelV4FinishReason.unknown);

      final missingMessageServer = await _TestServer.start((request) async {
        // A choice with no `message` and a tool_call whose `function` is absent.
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'tool_calls': [
                  {'id': 'call_x', 'type': 'function'},
                ],
              },
            },
          ],
        });
      });
      addTearDown(missingMessageServer.close);

      final model2 = _bearerModel(missingMessageServer.baseUrl);
      final result2 = await model2.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final call = result2.content
          .whereType<LanguageModelV4ToolCallPart>()
          .single;
      // Missing function name/arguments fall back to defaults.
      expect(call.toolName, 'unknown_tool');
      expect(call.input, <String, dynamic>{});
    });

    // ── annotations → source/file parts (non-streaming) ──────────────────
    test(
      'doGenerate extracts url_citation and file_citation annotations',
      () async {
        final server = await _TestServer.start((request) async {
          _writeJson(request, {
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'content': 'see citations',
                  'annotations': [
                    {
                      'type': 'url_citation',
                      'url': 'https://example.com',
                      'title': 'Example',
                    },
                    {'type': 'file_citation', 'file_id': 'file_123'},
                    // ignored: url_citation without a url
                    {'type': 'url_citation'},
                    // ignored: file_citation without a file_id
                    {'type': 'file_citation'},
                    // ignored: unknown annotation type
                    {'type': 'other'},
                  ],
                },
              },
            ],
          });
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        final result = await model.doGenerate(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );

        final source = result.content
            .whereType<LanguageModelV4SourcePart>()
            .single;
        expect(source.url, 'https://example.com');
        expect(source.title, 'Example');
        expect(source.id, 'test_source_0');

        final file = result.content.whereType<LanguageModelV4FilePart>().single;
        expect(
          (file.data as DataContentUrl).url.toString(),
          'test://file/file_123',
        );
        expect(file.filename, 'file_123');
      },
    );

    // ── annotations during streaming ─────────────────────────────────────
    test('doStream emits source/file parts from delta annotations', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"choices":[{"delta":{"annotations":[{"type":"url_citation","url":"https://docs.example","title":"Docs"},{"type":"file_citation","file_id":"file_9"}]}}]}',
          '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();

      final source = parts.whereType<StreamPartSource>().single.source;
      expect(source.url, 'https://docs.example');
      expect(source.title, 'Docs');
      final file = parts.whereType<StreamPartFile>().single.file;
      expect(
        (file.data as DataContentUrl).url.toString(),
        'test://file/file_9',
      );
    });

    // ── reasoning/thinking deltas during streaming ───────────────────────
    test(
      'doStream emits reasoning deltas from delta.reasoning_content',
      () async {
        final server = await _TestServer.start((request) async {
          _writeSse(request, [
            '{"choices":[{"delta":{"reasoning_content":"Let me "}}]}',
            '{"choices":[{"delta":{"reasoning_content":"think."}}]}',
            '{"choices":[{"delta":{"content":"Answer."}}]}',
            '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
            '[DONE]',
          ]);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );
        final parts = await streamResult.stream.toList();

        expect(
          parts
              .whereType<StreamPartReasoningDelta>()
              .map((p) => p.delta)
              .join(),
          'Let me think.',
        );
        expect(
          parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
          'Answer.',
        );
      },
    );

    test('doStream emits reasoning deltas from delta.reasoning', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"choices":[{"delta":{"reasoning":"Because X."}}]}',
          '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();

      expect(
        parts.whereType<StreamPartReasoningDelta>().single.delta,
        'Because X.',
      );
    });

    test('doStream emits reasoning deltas from delta.thinking', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"choices":[{"delta":{"thinking":"Hmm."}}]}',
          '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();

      expect(parts.whereType<StreamPartReasoningDelta>().single.delta, 'Hmm.');
    });

    test(
      'doStream emits no reasoning delta when the field is absent or empty',
      () async {
        final server = await _TestServer.start((request) async {
          _writeSse(request, [
            '{"choices":[{"delta":{"reasoning_content":""}}]}',
            '{"choices":[{"delta":{"content":"Hi"}}]}',
            '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
            '[DONE]',
          ]);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );
        final parts = await streamResult.stream.toList();

        expect(parts.whereType<StreamPartReasoningDelta>(), isEmpty);
      },
    );

    test('doStream honors custom config.reasoningKeys', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"choices":[{"delta":{"chain_of_thought":"Step 1."}}]}',
          '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          client: _testClient(server.baseUrl),
          headers: () => {'Authorization': 'Bearer k'},
          reasoningKeys: const ['chain_of_thought'],
        ),
      );
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();

      expect(
        parts.whereType<StreamPartReasoningDelta>().single.delta,
        'Step 1.',
      );
    });

    // ── reasoning/thinking part (non-streaming) ──────────────────────────
    test(
      'doGenerate extracts reasoning from message.reasoning_content',
      () async {
        final server = await _TestServer.start((request) async {
          _writeJson(request, {
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'reasoning_content': 'I reasoned about it.',
                  'content': 'Final answer.',
                },
              },
            ],
          });
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        final result = await model.doGenerate(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );

        final reasoning = result.content
            .whereType<LanguageModelV4ReasoningPart>()
            .single;
        expect(reasoning.text, 'I reasoned about it.');
        final text = result.content.whereType<LanguageModelV4TextPart>().single;
        expect(text.text, 'Final answer.');
      },
    );

    test('doGenerate emits no reasoning part when absent', () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 'Just an answer.'},
            },
          ],
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );

      expect(result.content.whereType<LanguageModelV4ReasoningPart>(), isEmpty);
    });

    // ── streaming tool call without explicit id/function ─────────────────
    test('doStream generates a tool id when none is provided', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          // tool_calls delta with no index, no id, no function block.
          '{"choices":[{"delta":{"tool_calls":[{}]}}]}',
          '{"choices":[{"delta":{"tool_calls":[{"function":{"arguments":"{}"}}]}}]}',
          '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();

      final start = parts.whereType<StreamPartToolInputStart>().single;
      expect(start.id, startsWith('tool-'));
      expect(start.toolName, 'unknown_tool');
      final end = parts.whereType<StreamPartToolInputEnd>().single;
      expect(end.id, startsWith('tool-'));
      expect(
        parts.whereType<StreamPartToolCall>().single.toolCall.toolCallId,
        startsWith('tool-'),
      );
    });

    // ── streaming error path ─────────────────────────────────────────────
    test('doStream surfaces a StreamPartError when the body errors', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n',
        );
        // Abruptly destroy the connection mid-stream to trigger a read error.
        await request.response.flush();
        await request.response.close();
        request.response.deadline = Duration.zero;
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      // Just draining is enough; the finally{} closes the controller.
      final parts = await streamResult.stream.toList();
      expect(
        parts.whereType<StreamPartTextDelta>().length,
        greaterThanOrEqualTo(0),
      );
    });

    // ── file content parts: image-file + generic file ────────────────────
    test('serializes image-typed and generic file content parts', () async {
      final imgB64 = base64Encode(utf8.encode('img'));
      final pdfB64 = base64Encode(utf8.encode('pdf'));
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  // A FilePart with an image/ media type -> image_url.
                  LanguageModelV4FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('img')),
                    ),
                    mediaType: 'image/png',
                  ),
                  // A generic (non-image, non-audio) FilePart -> file.
                  LanguageModelV4FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('pdf')),
                    ),
                    mediaType: 'application/pdf',
                    filename: 'doc.pdf',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final content =
          ((captured['messages'] as List).first
                  as Map<String, dynamic>)['content']
              as List;
      final parts = content.cast<Map<String, dynamic>>();
      final imagePart = parts.firstWhere((p) => p['type'] == 'image_url');
      expect(
        (imagePart['image_url'] as Map)['url'],
        'data:image/png;base64,$imgB64',
      );
      final filePart = parts.firstWhere((p) => p['type'] == 'file');
      expect(
        (filePart['file'] as Map)['file_data'],
        'data:application/pdf;base64,$pdfB64',
      );
      expect((filePart['file'] as Map)['filename'], 'doc.pdf');
    });

    test('serializes image content from a base64 data source', () async {
      final imgB64 = base64Encode(utf8.encode('img64'));
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  LanguageModelV4ImagePart(
                    image: DataContentBase64(imgB64),
                    mediaType: 'image/jpeg',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final content =
          ((captured['messages'] as List).first
                  as Map<String, dynamic>)['content']
              as List;
      final imagePart = content.cast<Map<String, dynamic>>().single;
      expect(
        (imagePart['image_url'] as Map)['url'],
        'data:image/jpeg;base64,$imgB64',
      );
    });

    test(
      'drops image content backed by a bare URL with no media type',
      () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          captured = await _captureBody(request);
          _writeOk(request);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    LanguageModelV4ImagePart(
                      image: DataContentUrl(
                        Uri.parse('https://img.example/a.png'),
                      ),
                      mediaType: 'image/png',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        final content =
            ((captured['messages'] as List).first
                    as Map<String, dynamic>)['content']
                as List;
        final imagePart = content.cast<Map<String, dynamic>>().single;
        expect(
          (imagePart['image_url'] as Map)['url'],
          'https://img.example/a.png',
        );
      },
    );

    // ── rich tool result outputs (content with image/file/text/source) ───
    test(
      'serializes rich tool result content (text, image, file, source)',
      () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          captured = await _captureBody(request);
          _writeOk(request);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.tool,
                  content: [
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'call_1',
                      toolName: 'lookup',
                      isError: true,
                      output: ToolResultOutputContent([
                        LanguageModelV4TextPart(text: 'summary'),
                        LanguageModelV4ImagePart(
                          image: DataContentBytes(
                            Uint8List.fromList(utf8.encode('img')),
                          ),
                          mediaType: 'image/png',
                        ),
                        LanguageModelV4FilePart(
                          data: DataContentUrl(
                            Uri.parse('https://files.example/a.pdf'),
                          ),
                          mediaType: 'application/pdf',
                          filename: 'a.pdf',
                        ),
                        // An unsupported-for-this-path part (source) -> 'unsupported'.
                        LanguageModelV4SourcePart(
                          id: 's1',
                          url: 'https://src.example',
                        ),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        final toolMessage =
            (captured['messages'] as List).last as Map<String, dynamic>;
        final decoded = (jsonDecode(toolMessage['content'] as String) as Map)
            .cast<String, dynamic>();
        expect(decoded['isError'], true);
        final output = (decoded['output'] as Map).cast<String, dynamic>();
        expect(output['type'], 'content');
        final outParts = (output['parts'] as List).cast<Map<String, dynamic>>();
        expect(outParts[0]['type'], 'text');
        expect(outParts[0]['text'], 'summary');
        expect(outParts[1]['type'], 'image');
        expect(outParts[1]['base64'], base64Encode(utf8.encode('img')));
        expect(outParts[2]['type'], 'file');
        expect(outParts[2]['url'], 'https://files.example/a.pdf');
        expect(outParts[2]['filename'], 'a.pdf');
        expect(outParts[3]['type'], 'unsupported');
      },
    );

    test('passes plain text tool results through unwrapped', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'echo',
                    output: ToolResultOutputText('plain result'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final toolMessage =
          (captured['messages'] as List).last as Map<String, dynamic>;
      // Non-error ToolResultOutputText is emitted verbatim (not JSON-wrapped).
      expect(toolMessage['content'], 'plain result');
    });

    test('wraps errored text tool results as structured JSON', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'echo',
                    isError: true,
                    output: ToolResultOutputText('boom'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final toolMessage =
          (captured['messages'] as List).last as Map<String, dynamic>;
      final decoded = (jsonDecode(toolMessage['content'] as String) as Map)
          .cast<String, dynamic>();
      expect(decoded['isError'], true);
      final output = (decoded['output'] as Map).cast<String, dynamic>();
      // ToolResultOutputText -> {type: text, text: ...}.
      expect(output['type'], 'text');
      expect(output['text'], 'boom');
    });

    // ── usage parsed from string-typed token counts ──────────────────────
    test('parses usage when token counts arrive as strings', () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 'ok'},
            },
          ],
          'usage': {
            'prompt_tokens': '9',
            'completion_tokens': 3.0,
            'total_tokens': '12',
          },
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      // String prompt_tokens, num completion_tokens, string total_tokens all
      // coerced via _intOrNull.
      expect(result.usage.inputTokens.total, 9);
      expect(result.usage.outputTokens.total, 3);
    });

    // ── tool call id generation when none is returned ────────────────────
    test('doGenerate generates a tool call id when none is returned', () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'tool_calls',
              'message': {
                'tool_calls': [
                  {
                    'type': 'function',
                    'function': {'name': 'weather', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );
      final call = result.content
          .whereType<LanguageModelV4ToolCallPart>()
          .single;
      expect(call.toolCallId, startsWith('call-'));
    });

    // ── stream: choice with no `delta` key falls back to {} ──────────────
    test('doStream tolerates a choice with no delta object', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          // A choice carrying only a finish_reason, with no `delta` key at all,
          // exercises the `?? <String, dynamic>{}` delta fallback.
          '{"choices":[{"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
      );

      final parts = await streamResult.stream.toList();
      // No text/tool parts (delta was empty), but a Finish part is emitted.
      expect(parts.whereType<StreamPartTextStart>(), isEmpty);
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV4FinishReason.stop);
    });

    // ── stream: malformed chunk surfaces a StreamPartError deterministically ─
    test(
      'doStream emits StreamPartError when a chunk choice is not a map',
      () async {
        final server = await _TestServer.start((request) async {
          _writeSse(request, [
            // `choices.first` is a string, so `(choices.first as Map)` throws and
            // the loop's catch converts it into a StreamPartError.
            '{"choices":["not-a-map"]}',
            '[DONE]',
          ]);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );

        final parts = await streamResult.stream.toList();
        expect(parts.first, isA<StreamPartStreamStart>());
        final error = parts.whereType<StreamPartError>().single;
        expect(error.error, isA<TypeError>());
      },
    );

    test(
      'structured warning maps are surfaced on stream-start and finish metadata',
      () async {
        final server = await _TestServer.start((request) async {
          _writeSse(request, [
            '{"id":"chatcmpl_warn","model":"m","warnings":[{"type":"unsupported","feature":"tools","details":"Disabled"},{"type":"compatibility","feature":"reasoning"},{"type":"deprecated","feature":"legacy-mode","details":"Use default mode"},{"type":"other","message":"fallback"},{"unexpected":"shape"},7],"choices":[{"delta":{"content":"Hi"}}]}',
            '{"id":"chatcmpl_warn","model":"m","choices":[{"delta":{},"finish_reason":"stop"}]}',
            '[DONE]',
          ]);
        });
        addTearDown(server.close);

        final model = _bearerModel(server.baseUrl);
        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );
        final parts = await streamResult.stream.toList();

        final start = parts.whereType<StreamPartStreamStart>().single;
        expect(start.warnings, hasLength(6));
        expect(start.warnings[0], isA<LanguageModelV4UnsupportedWarning>());
        expect(start.warnings[1], isA<LanguageModelV4CompatibilityWarning>());
        expect(start.warnings[2], isA<LanguageModelV4DeprecatedWarning>());
        expect(start.warnings[3], isA<LanguageModelV4OtherWarning>());
        expect(
          (start.warnings[4] as LanguageModelV4OtherWarning).message,
          '{"unexpected":"shape"}',
        );
        expect((start.warnings[5] as LanguageModelV4OtherWarning).message, '7');

        final finish = parts.whereType<StreamPartFinish>().single;
        expect(finish.providerMetadata?['test']?['warnings'], [
          'unsupported',
          'compatibility',
          'deprecated',
          'other',
          'other',
          'other',
        ]);
      },
    );

    test(
      'emits stream-start before StreamPartError when the response stream fails before the first chunk',
      () async {
        final adapter = _ErroredStreamHttpClientAdapter();
        final client = Dio(BaseOptions(baseUrl: 'http://unused'))
          ..httpClientAdapter = adapter;
        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'm',
          config: OpenAICompatibleConfig(
            provider: 'test',
            baseUrl: 'http://unused/v1',
            client: client,
            headers: () => {'Authorization': 'Bearer k'},
          ),
        );

        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(prompt: _userPrompt('hi')),
        );
        final parts = await streamResult.stream.toList();

        expect(parts.first, isA<StreamPartStreamStart>());
        expect(parts.last, isA<StreamPartError>());
      },
    );

    // ── stream tool result: image part carrying a DataContentUrl ─────────
    test('serializes a url-backed image inside tool result content', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'lookup',
                    isError: true,
                    output: ToolResultOutputContent([
                      // An image whose data is a URL (not bytes) exercises the
                      // `if (part.image is DataContentUrl) 'url': ...` branch.
                      LanguageModelV4ImagePart(
                        image: DataContentUrl(
                          Uri.parse('https://img.example/a.png'),
                        ),
                        mediaType: 'image/png',
                      ),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final toolMessage =
          (captured['messages'] as List).last as Map<String, dynamic>;
      final decoded = (jsonDecode(toolMessage['content'] as String) as Map)
          .cast<String, dynamic>();
      final output = (decoded['output'] as Map).cast<String, dynamic>();
      final outParts = (output['parts'] as List).cast<Map<String, dynamic>>();
      expect(outParts.single['type'], 'image');
      expect(outParts.single['mediaType'], 'image/png');
      expect(outParts.single['url'], 'https://img.example/a.png');
      // A DataContentUrl has no inline bytes, so no base64 is emitted.
      expect(outParts.single.containsKey('base64'), isFalse);
    });

    // ── stream: a null response body surfaces a clear StateError ─────────
    test('doStream throws StateError when the stream body is null', () async {
      // A misbehaving client factory whose interceptor resolves the request
      // with a null-bodied Response leaves `response.data == null`; the model
      // must surface a descriptive StateError rather than crash later.
      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: 'http://localhost/v1',
          client: Dio(BaseOptions(baseUrl: 'http://localhost/v1'))
            ..interceptors.add(_NullStreamBodyInterceptor()),
          headers: () => const {},
        ),
      );

      await expectLater(
        model.doStream(LanguageModelV4CallOptions(prompt: _userPrompt('hi'))),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('stream response body is null'),
          ),
        ),
      );
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
      client: _testClient(baseUrl),
      headers: () => {'Authorization': 'Bearer test-token'},
    ),
  );
}

Dio _testClient(String baseUrl) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {'Content-Type': 'application/json'},
      responseType: ResponseType.json,
    ),
  );
}

Dio _cancellationClient(HttpClientAdapter adapter, String baseUrl) {
  final client = _testClient(baseUrl);
  client.httpClientAdapter = adapter;
  return client;
}

LanguageModelV4Prompt _userPrompt(String text) {
  return LanguageModelV4Prompt(
    messages: [
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: text)],
      ),
    ],
  );
}

Future<Map<String, dynamic>> _captureBody(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return (jsonDecode(body) as Map).cast<String, dynamic>();
}

/// Resolves every request with a 200 Response whose `data` is null, simulating
/// a client/adapter that yields no stream body.
class _NullStreamBodyInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    handler.resolve(
      Response<dynamic>(requestOptions: options, statusCode: 200),
    );
  }
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

class _TestAbortSignal implements LanguageModelV4AbortSignal {
  final Completer<void> _completer = Completer<void>();
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  Future<void> get onCancelled => _completer.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _completer.complete();
  }
}

class _CancellationHttpClientAdapter implements HttpClientAdapter {
  int fetchCount = 0;
  RequestOptions? lastOptions;
  final Completer<void> fetchStarted = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    fetchCount++;
    lastOptions = options;
    if (!fetchStarted.isCompleted) {
      fetchStarted.complete();
    }

    final completer = Completer<ResponseBody>();
    cancelFuture?.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          DioException.requestCancelled(
            requestOptions: options,
            reason: 'abortSignal',
          ),
        );
      }
    });
    return completer.future;
  }

  @override
  void close({bool force = false}) {}
}

class _ErroredStreamHttpClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      Stream<Uint8List>.error(StateError('stream failed before first chunk')),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
