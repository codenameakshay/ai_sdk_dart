import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/contract/language_model_contract.dart';

void main() {
  group('GoogleGenerativeAIProvider', () {
    test('doGenerate parses text/functionCall and usage', () async {
      final server = await _TestServer.start((request) async {
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

      expect(result.finishReason, LanguageModelV3FinishReason.stop);
      expect(result.usage?.totalTokens, 16);
      expect(
        result.content.whereType<LanguageModelV3TextPart>().single.text,
        'Hello from gemini',
      );
      expect(
        result.content.whereType<LanguageModelV3ToolCallPart>().single.toolName,
        'weather',
      );
    });

    test('doGenerate extracts provider-native source and file parts', () async {
      final server = await _TestServer.start((request) async {
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

      expect(result.content.whereType<LanguageModelV3FilePart>(), hasLength(2));
      final source = result.content
          .whereType<LanguageModelV3SourcePart>()
          .single;
      expect(source.url, 'https://example.com/source');
      expect(source.title, 'Example Source');
    });

    test('doStream parses SSE chunks and finish', () async {
      final server = await _TestServer.start((request) async {
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

      final parts = await stream.stream.toList();
      expect(
        parts.whereType<StreamPartTextDelta>().map((e) => e.delta).join(),
        'Hello',
      );
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.stop,
      );
    });

    test('doStream emits provider-native source and file parts', () async {
      final server = await _TestServer.start((request) async {
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

      final parts = await stream.stream.toList();
      expect(parts.whereType<StreamPartFile>(), hasLength(2));
      final source = parts.whereType<StreamPartSource>().single.source;
      expect(source.url, 'https://example.com/ground');
      expect(source.title, 'Ground');
    });

    test('maps tool choice modes and tool declarations', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _TestServer.start((request) async {
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

    test(
      'preserves invalid strict tool arguments for downstream failure handling',
      () async {
        final server = await _TestServer.start((request) async {
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
        expect(call.input, ['not', 'object']);
      },
    );

    test('embedding parses vectors', () async {
      final server = await _TestServer.start((request) async {
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
      final server = await _TestServer.start((request) async {
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
            'google': {'cachedContent': 'cachedContents/123'},
          },
        ),
      );

      expect(
        result.content.whereType<LanguageModelV3TextPart>().single.text,
        'ok',
      );
    });

    test(
      'maps multimodal and tool result content to google wire format',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));

        final server = await _TestServer.start((request) async {
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
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [
                    LanguageModelV3TextPart(text: 'check this'),
                    LanguageModelV3ImagePart(
                      image: DataContentBytes(
                        Uint8List.fromList(utf8.encode('img')),
                      ),
                      mediaType: 'image/png',
                    ),
                    LanguageModelV3FilePart(
                      data: DataContentUrl(
                        Uri.parse('https://example.com/doc.pdf'),
                      ),
                      mediaType: 'application/pdf',
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
                      output: ToolResultOutputText('failure'),
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
      },
    );

    test('stream finish includes usage and metadata', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: {"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":2,"totalTokenCount":7},"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}\n\n',
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
      expect(finish.usage?.totalTokens, 7);
      expect(finish.providerMetadata?['google']?['model'], 'gemini-2.0-flash');
      expect(finish.providerMetadata?['google']?['warnings'], isNotEmpty);
    });

    test('exposes specification metadata for language model', () {
      final model = const GoogleGenerativeAIProvider().call('gemini-2.0-flash');
      expect(model.provider, 'google');
      expect(model.specificationVersion, 'v3');
      expect(model.modelId, 'gemini-2.0-flash');
    });

    test('exposes specification metadata for embedding model', () {
      final model = const GoogleGenerativeAIProvider().embedding(
        'text-embedding-004',
      );
      expect(model.provider, 'google');
      expect(model.specificationVersion, 'v2');
      expect(model.modelId, 'text-embedding-004');
    });

    test('doGenerate serializes system, generation config, and stops', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
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
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            system: 'You are concise.',
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'hi')],
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
    });

    test('doGenerate tolerates empty candidates and content', () async {
      final server = await _TestServer.start((request) async {
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

      expect(result.content, isEmpty);
      expect(result.finishReason, LanguageModelV3FinishReason.unknown);
      expect(result.usage, isNull);
    });

    test('doGenerate maps each finish reason to the AI SDK value', () async {
      Future<LanguageModelV3FinishReason> resolve(String? reason) async {
        final server = await _TestServer.start((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'candidates': [
                {
                  if (reason != null) 'finishReason': reason,
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
        return result.finishReason;
      }

      expect(await resolve('MAX_TOKENS'), LanguageModelV3FinishReason.length);
      expect(
        await resolve('SAFETY'),
        LanguageModelV3FinishReason.contentFilter,
      );
      expect(
        await resolve('RECITATION'),
        LanguageModelV3FinishReason.contentFilter,
      );
      expect(await resolve('OTHER'), LanguageModelV3FinishReason.other);
      expect(
        await resolve('BLOCKLIST'),
        LanguageModelV3FinishReason.other,
      );
      expect(await resolve(null), LanguageModelV3FinishReason.unknown);
    });

    test('doGenerate parses string and num usage token counts', () async {
      final server = await _TestServer.start((request) async {
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

      expect(result.usage?.inputTokens, 11);
      expect(result.usage?.outputTokens, 4);
      expect(result.usage?.totalTokens, 15);
    });

    test('serializes assistant tool calls into function calls', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
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
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.assistant,
                content: [
                  LanguageModelV3ToolCallPart(
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
      final fnCall = ((contents.single['parts'] as List).single
          as Map)['functionCall'];
      expect(fnCall, {
        'name': 'weather',
        'args': {'city': 'Paris'},
      });
    });

    test('falls back to joined text when no wire parts emitted', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
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
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.assistant,
                content: [
                  LanguageModelV3ReasoningPart(text: 'thinking...'),
                ],
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
      final server = await _TestServer.start((request) async {
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
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'lookup',
                    output: ToolResultOutputContent([
                      LanguageModelV3TextPart(text: 'summary'),
                      LanguageModelV3ImagePart(
                        image: DataContentBytes(
                          Uint8List.fromList(utf8.encode('img')),
                        ),
                        mediaType: 'image/png',
                      ),
                      LanguageModelV3FilePart(
                        data: DataContentBase64(imageB64),
                        mediaType: 'application/pdf',
                        filename: 'doc.pdf',
                      ),
                      // Unsupported inside tool-result content -> 'unsupported'.
                      LanguageModelV3ToolCallPart(
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
          ((contents.single['parts'] as List).single
                  as Map)['functionResponse']
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
      final server = await _TestServer.start((request) async {
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
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            system: 'be brief',
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'hi')],
              ),
            ],
          ),
          maxOutputTokens: 64,
          temperature: 0.2,
          topP: 0.8,
          topK: 10,
          tools: const [
            LanguageModelV3FunctionTool(
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

      expect(
        ((captured['systemInstruction'] as Map)['parts'] as List).first,
        {'text': 'be brief'},
      );
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
      expect(
        captured['toolConfig']['functionCallingConfig']['mode'],
        'ANY',
      );
      expect(captured['cachedContent'], 'cachedContents/9');
    });

    test('doStream surfaces function calls and inline files in deltas', () async {
      final server = await _TestServer.start((request) async {
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

      final parts = await stream.stream.toList();
      expect(
        parts.whereType<StreamPartTextDelta>().map((e) => e.delta).join(),
        'go',
      );
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.length,
      );
    });

    test('doStream ignores malformed JSON and missing content', () async {
      final server = await _TestServer.start((request) async {
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

      final parts = await stream.stream.toList();
      expect(parts.whereType<StreamPartTextDelta>(), isEmpty);
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.stop,
      );
    });

    test('doStream emits StreamPartError when reading the body fails', () async {
      final server = await _TestServer.start((request) async {
        // Detach the raw socket and promise more bytes than we deliver, then
        // destroy the connection so the client read fails mid-stream.
        final socket = await request.response.detachSocket(writeHeaders: false);
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

      final parts = await stream.stream.toList();
      expect(parts.whereType<StreamPartError>(), hasLength(1));
    });

    test('embedding sends provider options and keeps request metadata', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
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
      expect(
        ((requests.single['content'] as Map)['parts'] as List).single,
        {'text': 'only'},
      );
      expect(result.embeddings.single.value, 'only');
      expect(result.embeddings.single.embedding, [0.5, 0.6, 0.7]);
    });

    test('reads promptFeedback and warnings list into warnings', () async {
      final server = await _TestServer.start((request) async {
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

      // promptFeedback + the two non-empty warning strings (empty is skipped).
      expect(result.warnings, hasLength(3));
      expect(result.warnings, contains('too long'));
      expect(result.warnings, contains('truncated'));
      expect(
        result.warnings.any((w) => w.contains('promptFeedback')),
        isTrue,
      );
    });

    test('resolved api key throws when missing', () async {
      final model = const GoogleGenerativeAIProvider().call('gemini-2.0-flash');
      await expectLater(
        model.doGenerate(
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

  String get baseUrl => 'http://${_server.address.host}:${_server.port}/v1beta';

  Future<void> close() => _server.close(force: true);
}
