import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/contract/language_model_contract.dart';

void main() {
  group('OpenAIProvider', () {
    test('doGenerate maps text, tools, finish reason, usage', () async {
      final server = await _TestServer.start((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        final body = await utf8.decoder.bind(request).join();
        final jsonBody = jsonDecode(body) as Map<String, dynamic>;
        expect(jsonBody['model'], 'gpt-4.1-mini');
        expect(jsonBody['messages'], isA<List>());
        expect(jsonBody['tool_choice'], 'required');

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'chatcmpl_1',
            'model': 'gpt-4.1-mini',
            'choices': [
              {
                'finish_reason': 'tool_calls',
                'message': {
                  'content': 'I need to check weather.',
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
          }),
        );
        await request.response.close();
      });

      addTearDown(server.close);

      final provider = OpenAIProvider(apiKey: 'test', baseUrl: server.baseUrl);
      final model = provider.call('gpt-4.1-mini');

      final result = await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'weather in paris')],
              ),
            ],
          ),
          tools: [
            const LanguageModelV3FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
        ),
      );

      expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
      expect(result.usage?.totalTokens, 15);
      expect(
        result.content.whereType<LanguageModelV3TextPart>().first.text,
        'I need to check weather.',
      );
      final toolCall = result.content
          .whereType<LanguageModelV3ToolCallPart>()
          .first;
      expect(toolCall.toolName, 'weather');
      expect(toolCall.input, isA<Map>());
    });

    test('doStream parses text and tool deltas into stream parts', () async {
      final server = await _TestServer.start((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"content":"lo"}}]}\n\n',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"weather","arguments":"{\\"city\\":\\""}}]}}]}\n\n',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Paris\\"}"}}]}}]}\n\n',
        );
        request.response.write(
          'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });

      addTearDown(server.close);

      final provider = OpenAIProvider(apiKey: 'test', baseUrl: server.baseUrl);
      final model = provider.call('gpt-4.1-mini');

      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'Hi')],
              ),
            ],
          ),
        ),
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
      expect(parts.whereType<StreamPartToolCallEnd>().length, 1);
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.toolCalls,
      );
    });

    test('maps tool choice modes and strict tool schemas', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        seenBodies.add((jsonDecode(body) as Map).cast<String, dynamic>());

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': 'ok'},
              },
            ],
          }),
        );
        await request.response.close();
      });

      addTearDown(server.close);
      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gpt-4.1-mini');

      Future<void> call(LanguageModelV3ToolChoice toolChoice) async {
        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
            tools: const [
              LanguageModelV3FunctionTool(
                name: 'weather',
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
      expect(
        (tools.single['function'] as Map<String, dynamic>)['strict'],
        isTrue,
      );
    });

    test(
      'preserves invalid strict tool arguments for downstream failure handling',
      () async {
        final server = await _TestServer.start((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'tool_calls',
                  'message': {
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'weather',
                          'arguments': 'not-json',
                        },
                      },
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gpt-4.1-mini');
        final result = await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
            tools: const [
              LanguageModelV3FunctionTool(
                name: 'weather',
                inputSchema: {'type': 'object'},
                strict: true,
              ),
            ],
          ),
        );

        final call = result.content
            .whereType<LanguageModelV3ToolCallPart>()
            .single;
        expect(call.input, 'not-json');
      },
    );

    test(
      'extracts provider-native source and file parts from annotations',
      () async {
        final server = await _TestServer.start((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'chatcmpl-annotated',
              'model': 'gpt-4.1-mini',
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
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gpt-4.1-mini');
        final result = await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
          ),
        );

        expect(
          result.content.whereType<LanguageModelV3SourcePart>(),
          hasLength(1),
        );
        expect(
          result.content.whereType<LanguageModelV3FilePart>(),
          hasLength(1),
        );
      },
    );

    test('embedding endpoint parses vectors', () async {
      final server = await _TestServer.start((request) async {
        expect(request.uri.path, '/v1/embeddings');
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'embedding': [0.1, 0.2, 0.3],
              },
              {
                'embedding': [1, 2, 3],
              },
            ],
            'usage': {'total_tokens': 20},
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final provider = OpenAIProvider(apiKey: 'test', baseUrl: server.baseUrl);
      final model = provider.embedding('text-embedding-3-small');
      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions(values: ['a', 'b']),
      );

      expect(result.embeddings, hasLength(2));
      expect(result.embeddings.first.embedding, [0.1, 0.2, 0.3]);
      expect(result.usage?.tokens, 20);
    });

    test('image endpoint parses b64 images', () async {
      final imageBytes = utf8.encode('fakepng');
      final imageB64 = base64Encode(imageBytes);

      final server = await _TestServer.start((request) async {
        expect(request.uri.path, '/v1/images/generations');
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {'b64_json': imageB64},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final provider = OpenAIProvider(apiKey: 'test', baseUrl: server.baseUrl);
      final model = provider.image('gpt-image-1');
      final result = await model.doGenerate(
        const ImageModelV3CallOptions(prompt: 'a cat'),
      );

      expect(result.images, hasLength(1));
      expect(result.images.first.bytes, imageBytes);
      expect(result.usage?.imagesGenerated, 1);
    });

    test('passes providerOptions into request body', () async {
      final server = await _TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        final jsonBody = jsonDecode(body) as Map<String, dynamic>;
        expect(jsonBody['user'], 'user-123');
        expect(jsonBody['metadata'], {'trace': 'abc'});

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': 'ok'},
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gpt-4.1-mini');

      final result = await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'hi')],
              ),
            ],
          ),
          providerOptions: const {
            'openai': {
              'user': 'user-123',
              'metadata': {'trace': 'abc'},
            },
          },
        ),
      );

      expect(
        result.content.whereType<LanguageModelV3TextPart>().single.text,
        'ok',
      );
    });

    // ── OpenAILanguageModelOptions / reasoning ────────────────────────────

    group('OpenAILanguageModelOptions', () {
      test('toMap serialises reasoning_effort and reasoning_summary', () {
        final opts = const OpenAILanguageModelOptions(
          reasoningEffort: 'high',
          reasoningSummary: 'concise',
        );
        final map = opts.toMap();
        expect(map['reasoning_effort'], 'high');
        expect(map['reasoning_summary'], 'concise');
      });

      test('toMap omits null fields', () {
        final opts = const OpenAILanguageModelOptions(reasoningEffort: 'low');
        final map = opts.toMap();
        expect(map.containsKey('reasoning_summary'), isFalse);
      });

      test('doGenerate sends reasoning_effort from snake_case providerOptions',
          () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {'finish_reason': 'stop', 'message': {'content': 'ok'}},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('o3-mini');
        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
            providerOptions: const {
              'openai': {'reasoning_effort': 'high'},
            },
          ),
        );

        expect(captured['reasoning_effort'], 'high');
      });

      test('doGenerate sends reasoning_effort from typed options class',
          () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {'finish_reason': 'stop', 'message': {'content': 'ok'}},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('o3-mini');
        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
            providerOptions: {
              'openai': const OpenAILanguageModelOptions(
                reasoningEffort: 'medium',
                reasoningSummary: 'auto',
              ).toMap(),
            },
          ),
        );

        expect(captured['reasoning_effort'], 'medium');
        expect(captured['reasoning_summary'], 'auto');
        // camelCase keys must NOT appear in the request
        expect(captured.containsKey('reasoningEffort'), isFalse);
      });

      test('doGenerate converts camelCase reasoningEffort to snake_case',
          () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {'finish_reason': 'stop', 'message': {'content': 'ok'}},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('o3-mini');
        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
            providerOptions: const {
              'openai': {'reasoningEffort': 'low'},
            },
          ),
        );

        expect(captured['reasoning_effort'], 'low');
        expect(captured.containsKey('reasoningEffort'), isFalse);
      });
    });

    // ── outputSchema / response_format: json_schema ──────────────────────

    group('outputSchema (native structured output)', () {
      test('doGenerate sends response_format json_schema when outputSchema set',
          () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'content': '{"city":"Paris","tempC":21}',
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gpt-4o-mini');
        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'weather in Paris')],
                ),
              ],
            ),
            outputSchema: const {
              'type': 'object',
              'properties': {
                'city': {'type': 'string'},
                'tempC': {'type': 'number'},
              },
              'required': ['city', 'tempC'],
            },
          ),
        );

        final responseFormat =
            captured['response_format'] as Map<String, dynamic>?;
        expect(responseFormat, isNotNull);
        expect(responseFormat!['type'], 'json_schema');
        final jsonSchema =
            responseFormat['json_schema'] as Map<String, dynamic>?;
        expect(jsonSchema, isNotNull);
        expect(jsonSchema!['name'], 'response');
        expect(jsonSchema['strict'], isTrue);
        expect(jsonSchema['schema'], isA<Map>());
      });

      test('doGenerate does NOT send response_format when outputSchema is null',
          () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {'finish_reason': 'stop', 'message': {'content': 'ok'}},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gpt-4o-mini');
        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
          ),
        );

        expect(captured.containsKey('response_format'), isFalse);
      });
    });

    test('maps multimodal content and tool result messages', () async {
      final imageB64 = base64Encode(utf8.encode('img'));
      final audioB64 = base64Encode(utf8.encode('audio'));

      final server = await _TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        final jsonBody = jsonDecode(body) as Map<String, dynamic>;
        final messages = (jsonBody['messages'] as List)
            .cast<Map<String, dynamic>>();

        final userMessage = messages.first;
        expect(userMessage['role'], 'user');
        final userContent = (userMessage['content'] as List)
            .cast<Map<String, dynamic>>();
        expect(userContent[0]['type'], 'text');
        expect(userContent[1]['type'], 'image_url');
        expect(
          (userContent[1]['image_url'] as Map)['url'],
          'data:image/png;base64,$imageB64',
        );
        expect(userContent[2]['type'], 'input_audio');
        expect((userContent[2]['input_audio'] as Map)['data'], audioB64);

        final toolMessage = messages.last;
        expect(toolMessage['role'], 'tool');
        expect(toolMessage['tool_call_id'], 'call_1');
        expect(toolMessage['content'], contains('"isError":true'));

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {'content': 'ok'},
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gpt-4.1-mini');

      final result = await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3TextPart(text: 'describe this'),
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
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'weather',
                    isError: true,
                    output: ToolResultOutputContent([
                      LanguageModelV3TextPart(text: 'failed to fetch'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      expect(
        result.content.whereType<LanguageModelV3TextPart>().single.text,
        'ok',
      );
    });

    test('stream finish includes usage and metadata', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"id":"chatcmpl_123","model":"gpt-4.1-mini","warnings":["careful"],"choices":[{"delta":{"content":"Hello"}}]}\n\n',
        );
        request.response.write(
          'data: {"id":"chatcmpl_123","model":"gpt-4.1-mini","usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12},"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gpt-4.1-mini');

      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'hi')],
              ),
            ],
          ),
        ),
      );

      final finish = (await streamResult.stream.toList())
          .whereType<StreamPartFinish>()
          .single;
      expect(finish.usage?.totalTokens, 12);
      expect(finish.providerMetadata?['openai']?['id'], 'chatcmpl_123');
      expect(
        finish.providerMetadata?['openai']?['warnings'],
        contains('careful'),
      );
    });

    test('stream emits source/file parts from annotations', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"id":"chatcmpl_annotated","model":"gpt-4.1-mini","choices":[{"delta":{"annotations":[{"type":"url_citation","url":"https://example.com/docs","title":"Docs"},{"type":"file_citation","file_id":"file_456"}]}}]}\n\n',
        );
        request.response.write(
          'data: {"id":"chatcmpl_annotated","model":"gpt-4.1-mini","choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gpt-4.1-mini');

      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'hi')],
              ),
            ],
          ),
        ),
      );

      final parts = await streamResult.stream.toList();
      final source = parts.whereType<StreamPartSource>().single.source;
      final file = parts.whereType<StreamPartFile>().single.file;
      expect(source.url, 'https://example.com/docs');
      expect(source.title, 'Docs');
      expect(
        (file.data as DataContentUrl).url.toString(),
        'openai://file/file_456',
      );
      expect(file.filename, 'file_456');
    });

    runProviderContractTests(
      providerName: 'openai',
      captureRequestBody: _captureOpenAiRequestBody,
      expectMultimodalBody: (body) {
        final messages = (body['messages'] as List)
            .cast<Map<String, dynamic>>();
        final user = messages.first;
        final content = (user['content'] as List).cast<Map<String, dynamic>>();
        expect(content[0]['type'], 'text');
        expect(content[1]['type'], 'image_url');
        expect(content[2]['type'], 'input_audio');
      },
      expectToolResultBody: (body) {
        final messages = (body['messages'] as List)
            .cast<Map<String, dynamic>>();
        final toolMessage = messages.last;
        expect(toolMessage['role'], 'tool');
        expect(toolMessage['tool_call_id'], 'call_1');
        expect(toolMessage['content'], contains('"isError":true'));
      },
    );
  });
}

Future<Map<String, dynamic>> _captureOpenAiRequestBody(
  LanguageModelV3Prompt prompt,
) async {
  late Map<String, dynamic> captured;
  final server = await _TestServer.start((request) async {
    final body = await utf8.decoder.bind(request).join();
    captured = (jsonDecode(body) as Map).cast<String, dynamic>();

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'choices': [
          {
            'finish_reason': 'stop',
            'message': {'content': 'ok'},
          },
        ],
      }),
    );
    await request.response.close();
  });

  final model = OpenAIProvider(
    apiKey: 'test',
    baseUrl: server.baseUrl,
  ).call('gpt-4.1-mini');
  await model.doGenerate(LanguageModelV3CallOptions(prompt: prompt));
  await server.close();
  return captured;
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
