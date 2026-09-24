import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/cancellation_adapter.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  test('default provider exposes embedding capabilities', () {
    final model = ollama.embedding('nomic-embed-text');
    expect(model.provider, 'ollama');
    expect(model.maxEmbeddingsPerCall, isNull);
    expect(model.supportsParallelCalls, isTrue);
  });

  group('OllamaProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider('llama3');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'llama3');
      expect(model.specificationVersion, 'v4');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider.embedding('nomic-embed-text');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'nomic-embed-text');
      expect(model.specificationVersion, 'v2');
    });

    test('reuses an injected client across multiple requests', () async {
      final server = await _startServer((request) async {
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

      final provider = OllamaProvider(baseUrl: server.baseUrl, client: client);

      await provider(
        'llama3',
      ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      await provider(
        'llama3',
      ).doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(interceptedRequests, 2);
    });

    test(
      'doGenerate cancels an in-flight Dio request via abortSignal',
      () async {
        final adapter = CancellationHttpClientAdapter();
        final client = _cancellationClient(adapter, 'http://localhost/api');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal();
        final model = OllamaProvider(
          baseUrl: 'http://localhost/api',
          client: client,
        ).call('llama3');

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
        final client = _cancellationClient(adapter, 'http://localhost/api');
        addTearDown(() => client.close(force: true));
        final abortSignal = TestAbortSignal()..cancel();
        final model = OllamaProvider(
          baseUrl: 'http://localhost/api',
          client: client,
        ).call('llama3');

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
      final client = _cancellationClient(adapter, 'http://localhost/api');
      addTearDown(() => client.close(force: true));
      final abortSignal = TestAbortSignal();
      final model = OllamaProvider(
        baseUrl: 'http://localhost/api',
        client: client,
      ).call('llama3');

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
              'done': true,
              'done_reason': 'stop',
              'message': {'role': 'assistant', 'content': 'ok'},
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final ownedProvider = OllamaProvider(baseUrl: server.baseUrl);
        ownedProvider.dispose();
        await expectLater(
          ownedProvider('llama3').doGenerate(
            LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
          ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = OllamaProvider(
          baseUrl: server.baseUrl,
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider('llama3').doGenerate(
          LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
        );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );
  });

  test('malformed 2xx chat responses raise AiApiCallError', () async {
    final server = await _startServer((request) async {
      request.response.statusCode = 200;
      await request.response.close();
    });
    addTearDown(server.close);

    await expectLater(
      OllamaProvider(baseUrl: server.baseUrl)
          .call('llama3')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('hi'))),
      throwsA(isA<AiApiCallError>()),
    );
  });

  test('wrong-shaped 2xx chat responses raise AiApiCallError', () async {
    final server = await _startServer((request) async {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': 'not-an-object'}));
      await request.response.close();
    });
    addTearDown(server.close);

    await expectLater(
      OllamaProvider(baseUrl: server.baseUrl)
          .call('llama3')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('hi'))),
      throwsA(isA<AiApiCallError>()),
    );
  });

  group('Ollama doGenerate wire format', () {
    test('forwards providerOptions and headers', () async {
      late Map<String, dynamic> captured;
      String? clientHeader;
      final server = await _startServer((request) async {
        clientHeader = request.headers.value('x-client');
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': {'content': 'ok'},
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      await OllamaProvider(baseUrl: server.baseUrl)
          .call('llama3')
          .doGenerate(
            LanguageModelV4CallOptions(
              prompt: userPrompt('hi'),
              headers: {'x-client': 'test'},
              providerOptions: const {
                'ollama': {'num_ctx': 2048},
              },
            ),
          );

      expect(clientHeader, 'test');
      expect(captured['options'], {'num_ctx': 2048});
      expect(captured['stream'], isFalse);
    });

    test(
      'serializes tools and image content; parses tool calls and real usage',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));
        late Map<String, dynamic> captured;

        final server = await _startServer((request) async {
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
        expect(result.finishReason, LanguageModelV4FinishReason.toolCalls);
        final toolCall = result.content
            .whereType<LanguageModelV4ToolCallPart>()
            .single;
        expect(toolCall.toolName, 'weather');
        expect(toolCall.input, {'city': 'Paris'});
        expect(result.usage.inputTokens.total, 18);
        expect(result.usage.outputTokens.total, 9);
      },
    );

    test('serializes provider-defined tools', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'message': {'content': 'ok'},
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      await OllamaProvider(baseUrl: server.baseUrl)
          .call('llama3')
          .doGenerate(
            LanguageModelV4CallOptions(
              prompt: userPrompt('search'),
              tools: const [
                LanguageModelV4ProviderDefinedTool(
                  id: 'ollama.search',
                  name: 'search',
                  args: {'max_results': 5},
                ),
              ],
            ),
          );

      expect((captured['tools'] as List).single, {
        'type': 'ollama.search',
        'name': 'search',
        'max_results': 5,
      });
    });

    test(
      'serializes tool-result messages back into the conversation',
      () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
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

    test('serializes system prompt, system message, assistant tool calls, '
        'and generation options', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
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
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            system: 'be terse',
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.system,
                content: [LanguageModelV4TextPart(text: 'extra system')],
              ),
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [
                  LanguageModelV4TextPart(text: 'let me check'),
                  LanguageModelV4ToolCallPart(
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
    });

    test(
      'serializes base64 and file-part images and structured tool results',
      () async {
        final rawB64 = base64Encode(utf8.encode('filebytes'));
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
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
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                const LanguageModelV4Message(
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
                      output: ToolResultOutputContent([
                        LanguageModelV4TextPart(text: 'sunny'),
                      ]),
                    ),
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'call_2',
                      toolName: 'structured',
                      output: ToolResultOutputJson({'temperature': 21}),
                    ),
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'call_3',
                      toolName: 'failed',
                      output: ToolResultOutputErrorJson({'message': 'nope'}),
                    ),
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'call_4',
                      toolName: 'denied',
                      output: ToolResultOutputExecutionDenied(
                        'requires approval',
                        'approval-4',
                      ),
                    ),
                  ],
                ),
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    LanguageModelV4ImagePart(
                      image: DataContentBase64(rawB64),
                      mediaType: 'image/png',
                    ),
                    LanguageModelV4FilePart(
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
        final assistant = messages.firstWhere(
          (message) => message['role'] == 'assistant',
        );
        expect(assistant['tool_calls'], isA<List>());
        final toolMessages = messages
            .where((message) => message['role'] == 'tool')
            .toList();
        expect(toolMessages.map((message) => message['content']), [
          'sunny',
          '{"temperature":21}',
          '{"message":"nope"}',
          'requires approval',
        ]);
        // Base64 image part + image file part both land in `images`.
        final user = messages.firstWhere(
          (message) => message['role'] == 'user',
        );
        final images = (user['images'] as List).cast<String>();
        expect(images, [rawB64, rawB64]);
      },
    );

    test('drops remote URL images (Ollama embeds inline only)', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
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
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [
                  LanguageModelV4TextPart(text: 'see this'),
                  LanguageModelV4ImagePart(
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

    test('rejects provider file references before dispatch', () async {
      final model = OllamaProvider().call('llava');
      await expectLater(
        model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                const LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [
                    LanguageModelV4ImagePart(
                      image: DataContentProviderReference(
                        namespace: 'files',
                        id: 'file-1',
                      ),
                      mediaType: 'image/png',
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

    test(
      'parses a tool call with no arguments as an empty input map',
      () async {
        final server = await _startServer((request) async {
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
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [LanguageModelV4TextPart(text: 'time?')],
                ),
              ],
            ),
          ),
        );

        final call = result.content
            .whereType<LanguageModelV4ToolCallPart>()
            .single;
        expect(call.toolName, 'now');
        expect(call.input, <String, dynamic>{});
      },
    );

    test('parses tool calls and usage from the NDJSON stream', () async {
      final server = await _startServer((request) async {
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
      expect(
        parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
        'thinking',
      );
      final start = parts.whereType<StreamPartToolInputStart>().single;
      expect(start.toolName, 'weather');
      final end = parts.whereType<StreamPartToolInputEnd>().single;
      expect(end.id, start.id);
      expect(parts.whereType<StreamPartToolCall>().single.toolCall.input, {
        'city': 'Paris',
      });
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV4FinishReason.toolCalls);
      expect(finish.usage.inputTokens.total, 6);
      expect(finish.usage.outputTokens.total, 3);
    });

    test(
      'forwards providerOptions and headers while forcing stream mode',
      () async {
        late Map<String, dynamic> captured;
        String? clientHeader;
        final server = await _startServer((request) async {
          clientHeader = request.headers.value('x-client');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '${jsonEncode({
              'message': {'content': 'ok'},
              'done': true,
              'done_reason': 'stop',
            })}\n',
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final result = await OllamaProvider(baseUrl: server.baseUrl)
            .call('llama3')
            .doStream(
              LanguageModelV4CallOptions(
                prompt: userPrompt('hi'),
                headers: {'x-client': 'test'},
                providerOptions: const {
                  'ollama': {'num_ctx': 4096},
                },
              ),
            );
        await result.stream.drain<void>();

        expect(clientHeader, 'test');
        expect(captured['options'], {'num_ctx': 4096});
        expect(captured['stream'], isTrue);
      },
    );

    test(
      'plain text stream maps the length finish reason (no tool calls)',
      () async {
        final server = await _startServer((request) async {
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
        expect(
          parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
          'hello world',
        );
        final finish = parts.whereType<StreamPartFinish>().single;
        expect(finish.finishReason, LanguageModelV4FinishReason.length);
        expect(finish.usage.inputTokens.total, 4);
        expect(finish.usage.outputTokens.total, 2);
      },
    );

    test('emits a StreamPartError when stream processing throws', () async {
      final server = await _startServer((request) async {
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
    });
  });

  group('Ollama doEmbed wire format', () {
    test('forwards embedding providerOptions and headers', () async {
      late Map<String, dynamic> captured;
      String? clientHeader;
      final server = await _startServer((request) async {
        clientHeader = request.headers.value('x-client');
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'embeddings': [
              [0.1],
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      await OllamaProvider(baseUrl: server.baseUrl)
          .embedding('nomic-embed-text')
          .doEmbed(
            const EmbeddingModelV2CallOptions<String>(
              values: ['hello'],
              headers: {'x-client': 'test'},
              providerOptions: {
                'ollama': {'truncate': true},
              },
            ),
          );

      expect(clientHeader, 'test');
      expect(captured['truncate'], isTrue);
    });

    test('posts to /api/embed and parses embeddings in order', () async {
      late Map<String, dynamic> captured;
      String? path;
      final server = await _startServer((request) async {
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

    test('rejects a response without an embeddings list', () async {
      final server = await _startServer((request) async {
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

      await expectLater(
        model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['only']),
        ),
        throwsA(isA<AiApiCallError>()),
      );
    });

    test('normalizes numeric vectors', () async {
      final server = await _startServer((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'embeddings': [
              [1, 2.5],
              [-3, 4],
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final result = await OllamaProvider(baseUrl: server.baseUrl)
          .embedding('nomic-embed-text')
          .doEmbed(
            const EmbeddingModelV2CallOptions<String>(values: ['a', 'b']),
          );

      expect(result.embeddings, hasLength(2));
      expect(result.embeddings.map((embedding) => embedding.value), ['a', 'b']);
      expect(result.embeddings.map((embedding) => embedding.embedding), [
        [1.0, 2.5],
        [-3.0, 4.0],
      ]);
    });
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

Future<TestServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) => TestServer.start(handler, pathSuffix: '/api');
