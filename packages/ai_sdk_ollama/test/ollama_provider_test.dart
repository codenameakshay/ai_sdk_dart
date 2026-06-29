import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider('llama3');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'llama3');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider.embedding('nomic-embed-text');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'nomic-embed-text');
      expect(model.specificationVersion, 'v2');
    });

    test('default ollama constant is an OllamaProvider', () {
      expect(ollama, isA<OllamaProvider>());
    });

    test('accepts custom baseUrl', () {
      final provider = OllamaProvider(
        baseUrl: 'http://192.168.1.100:11434/api',
      );
      final model = provider('phi3');
      expect(model.modelId, 'phi3');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = OllamaProvider();
      final model = provider('llama3');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('embedding model implements EmbeddingModelV2<String>', () {
      final provider = OllamaProvider();
      final model = provider.embedding('nomic-embed-text');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });

  group('Ollama doGenerate wire format', () {
    test(
      'serializes tools and image content; parses tool calls and real usage',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));
        late Map<String, dynamic> captured;

        final server = await _TestServer.start((request) async {
          expect(request.uri.path, '/api/chat');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {
                'role': 'assistant',
                'content': 'Let me check.',
                'tool_calls': [
                  {
                    'function': {
                      'name': 'weather',
                      'arguments': {'city': 'Paris'},
                    },
                  },
                ],
              },
              'prompt_eval_count': 18,
              'eval_count': 9,
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(
          baseUrl: server.baseUrl,
        ).call('llama3.2-vision');

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
                  ],
                ),
              ],
            ),
            tools: const [
              LanguageModelV3FunctionTool(
                name: 'weather',
                description: 'Get the weather',
                inputSchema: {'type': 'object'},
              ),
            ],
          ),
        );

        // Tools serialized into Ollama's OpenAI-style tools field.
        final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
        final fn = tools.single['function'] as Map<String, dynamic>;
        expect(tools.single['type'], 'function');
        expect(fn['name'], 'weather');
        expect(fn['description'], 'Get the weather');
        expect(fn['parameters'], {'type': 'object'});

        // Image content serialized into the message's images field (no prefix).
        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        final userMessage = messages.single;
        expect(userMessage['content'], 'describe this');
        expect((userMessage['images'] as List).single, imageB64);

        // Tool calls parsed; real usage tokens reported.
        expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
        final toolCall = result.content
            .whereType<LanguageModelV3ToolCallPart>()
            .single;
        expect(toolCall.toolName, 'weather');
        expect(toolCall.input, {'city': 'Paris'});
        expect(result.usage?.inputTokens, 18);
        expect(result.usage?.outputTokens, 9);
        expect(result.usage?.totalTokens, 27);
      },
    );

    test(
      'serializes tool-result messages back into the conversation',
      () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {'role': 'assistant', 'content': 'ok'},
              'prompt_eval_count': 5,
              'eval_count': 2,
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');

        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.tool,
                  content: [
                    LanguageModelV3ToolResultPart(
                      toolCallId: 'call_1',
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
        final toolMessage = messages.single;
        expect(toolMessage['role'], 'tool');
        expect(toolMessage['tool_name'], 'weather');
        expect(toolMessage['content'], 'sunny');
      },
    );

    test(
      'serializes system prompt, system message, assistant tool calls, '
      'and generation options',
      () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {'role': 'assistant', 'content': 'ok'},
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');

        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              system: 'be terse',
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.system,
                  content: [LanguageModelV3TextPart(text: 'extra system')],
                ),
                LanguageModelV3Message(
                  role: LanguageModelV3Role.assistant,
                  content: [
                    LanguageModelV3TextPart(text: 'let me check'),
                    LanguageModelV3ToolCallPart(
                      toolCallId: 'call_1',
                      toolName: 'weather',
                      input: {'city': 'Paris'},
                    ),
                  ],
                ),
              ],
            ),
            temperature: 0.5,
            topP: 0.9,
            topK: 40,
            seed: 7,
            maxOutputTokens: 128,
            stopSequences: const ['STOP'],
          ),
        );

        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        // prompt.system becomes the first system message.
        expect(messages[0]['role'], 'system');
        expect(messages[0]['content'], 'be terse');
        // An explicit system-role message is preserved.
        expect(messages[1]['role'], 'system');
        expect(messages[1]['content'], 'extra system');
        // Assistant tool calls serialized into Ollama's tool_calls field.
        final assistant = messages[2];
        expect(assistant['role'], 'assistant');
        expect(assistant['content'], 'let me check');
        final toolCalls = (assistant['tool_calls'] as List)
            .cast<Map<String, dynamic>>();
        final fn = toolCalls.single['function'] as Map<String, dynamic>;
        expect(fn['name'], 'weather');
        expect(fn['arguments'], {'city': 'Paris'});
        // Generation options serialized under the Ollama options field.
        final options = captured['options'] as Map<String, dynamic>;
        expect(options['temperature'], 0.5);
        expect(options['top_p'], 0.9);
        expect(options['top_k'], 40);
        expect(options['seed'], 7);
        expect(options['num_predict'], 128);
        expect(options['stop'], ['STOP']);
      },
    );

    test(
      'serializes base64 and file-part images and structured tool results',
      () async {
        final rawB64 = base64Encode(utf8.encode('filebytes'));
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {'role': 'assistant', 'content': 'ok'},
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(baseUrl: server.baseUrl).call('llava');

        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.tool,
                  content: [
                    LanguageModelV3ToolResultPart(
                      toolCallId: 'call_1',
                      toolName: 'weather',
                      output: ToolResultOutputContent([
                        LanguageModelV3TextPart(text: 'sunny'),
                      ]),
                    ),
                  ],
                ),
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [
                    LanguageModelV3ImagePart(
                      image: DataContentBase64(rawB64),
                      mediaType: 'image/png',
                    ),
                    LanguageModelV3FilePart(
                      data: DataContentBytes(
                        Uint8List.fromList(utf8.encode('filebytes')),
                      ),
                      mediaType: 'image/jpeg',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        // ToolResultOutputContent flattened to its text parts.
        expect(messages[0]['role'], 'tool');
        expect(messages[0]['content'], 'sunny');
        // Base64 image part + image file part both land in `images`.
        final images = (messages[1]['images'] as List).cast<String>();
        expect(images, [rawB64, rawB64]);
      },
    );

    test('drops remote URL images (Ollama embeds inline only)', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'done': true,
            'done_reason': 'stop',
            'message': {'role': 'assistant', 'content': 'ok'},
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OllamaProvider(baseUrl: server.baseUrl).call('llava');
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3TextPart(text: 'see this'),
                  LanguageModelV3ImagePart(
                    image: DataContentUrl(Uri.parse('https://x/y.png')),
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
      expect(messages.single['content'], 'see this');
      // No images field because the URL image is not embeddable.
      expect(messages.single.containsKey('images'), isFalse);
    });

    test(
      'parses a tool call with no arguments as an empty input map',
      () async {
        final server = await _TestServer.start((request) async {
          await utf8.decoder.bind(request).join();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  {
                    'function': {'name': 'now'},
                  },
                ],
              },
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');
        final result = await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'time?')],
                ),
              ],
            ),
          ),
        );

        final call = result.content
            .whereType<LanguageModelV3ToolCallPart>()
            .single;
        expect(call.toolName, 'now');
        expect(call.input, <String, dynamic>{});
      },
    );

    test('parses tool calls and usage from the NDJSON stream', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '${jsonEncode({
            'message': {'role': 'assistant', 'content': 'thinking'},
            'done': false,
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'function': {
                    'name': 'weather',
                    'arguments': {'city': 'Paris'},
                  },
                },
              ],
            },
            'done': true,
            'done_reason': 'stop',
            'prompt_eval_count': 6,
            'eval_count': 3,
          })}\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');

      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'weather?')],
              ),
            ],
          ),
        ),
      );

      final parts = await streamResult.stream.toList();
      expect(
        parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
        'thinking',
      );
      final start = parts.whereType<StreamPartToolCallStart>().single;
      expect(start.toolName, 'weather');
      final end = parts.whereType<StreamPartToolCallEnd>().single;
      expect(end.input, {'city': 'Paris'});
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV3FinishReason.toolCalls);
      expect(finish.usage?.inputTokens, 6);
      expect(finish.usage?.outputTokens, 3);
    });

    test(
      'plain text stream maps the length finish reason (no tool calls)',
      () async {
        final server = await _TestServer.start((request) async {
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '${jsonEncode({
              'message': {'role': 'assistant', 'content': 'hello '},
              'done': false,
            })}\n',
          );
          request.response.write(
            '${jsonEncode({
              'message': {'role': 'assistant', 'content': 'world'},
              'done': true,
              'done_reason': 'length',
              'prompt_eval_count': 4,
              'eval_count': 2,
            })}\n',
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');
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
        expect(
          parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
          'hello world',
        );
        final finish = parts.whereType<StreamPartFinish>().single;
        expect(finish.finishReason, LanguageModelV3FinishReason.length);
        expect(finish.usage?.inputTokens, 4);
        expect(finish.usage?.outputTokens, 2);
      },
    );

    test(
      'emits a StreamPartError when stream processing throws',
      () async {
        final server = await _TestServer.start((request) async {
          // 200 response whose body is invalid UTF-8, so utf8.decode throws
          // inside _processStream and is routed to a StreamPartError.
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.add([0xff, 0xfe, 0xfd]);
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');
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
        expect(parts.whereType<StreamPartError>(), isNotEmpty);
      },
    );
  });

  group('Ollama doEmbed wire format', () {
    test('posts to /api/embed and parses embeddings in order', () async {
      late Map<String, dynamic> captured;
      String? path;
      final server = await _TestServer.start((request) async {
        path = request.uri.path;
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'embeddings': [
              [0.1, 0.2],
              [0.3, 0.4],
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OllamaProvider(
        baseUrl: server.baseUrl,
      ).embedding('nomic-embed-text');

      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['a', 'b']),
      );

      expect(path, '/api/embed');
      expect(captured['model'], 'nomic-embed-text');
      expect(captured['input'], ['a', 'b']);
      expect(result.embeddings, hasLength(2));
      expect(result.embeddings[0].value, 'a');
      expect(result.embeddings[0].embedding, [0.1, 0.2]);
      expect(result.embeddings[1].value, 'b');
      expect(result.embeddings[1].embedding, [0.3, 0.4]);
    });

    test('tolerates a response without an embeddings list', () async {
      final server = await _TestServer.start((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OllamaProvider(
        baseUrl: server.baseUrl,
      ).embedding('nomic-embed-text');

      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['only']),
      );
      expect(result.embeddings, isEmpty);
    });
  });
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

  String get baseUrl => 'http://${_server.address.host}:${_server.port}/api';

  Future<void> close() => _server.close(force: true);
}
