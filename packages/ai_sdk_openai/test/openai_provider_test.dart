import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/contract/language_model_contract.dart';
import '../../ai_sdk_provider/test/support/prompts.dart';
import '../../ai_sdk_provider/test/support/test_server.dart';
import '../../ai_sdk_provider/test/support/tracking_http_client_adapter.dart';

void main() {
  group('OpenAIProvider', () {
    test('doGenerate maps text, tools, finish reason, usage', () async {
      final server = await _startServer((request) async {
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
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'weather in paris')],
              ),
            ],
          ),
          tools: [
            const LanguageModelV4FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
        ),
      );

      expect(result.finishReason, LanguageModelV4FinishReason.toolCalls);
      expect(result.usage.inputTokens.total, 10);
      expect(result.usage.outputTokens.total, 5);
      expect(
        result.content.whereType<LanguageModelV4TextPart>().first.text,
        'I need to check weather.',
      );
      final toolCall = result.content
          .whereType<LanguageModelV4ToolCallPart>()
          .first;
      expect(toolCall.toolName, 'weather');
      expect(toolCall.input, isA<Map>());
    });

    test('doStream parses text and tool deltas into stream parts', () async {
      final server = await _startServer((request) async {
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
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.user,
                content: [LanguageModelV4TextPart(text: 'Hi')],
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
      expect(parts.whereType<StreamPartToolInputStart>().length, 1);
      expect(parts.whereType<StreamPartToolInputDelta>().length, 2);
      expect(parts.whereType<StreamPartToolInputEnd>().length, 1);
      expect(parts.whereType<StreamPartToolCall>().length, 1);
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.toolCalls,
      );
    });

    test('credentials are resolved immediately before each request', () async {
      final authorizations = <String?>[];
      final server = await _startServer((request) async {
        authorizations.add(request.headers.value('authorization'));
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

      var token = 'first-token';
      final provider = OpenAIProvider(
        baseUrl: server.baseUrl,
        credentialProvider: () async => token,
      );

      await provider
          .call('gpt-4.1-mini')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      token = 'second-token';
      await provider
          .call('gpt-4.1-mini')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(authorizations, ['Bearer first-token', 'Bearer second-token']);
    });

    test('reuses an injected client across multiple requests', () async {
      final server = await _startServer((request) async {
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

      final provider = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
        client: client,
      );

      await provider
          .call('gpt-4.1-mini')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('first')));
      await provider
          .call('gpt-4.1-mini')
          .doGenerate(LanguageModelV4CallOptions(prompt: userPrompt('second')));

      expect(interceptedRequests, 2);
    });

    test(
      'stream and auxiliary surfaces resolve credentials immediately before dispatch',
      () async {
        final authorizations = <String, String?>{};
        final server = await _startServer((request) async {
          authorizations[request.uri.path] = request.headers.value(
            'authorization',
          );
          switch (request.uri.path) {
            case '/v1/chat/completions':
              request.response.statusCode = 200;
              request.response.headers.set('content-type', 'text/event-stream');
              request.response.write(
                'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
              );
              request.response.write('data: [DONE]\n\n');
              break;
            case '/v1/embeddings':
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'data': [
                    {
                      'embedding': [0.1, 0.2],
                    },
                  ],
                }),
              );
              break;
            case '/v1/images/generations':
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'data': [
                    {'b64_json': base64Encode(utf8.encode('png'))},
                  ],
                }),
              );
              break;
            case '/v1/audio/speech':
              request.response.statusCode = 200;
              request.response.headers.set('content-type', 'audio/mpeg');
              request.response.add(Uint8List.fromList(utf8.encode('audio')));
              break;
            case '/v1/audio/transcriptions':
              await request.drain<void>();
              request.response.statusCode = 200;
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode({'text': 'ok'}));
              break;
            default:
              fail('Unexpected path: ${request.uri.path}');
          }
          await request.response.close();
        });
        addTearDown(server.close);

        var token = 'stream-token';
        final provider = OpenAIProvider(
          baseUrl: server.baseUrl,
          credentialProvider: () async => token,
        );

        final streamResult = await provider
            .call('gpt-4.1-mini')
            .doStream(LanguageModelV4CallOptions(prompt: userPrompt('stream')));
        await streamResult.stream.drain<void>();

        token = 'embed-token';
        await provider
            .embedding('text-embedding-3-small')
            .doEmbed(const EmbeddingModelV2CallOptions(values: ['a']));

        token = 'image-token';
        await provider
            .image('gpt-image-1')
            .doGenerate(const ImageModelV3CallOptions(prompt: 'cat'));

        token = 'speech-token';
        await provider
            .speech('tts-1')
            .doGenerate(const SpeechModelV1CallOptions(text: 'hi'));

        token = 'transcription-token';
        await provider
            .transcription('whisper-1')
            .doGenerate(
              TranscriptionModelV1CallOptions(
                audio: Uint8List.fromList([1, 2, 3]),
              ),
            );

        expect(authorizations, {
          '/v1/chat/completions': 'Bearer stream-token',
          '/v1/embeddings': 'Bearer embed-token',
          '/v1/images/generations': 'Bearer image-token',
          '/v1/audio/speech': 'Bearer speech-token',
          '/v1/audio/transcriptions': 'Bearer transcription-token',
        });
      },
    );

    test('embedding provider auth wins over request headers', () async {
      String? authorization;
      final server = await _startServer((request) async {
        authorization = request.headers.value('authorization');
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'data': [
              {
                'embedding': [0.1, 0.2],
              },
            ],
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final provider = OpenAIProvider(
        baseUrl: server.baseUrl,
        credentialProvider: () async => 'provider-token',
      );

      await provider
          .embedding('text-embedding-3-small')
          .doEmbed(
            const EmbeddingModelV2CallOptions(
              values: ['a'],
              headers: {'Authorization': 'Bearer request-token'},
            ),
          );

      expect(authorization, 'Bearer provider-token');
    });

    test(
      'dispose closes owned clients and leaves injected clients open',
      () async {
        final server = await _startServer((request) async {
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

        final ownedProvider = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        );
        ownedProvider.dispose();
        await expectLater(
          ownedProvider
              .call('gpt-4.1-mini')
              .doGenerate(
                LanguageModelV4CallOptions(prompt: userPrompt('after-dispose')),
              ),
          throwsA(anything),
        );

        final client = Dio(BaseOptions(baseUrl: server.baseUrl));
        final adapter = attachTrackingAdapter(client);
        final injectedProvider = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
          client: client,
        );

        injectedProvider.dispose(force: false);
        await injectedProvider
            .call('gpt-4.1-mini')
            .doGenerate(
              LanguageModelV4CallOptions(prompt: userPrompt('still-open')),
            );

        expect(adapter.closeCount, 0);
        client.close(force: true);
        expect(adapter.closeCount, 1);
        expect(adapter.lastForce, true);
      },
    );

    test(
      'doStream emits reasoning deltas from the default OpenAI config',
      () async {
        final server = await _startServer((request) async {
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'text/event-stream');
          request.response.write(
            'data: {"choices":[{"delta":{"reasoning_content":"Thinking"}}]}\n\n',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"reasoning_content":"..."}}]}\n\n',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"content":"Answer"}}]}\n\n',
          );
          request.response.write(
            'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n',
          );
          request.response.write('data: [DONE]\n\n');
          await request.response.close();
        });

        addTearDown(server.close);

        final provider = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        );
        final model = provider.call('gpt-4.1-mini');

        final streamResult = await model.doStream(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [LanguageModelV4TextPart(text: 'Hi')],
                ),
              ],
            ),
            providerOptions: const {
              'openai': {'reasoning_effort': 'high'},
            },
          ),
        );

        final parts = await streamResult.stream.toList();
        expect(
          parts
              .whereType<StreamPartReasoningDelta>()
              .map((p) => p.delta)
              .join(),
          'Thinking...',
        );
        expect(
          parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
          'Answer',
        );
      },
    );

    test('maps tool choice modes and strict tool schemas', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _startServer((request) async {
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
        final server = await _startServer((request) async {
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
        expect(call.input, 'not-json');
      },
    );

    test(
      'extracts provider-native source and file parts from annotations',
      () async {
        final server = await _startServer((request) async {
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

        expect(
          result.content.whereType<LanguageModelV4SourcePart>(),
          hasLength(1),
        );
        expect(
          result.content.whereType<LanguageModelV4FilePart>(),
          hasLength(1),
        );
      },
    );

    test('embedding endpoint parses vectors', () async {
      final server = await _startServer((request) async {
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

      final server = await _startServer((request) async {
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
      final server = await _startServer((request) async {
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
            'openai': {
              'user': 'user-123',
              'metadata': {'trace': 'abc'},
            },
          },
        ),
      );

      expect(
        result.content.whereType<LanguageModelV4TextPart>().single.text,
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

      test(
        'doGenerate sends reasoning_effort from snake_case providerOptions',
        () async {
          late Map<String, dynamic> captured;
          final server = await _startServer((request) async {
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
          addTearDown(server.close);

          final model = OpenAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('o3-mini');
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
              providerOptions: const {
                'openai': {'reasoning_effort': 'high'},
              },
            ),
          );

          expect(captured['reasoning_effort'], 'high');
        },
      );

      test(
        'doGenerate sends reasoning_effort from typed options class',
        () async {
          late Map<String, dynamic> captured;
          final server = await _startServer((request) async {
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
          addTearDown(server.close);

          final model = OpenAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('o3-mini');
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
        },
      );

      test(
        'doGenerate converts camelCase reasoningEffort to snake_case',
        () async {
          late Map<String, dynamic> captured;
          final server = await _startServer((request) async {
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
          addTearDown(server.close);

          final model = OpenAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('o3-mini');
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
              providerOptions: const {
                'openai': {'reasoningEffort': 'low'},
              },
            ),
          );

          expect(captured['reasoning_effort'], 'low');
          expect(captured.containsKey('reasoningEffort'), isFalse);
        },
      );

      test('serializes the provider-neutral reasoning control', () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
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
        addTearDown(server.close);

        final model = OpenAIProvider(apiKey: 'test', baseUrl: server.baseUrl)(
          'o3-mini',
        );
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: userPrompt('reason'),
            reasoning: LanguageModelV4Reasoning.high,
          ),
        );

        expect(captured['reasoning_effort'], 'high');
      });

      test('serializes the xhigh provider-neutral reasoning control', () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
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
        addTearDown(server.close);

        final model = OpenAIProvider(apiKey: 'test', baseUrl: server.baseUrl)(
          'o3-mini',
        );
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: userPrompt('reason'),
            reasoning: LanguageModelV4Reasoning.xhigh,
          ),
        );

        expect(captured['reasoning_effort'], 'xhigh');
      });
    });

    // ── responseFormat / response_format: json_schema ───────────────────

    group('responseFormat (native structured output)', () {
      test(
        'doGenerate sends response_format json_schema for JSON output',
        () async {
          late Map<String, dynamic> captured;
          final server = await _startServer((request) async {
            final body = await utf8.decoder.bind(request).join();
            captured = (jsonDecode(body) as Map).cast<String, dynamic>();
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {'content': '{"city":"Paris","tempC":21}'},
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
            LanguageModelV4CallOptions(
              prompt: LanguageModelV4Prompt(
                messages: [
                  LanguageModelV4Message(
                    role: LanguageModelV4Role.user,
                    content: [
                      LanguageModelV4TextPart(text: 'weather in Paris'),
                    ],
                  ),
                ],
              ),
              responseFormat: const LanguageModelV4JsonResponseFormat(
                schema: {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                    'tempC': {'type': 'number'},
                  },
                  'required': ['city', 'tempC'],
                },
              ),
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
        },
      );

      test(
        'doGenerate omits response_format when no format is requested',
        () async {
          late Map<String, dynamic> captured;
          final server = await _startServer((request) async {
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
          addTearDown(server.close);

          final model = OpenAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('gpt-4o-mini');
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
            ),
          );

          expect(captured.containsKey('response_format'), isFalse);
        },
      );
    });

    test('maps multimodal content and tool result messages', () async {
      final imageB64 = base64Encode(utf8.encode('img'));
      final audioB64 = base64Encode(utf8.encode('audio'));

      final server = await _startServer((request) async {
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
                  LanguageModelV4FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('audio')),
                    ),
                    mediaType: 'audio/wav',
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
                      LanguageModelV4TextPart(text: 'failed to fetch'),
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
    });

    test('stream finish includes usage and metadata', () async {
      final server = await _startServer((request) async {
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
      expect(finish.usage.inputTokens.total, 9);
      expect(finish.usage.outputTokens.total, 3);
      expect(finish.providerMetadata?['openai']?['id'], 'chatcmpl_123');
      expect(
        finish.providerMetadata?['openai']?['warnings'],
        contains('other'),
      );
    });

    test('stream emits source/file parts from annotations', () async {
      final server = await _startServer((request) async {
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

    // ── embedding providerOptions + string usage tokens ──────────────────

    test(
      'embedding forwards providerOptions and parses string tokens',
      () async {
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          expect(request.uri.path, '/v1/embeddings');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'embedding': [0.5, 0.6],
                },
              ],
              // total_tokens as a string exercises the String branch of
              // _intOrNull.
              'usage': {'total_tokens': '42'},
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).embedding('text-embedding-3-small');
        final result = await model.doEmbed(
          const EmbeddingModelV2CallOptions(
            values: ['a'],
            providerOptions: {
              'openai': {'dimensions': 256},
            },
          ),
        );

        expect(captured['model'], 'text-embedding-3-small');
        expect(captured['dimensions'], 256);
        expect(result.embeddings.single.embedding, [0.5, 0.6]);
        expect(result.usage?.tokens, 42);
        expect(model.provider, 'openai');
        expect(model.specificationVersion, 'v2');
      },
    );

    // ── image providerOptions + metadata ─────────────────────────────────

    test(
      'image forwards size/n/providerOptions and exposes metadata',
      () async {
        final imageB64 = base64Encode(utf8.encode('png'));
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          expect(request.uri.path, '/v1/images/generations');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {'b64_json': imageB64},
                {'b64_json': ''}, // empty b64 is skipped
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).image('gpt-image-1');
        final result = await model.doGenerate(
          const ImageModelV3CallOptions(
            prompt: 'a cat',
            n: 2,
            size: '1024x1024',
            providerOptions: {
              'openai': {'quality': 'high'},
            },
          ),
        );

        expect(captured['n'], 2);
        expect(captured['size'], '1024x1024');
        // gpt-image-1 always returns base64 and rejects response_format.
        expect(captured.containsKey('response_format'), isFalse);
        expect(captured['quality'], 'high');
        expect(result.images, hasLength(1));
        expect(result.responses.single.modelId, 'gpt-image-1');
        expect(model.provider, 'openai');
        expect(model.specificationVersion, 'v3');
      },
    );

    test('image sends response_format b64_json for dall-e models', () async {
      final imageB64 = base64Encode(utf8.encode('png'));
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        expect(request.uri.path, '/v1/images/generations');
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
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

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).image('dall-e-3');
      final result = await model.doGenerate(
        const ImageModelV3CallOptions(prompt: 'a cat'),
      );

      // dall-e-* default to a hosted URL, so we must request b64_json.
      expect(captured['response_format'], 'b64_json');
      expect(result.images, hasLength(1));
    });

    // ── speech (text-to-speech) ──────────────────────────────────────────

    test(
      'speech sends text/voice/format/speed and returns audio bytes',
      () async {
        final audioBytes = Uint8List.fromList(utf8.encode('mp3-data'));
        late Map<String, dynamic> captured;
        final server = await _startServer((request) async {
          expect(request.uri.path, '/v1/audio/speech');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'audio/mpeg; charset=x');
          request.response.add(audioBytes);
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).speech('tts-1');
        final result = await model.doGenerate(
          const SpeechModelV1CallOptions(
            text: 'hello world',
            voice: 'alloy',
            format: 'mp3',
            speed: 1.25,
            providerOptions: {
              'openai': {'instructions': 'cheerful'},
            },
          ),
        );

        expect(captured['model'], 'tts-1');
        expect(captured['input'], 'hello world');
        expect(captured['voice'], 'alloy');
        expect(captured['response_format'], 'mp3');
        expect(captured['speed'], 1.25);
        expect(captured['instructions'], 'cheerful');
        expect(result.audio, audioBytes);
        // content-type parameters are stripped to the bare media type.
        expect(result.mediaType, 'audio/mpeg');
        expect(model.provider, 'openai');
        expect(model.specificationVersion, 'v1');
      },
    );

    test('speech omits optional fields and defaults media type', () async {
      late Map<String, dynamic> captured;
      final server = await _startServer((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        // No content-type header -> default audio/mpeg.
        request.response.headers.removeAll('content-type');
        request.response.headers.contentType = null;
        request.response.add(utf8.encode('x'));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).speech('tts-1');
      final result = await model.doGenerate(
        const SpeechModelV1CallOptions(text: 'hi'),
      );

      expect(captured.containsKey('voice'), isFalse);
      expect(captured.containsKey('response_format'), isFalse);
      expect(captured.containsKey('speed'), isFalse);
      expect(result.mediaType, 'audio/mpeg');
    });

    // ── transcription (speech-to-text) ───────────────────────────────────

    test('transcription posts multipart audio and parses text', () async {
      late String contentTypeHeader;
      late String rawBody;
      final server = await _startServer((request) async {
        expect(request.uri.path, '/v1/audio/transcriptions');
        contentTypeHeader = request.headers.value('content-type') ?? '';
        rawBody = await utf8.decoder.bind(request).join();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'text': 'hello there'}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).transcription('whisper-1');
      final result = await model.doGenerate(
        TranscriptionModelV1CallOptions(
          audio: Uint8List.fromList(utf8.encode('audio-bytes')),
          audioMediaType: 'audio/wav',
          language: 'en',
          prompt: 'a greeting',
          providerOptions: const {
            'openai': {
              'temperature': 0.2,
              'model': 'ignored-model',
              'response_format': 'text',
              'language': 'ignored-language',
              'prompt': 'ignored-prompt',
            },
          },
        ),
      );

      expect(contentTypeHeader, contains('multipart/form-data'));
      // Multipart form should carry provider fields and controlled call fields.
      expect(rawBody, contains('whisper-1'));
      expect(rawBody, contains('audio.wav'));
      expect(rawBody, contains('a greeting'));
      expect(rawBody, contains('name="language"'));
      expect(rawBody, contains('name="temperature"'));
      expect(rawBody, contains('0.2'));
      expect(rawBody, contains('name="response_format"'));
      expect(rawBody, contains('json'));
      expect(rawBody, isNot(contains('ignored-model')));
      expect(rawBody, isNot(contains('ignored-language')));
      expect(rawBody, isNot(contains('ignored-prompt')));
      expect(result.text, 'hello there');
      expect(model.provider, 'openai');
      expect(model.specificationVersion, 'v1');
    });

    test('transcription maps audio media types to file extensions', () async {
      Future<String> filenameFor(String? mediaType) async {
        late String rawBody;
        final server = await _startServer((request) async {
          rawBody = await utf8.decoder.bind(request).join();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'text': 'ok'}));
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).transcription('whisper-1');
        await model.doGenerate(
          TranscriptionModelV1CallOptions(
            audio: Uint8List.fromList([1, 2, 3]),
            audioMediaType: mediaType,
          ),
        );
        await server.close();
        final match = RegExp('audio\\.([a-z0-9]+)').firstMatch(rawBody);
        return match!.group(1)!;
      }

      expect(await filenameFor('audio/mpeg'), 'mp3');
      expect(await filenameFor('audio/mp3'), 'mp3');
      expect(await filenameFor('audio/wav'), 'wav');
      expect(await filenameFor('audio/ogg'), 'ogg');
      expect(await filenameFor('audio/flac'), 'flac');
      expect(await filenameFor('audio/mp4'), 'm4a');
      expect(await filenameFor('audio/m4a'), 'm4a');
      expect(await filenameFor('audio/webm'), 'webm');
      // unknown / null media types fall back to mp3.
      expect(await filenameFor('audio/unknown'), 'mp3');
      expect(await filenameFor(null), 'mp3');
    });

    test('transcription defaults to empty text when none returned', () async {
      final server = await _startServer((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, dynamic>{}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OpenAIProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).transcription('whisper-1');
      final result = await model.doGenerate(
        TranscriptionModelV1CallOptions(audio: Uint8List.fromList([1, 2, 3])),
      );

      expect(result.text, '');
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
  await model.doGenerate(LanguageModelV4CallOptions(prompt: prompt));
  await server.close();
  return captured;
}

Future<TestServer> _startServer(
  Future<void> Function(HttpRequest request) handler,
) => TestServer.start(handler, pathSuffix: '/v1');
