import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/contract/language_model_contract.dart';

void main() {
  group('AnthropicProvider', () {
    test('doGenerate maps text/tool_use/reasoning and usage', () async {
      final server = await _TestServer.start((request) async {
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

      expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
      expect(result.usage?.inputTokens, 12);
      expect(
        result.content.whereType<LanguageModelV3ReasoningPart>().length,
        1,
      );
      expect(
        result.content.whereType<LanguageModelV3ToolCallPart>().single.toolName,
        'weather',
      );
    });

    test('doStream parses content and message delta events', () async {
      final server = await _TestServer.start((request) async {
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
        parts.whereType<StreamPartToolCallStart>().single.toolName,
        'weather',
      );
      expect(parts.whereType<StreamPartToolCallEnd>().single.input, isA<Map>());
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.toolCalls,
      );
    });

    test('maps tool choice modes to anthropic wire format', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _TestServer.start((request) async {
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
      final server = await _TestServer.start((request) async {
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
      final server = await _TestServer.start((request) async {
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

      final source = result.content
          .whereType<LanguageModelV3SourcePart>()
          .single;
      expect(source.url, 'https://example.com/a');
      expect(source.title, 'Example A');
    });

    test(
      'preserves invalid strict tool arguments for downstream failure handling',
      () async {
        final server = await _TestServer.start((request) async {
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
        expect(call.input, 'not-an-object');
      },
    );

    test('passes providerOptions into request body', () async {
      final server = await _TestServer.start((request) async {
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
            'anthropic': {
              'metadata': {'trace_id': 'abc'},
            },
          },
        ),
      );

      expect(
        result.content.whereType<LanguageModelV3TextPart>().single.text,
        'ok',
      );
    });

    test(
      'maps multimodal and tool result content to anthropic wire format',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));
        final fileB64 = base64Encode(utf8.encode('pdf'));

        final server = await _TestServer.start((request) async {
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
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [
                    LanguageModelV3TextPart(text: 'check these files'),
                    LanguageModelV3ImagePart(
                      image: DataContentBytes(
                        Uint8List.fromList(utf8.encode('img')),
                      ),
                      mediaType: 'image/png',
                    ),
                    LanguageModelV3FilePart(
                      data: DataContentBase64(fileB64),
                      mediaType: 'application/pdf',
                      filename: 'doc.pdf',
                    ),
                  ],
                ),
                LanguageModelV3Message(
                  role: LanguageModelV3Role.tool,
                  content: [
                    LanguageModelV3ToolResultPart(
                      toolCallId: 'toolu_1',
                      toolName: 'weather',
                      isError: true,
                      output: ToolResultOutputContent([
                        LanguageModelV3TextPart(text: 'error payload'),
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
      },
    );

    test('stream finish includes usage and metadata', () async {
      final server = await _TestServer.start((request) async {
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
      expect(finish.usage?.inputTokens, 8);
      expect(finish.usage?.outputTokens, 3);
      expect(finish.providerMetadata?['anthropic']?['id'], 'msg_123');
      expect(
        finish.providerMetadata?['anthropic']?['warnings'],
        contains('careful'),
      );
    });

    // ── AnthropicThinkingOptions / speed ─────────────────────────────────

    group('AnthropicThinkingOptions', () {
      test('toMap produces enabled thinking object with budget_tokens', () {
        final opts = const AnthropicThinkingOptions(budgetTokens: 5000);
        final map = opts.toMap();
        expect(map['thinking'], {'type': 'enabled', 'budget_tokens': 5000});
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
        );
        final map = langOpts.toMap();
        expect(map['thinking'], {'type': 'enabled', 'budget_tokens': 2000});
      });

      test('doGenerate sends thinking object when passed via providerOptions',
          () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
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
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'think')],
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
      });

      test('doGenerate sends disabled thinking when speed=fast', () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
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
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'quick')],
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
    });

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
        expect(content[2]['type'], anyOf('document', 'image'));
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
  });
}

Future<Map<String, dynamic>> _captureAnthropicRequestBody(
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
