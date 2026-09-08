import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/cancellation_adapter.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  group('CohereProvider', () {
    test('creates language model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider('command-r-plus');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'command-r-plus');
      expect(model.specificationVersion, 'v4');
    });

    test('creates embedding model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider.embedding('embed-english-v4.0');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'embed-english-v4.0');
      expect(model.specificationVersion, 'v2');
    });

    test('creates rerank model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider.rerank('rerank-english-v4.0');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'rerank-english-v4.0');
      expect(model.specificationVersion, 'v1');
    });
  });

  group('Cohere doGenerate wire format', () {
    test(
      'serializes tools, tool_choice, and image content; parses tool calls',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));
        late Map<String, dynamic> captured;

        final server = await TestServer.start((request) async {
          expect(request.uri.path, '/chat');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'finish_reason': 'TOOL_CALL',
              'message': {
                'content': [
                  {'type': 'text', 'text': 'Let me check.'},
                ],
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
              'usage': {
                'tokens': {'input_tokens': 12, 'output_tokens': 7},
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
                  content: [
                    LanguageModelV4TextPart(text: 'describe this'),
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
            tools: const [
              LanguageModelV4FunctionTool(
                name: 'weather',
                description: 'Get the weather',
                inputSchema: {'type': 'object'},
              ),
            ],
            toolChoice: const ToolChoiceRequired(),
          ),
        );

        // Tools serialized into the Cohere v2 tools field.
        final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
        final fn = tools.single['function'] as Map<String, dynamic>;
        expect(tools.single['type'], 'function');
        expect(fn['name'], 'weather');
        expect(fn['description'], 'Get the weather');
        expect(fn['parameters'], {'type': 'object'});
        expect(captured['tool_choice'], 'REQUIRED');

        // Image content serialized (not dropped) into a content array.
        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        final userContent = (messages.first['content'] as List)
            .cast<Map<String, dynamic>>();
        expect(userContent[0]['type'], 'text');
        expect(userContent[1]['type'], 'image_url');
        expect(
          (userContent[1]['image_url'] as Map)['url'],
          'data:image/png;base64,$imageB64',
        );

        // Tool calls parsed out of the response.
        expect(result.finishReason, LanguageModelV4FinishReason.toolCalls);
        final toolCall = result.content
            .whereType<LanguageModelV4ToolCallPart>()
            .single;
        expect(toolCall.toolName, 'weather');
        expect(toolCall.input, {'city': 'Paris'});
        expect(result.usage.inputTokens.total, 12);
        expect(result.usage.outputTokens.total, 7);
      },
    );

    test('maps tool choice none and serializes tool-result messages', () async {
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
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'weather',
                    output: ToolResultOutputText('sunny'),
                  ),
                ],
              ),
            ],
          ),
          tools: const [
            LanguageModelV4FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceNone(),
        ),
      );

      expect(captured['tool_choice'], 'NONE');
      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final toolMessage = messages.single;
      expect(toolMessage['role'], 'tool');
      expect(toolMessage['tool_call_id'], 'call_1');
      expect(toolMessage['content'], 'sunny');
    });

    test('credentials are resolved immediately before each request', () async {
      final authorizations = <String?>[];
      final server = await TestServer.start((request) async {
        authorizations.add(request.headers.value('authorization'));
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
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      var token = 'first-key';
      final provider = CohereProvider(
        baseUrl: server.baseUrl,
        credentialProvider: () async => token,
      );

      await provider
          .call('command-r-plus')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      token = 'second-key';
      await provider
          .call('command-r-plus')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(authorizations, ['Bearer first-key', 'Bearer second-key']);
    });

    test('reuses an injected client across multiple requests', () async {
      final server = await TestServer.start((request) async {
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
          }),
        );
        await request.response.close();
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

      final provider = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
        client: client,
      );

      await provider
          .call('command-r-plus')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      await provider
          .call('command-r-plus')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(interceptedRequests, 2);
    });

    test(
      'doGenerate cancels an in-flight Dio request via abortSignal',
      () async {
        final adapter = CancellationHttpClientAdapter();
        final client = _cancellationClient(adapter, 'http://localhost');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal();
        final model = CohereProvider(
          apiKey: 'test',
          baseUrl: 'http://localhost',
          client: client,
        ).call('command-r-plus');

        final future = model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: userPrompt('hi'),
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
        final adapter = CancellationHttpClientAdapter();
        final client = _cancellationClient(adapter, 'http://localhost');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal()..cancel();
        final model = CohereProvider(
          apiKey: 'test',
          baseUrl: 'http://localhost',
          client: client,
        ).call('command-r-plus');

        await expectLater(
          model.doGenerate(
            LanguageModelV4CallOptions(
              prompt: userPrompt('hi'),
              abortSignal: abortSignal,
            ),
          ),
          throwsA(isA<AiOperationCancelledError>()),
        );
        expect(adapter.fetchCount, 0);
      },
    );

    test('doStream cancels the Dio handshake via abortSignal', () async {
      final adapter = CancellationHttpClientAdapter();
      final client = _cancellationClient(adapter, 'http://localhost');
      addTearDown(() => client.close(force: true));
      final abortSignal = TestAbortSignal();
      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: 'http://localhost',
        client: client,
      ).call('command-r-plus');

      final future = model.doStream(
        LanguageModelV4CallOptions(
          prompt: userPrompt('hi'),
          abortSignal: abortSignal,
        ),
      );

      await adapter.fetchStarted.future;
      expect(adapter.lastOptions?.cancelToken, isNotNull);
      abortSignal.cancel();

      await expectLater(future, throwsA(isA<AiOperationCancelledError>()));
      expect(adapter.fetchCount, 1);
    });

    test(
      'stream, embedding, and rerank resolve credentials per dispatch',
      () async {
        final authorizations = <String, String?>{};
        final server = await TestServer.start((request) async {
          authorizations[request.uri.path] = request.headers.value(
            'authorization',
          );
          switch (request.uri.path) {
            case '/chat':
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                '${jsonEncode({
                  'type': 'message-start',
                  'delta': {
                    'message': {'role': 'assistant'},
                  },
                })}\n',
              );
              request.response.write(
                '${jsonEncode({
                  'type': 'text-generation',
                  'delta': {'text': 'ok'},
                })}\n',
              );
              request.response.write(
                '${jsonEncode({
                  'type': 'message-end',
                  'delta': {'finish_reason': 'COMPLETE'},
                })}\n',
              );
              break;
            case '/embed':
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'embeddings': {
                    'float': [
                      [0.1, 0.2],
                    ],
                  },
                }),
              );
              break;
            case '/rerank':
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'results': [
                    {'index': 0, 'relevance_score': 0.9},
                  ],
                }),
              );
              break;
            default:
              fail('Unexpected path: ${request.uri.path}');
          }
          await request.response.close();
        });
        addTearDown(server.close);

        var token = 'stream-token';
        final provider = CohereProvider(
          baseUrl: server.baseUrl,
          credentialProvider: () async => token,
        );

        final stream = await provider
            .call('command-r-plus')
            .doStream(LanguageModelV4CallOptions(prompt: userPrompt('stream')));
        await stream.stream.drain<void>();

        token = 'embed-token';
        await provider
            .embedding('embed-v4.0')
            .doEmbed(const EmbeddingModelV2CallOptions(values: ['a']));

        token = 'rerank-token';
        await provider
            .rerank('rerank-v4.5')
            .doRerank(
              const RerankModelV1CallOptions(query: 'q', documents: ['doc']),
            );

        expect(authorizations, {
          '/chat': 'Bearer stream-token',
          '/embed': 'Bearer embed-token',
          '/rerank': 'Bearer rerank-token',
        });
      },
    );

    test(
      'normalizes numeric vectors and ignores response rows beyond the input',
      () async {
        final server = await TestServer.start((request) async {
          await utf8.decoder.bind(request).join();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'embeddings': {
                'float': [
                  [1, 2.5],
                  [-3, 4],
                  [99],
                ],
              },
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final result =
            await CohereProvider(apiKey: 'key', baseUrl: server.baseUrl)
                .embedding('embed-v4.0')
                .doEmbed(
                  const EmbeddingModelV2CallOptions<String>(values: ['a', 'b']),
                );

        expect(result.embeddings, hasLength(2));
        expect(result.embeddings.map((embedding) => embedding.value), [
          'a',
          'b',
        ]);
        expect(result.embeddings.map((embedding) => embedding.embedding), [
          [1.0, 2.5],
          [-3.0, 4.0],
        ]);
      },
    );

    test(
      'dispose closes owned clients and leaves injected clients open',
      () async {
        final server = await TestServer.start((request) async {
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
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final ownedProvider = CohereProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        );
        ownedProvider.dispose();
        await expectLater(
          ownedProvider
              .call('command-r-plus')
              .doGenerate(
                LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
              ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = CohereProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider
            .call('command-r-plus')
            .doGenerate(
              LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
            );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );

    test('parses tool calls from the NDJSON stream', () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-start',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'weather', 'arguments': ''},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-delta',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'function': {'arguments': '{"city":"Paris"}'},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({'type': 'tool-call-end', 'index': 0})}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'message-end',
            'delta': {
              'finish_reason': 'TOOL_CALL',
              'usage': {
                'tokens': {'input_tokens': 3, 'output_tokens': 4},
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
      expect(start.toolName, 'weather');
      expect(start.id, 'call_1');
      final end = parts.whereType<StreamPartToolInputEnd>().single;
      expect(end.id, 'call_1');
      expect(parts.whereType<StreamPartToolCall>().single.toolCall.input, {
        'city': 'Paris',
      });
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV4FinishReason.toolCalls);
      expect(finish.usage.inputTokens.total, 3);
      expect(finish.usage.outputTokens.total, 4);
    });

    test('finalizes buffered tool calls once at message end', () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-start',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'id': 'call_implicit_end',
                  'type': 'function',
                  'function': {'name': 'weather', 'arguments': '{"city":"'},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-delta',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'function': {'arguments': 'Paris","unit":"C"}'},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'message-end',
            'delta': {
              'finish_reason': 'TOOL_CALL',
              'usage': {
                'tokens': {'input_tokens': 6, 'output_tokens': 8},
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
      expect(start.id, 'call_implicit_end');
      expect(start.toolName, 'weather');

      final deltas = parts.whereType<StreamPartToolInputDelta>().toList();
      expect(deltas, hasLength(2));
      expect(
        deltas.map((delta) => delta.delta).join(),
        '{"city":"Paris","unit":"C"}',
      );

      final ends = parts.whereType<StreamPartToolInputEnd>().toList();
      expect(ends, hasLength(1));
      final end = ends.single;
      expect(end.id, 'call_implicit_end');

      final toolCallPart = parts.whereType<StreamPartToolCall>().single;
      expect(toolCallPart.toolCall.toolCallId, 'call_implicit_end');
      expect(toolCallPart.toolCall.toolName, 'weather');
      expect(toolCallPart.toolCall.input, {'city': 'Paris', 'unit': 'C'});

      final finish = parts.whereType<StreamPartFinish>().single;
      expect(parts.indexOf(end), lessThan(parts.indexOf(toolCallPart)));
      expect(parts.indexOf(toolCallPart), lessThan(parts.indexOf(finish)));
      expect(finish.finishReason, LanguageModelV4FinishReason.toolCalls);
      expect(finish.usage.inputTokens.total, 6);
      expect(finish.usage.outputTokens.total, 8);
    });

    test('does not duplicate an explicit tool-call-end at message end', () async {
      final server = await TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-start',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'id': 'call_explicit_end',
                  'type': 'function',
                  'function': {'name': 'weather', 'arguments': '{"city":"Berlin"}'},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({'type': 'tool-call-end', 'index': 0})}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'message-end',
            'delta': {
              'finish_reason': 'TOOL_CALL',
              'usage': {
                'tokens': {'input_tokens': 2, 'output_tokens': 3},
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
      final ends = parts.whereType<StreamPartToolInputEnd>().toList();
      expect(ends, hasLength(1));
      expect(ends.single.id, 'call_explicit_end');

      final toolCallPart = parts.whereType<StreamPartToolCall>().single;
      expect(toolCallPart.toolCall.toolCallId, 'call_explicit_end');
      expect(toolCallPart.toolCall.toolName, 'weather');
      expect(toolCallPart.toolCall.input, {'city': 'Berlin'});

      final finish = parts.whereType<StreamPartFinish>().single;
      expect(parts.indexOf(ends.single), lessThan(parts.indexOf(toolCallPart)));
      expect(parts.indexOf(toolCallPart), lessThan(parts.indexOf(finish)));
      expect(finish.usage.inputTokens.total, 2);
      expect(finish.usage.outputTokens.total, 3);
    });

    test(
      'finalizes interleaved pending tool-call indexes in sorted order before finish',
      () async {
        final server = await TestServer.start((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '${jsonEncode({
              'type': 'tool-call-start',
              'index': 1,
              'delta': {
                'message': {
                  'tool_calls': {
                    'id': 'call_2',
                    'type': 'function',
                    'function': {'name': 'forecast', 'arguments': '{"days":'},
                  },
                },
              },
            })}\n',
          );
          request.response.write(
            '${jsonEncode({
              'type': 'tool-call-start',
              'index': 0,
              'delta': {
                'message': {
                  'tool_calls': {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {'name': 'weather', 'arguments': '{"city":"'},
                  },
                },
              },
            })}\n',
          );
          request.response.write(
            '${jsonEncode({
              'type': 'tool-call-delta',
              'index': 1,
              'delta': {
                'message': {
                  'tool_calls': {
                    'function': {'arguments': '5,"unit":"C"}'},
                  },
                },
              },
            })}\n',
          );
          request.response.write(
            '${jsonEncode({
              'type': 'tool-call-delta',
              'index': 0,
              'delta': {
                'message': {
                  'tool_calls': {
                    'function': {'arguments': 'Paris"}'},
                  },
                },
              },
            })}\n',
          );
          request.response.write(
            '${jsonEncode({
              'type': 'message-end',
              'delta': {
                'finish_reason': 'TOOL_CALL',
                'usage': {
                  'tokens': {'input_tokens': 7, 'output_tokens': 9},
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
        final ends = parts.whereType<StreamPartToolInputEnd>().toList();
        expect(ends, hasLength(2));
        expect(ends.map((end) => end.id).toList(), ['call_1', 'call_2']);
        final toolCalls = parts.whereType<StreamPartToolCall>().toList();
        expect(toolCalls, hasLength(2));
        expect(toolCalls.map((part) => part.toolCall.toolName).toList(), [
          'weather',
          'forecast',
        ]);
        expect(toolCalls[0].toolCall.input, {'city': 'Paris'});
        expect(toolCalls[1].toolCall.input, {'days': 5, 'unit': 'C'});

        final finish = parts.whereType<StreamPartFinish>().single;
        expect(parts.indexOf(ends[0]), lessThan(parts.indexOf(toolCalls[0])));
        expect(parts.indexOf(toolCalls[0]), lessThan(parts.indexOf(ends[1])));
        expect(parts.indexOf(ends[1]), lessThan(parts.indexOf(toolCalls[1])));
        expect(parts.indexOf(toolCalls[1]), lessThan(parts.indexOf(finish)));
        expect(finish.finishReason, LanguageModelV4FinishReason.toolCalls);
        expect(finish.usage.inputTokens.total, 7);
        expect(finish.usage.outputTokens.total, 9);
      },
    );
  });
}

Dio _cancellationClient(HttpClientAdapter adapter, String baseUrl) {
  final client = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {'Content-Type': 'application/json'},
      responseType: ResponseType.json,
    ),
  );
  client.httpClientAdapter = adapter;
  return client;
}
