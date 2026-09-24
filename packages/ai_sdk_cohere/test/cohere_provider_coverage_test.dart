import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/test_server.dart';

void main() {
  test('default provider exposes all model families', () {
    expect(cohere('command-r').provider, 'cohere');
    expect(cohere.embedding('embed-v4.0').maxEmbeddingsPerCall, 96);
    expect(cohere.embedding('embed-v4.0').supportsParallelCalls, isTrue);
    expect(cohere.rerank('rerank-v3.5').specificationVersion, 'v1');
  });

  test('wraps malformed rerank responses as API errors', () async {
    final server = await TestServer.start((request) async {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'results': [
            {'index': 4},
          ],
        }),
      );
      await request.response.close();
    });
    addTearDown(server.close);

    await expectLater(
      CohereProvider(apiKey: 'test', baseUrl: server.baseUrl)
          .rerank('rerank-v3.5')
          .doRerank(
            const RerankModelV1CallOptions(
              query: 'query',
              documents: ['document'],
            ),
          ),
      throwsA(isA<AiApiCallError>()),
    );
  });

  test('rejects unsupported prompt and tool-result media', () async {
    final model = CohereProvider(apiKey: 'test').call('command-r');
    for (final part in <LanguageModelV4ContentPart>[
      const LanguageModelV4DocumentSourcePart(
        id: 'doc',
        mediaType: 'application/pdf',
        title: 'doc',
      ),
      const LanguageModelV4ReasoningFilePart(
        data: DataContentBase64('YQ=='),
        mediaType: 'text/plain',
      ),
    ]) {
      await expectLater(
        model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    const LanguageModelV4ImagePart(
                      image: DataContentBase64('YQ=='),
                    ),
                    part,
                  ],
                ),
              ],
            ),
          ),
        ),
        throwsUnsupportedError,
      );
    }

    await expectLater(
      model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  const LanguageModelV4ToolResultPart(
                    toolCallId: 'call',
                    toolName: 'tool',
                    output: ToolResultOutputContent([
                      LanguageModelV4ImagePart(
                        image: DataContentBase64('YQ=='),
                      ),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('embedding and rerank rethrow credential-provider errors', () async {
    final provider = CohereProvider(
      credentialProvider: () async => throw StateError('credential failed'),
    );
    await expectLater(
      provider
          .embedding('embed-v4.0')
          .doEmbed(const EmbeddingModelV2CallOptions<String>(values: ['x'])),
      throwsStateError,
    );
    await expectLater(
      provider
          .rerank('rerank-v3.5')
          .doRerank(
            const RerankModelV1CallOptions(query: 'x', documents: ['x']),
          ),
      throwsStateError,
    );
    provider.dispose();
  });

  group('Cohere embedding model', () {
    test('serializes /embed request and parses float embeddings', () async {
      late String capturedPath;
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        capturedPath = request.uri.path;
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'embeddings': {
              'float': [
                [0.1, 0.2, 0.3],
                [0.4, 0.5, 0.6],
              ],
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).embedding('embed-english-v4.0');

      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(
          values: ['hello world', 'goodbye world'],
        ),
      );

      // Request serialization.
      expect(capturedPath, '/embed');
      expect(captured['model'], 'embed-english-v4.0');
      expect(captured['texts'], ['hello world', 'goodbye world']);
      expect(captured['input_type'], 'search_document');
      expect(captured['embedding_types'], ['float']);

      // Response deserialization: one embedding per input value, in order.
      expect(result.embeddings, hasLength(2));
      expect(result.embeddings[0].value, 'hello world');
      expect(result.embeddings[0].embedding, [0.1, 0.2, 0.3]);
      expect(result.embeddings[1].value, 'goodbye world');
      expect(result.embeddings[1].embedding, [0.4, 0.5, 0.6]);
    });

    test(
      'forwards providerOptions and defaults input_type when omitted',
      () async {
        late Map<String, dynamic> captured;
        final server = await TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'embeddings': {
                'float': [
                  [0.1],
                ],
              },
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = CohereProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).embedding('embed-english-v4.0');

        await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(
            values: ['query'],
            providerOptions: {
              'cohere': {'input_type': 'search_query', 'truncate': 'END'},
            },
          ),
        );

        expect(captured['input_type'], 'search_query');
        expect(captured['truncate'], 'END');
      },
    );

    test('rejects a missing embeddings field', () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'id': 'x'}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).embedding('embed-english-v4.0');

      await expectLater(
        model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['only']),
        ),
        throwsA(isA<AiApiCallError>()),
      );
    });
  });

  group('Cohere rerank model', () {
    test('serializes /rerank request and parses ranked results', () async {
      late String capturedPath;
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        capturedPath = request.uri.path;
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'results': [
              {'index': 1, 'relevance_score': 0.9},
              {'index': 0, 'relevance_score': 0.4},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).rerank('rerank-english-v4.0');

      final result = await model.doRerank(
        const RerankModelV1CallOptions(
          query: 'What is AI?',
          documents: ['Machines are useful.', 'AI is intelligence.'],
          topN: 2,
        ),
      );

      // Request serialization.
      expect(capturedPath, '/rerank');
      expect(captured['model'], 'rerank-english-v4.0');
      expect(captured['query'], 'What is AI?');
      expect(captured['documents'], [
        'Machines are useful.',
        'AI is intelligence.',
      ]);
      expect(captured['top_n'], 2);

      // Response deserialization: ranked order, original index + document text.
      expect(result.documents, hasLength(2));
      expect(result.documents[0].index, 1);
      expect(result.documents[0].document, 'AI is intelligence.');
      expect(result.documents[0].relevanceScore, 0.9);
      expect(result.documents[1].index, 0);
      expect(result.documents[1].document, 'Machines are useful.');
      expect(result.documents[1].relevanceScore, 0.4);
    });

    test('omits top_n when not provided and handles empty results', () async {
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'id': 'x'}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).rerank('rerank-english-v4.0');

      final result = await model.doRerank(
        const RerankModelV1CallOptions(query: 'q', documents: ['a', 'b']),
      );

      expect(captured.containsKey('top_n'), isFalse);
      expect(result.documents, isEmpty);
    });
  });

  group('Cohere doGenerate message serialization', () {
    test('serializes system, file-image, and tool-content messages', () async {
      final imageB64 = base64Encode(utf8.encode('file-bytes'));
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'finish_reason': 'COMPLETE',
            'message': {
              'content': [
                {'type': 'text', 'text': 'done'},
              ],
            },
            'usage': {
              'tokens': {'input_tokens': 2, 'output_tokens': 3},
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      final result = await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            // Top-level system prompt -> system message (line 98).
            system: 'You are helpful.',
            messages: [
              // Explicit system role message -> 'system' switch arm (line 105).
              LanguageModelV4Message(
                role: LanguageModelV4Role.system,
                content: [LanguageModelV4TextPart(text: 'Stay concise.')],
              ),
              // File part with image/* media type -> image_url (lines 187-193).
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  LanguageModelV4TextPart(text: 'look'),
                  LanguageModelV4FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('file-bytes')),
                    ),
                    mediaType: 'image/jpeg',
                  ),
                ],
              ),
              // Tool result with content parts -> ToolResultOutputContent
              // branch (lines 204-208).
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call_9',
                    toolName: 'search',
                    output: ToolResultOutputContent([
                      LanguageModelV4TextPart(text: 'line one'),
                      LanguageModelV4TextPart(text: 'line two'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          // max_tokens (line 255) + stop_sequences (line 260) body fields.
          maxOutputTokens: 256,
          stopSequences: const ['STOP'],
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();

      // First message: the top-level system prompt.
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], 'You are helpful.');

      // Second message: the explicit system-role message.
      expect(messages[1]['role'], 'system');
      expect(messages[1]['content'], 'Stay concise.');

      // Third message: user with text + file image rendered as content array.
      expect(messages[2]['role'], 'user');
      final userContent = (messages[2]['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(userContent[0]['type'], 'text');
      expect(userContent[0]['text'], 'look');
      expect(userContent[1]['type'], 'image_url');
      expect(
        (userContent[1]['image_url'] as Map)['url'],
        'data:image/jpeg;base64,$imageB64',
      );

      // Fourth message: tool result text joined from content parts.
      expect(messages[3]['role'], 'tool');
      expect(messages[3]['tool_call_id'], 'call_9');
      expect(messages[3]['content'], 'line one\nline two');

      // Body-level options.
      expect(captured['max_tokens'], 256);
      expect(captured['stop_sequences'], ['STOP']);

      expect(result.finishReason, LanguageModelV4FinishReason.stop);
    });

    test('serializes assistant tool calls with a tool_plan', () async {
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'finish_reason': 'COMPLETE',
            'message': {
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            },
            'usage': {
              'tokens': {'input_tokens': 1, 'output_tokens': 1},
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              // Assistant message with text (tool_plan) + tool call
              // (lines 131-148).
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [
                  LanguageModelV4TextPart(text: 'I will check the weather.'),
                  LanguageModelV4ToolCallPart(
                    toolCallId: 'call_5',
                    toolName: 'weather',
                    input: {'city': 'Berlin'},
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final assistant = messages.single;
      expect(assistant['role'], 'assistant');
      expect(assistant['tool_plan'], 'I will check the weather.');
      final toolCalls = (assistant['tool_calls'] as List)
          .cast<Map<String, dynamic>>();
      expect(toolCalls.single['id'], 'call_5');
      expect(toolCalls.single['type'], 'function');
      final fn = toolCalls.single['function'] as Map<String, dynamic>;
      expect(fn['name'], 'weather');
      expect(fn['arguments'], jsonEncode({'city': 'Berlin'}));
    });

    test('maps specific tool choice to REQUIRED', () async {
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'finish_reason': 'COMPLETE',
            'message': {
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            },
            'usage': {
              'tokens': {'input_tokens': 1, 'output_tokens': 1},
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'hi')],
              ),
            ],
          ),
          tools: const [
            LanguageModelV4FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          // ToolChoiceSpecific -> REQUIRED (line 241).
          toolChoice: const ToolChoiceSpecific(toolName: 'weather'),
        ),
      );

      expect(captured['tool_choice'], 'REQUIRED');
    });

    test('generates a tool call id when the response omits one', () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'finish_reason': 'TOOL_CALL',
            'message': {
              'content': <Map<String, dynamic>>[],
              'tool_calls': [
                {
                  // No 'id' field -> _generateId() (line 489).
                  'type': 'function',
                  'function': {
                    'name': 'weather',
                    'arguments': '{"city":"Rome"}',
                  },
                },
              ],
            },
            'usage': {
              'tokens': {'input_tokens': 1, 'output_tokens': 1},
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      final result = await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'weather?')],
              ),
            ],
          ),
        ),
      );

      final toolCall = result.content
          .whereType<LanguageModelV4ToolCallPart>()
          .single;
      expect(toolCall.toolName, 'weather');
      expect(toolCall.toolCallId, isNotEmpty);
      expect(toolCall.toolCallId, startsWith('cohere-tool-'));
      expect(toolCall.input, {'city': 'Rome'});
    });
  });

  group('Cohere image url resolution', () {
    test('serializes a base64 image part as a data URI', () async {
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'finish_reason': 'COMPLETE',
            'message': {
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            },
            'usage': {
              'tokens': {'input_tokens': 1, 'output_tokens': 1},
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  // DataContentBase64 -> uses the base64 string directly
                  // (line 474).
                  LanguageModelV4ImagePart(
                    image: const DataContentBase64('QUJD'),
                    mediaType: 'image/webp',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final content = (messages.single['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(content.single['type'], 'image_url');
      expect(
        (content.single['image_url'] as Map)['url'],
        'data:image/webp;base64,QUJD',
      );
    });

    test('serializes a URL image part as the raw url', () async {
      late Map<String, dynamic> captured;

      final server = await TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'finish_reason': 'COMPLETE',
            'message': {
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            },
            'usage': {
              'tokens': {'input_tokens': 1, 'output_tokens': 1},
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  // DataContentUrl -> raw URL string (line 471).
                  LanguageModelV4ImagePart(
                    image: DataContentUrl(
                      Uri.parse('https://example.com/cat.png'),
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
      final content = (messages.single['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        (content.single['image_url'] as Map)['url'],
        'https://example.com/cat.png',
      );
    });
  });

  group('Cohere doStream', () {
    test('emits text deltas from content-delta events', () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '${jsonEncode({
            'type': 'content-delta',
            'delta': {
              'message': {
                'content': {'text': 'Hello'},
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'content-delta',
            'delta': {
              'message': {
                'content': {'text': ' world'},
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'message-end',
            'delta': {
              'finish_reason': 'COMPLETE',
              'usage': {
                'tokens': {'input_tokens': 5, 'output_tokens': 6},
              },
            },
          })}\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(
          includeRawChunks: true,
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'hi')],
              ),
            ],
          ),
        ),
      );

      final parts = await streamResult.stream.toList();
      final deltas = parts.whereType<StreamPartTextDelta>().toList();
      expect(parts.whereType<StreamPartRaw>(), isNotEmpty);
      expect(deltas.map((d) => d.delta).join(), 'Hello world');
      expect(deltas.every((d) => d.id == 'text-0'), isTrue);
      expect(parts.whereType<StreamPartTextStart>().single.id, 'text-0');
      expect(parts.whereType<StreamPartTextEnd>().single.id, 'text-0');

      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV4FinishReason.stop);
      expect(finish.usage.inputTokens.total, 5);
      expect(finish.usage.outputTokens.total, 6);
    });

    test('emits tool-call-start args delta when start carries args', () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        // tool-call-start with non-empty arguments -> lines 386-388.
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-start',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'id': 'call_7',
                  'type': 'function',
                  'function': {'name': 'weather', 'arguments': '{"city":"Oslo"}'},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({'type': 'tool-call-end', 'index': 0})}\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'weather?')],
              ),
            ],
          ),
        ),
      );

      final parts = await streamResult.stream.toList();
      final start = parts.whereType<StreamPartToolInputStart>().single;
      expect(start.id, 'call_7');
      expect(start.toolName, 'weather');

      // The start event carried args, so a delta is emitted from within
      // tool-call-start handling.
      final delta = parts.whereType<StreamPartToolInputDelta>().single;
      expect(delta.id, 'call_7');
      expect(delta.delta, '{"city":"Oslo"}');

      final end = parts.whereType<StreamPartToolInputEnd>().single;
      expect(end.id, 'call_7');
      expect(parts.whereType<StreamPartToolCall>().single.toolCall.input, {
        'city': 'Oslo',
      });
    });

    test('connection failure surfaces as AiApiCallError', () async {
      // Bind a server, capture its port, then close it so the connection is
      // refused before doStream's request even completes.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadBaseUrl = 'http://${probe.address.host}:${probe.port}';
      await probe.close(force: true);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: deadBaseUrl,
      ).call('command-r-plus');

      await expectLater(
        model.doStream(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [LanguageModelV4TextPart(text: 'hi')],
                ),
              ],
            ),
          ),
        ),
        throwsA(
          isA<AiApiCallError>().having(
            (e) => e.statusCode,
            'statusCode',
            isNull,
          ),
        ),
      );
    });

    test(
      'emits StreamPartError when the byte stream aborts mid-flight',
      () async {
        // Raw socket server: send valid HTTP headers promising a larger
        // content-length than the bytes actually written, then destroy the
        // socket. The response stream opens successfully, but reading the body
        // throws mid-flight, so _processStream's catchError handler emits a
        // StreamPartError (lines 338-340).
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close());
        server.listen((socket) {
          // Wait for the full request to arrive, then reply with headers that
          // promise more body than we send so the stream opens but the read
          // aborts mid-body.
          socket.listen(
            (_) {},
            onDone: () => socket.destroy(),
            onError: (_) => socket.destroy(),
          );
          const body = '{"type":"content-delta"';
          socket.write(
            'HTTP/1.1 200 OK\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: 4096\r\n'
            '\r\n'
            '$body',
          );
          // Flush headers + partial body, give dio time to resolve post() and
          // start consuming the body stream, then forcibly abort.
          socket.flush().then((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 200));
            socket.destroy();
          });
        });
        final baseUrl = 'http://${server.address.host}:${server.port}';

        final model = CohereProvider(
          apiKey: 'test',
          baseUrl: baseUrl,
        ).call('command-r-plus');

        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [LanguageModelV4TextPart(text: 'hi')],
                ),
              ],
            ),
          ),
        );
        final parts = await streamResult.stream.toList();
        expect(parts.whereType<StreamPartError>(), isNotEmpty);
      },
    );
  });
}
