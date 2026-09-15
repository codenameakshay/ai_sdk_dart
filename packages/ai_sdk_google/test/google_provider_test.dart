import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/contract/language_model_contract.dart';
import '../../ai_sdk_provider/test/support/cancellation_adapter.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  group('GoogleGenerativeAIProvider', () {
    test('doGenerate parses text/functionCall and usage', () async {
      final server = await _startServer((request) async {
        expect(
          request.uri.path,
          '/v1beta/models/gemini-2.0-flash:generateContent',
        );
        expect(request.uri.queryParameters['key'], 'test');
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'Hello from gemini'},
                    {
                      'functionCall': {
                        'name': 'weather',
                        'args': {'city': 'Paris'},
                      },
                    },
                  ],
                },
              },
            ],
            'usageMetadata': {
              'promptTokenCount': 10,
              'candidatesTokenCount': 6,
              'totalTokenCount': 16,
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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

      expect(result.finishReason, LanguageModelV4FinishReason.stop);
      expect(result.usage.inputTokens.total, 10);
      expect(result.usage.inputTokens.cacheRead, isNull);
      expect(result.usage.outputTokens.total, 6);
      expect(
        result.content.whereType<LanguageModelV4TextPart>().single.text,
        'Hello from gemini',
      );
      expect(
        result.content.whereType<LanguageModelV4ToolCallPart>().single.toolName,
        'weather',
      );
    });

    test(
      'doGenerate maps cachedContentTokenCount into nested inputTokens',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'hi'},
                    ],
                  },
                },
              ],
              'usageMetadata': {
                'promptTokenCount': 100,
                'candidatesTokenCount': 6,
                'totalTokenCount': 106,
                'cachedContentTokenCount': 80,
              },
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

        final result = await model.doGenerate(
          LanguageModelV4CallOptions(prompt: userPrompt('hi')),
        );

        expect(result.usage.inputTokens.total, 100);
        expect(result.usage.inputTokens.cacheRead, 80);
        expect(result.usage.inputTokens.cacheWrite, isNull);
        expect(result.usage.inputTokens.noCache, 20);
        expect(result.usage.outputTokens.total, 6);
      },
    );

    test('credentials are resolved immediately before each request', () async {
      final apiKeys = <String?>[];
      final server = await _startServer((request) async {
        apiKeys.add(request.uri.queryParameters['key']);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      var token = 'first-key';
      final provider = GoogleGenerativeAIProvider(
        baseUrl: server.baseUrl,
        credentialProvider: () async => token,
      );

      await provider
          .call('gemini-2.0-flash')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      token = 'second-key';
      await provider
          .call('gemini-2.0-flash')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(apiKeys, ['first-key', 'second-key']);
    });

    test('reuses an injected client across multiple requests', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
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

      final provider = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
        client: client,
      );

      await provider
          .call('gemini-2.0-flash')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      await provider
          .call('gemini-2.0-flash')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(interceptedRequests, 2);
    });

    test(
      'doGenerate cancels an in-flight Dio request via abortSignal',
      () async {
        final adapter = CancellationHttpClientAdapter();
        final client = _cancellationClient(adapter, 'http://localhost/v1beta');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal();
        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: 'http://localhost/v1beta',
          client: client,
        ).call('gemini-2.0-flash');

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
        final client = _cancellationClient(adapter, 'http://localhost/v1beta');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal()..cancel();
        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: 'http://localhost/v1beta',
          client: client,
        ).call('gemini-2.0-flash');

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
      final client = _cancellationClient(adapter, 'http://localhost/v1beta');
      addTearDown(() => client.close(force: true));
      final abortSignal = TestAbortSignal();
      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: 'http://localhost/v1beta',
        client: client,
      ).call('gemini-2.0-flash');

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
      'stream and embedding resolve api keys immediately before dispatch',
      () async {
        final apiKeys = <String, String?>{};
        final server = await _startServer((request) async {
          apiKeys[request.uri.path] = request.uri.queryParameters['key'];
          switch (request.uri.path) {
            case '/v1beta/models/gemini-2.0-flash:streamGenerateContent':
              request.response.statusCode = 200;
              request.response.headers.set('content-type', 'text/event-stream');
              request.response.write(
                'data: {"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}\n\n',
              );
              request.response.write(
                'data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
              );
              break;
            case '/v1beta/models/text-embedding-004:batchEmbedContents':
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'embeddings': [
                    {
                      'values': [0.1, 0.2],
                    },
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

        var token = 'stream-key';
        final provider = GoogleGenerativeAIProvider(
          baseUrl: server.baseUrl,
          credentialProvider: () async => token,
        );

        final stream = await provider
            .call('gemini-2.0-flash')
            .doStream(LanguageModelV4CallOptions(prompt: userPrompt('stream')));
        await stream.stream.drain<void>();

        token = 'embed-key';
        await provider
            .embedding('text-embedding-004')
            .doEmbed(const EmbeddingModelV2CallOptions(values: ['a']));

        expect(apiKeys, {
          '/v1beta/models/gemini-2.0-flash:streamGenerateContent': 'stream-key',
          '/v1beta/models/text-embedding-004:batchEmbedContents': 'embed-key',
        });
      },
    );

    test(
      'dispose closes owned clients and leaves injected clients open',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final ownedProvider = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        );
        ownedProvider.dispose();
        await expectLater(
          ownedProvider
              .call('gemini-2.0-flash')
              .doGenerate(
                LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
              ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider
            .call('gemini-2.0-flash')
            .doGenerate(
              LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
            );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );

    test('doGenerate extracts provider-native source and file parts', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {
                      'fileData': {
                        'fileUri': 'https://example.com/doc.pdf',
                        'mimeType': 'application/pdf',
                      },
                    },
                    {
                      'inlineData': {
                        'mimeType': 'text/plain',
                        'data': base64Encode(utf8.encode('hello')),
                      },
                    },
                  ],
                },
                'groundingMetadata': {
                  'groundingChunks': [
                    {
                      'web': {
                        'uri': 'https://example.com/source',
                        'title': 'Example Source',
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

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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

      expect(result.content.whereType<LanguageModelV4FilePart>(), hasLength(2));
      final source = result.content
          .whereType<LanguageModelV4SourcePart>()
          .single;
      expect(source.url, 'https://example.com/source');
      expect(source.title, 'Example Source');
    });

    test('doStream parses SSE chunks and finish', () async {
      final server = await _startServer((request) async {
        expect(
          request.uri.path,
          '/v1beta/models/gemini-2.0-flash:streamGenerateContent',
        );
        expect(request.uri.queryParameters['key'], 'test');
        expect(request.uri.queryParameters['alt'], 'sse');
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[{"text":"Hel"}]}}]}\n\n',
        );
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[{"text":"lo"}]},"finishReason":"STOP"}]}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.stop,
      );
    });

    test('doStream emits provider-native source and file parts', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[{"fileData":{"fileUri":"https://example.com/file.pdf","mimeType":"application/pdf"}},{"inlineData":{"mimeType":"text/plain","data":"aGVsbG8="}}]},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com/ground","title":"Ground"}}]}}]}\n\n',
        );
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
      expect(parts.whereType<StreamPartFile>(), hasLength(2));
      final source = parts.whereType<StreamPartSource>().single.source;
      expect(source.url, 'https://example.com/ground');
      expect(source.title, 'Ground');
    });

    test('maps tool choice modes and tool declarations', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        seenBodies.add((jsonDecode(body) as Map).cast<String, dynamic>());

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
                description: 'Get weather',
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

      expect(
        seenBodies[0]['toolConfig']['functionCallingConfig']['mode'],
        'AUTO',
      );
      expect(
        seenBodies[1]['toolConfig']['functionCallingConfig']['mode'],
        'NONE',
      );
      expect(
        seenBodies[2]['toolConfig']['functionCallingConfig']['mode'],
        'ANY',
      );
      expect(
        seenBodies[3]['toolConfig']['functionCallingConfig']['allowedFunctionNames'],
        ['weather'],
      );

      final declarations =
          (((seenBodies[0]['tools'] as List).first
                  as Map)['functionDeclarations']
              as List);
      expect((declarations.first as Map)['name'], 'weather');
      expect((declarations.first as Map)['parameters'], {'type': 'object'});
    });

    test('serializes provider-defined tools', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      await GoogleGenerativeAIProvider(apiKey: 'test', baseUrl: server.baseUrl)
          .call('gemini-2.0-flash')
          .doGenerate(
            LanguageModelV4CallOptions(
              prompt: userPrompt('search'),
              tools: const [
                LanguageModelV4ProviderDefinedTool(
                  id: 'google.google_search',
                  name: 'search',
                  args: {
                    'dynamicRetrievalConfig': {'mode': 'MODE_DYNAMIC'},
                  },
                ),
              ],
            ),
          );

      final googleSearch =
          ((captured['tools'] as List).single as Map)['googleSearch'];
      expect(googleSearch, {
        'dynamicRetrievalConfig': {'mode': 'MODE_DYNAMIC'},
      });
    });

    test(
      'keeps function and provider-defined tools in separate entries',
      () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        await GoogleGenerativeAIProvider(
              apiKey: 'test',
              baseUrl: server.baseUrl,
            )
            .call('gemini-2.0-flash')
            .doGenerate(
              LanguageModelV4CallOptions(
                prompt: userPrompt('search and weather'),
                tools: const [
                  LanguageModelV4FunctionTool(
                    name: 'weather',
                    inputSchema: {'type': 'object'},
                  ),
                  LanguageModelV4ProviderDefinedTool(
                    id: 'google.google_search',
                    name: 'search',
                    args: {},
                  ),
                ],
              ),
            );

        final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
        expect(tools, hasLength(2));
        expect(tools[0].containsKey('functionDeclarations'), isTrue);
        expect(tools[0].containsKey('googleSearch'), isFalse);
        expect(tools[1], {'googleSearch': {}});
      },
    );

    test(
      'preserves invalid strict tool arguments for downstream failure handling',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'weather',
                          'args': ['not', 'object'],
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

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');
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
        expect(call.input, ['not', 'object']);
      },
    );

    test('embedding parses vectors', () async {
      final server = await _startServer((request) async {
        expect(
          request.uri.path,
          '/v1beta/models/text-embedding-004:batchEmbedContents',
        );
        expect(request.uri.queryParameters['key'], 'test');
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'embeddings': [
              {
                'values': [0.1, 0.2],
              },
              {
                'values': [0.3, 0.4],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).embedding('text-embedding-004');

      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions(values: ['a', 'b']),
      );

      expect(result.embeddings, hasLength(2));
      expect(result.embeddings.first.embedding, [0.1, 0.2]);
      expect(result.embeddings.last.embedding, [0.3, 0.4]);
    });

    test('passes providerOptions into request body', () async {
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        final jsonBody = jsonDecode(body) as Map<String, dynamic>;
        expect(jsonBody['cachedContent'], 'cachedContents/123');

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
            'google': {'cachedContent': 'cachedContents/123'},
          },
        ),
      );

      expect(
        result.content.whereType<LanguageModelV4TextPart>().single.text,
        'ok',
      );
    });

    test(
      'maps multimodal and tool result content to google wire format',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));

        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          final jsonBody = jsonDecode(body) as Map<String, dynamic>;
          final contents = (jsonBody['contents'] as List)
              .cast<Map<String, dynamic>>();

          final userParts = (contents.first['parts'] as List)
              .cast<Map<String, dynamic>>();
          expect(userParts[1]['inlineData'], isA<Map>());
          expect(
            ((userParts[1]['inlineData'] as Map)['data'] as String),
            imageB64,
          );
          expect(userParts[2]['fileData'], isA<Map>());

          final toolParts = (contents.last['parts'] as List)
              .cast<Map<String, dynamic>>();
          final functionResponse = (toolParts.single['functionResponse'] as Map)
              .cast<String, dynamic>();
          expect(functionResponse['name'], 'weather');
          expect((functionResponse['response'] as Map)['isError'], isTrue);

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

        final result = await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    LanguageModelV4TextPart(text: 'check this'),
                    LanguageModelV4ImagePart(
                      image: DataContentBytes(
                        Uint8List.fromList(utf8.encode('img')),
                      ),
                      mediaType: 'image/png',
                    ),
                    LanguageModelV4FilePart(
                      data: DataContentUrl(
                        Uri.parse('https://example.com/doc.pdf'),
                      ),
                      mediaType: 'application/pdf',
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
                      output: ToolResultOutputText('failure'),
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
          'data: {"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":2,"totalTokenCount":7,"cachedContentTokenCount":3},"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}\n\n',
        );
        request.response.write(
          'data: {"promptFeedback":{"blockReason":"SAFETY"},"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
      expect(finish.usage.inputTokens.total, 5);
      expect(finish.usage.inputTokens.cacheRead, 3);
      expect(finish.usage.inputTokens.noCache, 2);
      expect(finish.usage.outputTokens.total, 2);
      expect(finish.providerMetadata?['google']?['model'], 'gemini-2.0-flash');
      expect(finish.providerMetadata?['google']?['warnings'], isNotEmpty);
    });

    test('exposes specification metadata for language model', () {
      final model = GoogleGenerativeAIProvider().call('gemini-2.0-flash');
      expect(model.provider, 'google');
      expect(model.specificationVersion, 'v4');
      expect(model.modelId, 'gemini-2.0-flash');
    });

    test('exposes specification metadata for embedding model', () {
      final model = GoogleGenerativeAIProvider().embedding(
        'text-embedding-004',
      );
      expect(model.provider, 'google');
      expect(model.specificationVersion, 'v2');
      expect(model.modelId, 'text-embedding-004');
    });

    test(
      'doGenerate serializes system, generation config, and stops',
      () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

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
            maxOutputTokens: 128,
            temperature: 0.5,
            topP: 0.9,
            topK: 40,
            stopSequences: const ['STOP', 'END'],
          ),
        );

        expect(
          ((captured['systemInstruction'] as Map)['parts'] as List).first,
          {'text': 'You are concise.'},
        );
        final config = (captured['generationConfig'] as Map)
            .cast<String, dynamic>();
        expect(config['maxOutputTokens'], 128);
        expect(config['temperature'], 0.5);
        expect(config['topP'], 0.9);
        expect(config['topK'], 40);
        expect(config['stopSequences'], ['STOP', 'END']);
      },
    );

    test('doGenerate tolerates empty candidates and content', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'candidates': <dynamic>[]}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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

      expect(result.content, isEmpty);
      expect(result.finishReason, LanguageModelV4FinishReason.unknown);
      expect(result.usage.inputTokens.total, isNull);
      expect(result.usage.outputTokens.total, isNull);
    });

    test('doGenerate maps each finish reason to the AI SDK value', () async {
      Future<LanguageModelV4FinishReason> resolve(String? reason) async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': ?reason,
                  'content': {
                    'parts': [
                      {'text': 'x'},
                    ],
                  },
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);
        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');
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
        return result.finishReason;
      }

      expect(await resolve('MAX_TOKENS'), LanguageModelV4FinishReason.length);
      expect(
        await resolve('SAFETY'),
        LanguageModelV4FinishReason.contentFilter,
      );
      expect(
        await resolve('RECITATION'),
        LanguageModelV4FinishReason.contentFilter,
      );
      expect(await resolve('OTHER'), LanguageModelV4FinishReason.other);
      expect(await resolve('BLOCKLIST'), LanguageModelV4FinishReason.other);
      expect(await resolve(null), LanguageModelV4FinishReason.unknown);
    });

    test('doGenerate parses string and num usage token counts', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
            'usageMetadata': {
              'promptTokenCount': '11',
              'candidatesTokenCount': 4.0,
              'totalTokenCount': 15,
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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

      expect(result.usage.inputTokens.total, 11);
      expect(result.usage.outputTokens.total, 4);
    });

    test('serializes assistant tool calls into function calls', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
                    input: const {'city': 'Paris'},
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final contents = (captured['contents'] as List)
          .cast<Map<String, dynamic>>();
      expect(contents.single['role'], 'model');
      final fnCall =
          ((contents.single['parts'] as List).single as Map)['functionCall'];
      expect(fnCall, {
        'name': 'weather',
        'args': {'city': 'Paris'},
      });
    });

    test('falls back to joined text when no wire parts emitted', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

      // A reasoning part is not serialized into any wire part, so the
      // empty-parts fallback joins any text parts in the message.
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [LanguageModelV4ReasoningPart(text: 'thinking...')],
              ),
            ],
          ),
        ),
      );

      final contents = (captured['contents'] as List)
          .cast<Map<String, dynamic>>();
      expect((contents.single['parts'] as List).single, {'text': ''});
    });

    test('serializes content tool result output with media parts', () async {
      late Map<String, dynamic> captured;
      final imageB64 = base64Encode(utf8.encode('img'));
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
                    output: ToolResultOutputContent([
                      LanguageModelV4TextPart(text: 'summary'),
                      LanguageModelV4ImagePart(
                        image: DataContentBytes(
                          Uint8List.fromList(utf8.encode('img')),
                        ),
                        mediaType: 'image/png',
                      ),
                      LanguageModelV4FilePart(
                        data: DataContentBase64(imageB64),
                        mediaType: 'application/pdf',
                        filename: 'doc.pdf',
                      ),
                      // Unsupported inside tool-result content -> 'unsupported'.
                      LanguageModelV4ToolCallPart(
                        toolCallId: 'x',
                        toolName: 'y',
                        input: const {},
                      ),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final contents = (captured['contents'] as List)
          .cast<Map<String, dynamic>>();
      final response =
          ((contents.single['parts'] as List).single as Map)['functionResponse']
              as Map;
      final output = (response['response'] as Map)['output'] as Map;
      expect(output['type'], 'content');
      final outParts = (output['parts'] as List).cast<Map<String, dynamic>>();
      expect(outParts[0], {'type': 'text', 'text': 'summary'});
      expect(outParts[1]['type'], 'image');
      expect((outParts[1]['inlineData'] as Map)['data'], imageB64);
      expect(outParts[2]['type'], 'file');
      expect(outParts[2]['mediaType'], 'application/pdf');
      expect(outParts[2]['filename'], 'doc.pdf');
      expect((outParts[2]['inlineData'] as Map)['data'], imageB64);
      expect(outParts[3], {'type': 'unsupported'});
    });

    test('doStream serializes system, config, tools, and tool choice', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[{"text":"hi"}]},"finishReason":"STOP"}]}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

      final stream = await model.doStream(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            system: 'be brief',
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'hi')],
              ),
            ],
          ),
          maxOutputTokens: 64,
          temperature: 0.2,
          topP: 0.8,
          topK: 10,
          tools: const [
            LanguageModelV4FunctionTool(
              name: 'weather',
              description: 'Get weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
          providerOptions: const {
            'google': {'cachedContent': 'cachedContents/9'},
          },
        ),
      );
      await stream.stream.toList();

      expect(((captured['systemInstruction'] as Map)['parts'] as List).first, {
        'text': 'be brief',
      });
      final config = (captured['generationConfig'] as Map)
          .cast<String, dynamic>();
      expect(config['maxOutputTokens'], 64);
      expect(config['temperature'], 0.2);
      expect(config['topP'], 0.8);
      expect(config['topK'], 10);
      final declarations =
          (((captured['tools'] as List).first as Map)['functionDeclarations']
              as List);
      expect((declarations.single as Map)['name'], 'weather');
      expect((declarations.single as Map)['description'], 'Get weather');
      expect(captured['toolConfig']['functionCallingConfig']['mode'], 'ANY');
      expect(captured['cachedContent'], 'cachedContents/9');
    });

    test('doStream emits tool call stream parts for Gemini functionCall', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[{"text":"go"},{"functionCall":{"name":"weather","args":{"city":"NYC"}}}]}}]}\n\n',
        );
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[]},"finishReason":"MAX_TOKENS"}]}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
        'go',
      );
      final toolStart = parts.whereType<StreamPartToolInputStart>().single;
      expect(toolStart.toolName, 'weather');
      expect(toolStart.id, startsWith('tool-'));

      final toolDelta = parts.whereType<StreamPartToolInputDelta>().single;
      expect(toolDelta.id, toolStart.id);
      expect(toolDelta.delta, '{"city":"NYC"}');

      final toolEnd = parts.whereType<StreamPartToolInputEnd>().single;
      expect(toolEnd.id, toolStart.id);

      final toolCall = parts.whereType<StreamPartToolCall>().single.toolCall;
      expect(toolCall.toolCallId, toolStart.id);
      expect(toolCall.toolName, 'weather');
      expect(toolCall.input, {'city': 'NYC'});

      expect(
        parts
            .where(
              (part) =>
                  part is StreamPartToolInputStart ||
                  part is StreamPartToolInputDelta ||
                  part is StreamPartToolInputEnd ||
                  part is StreamPartToolCall,
            )
            .map((part) => part.runtimeType)
            .toList(),
        [
          StreamPartToolInputStart,
          StreamPartToolInputDelta,
          StreamPartToolInputEnd,
          StreamPartToolCall,
        ],
      );
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.length,
      );
    });

    test(
      'doStream reuses one tool call ID for cumulative functionCall args and ends once',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'text/event-stream');
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":"{\\"city\\":\\"N"}}]}}]}\n\n',
          );
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":"{\\"city\\":\\"NY\\"}"}}]}}]}\n\n',
          );
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":"{\\"city\\":\\"NY\\"}"}}]}}]}\n\n',
          );
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

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
        final starts = parts.whereType<StreamPartToolInputStart>().toList();
        expect(starts, hasLength(1));
        expect(starts.single.toolName, 'weather');

        final deltas = parts.whereType<StreamPartToolInputDelta>().toList();
        expect(deltas, hasLength(2));
        expect(deltas.first.id, starts.single.id);
        expect(deltas.first.delta, '{"city":"N');
        expect(deltas.last.id, starts.single.id);
        expect(deltas.last.delta, 'Y"}');

        final ends = parts.whereType<StreamPartToolInputEnd>().toList();
        expect(ends, hasLength(1));
        expect(ends.single.id, starts.single.id);

        final toolCalls = parts.whereType<StreamPartToolCall>().toList();
        expect(toolCalls, hasLength(1));
        expect(toolCalls.single.toolCall.toolCallId, starts.single.id);
        expect(toolCalls.single.toolCall.toolName, 'weather');
        expect(toolCalls.single.toolCall.input, '{"city":"NY"}');
      },
    );

    test(
      'doStream emits raw chunks and closes the previous tool call when Gemini switches tools',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'text/event-stream');
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":{"city":"Paris"}}}]}}]}\n\n',
          );
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"calendar","args":{"day":"today"}}}]},"finishReason":"STOP"}]}\n\n',
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

        final stream = await model.doStream(
          LanguageModelV4CallOptions(
            prompt: userPrompt('hi'),
            includeRawChunks: true,
          ),
        );

        final parts = await stream.stream.toList();
        expect(parts.whereType<StreamPartRaw>(), hasLength(2));
        final calls = parts.whereType<StreamPartToolCall>().toList();
        expect(calls, hasLength(2));
        expect(calls[0].toolCall.toolName, 'weather');
        expect(calls[0].toolCall.input, {'city': 'Paris'});
        expect(calls[1].toolCall.toolName, 'calendar');
        expect(calls[1].toolCall.input, {'day': 'today'});
      },
    );

    test(
      'doStream preserves raw non-object functionCall args verbatim',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'text/event-stream');
          request.response.write(
            'data: {"candidates":[{"content":{"parts":[{"functionCall":{"name":"weather","args":"not-json"}}]},"finishReason":"STOP"}]}\n\n',
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

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
        final delta = parts.whereType<StreamPartToolInputDelta>().single;
        expect(delta.delta, 'not-json');

        final end = parts.whereType<StreamPartToolInputEnd>().single;
        expect(end.id, delta.id);
        expect(
          parts.whereType<StreamPartToolCall>().single.toolCall.input,
          'not-json',
        );
      },
    );

    test('doStream sends stopSequences in generationConfig', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        captured = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
            .cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
          stopSequences: const ['END'],
        ),
      );

      await stream.stream.toList();

      final config = (captured['generationConfig'] as Map)
          .cast<String, dynamic>();
      expect(config['stopSequences'], ['END']);
    });

    test('doStream ignores malformed JSON and missing content', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        // Malformed JSON -> safely parsed to null and skipped.
        request.response.write('data: {not json}\n\n');
        // Candidate without a content object -> empty-content fallback.
        request.response.write(
          'data: {"candidates":[{"finishReason":"STOP"}]}\n\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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
      expect(parts.whereType<StreamPartTextDelta>(), isEmpty);
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.stop,
      );
    });

    test(
      'doStream emits StreamPartError when reading the body fails',
      () async {
        final server = await _startServer((request) async {
          // Detach the raw socket and promise more bytes than we deliver, then
          // destroy the connection so the client read fails mid-stream.
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.write(
            'HTTP/1.1 200 OK\r\n'
            'content-type: text/event-stream\r\n'
            'content-length: 4096\r\n'
            '\r\n'
            'data: {"candidates":[{"content":{"parts":[{"text":"hi"}]}}]}\n\n',
          );
          await socket.flush();
          socket.destroy();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

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
        expect(parts.whereType<StreamPartError>(), hasLength(1));
      },
    );

    test(
      'doStream emits stream start before error when the body fails before any valid chunk',
      () async {
        final server = await _startServer((request) async {
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

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');

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
        expect(parts[0], isA<StreamPartStreamStart>());
        expect(parts[1], isA<StreamPartError>());
      },
    );

    test(
      'embedding sends provider options and keeps request metadata',
      () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'embeddings': [
                {
                  'values': [0.5, 0.6, 0.7],
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).embedding('text-embedding-004');

        final result = await model.doEmbed(
          const EmbeddingModelV2CallOptions(
            values: ['only'],
            providerOptions: {
              'google': {'taskType': 'RETRIEVAL_QUERY'},
            },
          ),
        );

        expect(captured['taskType'], 'RETRIEVAL_QUERY');
        final requests = (captured['requests'] as List)
            .cast<Map<String, dynamic>>();
        expect(requests.single['model'], 'models/text-embedding-004');
        expect(((requests.single['content'] as Map)['parts'] as List).single, {
          'text': 'only',
        });
        expect(result.embeddings.single.value, 'only');
        expect(result.embeddings.single.embedding, [0.5, 0.6, 0.7]);
      },
    );

    test('reads promptFeedback and warnings list into warnings', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'promptFeedback': {'blockReason': 'SAFETY'},
            'warnings': ['too long', '', 'truncated'],
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

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

      // promptFeedback + the two non-empty warning strings (empty is skipped).
      expect(result.warnings, hasLength(3));
      expect(
        result.warnings.any(
          (warning) =>
              warning is LanguageModelV4OtherWarning &&
              warning.message == 'too long',
        ),
        isTrue,
      );
      expect(
        result.warnings.any(
          (warning) =>
              warning is LanguageModelV4OtherWarning &&
              warning.message == 'truncated',
        ),
        isTrue,
      );
      expect(
        result.warnings.any(
          (warning) =>
              warning is LanguageModelV4OtherWarning &&
              warning.message.contains('promptFeedback'),
        ),
        isTrue,
      );
    });

    test('reads structured and fallback warning variants', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'warnings': [
              {'type': 'unsupported', 'feature': 'topK', 'details': 'ignored'},
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
            'candidates': [
              {
                'finishReason': 'STOP',
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('gemini-2.0-flash');

      final result = await model.doGenerate(
        LanguageModelV4CallOptions(prompt: userPrompt('hi')),
      );

      expect(result.warnings, hasLength(6));
      expect(
        result.warnings
            .whereType<LanguageModelV4UnsupportedWarning>()
            .single
            .feature,
        'topK',
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
    });

    test('resolved api key throws when missing', () async {
      final model = GoogleGenerativeAIProvider().call('gemini-2.0-flash');
      await expectLater(
        model.doGenerate(
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
        throwsA(isA<StateError>()),
      );
    });

    runProviderContractTests(
      providerName: 'google',
      captureRequestBody: _captureGoogleRequestBody,
      expectMultimodalBody: (body) {
        final contents = (body['contents'] as List)
            .cast<Map<String, dynamic>>();
        final user = contents.first;
        final parts = (user['parts'] as List).cast<Map<String, dynamic>>();
        expect(parts[0]['text'], isNotEmpty);
        expect(parts[1]['inlineData'], isA<Map>());
        expect(parts[2]['inlineData'], {
          'mimeType': 'audio/wav',
          'data': base64Encode(utf8.encode('audio')),
        });
      },
      expectToolResultBody: (body) {
        final contents = (body['contents'] as List)
            .cast<Map<String, dynamic>>();
        final tool = contents.last;
        final parts = (tool['parts'] as List).cast<Map<String, dynamic>>();
        final functionResponse = (parts.single['functionResponse'] as Map?)
            ?.cast<String, dynamic>();
        expect(functionResponse?['name'], 'weather');
      },
    );
  });
}

Future<Map<String, dynamic>> _captureGoogleRequestBody(
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
        'candidates': [
          {
            'finishReason': 'STOP',
            'content': {
              'parts': [
                {'text': 'ok'},
              ],
            },
          },
        ],
      }),
    );
    await request.response.close();
  });

  final model = GoogleGenerativeAIProvider(
    apiKey: 'test',
    baseUrl: server.baseUrl,
  ).call('gemini-2.0-flash');
  await model.doGenerate(LanguageModelV4CallOptions(prompt: prompt));
  await server.close();
  return captured;
}

Dio _cancellationClient(HttpClientAdapter adapter, String baseUrl) {
  final client = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {'content-type': 'application/json'},
      responseType: ResponseType.json,
    ),
  );
  client.httpClientAdapter = adapter;
  return client;
}

Future<TestServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) => TestServer.start(handler, pathSuffix: '/v1beta');
