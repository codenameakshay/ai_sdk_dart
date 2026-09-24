import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/contract/language_model_contract.dart';
import '../../ai_sdk_provider/test/support/cancellation_adapter.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  test('default provider exposes the Anthropic model contract', () {
    expect(anthropic('claude-sonnet-4-5').provider, 'anthropic');
    expect(anthropic('claude-sonnet-4-5').modelId, 'claude-sonnet-4-5');
  });

  test(
    'rejects provider-only prompt parts and maps legacy reasoning none',
    () async {
      final server = await _startServer((request) async {
        final body =
            (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                .cast<String, dynamic>();
        final thinking = body['thinking'];
        expect(thinking, {'type': 'disabled'});
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'content': []}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-3-7-sonnet-20250219');
      await expectLater(
        model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    const LanguageModelV4DocumentSourcePart(
                      id: 'doc',
                      mediaType: 'application/pdf',
                      title: 'doc',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        throwsUnsupportedError,
      );
      await expectLater(
        model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    const LanguageModelV4ReasoningFilePart(
                      data: DataContentBase64('YQ=='),
                      mediaType: 'text/plain',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        throwsUnsupportedError,
      );

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: userPrompt('none'),
          reasoning: LanguageModelV4Reasoning.none,
        ),
      );
    },
  );

  test('stream preserves reasoning signatures and cache-only usage', () async {
    final server = await _startServer((request) async {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"type":"message_start","message":{"usage":{"cache_read_input_tokens":7}}}\n\n'
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","id":"reason-0"}}\n\n'
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"signed"}}\n\n'
        'data: {"type":"message_delta","usage":{"output_tokens":2},"delta":{"stop_reason":"end_turn"}}\n\n',
      );
      await request.response.close();
    });
    addTearDown(server.close);

    final result =
        await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
            .call('claude-sonnet-4-5')
            .doStream(LanguageModelV4CallOptions(prompt: userPrompt('reason')));
    final parts = await result.stream.toList();
    final reasoningEnd = parts.whereType<StreamPartReasoningEnd>().single;
    expect(reasoningEnd.signature, 'signed');
    expect(reasoningEnd.providerMetadata?['anthropic'], {
      'signature': 'signed',
    });
    final finish = parts.whereType<StreamPartFinish>().single;
    expect(finish.usage.inputTokens.total, 7);
    expect(finish.usage.outputTokens.total, 2);
  });

  test('empty stream still starts and closes cleanly', () async {
    final server = await _startServer((request) async {
      request.response.statusCode = 200;
      request.response.headers.set('content-type', 'text/event-stream');
      await request.response.close();
    });
    addTearDown(server.close);

    final result =
        await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
            .call('claude-sonnet-4-5')
            .doStream(LanguageModelV4CallOptions(prompt: userPrompt('empty')));
    expect(
      await result.stream.toList(),
      contains(isA<StreamPartStreamStart>()),
    );
  });

  group('AnthropicProvider', () {
    test('rejects null and malformed 2xx chat responses', () async {
      final nullServer = await _startServer((request) async {
        request.response.statusCode = 200;
        await request.response.close();
      });
      addTearDown(nullServer.close);

      await expectLater(
        AnthropicProvider(apiKey: 'test', baseUrl: nullServer.baseUrl)
            .call('claude-sonnet-4-5')
            .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('hi'))),
        throwsA(
          isA<AiApiCallError>()
              .having((error) => error.statusCode, 'statusCode', 200)
              .having((error) => error.url, 'url', contains('/v1/messages'))
              .having((error) => error.cause, 'cause', isNull),
        ),
      );

      final malformedServer = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'content': 'not-a-list'}));
        await request.response.close();
      });
      addTearDown(malformedServer.close);

      await expectLater(
        AnthropicProvider(apiKey: 'test', baseUrl: malformedServer.baseUrl)
            .call('claude-sonnet-4-5')
            .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('hi'))),
        throwsA(
          isA<AiApiCallError>()
              .having((error) => error.statusCode, 'statusCode', 200)
              .having((error) => error.cause, 'cause', isNotNull),
        ),
      );
    });

    test('allows absent optional chat output', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({}));
        await request.response.close();
      });
      addTearDown(server.close);

      final result =
          await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
              .call('claude-sonnet-4-5')
              .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('hi')));
      expect(result.content, isEmpty);
    });

    test('rejects malformed nested 2xx chat response fields', () async {
      final cases = <Map<String, dynamic>>[
        {
          'content': [
            {
              'type': 'text',
              'text': 'citation',
              'citations': ['invalid'],
            },
          ],
        },
        {
          'content': [
            {'type': 'text', 'text': 'citation', 'citations': 'invalid'},
          ],
        },
        {'usage': 'invalid'},
      ];

      for (final body in cases) {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
          await request.response.close();
        });

        try {
          await expectLater(
            AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
                .call('claude-sonnet-4-5')
                .doGenerate(
                  LanguageModelV4CallOptions(prompt: userPrompt('hi')),
                ),
            throwsA(isA<AiApiCallError>()),
          );
        } finally {
          await server.close();
        }
      }
    });

    test('doGenerate maps text/tool_use/reasoning and usage', () async {
      final server = await _startServer((request) async {
        expect(request.uri.path, '/v1/messages');
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'msg_1',
            'model': 'claude-sonnet-4-5',
            'stop_reason': 'tool_use',
            'content': [
              {
                'type': 'thinking',
                'thinking': 'Need weather lookup',
                'signature': 'sig1',
              },
              {'type': 'text', 'text': 'Let me check that.'},
              {
                'type': 'tool_use',
                'id': 'toolu_1',
                'name': 'weather',
                'input': {'city': 'Paris'},
              },
            ],
            'usage': {'input_tokens': 12, 'output_tokens': 8},
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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

      expect(result.finishReason, LanguageModelV4FinishReason.toolCalls);
      expect(result.usage.inputTokens.total, 12);
      // No cache fields in the response -> no input token breakdown.
      expect(result.usage.inputTokens.noCache, isNull);
      expect(result.usage.inputTokens.cacheRead, isNull);
      expect(result.usage.inputTokens.cacheWrite, isNull);
      expect(
        result.content.whereType<LanguageModelV4ReasoningPart>().length,
        1,
      );
      expect(
        result.content.whereType<LanguageModelV4ToolCallPart>().single.toolName,
        'weather',
      );
    });

    test(
      'preserves signed and redacted thinking across tool continuation',
      () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          captured =
              (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                  .cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'msg_2',
              'model': 'claude-sonnet-4-5',
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'done'},
              ],
              'usage': {'input_tokens': 2, 'output_tokens': 1},
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);
        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.assistant,
                  content: [
                    LanguageModelV4ReasoningPart(
                      text: 'think',
                      signature: 'sig-fragment-1sig-fragment-2',
                    ),
                    LanguageModelV4RedactedReasoningPart(
                      data: Uint8List.fromList([1, 2, 3]),
                    ),
                    LanguageModelV4ToolCallPart(
                      toolCallId: 'toolu_1',
                      toolName: 'weather',
                      input: {'city': 'Paris'},
                    ),
                  ],
                ),
                LanguageModelV4Message(
                  role: LanguageModelV4Role.tool,
                  content: [
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'toolu_1',
                      toolName: 'weather',
                      output: ToolResultOutputText('sunny'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        final messages = (captured['messages'] as List).cast<Map>();
        final assistant = messages.firstWhere((m) => m['role'] == 'assistant');
        final content = (assistant['content'] as List).cast<Map>();
        expect(content[0], {
          'type': 'thinking',
          'thinking': 'think',
          'signature': 'sig-fragment-1sig-fragment-2',
        });
        expect(content[1]['type'], 'redacted_thinking');
        expect(content[2]['id'], 'toolu_1');
        final tool = messages.firstWhere((m) => m['role'] == 'user');
        expect((tool['content'] as List).single['tool_use_id'], 'toolu_1');
      },
    );

    test('doStream parses content and message delta events', () async {
      final server = await _startServer((request) async {
        expect(request.uri.path, '/v1/messages');
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"weather"}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"city\\":\\"Paris\\"}"}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_stop","index":1}\n\n',
        );
        request.response.write(
          'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');
      final stream = await model.doStream(
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

      final parts = await stream.stream.toList();
      expect(
        parts.whereType<StreamPartTextDelta>().map((e) => e.delta).join(),
        'Hello',
      );
      expect(
        parts.whereType<StreamPartToolInputStart>().single.toolName,
        'weather',
      );
      expect(
        parts.whereType<StreamPartToolCall>().single.toolCall.input,
        isA<Map>(),
      );
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.toolCalls,
      );
    });

    test('credentials are resolved immediately before each request', () async {
      final apiKeys = <String?>[];
      final server = await _startServer((request) async {
        apiKeys.add(request.headers.value('x-api-key'));
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      var token = 'first-key';
      final provider = AnthropicProvider(
        baseUrl: server.baseUrl,
        credentialProvider: () async => token,
      );

      await provider
          .call('claude-sonnet-4-5')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      token = 'second-key';
      await provider
          .call('claude-sonnet-4-5')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(apiKeys, ['first-key', 'second-key']);
    });

    test('reuses an injected client across multiple requests', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
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

      final provider = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
        client: client,
      );

      await provider
          .call('claude-sonnet-4-5')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      await provider
          .call('claude-sonnet-4-5')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(interceptedRequests, 2);
    });

    test(
      'doGenerate cancels an in-flight Dio request via abortSignal',
      () async {
        final adapter = CancellationHttpClientAdapter();
        final client = _cancellationClient(adapter, 'http://localhost/v1');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal();
        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: 'http://localhost/v1',
          client: client,
        ).call('claude-sonnet-4-5');

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
        final client = _cancellationClient(adapter, 'http://localhost/v1');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal()..cancel();
        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: 'http://localhost/v1',
          client: client,
        ).call('claude-sonnet-4-5');

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
      final client = _cancellationClient(adapter, 'http://localhost/v1');
      addTearDown(() => client.close(force: true));
      final abortSignal = TestAbortSignal();
      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: 'http://localhost/v1',
        client: client,
      ).call('claude-sonnet-4-5');

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
      'dispose closes owned clients and leaves injected clients open',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final ownedProvider = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        );
        ownedProvider.dispose();
        await expectLater(
          ownedProvider
              .call('claude-sonnet-4-5')
              .doGenerate(
                LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
              ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider
            .call('claude-sonnet-4-5')
            .doGenerate(
              LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
            );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );

    test('maps tool choice modes to anthropic wire format', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        seenBodies.add((jsonDecode(body) as Map).cast<String, dynamic>());

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      Future<void> call(LanguageModelV4ToolChoice toolChoice) async {
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
            toolChoice: toolChoice,
          ),
        );
      }

      await call(const ToolChoiceAuto());
      await call(const ToolChoiceNone());
      await call(const ToolChoiceRequired());
      await call(const ToolChoiceSpecific(toolName: 'weather'));

      expect(seenBodies[0]['tool_choice'], {'type': 'auto'});
      expect(seenBodies[1]['tool_choice'], {'type': 'auto'});
      expect(seenBodies[2]['tool_choice'], {'type': 'any'});
      expect(seenBodies[3]['tool_choice'], {'type': 'tool', 'name': 'weather'});
    });

    test('forwards tool input examples to anthropic input_examples', () async {
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        final jsonBody = (jsonDecode(body) as Map).cast<String, dynamic>();
        final tools = (jsonBody['tools'] as List).cast<Map<String, dynamic>>();
        expect(tools.single['input_examples'], [
          {'city': 'Paris'},
          {'city': 'Berlin'},
        ]);

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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
              inputExamples: [
                {'city': 'Paris'},
                {'city': 'Berlin'},
              ],
            ),
          ],
        ),
      );
    });

    test('extracts provider-native source parts from text citations', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'msg_1',
            'model': 'claude-sonnet-4-5',
            'stop_reason': 'end_turn',
            'content': [
              {
                'type': 'text',
                'text': 'see source',
                'citations': [
                  {'url': 'https://example.com/a', 'title': 'Example A'},
                ],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');
      final result = await model.doGenerate(
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

      final source = result.content
          .whereType<LanguageModelV4SourcePart>()
          .single;
      expect(source.url, 'https://example.com/a');
      expect(source.title, 'Example A');
    });

    test(
      'preserves invalid strict tool arguments for downstream failure handling',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'msg_1',
              'model': 'claude-sonnet-4-5',
              'stop_reason': 'tool_use',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 'toolu_1',
                  'name': 'weather',
                  'input': 'not-an-object',
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');
        final result = await model.doGenerate(
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
                strict: true,
              ),
            ],
          ),
        );

        final call = result.content
            .whereType<LanguageModelV4ToolCallPart>()
            .single;
        expect(call.input, 'not-an-object');
      },
    );

    test('passes providerOptions into request body', () async {
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        final jsonBody = jsonDecode(body) as Map<String, dynamic>;
        expect(jsonBody['metadata'], {'trace_id': 'abc'});

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      final result = await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'hi')],
              ),
            ],
          ),
          providerOptions: const {
            'anthropic': {
              'metadata': {'trace_id': 'abc'},
            },
          },
        ),
      );

      expect(
        result.content.whereType<LanguageModelV4TextPart>().single.text,
        'ok',
      );
    });

    test(
      'maps multimodal and tool result content to anthropic wire format',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));
        final fileB64 = base64Encode(utf8.encode('pdf'));

        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          final jsonBody = jsonDecode(body) as Map<String, dynamic>;
          final messages = (jsonBody['messages'] as List)
              .cast<Map<String, dynamic>>();

          final userContent = (messages.first['content'] as List)
              .cast<Map<String, dynamic>>();
          expect(userContent[1]['type'], 'image');
          expect(
            ((userContent[1]['source'] as Map)['data'] as String),
            imageB64,
          );
          expect(userContent[2]['type'], 'document');
          expect(
            ((userContent[2]['source'] as Map)['data'] as String),
            fileB64,
          );

          final toolContent = (messages.last['content'] as List)
              .cast<Map<String, dynamic>>();
          expect(toolContent.single['type'], 'tool_result');
          expect(toolContent.single['is_error'], isTrue);
          expect(toolContent.single['content'], isA<List>());

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

        final result = await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    LanguageModelV4TextPart(text: 'check these files'),
                    LanguageModelV4ImagePart(
                      image: DataContentBytes(
                        Uint8List.fromList(utf8.encode('img')),
                      ),
                      mediaType: 'image/png',
                    ),
                    LanguageModelV4FilePart(
                      data: DataContentBase64(fileB64),
                      mediaType: 'application/pdf',
                      filename: 'doc.pdf',
                    ),
                  ],
                ),
                LanguageModelV4Message(
                  role: LanguageModelV4Role.tool,
                  content: [
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'toolu_1',
                      toolName: 'weather',
                      isError: true,
                      output: ToolResultOutputContent([
                        LanguageModelV4TextPart(text: 'error payload'),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        expect(
          result.content.whereType<LanguageModelV4TextPart>().single.text,
          'ok',
        );
      },
    );

    test('stream finish includes usage and metadata', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"message_start","message":{"id":"msg_123","model":"claude-sonnet-4-5","usage":{"input_tokens":8,"output_tokens":1}}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}\n\n',
        );
        request.response.write(
          'data: {"type":"message_delta","warnings":["careful"],"usage":{"output_tokens":3},"delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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

      final finish = (await streamResult.stream.toList())
          .whereType<StreamPartFinish>()
          .single;
      expect(finish.usage.inputTokens.total, 8);
      expect(finish.usage.outputTokens.total, 3);
      expect(finish.providerMetadata?['anthropic']?['id'], 'msg_123');
      expect(
        finish.providerMetadata?['anthropic']?['warnings'],
        contains('other'),
      );
    });
    test(
      'stream emits raw chunks and closes explicit thinking and tool blocks',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'text/event-stream');
          request.response.write(
            'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","id":"thinking-1"}}\n\n',
          );
          request.response.write(
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"pondering"}}\n\n',
          );
          request.response.write(
            'data: {"type":"content_block_stop","index":0}\n\n',
          );
          request.response.write(
            'data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"lookup"}}\n\n',
          );
          request.response.write(
            'data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"city\\":\\"Paris\\"}"}}\n\n',
          );
          request.response.write(
            'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}\n\n',
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(
            prompt: userPrompt('hi'),
            includeRawChunks: true,
          ),
        );

        final parts = await streamResult.stream.toList();
        expect(parts.whereType<StreamPartRaw>(), isNotEmpty);
        expect(
          parts.whereType<StreamPartReasoningStart>().single.id,
          'thinking-1',
        );
        expect(
          parts.whereType<StreamPartReasoningEnd>().single.id,
          'thinking-1',
        );
        expect(parts.whereType<StreamPartToolInputEnd>().single.id, 'toolu_1');
        expect(parts.whereType<StreamPartToolCall>().single.toolCall.input, {
          'city': 'Paris',
        });
      },
    );
    test(
      'doGenerate maps cache_read/creation into V4 input token fields',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'msg_c',
              'model': 'claude-sonnet-4-5',
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'hi'},
              ],
              'usage': {
                'input_tokens': 10,
                'output_tokens': 5,
                'cache_read_input_tokens': 100,
                'cache_creation_input_tokens': 20,
              },
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

        final result = await model.doGenerate(
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

        // Anthropic reports cache tokens separately, so inputTokens is the sum:
        // input_tokens (10) + cache_read (100) + cache_creation (20) = 130.
        expect(result.usage.inputTokens.total, 130);
        expect(result.usage.outputTokens.total, 5);
        expect(result.usage.inputTokens.noCache, 10);
        expect(result.usage.inputTokens.cacheRead, 100);
        expect(result.usage.inputTokens.cacheWrite, 20);
      },
    );

    test('stream carries cache token fields from message_start to finish', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        // message_start carries the input/cache breakdown; the trailing
        // message_delta reports only output_tokens.
        request.response.write(
          'data: {"type":"message_start","message":{"id":"msg_c","model":"claude-sonnet-4-5","usage":{"input_tokens":8,"output_tokens":1,"cache_read_input_tokens":40,"cache_creation_input_tokens":0}}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}\n\n',
        );
        request.response.write(
          'data: {"type":"message_delta","usage":{"output_tokens":3},"delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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

      final finish = (await streamResult.stream.toList())
          .whereType<StreamPartFinish>()
          .single;
      // input_tokens (8) + cache_read (40) = 48; output from message_delta.
      expect(finish.usage.inputTokens.total, 48);
      expect(finish.usage.outputTokens.total, 3);
      // Cache breakdown captured at message_start survives the output-only delta.
      expect(finish.usage.inputTokens.noCache, 8);
      expect(finish.usage.inputTokens.cacheRead, 40);
      expect(finish.usage.inputTokens.cacheWrite, 0);
    });

    test('stream resets stale cache fields on an input-only delta', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"message_start","message":{"id":"msg_c2","model":"claude-sonnet-4-5","usage":{"input_tokens":8,"output_tokens":1,"cache_read_input_tokens":40,"cache_creation_input_tokens":2}}}\n\n',
        );
        request.response.write(
          'data: {"type":"message_delta","usage":{"input_tokens":9},"delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: userPrompt('hi')),
      );

      final finish = (await streamResult.stream.toList())
          .whereType<StreamPartFinish>()
          .single;
      expect(finish.usage.inputTokens.total, 9);
      expect(finish.usage.inputTokens.noCache, 9);
      expect(finish.usage.inputTokens.cacheRead, isNull);
      expect(finish.usage.inputTokens.cacheWrite, isNull);
      expect(finish.usage.outputTokens.total, 1);
    });

    // ── AnthropicThinkingOptions / speed ─────────────────────────────────

    group('AnthropicThinkingOptions', () {
      test('toMap produces enabled thinking object with budget_tokens', () {
        final opts = const AnthropicThinkingOptions(budgetTokens: 5000);
        final map = opts.toMap();
        expect(map['thinking'], {'type': 'enabled', 'budget_tokens': 5000});
      });

      test('toMap produces adaptive thinking object', () {
        expect(
          const AnthropicThinkingOptions(
            adaptive: true,
            budgetTokens: 5000,
          ).toMap()['thinking'],
          {'type': 'adaptive'},
        );
      });

      test('toMap produces disabled when enabled = false', () {
        final opts = const AnthropicThinkingOptions(enabled: false);
        final map = opts.toMap();
        expect(map['thinking'], {'type': 'disabled'});
      });

      test('toMap treats speed=fast as disabled', () {
        final opts = const AnthropicThinkingOptions(speed: 'fast');
        final map = opts.toMap();
        expect(map['thinking'], {'type': 'disabled'});
      });

      test('toMap omits budget_tokens when disabled', () {
        final opts = const AnthropicThinkingOptions(
          enabled: false,
          budgetTokens: 9999,
        );
        final map = opts.toMap();
        expect((map['thinking'] as Map).containsKey('budget_tokens'), isFalse);
      });

      test('AnthropicLanguageModelOptions wraps thinking', () {
        final langOpts = const AnthropicLanguageModelOptions(
          thinking: AnthropicThinkingOptions(budgetTokens: 2000),
          effort: 'high',
        );
        final map = langOpts.toMap();
        expect(map['thinking'], {'type': 'enabled', 'budget_tokens': 2000});
        expect(map['effort'], 'high');
      });

      test('maps portable reasoning to current adaptive effort', () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          captured =
              (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                  .cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'content': []}));
          await request.response.close();
        });
        addTearDown(server.close);

        await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
            .call('claude-sonnet-5')
            .doGenerate(
              LanguageModelV4CallOptions(
                prompt: userPrompt('reason'),
                reasoning: LanguageModelV4Reasoning.xhigh,
              ),
            );

        expect(captured['thinking'], {'type': 'adaptive'});
        expect((captured['output_config'] as Map)['effort'], 'max');
      });

      test('maps legacy reasoning to a bounded thinking budget', () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          captured =
              (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                  .cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'content': []}));
          await request.response.close();
        });
        addTearDown(server.close);

        await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
            .call('claude-3-7-sonnet-20250219')
            .doGenerate(
              LanguageModelV4CallOptions(
                prompt: userPrompt('reason'),
                maxOutputTokens: 4096,
                reasoning: LanguageModelV4Reasoning.high,
              ),
            );

        expect(captured['thinking'], {
          'type': 'enabled',
          'budget_tokens': 2458,
        });
      });

      test('serializes typed cache control options', () {
        const cache = AnthropicCacheControlOptions(ttl: '1h');
        expect(cache.toMap(), {
          'cache_control': {'type': 'ephemeral', 'ttl': '1h'},
        });
        expect(
          const AnthropicLanguageModelOptions(cacheControl: cache).toMap(),
          cache.toMap(),
        );
      });

      test(
        'doGenerate sends thinking object when passed via providerOptions',
        () async {
          late Map<String, dynamic> captured;
          final server = await _startServer((request) async {
            final body = await utf8.decoder.bind(request).join();
            captured = (jsonDecode(body) as Map).cast<String, dynamic>();
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'stop_reason': 'end_turn',
                'content': [
                  {'type': 'text', 'text': 'ok'},
                ],
              }),
            );
            await request.response.close();
          });
          addTearDown(server.close);

          final model = AnthropicProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('claude-3-7-sonnet-20250219');
          await model.doGenerate(
            LanguageModelV4CallOptions(
              prompt: LanguageModelV4Prompt(
                messages: [
                  LanguageModelV4Message(
                    role: LanguageModelV4Role.user,
                    content: [LanguageModelV4TextPart(text: 'think')],
                  ),
                ],
              ),
              providerOptions: {
                'anthropic': const AnthropicThinkingOptions(
                  budgetTokens: 4096,
                ).toMap(),
              },
            ),
          );

          expect(captured['thinking'], {
            'type': 'enabled',
            'budget_tokens': 4096,
          });
        },
      );

      test('doGenerate sends disabled thinking when speed=fast', () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'fast'},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-3-5-haiku-20241022');
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [LanguageModelV4TextPart(text: 'quick')],
                ),
              ],
            ),
            providerOptions: const {
              'anthropic': {'speed': 'fast'},
            },
          ),
        );

        expect(captured['thinking'], {'type': 'disabled'});
        expect(captured.containsKey('speed'), isFalse);
      });

      test(
        'doGenerate sends native output_config format for JSON response format',
        () async {
          late Map<String, dynamic> captured;
          final server = await _startServer((request) async {
            captured =
                (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
                    .cast<String, dynamic>();
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'content': []}));
            await request.response.close();
          });
          addTearDown(server.close);
          await AnthropicProvider(apiKey: 'test', baseUrl: server.baseUrl)
              .call('claude-sonnet-4-5')
              .doGenerate(
                LanguageModelV4CallOptions(
                  prompt: userPrompt('json'),
                  responseFormat: const LanguageModelV4JsonResponseFormat(
                    name: 'answer',
                    schema: {'type': 'object'},
                  ),
                ),
              );
          expect(captured['output_config'], {
            'format': {
              'type': 'json_schema',
              'schema': {'type': 'object'},
            },
          });
        },
      );

      test('sends typed cache control on requests and content parts', () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    LanguageModelV4TextPart(
                      text: 'cached',
                      providerOptions: const {
                        'anthropic': {
                          'cacheControl': {'type': 'ephemeral'},
                        },
                      },
                    ),
                  ],
                ),
              ],
            ),
            providerOptions: const {
              'anthropic': {
                'cache_control': {'type': 'ephemeral', 'ttl': '1h'},
              },
            },
          ),
        );

        expect(captured['cache_control'], {'type': 'ephemeral', 'ttl': '1h'});
        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        final content = (messages.single['content'] as List)
            .cast<Map<String, dynamic>>();
        expect(content.single['cache_control'], {'type': 'ephemeral'});
      });
    });

    // ── Additional coverage ──────────────────────────────────────────────

    test('exposes specification version and provider id', () {
      final model = AnthropicProvider(apiKey: 'test').call('claude-sonnet-4-5');
      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'anthropic');
      expect(model.modelId, 'claude-sonnet-4-5');
    });

    test('sends stop_sequences when provided', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'stop_sequence',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      final result = await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'hi')],
              ),
            ],
          ),
          stopSequences: const ['STOP', 'END'],
        ),
      );

      expect(captured['stop_sequences'], ['STOP', 'END']);
      // 'stop_sequence' maps to stop finish reason.
      expect(result.finishReason, LanguageModelV4FinishReason.stop);
    });

    test('sends stop_sequences when streaming', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: userPrompt('hi'),
          stopSequences: const ['STOP', 'END'],
        ),
      );
      await streamResult.stream.toList();

      expect(captured['stop_sequences'], ['STOP', 'END']);
    });

    test('maps unknown stop_reason to other', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'pause_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      final result = await model.doGenerate(
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

      expect(result.finishReason, LanguageModelV4FinishReason.other);
    });

    test('decodes redacted_thinking content part', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'msg_1',
            'model': 'claude-sonnet-4-5',
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'redacted_thinking', 'data': 'REDACTED-PAYLOAD'},
              {'type': 'text', 'text': 'visible'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      final result = await model.doGenerate(
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

      final redacted = result.content
          .whereType<LanguageModelV4RedactedReasoningPart>()
          .single;
      expect(utf8.decode(redacted.data), 'REDACTED-PAYLOAD');
    });

    test('streams redacted_thinking content with provider metadata', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"redacted_thinking","data":"REDACTED-PAYLOAD"}}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_stop","index":0}\n\n',
        );
        request.response.write(
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      final streamResult = await model.doStream(
        LanguageModelV4CallOptions(prompt: userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();
      final start = parts.whereType<StreamPartReasoningStart>().single;

      expect(
        start.providerMetadata?['anthropic']?['redactedData'],
        'REDACTED-PAYLOAD',
      );
      expect(parts.whereType<StreamPartReasoningEnd>().single.id, start.id);
    });

    test('serializes assistant tool calls and image url parts', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  LanguageModelV4TextPart(text: 'look'),
                  LanguageModelV4ImagePart(
                    image: DataContentUrl(
                      Uri.parse('https://example.com/pic.png'),
                    ),
                  ),
                  LanguageModelV4FilePart(
                    data: DataContentUrl(
                      Uri.parse('https://example.com/doc.pdf'),
                    ),
                    mediaType: 'application/pdf',
                    filename: 'doc.pdf',
                  ),
                ],
              ),
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [
                  LanguageModelV4ToolCallPart(
                    toolCallId: 'toolu_1',
                    toolName: 'weather',
                    input: const {'city': 'Paris'},
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final userParts = (messages.first['content'] as List)
          .cast<Map<String, dynamic>>();
      // Image URL part.
      expect(userParts[1]['type'], 'image');
      expect((userParts[1]['source'] as Map)['type'], 'url');
      expect(
        (userParts[1]['source'] as Map)['url'],
        'https://example.com/pic.png',
      );
      // File URL part becomes a document with a url source.
      expect(userParts[2]['type'], 'document');
      expect((userParts[2]['source'] as Map)['type'], 'url');
      expect(userParts[2]['title'], 'doc.pdf');
      // Assistant tool call.
      final assistantParts = (messages.last['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(assistantParts.single['type'], 'tool_use');
      expect(assistantParts.single['id'], 'toolu_1');
      expect(assistantParts.single['input'], {'city': 'Paris'});
    });

    test('serializes image/file tool result parts', () async {
      late Map<String, dynamic> captured;
      final imageB64 = base64Encode(utf8.encode('img'));
      final fileB64 = base64Encode(utf8.encode('pdf'));
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'toolu_1',
                    toolName: 'render',
                    output: ToolResultOutputContent([
                      LanguageModelV4TextPart(text: 'text part'),
                      LanguageModelV4ImagePart(
                        image: DataContentBase64(imageB64),
                        mediaType: 'image/png',
                      ),
                      LanguageModelV4FilePart(
                        data: DataContentBase64(fileB64),
                        mediaType: 'application/pdf',
                      ),
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
      final toolResult = (messages.single['content'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      final parts = (toolResult['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(parts[0], {'type': 'text', 'text': 'text part'});
      expect(parts[1]['type'], 'image');
      expect((parts[1]['source'] as Map)['data'], imageB64);
      expect(parts[2]['type'], 'document');
      expect((parts[2]['source'] as Map)['data'], fileB64);
      expect(parts, hasLength(3));
    });

    test('rejects unsupported tool result content explicitly', () async {
      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: 'http://127.0.0.1:1',
      ).call('claude-sonnet-4-5');

      await expectLater(
        model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.tool,
                  content: [
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'toolu_1',
                      toolName: 'render',
                      output: ToolResultOutputContent([
                        LanguageModelV4SourcePart(
                          id: 's1',
                          url: 'https://example.com',
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

    test('uses text tool result output directly', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'toolu_1',
                    toolName: 'weather',
                    output: ToolResultOutputText('sunny'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final toolResult = (messages.single['content'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      expect(toolResult['content'], 'sunny');
    });

    test('drops image part with url data source unsupported by base64', () async {
      // A base64-less data content (URL) for an image inside a file part with a
      // non-image media type goes through the document/base64 branch and is
      // dropped when no base64 is available — exercised via _toBase64 url path.
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'stop_reason': 'end_turn',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'toolu_1',
                    toolName: 'render',
                    output: ToolResultOutputContent([
                      // Image media-type file part that resolves through the
                      // image URL branch.
                      LanguageModelV4FilePart(
                        data: DataContentUrl(
                          Uri.parse('https://example.com/pic.png'),
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

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final toolResult = (messages.single['content'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      final parts = (toolResult['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(parts.single['type'], 'image');
      expect((parts.single['source'] as Map)['type'], 'url');
    });

    test('stream handles message_start, thinking_delta, tools and errors', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        // message_start with no message field exercises default empty map.
        request.response.write('data: {"type":"message_start"}\n\n');
        // content_block_start with empty content_block exercises defaults.
        request.response.write(
          'data: {"type":"content_block_start","index":0}\n\n',
        );
        // thinking delta.
        request.response.write(
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"pondering"}}\n\n',
        );
        // text delta where text starts via delta path (no preceding text start).
        request.response.write(
          'data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Hi"}}\n\n',
        );
        // error event.
        request.response.write(
          'data: {"type":"error","error":{"type":"overloaded_error"}}\n\n',
        );
        // message_delta with usage only, then stop reason.
        request.response.write(
          'data: {"type":"message_delta","usage":{"output_tokens":5},"delta":{}}\n\n',
        );
        request.response.write(
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-3-7-sonnet-20250219');

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
          tools: const [
            LanguageModelV4FunctionTool(
              name: 'weather',
              description: 'Get weather',
              inputSchema: {'type': 'object'},
              inputExamples: [
                {'city': 'Paris'},
              ],
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
          temperature: 0.5,
          topP: 0.9,
          providerOptions: const {
            'anthropic': {
              'thinking': {'type': 'enabled', 'budget_tokens': 1024},
            },
          },
        ),
      );

      final parts = await streamResult.stream.toList();
      // Stream request body included tools and thinking.
      expect(captured['stream'], isTrue);
      expect(captured['tools'], isA<List>());
      expect(captured['thinking'], {'type': 'enabled', 'budget_tokens': 1024});
      expect(captured['tool_choice'], {'type': 'any'});
      expect(captured['temperature'], 0.5);
      expect(captured['top_p'], 0.9);

      expect(
        parts.whereType<StreamPartReasoningDelta>().single.delta,
        'pondering',
      );
      expect(parts.whereType<StreamPartTextDelta>().single.delta, 'Hi');
      expect(parts.whereType<StreamPartError>(), isNotEmpty);
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.stop,
      );
    });

    test('stream surfaces transport errors as StreamPartError', () async {
      // Fully drain the request first so the client's POST write always
      // completes, then detach the socket and send chunked headers plus a
      // single partial event before destroying the connection. The response
      // byte stream errors mid-read, exercising the catch in doStream.
      //
      // Draining before destroying is what makes this deterministic: writing
      // the partial response and tearing down the socket while the client is
      // still sending its request body would surface a "broken pipe" write
      // error instead of the intended mid-stream read error, which made this
      // test flaky under different socket timing.
      final server = await _startServer((request) async {
        await request.drain<void>();
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\n'
          'content-type: text/event-stream\r\n'
          'transfer-encoding: chunked\r\n'
          '\r\n',
        );
        final event =
            'data: {"type":"content_block_start","index":0,'
            '"content_block":{"type":"text"}}\n\n';
        // Write one valid chunk, then destroy without the terminating chunk.
        socket.write('${event.length.toRadixString(16)}\r\n$event\r\n');
        await socket.flush();
        socket.destroy();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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
      // The abrupt disconnect propagates as a StreamPartError.
      expect(parts.whereType<StreamPartError>(), isNotEmpty);
    });

    test(
      'stream emits stream start before error when the body fails before any valid chunk',
      () async {
        final server = await _startServer((request) async {
          await request.drain<void>();
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.write(
            'HTTP/1.1 200 OK\r\n'
            'content-type: text/event-stream\r\n'
            'content-length: 4096\r\n'
            '\r\n',
          );
          await socket.flush();
          socket.destroy();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

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
        expect(parts[0], isA<StreamPartStreamStart>());
        expect(parts[1], isA<StreamPartError>());
      },
    );

    test('doStream forwards extra providerOptions into request body', () async {
      // providerOptions carrying a key beyond thinking/speed leaves a non-null
      // cleaned map, which the stream request body spreads via `...?cleanedPo`.
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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
          providerOptions: const {
            'anthropic': {
              'metadata': {'trace_id': 'stream-abc'},
            },
          },
        ),
      );

      await streamResult.stream.toList();
      expect(captured['metadata'], {'trace_id': 'stream-abc'});
    });

    test('doStream tolerates content_block_delta with no delta field', () async {
      // A content_block_delta event missing its `delta` falls back to the empty
      // map, so the unknown delta type is simply ignored.
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}\n\n',
        );
        // Delta event without a `delta` object → defaults to empty map.
        request.response.write(
          'data: {"type":"content_block_delta","index":0}\n\n',
        );
        request.response.write(
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}\n\n',
        );
        request.response.write(
          'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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
      // The delta-less event produced no output; only the real text delta did.
      expect(
        parts.whereType<StreamPartTextDelta>().map((e) => e.delta).join(),
        'Hi',
      );
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.stop,
      );
    });

    test(
      'doStream message_delta without delta still applies usage and finishes',
      () async {
        // A message_delta carrying usage but no `delta` exercises the empty-map
        // fallback for `delta`; a later message_delta supplies the stop reason.
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'text/event-stream');
          request.response.write(
            'data: {"type":"message_start","message":{"id":"msg_9","model":"claude-sonnet-4-5","usage":{"input_tokens":4,"output_tokens":1}}}\n\n',
          );
          // message_delta with usage only (no `delta`, and no output_tokens):
          // exercises both the empty-map delta fallback and the
          // `streamUsage?.outputTokens.total` carry-over fallback.
          request.response.write(
            'data: {"type":"message_delta","usage":{"input_tokens":9}}\n\n',
          );
          request.response.write(
            'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

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

        final finish = (await streamResult.stream.toList())
            .whereType<StreamPartFinish>()
            .single;
        // input_tokens updated from the usage-only delta...
        expect(finish.usage.inputTokens.total, 9);
        // ...while output_tokens carries over from message_start (1) because the
        // usage-only delta omitted it.
        expect(finish.usage.outputTokens.total, 1);
        expect(finish.finishReason, LanguageModelV4FinishReason.stop);
      },
    );

    test('doGenerate synthesizes a tool call id when none is provided', () async {
      // A tool_use content block with no `id` forces the `_generateId` fallback.
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'msg_1',
            'model': 'claude-sonnet-4-5',
            'stop_reason': 'tool_use',
            'content': [
              {
                'type': 'tool_use',
                // No `id` → provider must synthesize one.
                'name': 'weather',
                'input': {'city': 'Paris'},
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');

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

      final call = result.content
          .whereType<LanguageModelV4ToolCallPart>()
          .single;
      expect(call.toolName, 'weather');
      // The synthesized id uses the `tool-<micros>` shape from _generateId.
      expect(call.toolCallId, startsWith('tool-'));
    });

    test(
      'serializes provider-defined tools and parses structured warnings',
      () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
              'warnings': [
                {
                  'type': 'unsupported',
                  'feature': 'top_k',
                  'details': 'ignored',
                },
                {
                  'type': 'compatibility',
                  'feature': 'sources',
                  'details': 'partial',
                },
                {'type': 'deprecated', 'feature': 'legacy-mode'},
                {'type': 'other', 'message': 'custom'},
                {'type': 'mystery'},
                7,
                '',
                null,
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');

        final result = await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: userPrompt('hi'),
            tools: const [
              LanguageModelV4ProviderDefinedTool(
                id: 'anthropic.web_search_20250305',
                name: 'web_search',
                args: {'max_uses': 2},
              ),
            ],
          ),
        );

        final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
        expect(tools.single, {
          'type': 'web_search_20250305',
          'name': 'web_search',
          'max_uses': 2,
        });

        expect(result.warnings, hasLength(6));
        expect(
          result.warnings
              .whereType<LanguageModelV4UnsupportedWarning>()
              .single
              .feature,
          'top_k',
        );
        expect(
          result.warnings
              .whereType<LanguageModelV4CompatibilityWarning>()
              .single
              .feature,
          'sources',
        );
        expect(
          result.warnings
              .whereType<LanguageModelV4DeprecatedWarning>()
              .single
              .message,
          'This setting is deprecated.',
        );
        expect(
          result.warnings.whereType<LanguageModelV4OtherWarning>().map(
            (w) => w.message,
          ),
          containsAll(['custom', '{"type":"mystery"}', '7']),
        );
      },
    );

    runProviderContractTests(
      providerName: 'anthropic',
      captureRequestBody: _captureAnthropicRequestBody,
      expectMultimodalBody: (body) {
        final messages = (body['messages'] as List)
            .cast<Map<String, dynamic>>();
        final user = messages.first;
        final content = (user['content'] as List).cast<Map<String, dynamic>>();
        expect(content[0]['type'], 'text');
        expect(content[1]['type'], 'image');
        expect(content[2]['type'], 'document');
      },
      expectToolResultBody: (body) {
        final messages = (body['messages'] as List)
            .cast<Map<String, dynamic>>();
        final toolMessage = messages.last;
        final content = (toolMessage['content'] as List)
            .cast<Map<String, dynamic>>();
        expect(content.single['type'], 'tool_result');
        expect(content.single['is_error'], isTrue);
      },
    );

    test('streams signed thinking continuation with tool response', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
            .cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"type":"message_start","message":{"id":"m2","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}\n\n'
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}\n\n'
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"done"}}\n\n'
          'data: {"type":"message_stop"}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);
      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');
      final result = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: const [
                  LanguageModelV4ReasoningPart(
                    text: 'think',
                    signature: 'sig-1',
                  ),
                ],
              ),
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'toolu-1',
                    toolName: 'lookup',
                    output: ToolResultOutputText('ok'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await result.stream.toList();
      final messages = (captured['messages'] as List).cast<Map>();
      final assistant = messages.firstWhere((m) => m['role'] == 'assistant');
      expect((assistant['content'] as List).single['signature'], 'sig-1');
      final tool = messages.firstWhere((m) => m['role'] == 'user');
      expect((tool['content'] as List).single['tool_use_id'], 'toolu-1');
    });

    test('preserves fragmented signatures and IDs through a real streamText loop', () async {
      final requests = <Map<String, dynamic>>[];
      var requestCount = 0;
      final server = await _startServer((request) async {
        requests.add(
          (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
              .cast<String, dynamic>(),
        );
        requestCount++;
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        if (requestCount == 1) {
          request.response.write(
            'data: {"type":"message_start","message":{"id":"m1","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}\n\n'
            'data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}\n\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"think"}}\n\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig-"}}\n\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"a"}}\n\n'
            'data: {"type":"content_block_stop","index":0}\n\n'
            'data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu-a","name":"lookup"}}\n\n'
            'data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\\"q\\":\\"x\\"}"}}\n\n'
            'data: {"type":"content_block_stop","index":1}\n\n'
            'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}\n\n'
            'data: {"type":"message_stop"}\n\n',
          );
        } else {
          request.response.write(
            'data: {"type":"message_start","message":{"id":"m2","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":1}}}\n\n'
            'data: {"type":"content_block_start","index":0,"content_block":{"type":"text"}}\n\n'
            'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"done"}}\n\n'
            'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n'
            'data: {"type":"message_stop"}\n\n',
          );
        }
        await request.response.close();
      });
      addTearDown(server.close);

      final model = AnthropicProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('claude-sonnet-4-5');
      final result = await streamText(
        model: model,
        prompt: 'lookup',
        maxSteps: 2,
        tools: {
          'lookup': tool<Map<String, dynamic>, String>(
            inputSchema: jsonSchema(const {'type': 'object'}),
            execute: (_, _) async => 'ok',
          ),
        },
      );

      expect(await result.text, 'done');
      expect(requests, hasLength(2));
      final assistant = (requests[1]['messages'] as List)
          .cast<Map>()
          .firstWhere((m) => m['role'] == 'assistant');
      final assistantContent = (assistant['content'] as List).cast<Map>();
      expect(assistantContent[0]['signature'], 'sig-a');
      expect(assistantContent[1]['id'], 'toolu-a');
      final toolBody = (requests[1]['messages'] as List).cast<Map>().firstWhere(
        (m) => (m['content'] as List).any(
          (part) => (part as Map)['type'] == 'tool_result',
        ),
      );
      expect((toolBody['content'] as List).single['tool_use_id'], 'toolu-a');
    });
  });
}

Future<Map<String, dynamic>> _captureAnthropicRequestBody(
  LanguageModelV4Prompt prompt,
) async {
  late Map<String, dynamic> captured;
  final server = await _startServer((request) async {
    final body = await utf8.decoder.bind(request).join();
    captured = (jsonDecode(body) as Map).cast<String, dynamic>();

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'text', 'text': 'ok'},
        ],
      }),
    );
    await request.response.close();
  });

  final model = AnthropicProvider(
    apiKey: 'test',
    baseUrl: server.baseUrl,
  ).call('claude-sonnet-4-5');
  await model.doGenerate(LanguageModelV4CallOptions(prompt: prompt));
  await server.close();
  return captured;
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

Future<TestServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) => TestServer.start(handler, pathSuffix: '/v1');
