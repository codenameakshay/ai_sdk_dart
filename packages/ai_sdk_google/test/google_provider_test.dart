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
