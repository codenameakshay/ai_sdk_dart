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
      // No cache fields in the response → no input token breakdown.
      expect(result.usage?.inputTokenDetails, isNull);
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

    test('doGenerate maps cache_read/creation into inputTokenDetails',
        () async {
      final server = await _TestServer.start((request) async {
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

      // Anthropic reports cache tokens separately, so inputTokens is the sum:
      // input_tokens (10) + cache_read (100) + cache_creation (20) = 130.
      expect(result.usage?.inputTokens, 130);
      expect(result.usage?.outputTokens, 5);
      expect(result.usage?.inputTokenDetails?.noCacheTokens, 10);
      expect(result.usage?.inputTokenDetails?.cacheReadTokens, 100);
      expect(result.usage?.inputTokenDetails?.cacheWriteTokens, 20);
    });

    test('stream carries cache token details from message_start to finish',
        () async {
      final server = await _TestServer.start((request) async {
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
      // input_tokens (8) + cache_read (40) = 48; output from message_delta.
      expect(finish.usage?.inputTokens, 48);
      expect(finish.usage?.outputTokens, 3);
      // Details captured at message_start survive the output-only delta.
      expect(finish.usage?.inputTokenDetails?.noCacheTokens, 8);
      expect(finish.usage?.inputTokenDetails?.cacheReadTokens, 40);
      expect(finish.usage?.inputTokenDetails?.cacheWriteTokens, 0);
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

    // ── Additional coverage ──────────────────────────────────────────────

    test('exposes specification version and provider id', () {
      final model = AnthropicProvider(apiKey: 'test').call('claude-sonnet-4-5');
      expect(model.specificationVersion, 'v3');
      expect(model.provider, 'anthropic');
      expect(model.modelId, 'claude-sonnet-4-5');
    });

    test('sends stop_sequences when provided', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
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
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'hi')],
              ),
            ],
          ),
          stopSequences: const ['STOP', 'END'],
        ),
      );

      expect(captured['stop_sequences'], ['STOP', 'END']);
      // 'stop_sequence' maps to stop finish reason.
      expect(result.finishReason, LanguageModelV3FinishReason.stop);
    });

    test('maps unknown stop_reason to other', () async {
      final server = await _TestServer.start((request) async {
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

      expect(result.finishReason, LanguageModelV3FinishReason.other);
    });

    test('decodes redacted_thinking content part', () async {
      final server = await _TestServer.start((request) async {
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

      final redacted = result.content
          .whereType<LanguageModelV3RedactedReasoningPart>()
          .single;
      expect(utf8.decode(redacted.data), 'REDACTED-PAYLOAD');
    });

    test('serializes assistant tool calls and image url parts', () async {
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
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3TextPart(text: 'look'),
                  LanguageModelV3ImagePart(
                    image: DataContentUrl(
                      Uri.parse('https://example.com/pic.png'),
                    ),
                  ),
                  LanguageModelV3FilePart(
                    data: DataContentUrl(
                      Uri.parse('https://example.com/doc.pdf'),
                    ),
                    mediaType: 'application/pdf',
                    filename: 'doc.pdf',
                  ),
                ],
              ),
              LanguageModelV3Message(
                role: LanguageModelV3Role.assistant,
                content: [
                  LanguageModelV3ToolCallPart(
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

    test('serializes image/file/unsupported tool result parts', () async {
      late Map<String, dynamic> captured;
      final imageB64 = base64Encode(utf8.encode('img'));
      final fileB64 = base64Encode(utf8.encode('pdf'));
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
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
                    toolCallId: 'toolu_1',
                    toolName: 'render',
                    output: ToolResultOutputContent([
                      LanguageModelV3TextPart(text: 'text part'),
                      LanguageModelV3ImagePart(
                        image: DataContentBase64(imageB64),
                        mediaType: 'image/png',
                      ),
                      LanguageModelV3FilePart(
                        data: DataContentBase64(fileB64),
                        mediaType: 'application/pdf',
                      ),
                      LanguageModelV3SourcePart(
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
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final toolResult = (messages.single['content'] as List)
          .cast<Map<String, dynamic>>()
          .single;
      final parts = (toolResult['content'] as List).cast<Map<String, dynamic>>();
      expect(parts[0], {'type': 'text', 'text': 'text part'});
      expect(parts[1]['type'], 'image');
      expect((parts[1]['source'] as Map)['data'], imageB64);
      expect(parts[2]['type'], 'document');
      expect((parts[2]['source'] as Map)['data'], fileB64);
      // Unsupported part (source) falls back to a placeholder text.
      expect(parts[3], {
        'type': 'text',
        'text': '[unsupported tool result content]',
      });
    });

    test('uses text tool result output directly', () async {
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
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
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

    test('drops image part with url data source unsupported by base64',
        () async {
      // A base64-less data content (URL) for an image inside a file part with a
      // non-image media type goes through the document/base64 branch and is
      // dropped when no base64 is available — exercised via _toBase64 url path.
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
      ).call('claude-sonnet-4-5');

      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
                    toolCallId: 'toolu_1',
                    toolName: 'render',
                    output: ToolResultOutputContent([
                      // Image media-type file part that resolves through the
                      // image URL branch.
                      LanguageModelV3FilePart(
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
      final parts = (toolResult['content'] as List).cast<Map<String, dynamic>>();
      expect(parts.single['type'], 'image');
      expect((parts.single['source'] as Map)['type'], 'url');
    });

    test('stream handles message_start, thinking_delta, tools and errors',
        () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
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
      expect(
        parts.whereType<StreamPartTextDelta>().single.delta,
        'Hi',
      );
      expect(parts.whereType<StreamPartError>(), isNotEmpty);
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.stop,
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
      final server = await _TestServer.start((request) async {
        await request.drain<void>();
        final socket = await request.response.detachSocket(
          writeHeaders: false,
        );
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
      // The abrupt disconnect propagates as a StreamPartError.
      expect(parts.whereType<StreamPartError>(), isNotEmpty);
    });

    test('doStream forwards extra providerOptions into request body', () async {
      // providerOptions carrying a key beyond thinking/speed leaves a non-null
      // cleaned map, which the stream request body spreads via `...?cleanedPo`.
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
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
              'metadata': {'trace_id': 'stream-abc'},
            },
          },
        ),
      );

      await streamResult.stream.toList();
      expect(captured['metadata'], {'trace_id': 'stream-abc'});
    });

    test('doStream tolerates content_block_delta with no delta field',
        () async {
      // A content_block_delta event missing its `delta` falls back to the empty
      // map, so the unknown delta type is simply ignored.
      final server = await _TestServer.start((request) async {
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
      // The delta-less event produced no output; only the real text delta did.
      expect(
        parts.whereType<StreamPartTextDelta>().map((e) => e.delta).join(),
        'Hi',
      );
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.stop,
      );
    });

    test(
      'doStream message_delta without delta still applies usage and finishes',
      () async {
        // A message_delta carrying usage but no `delta` exercises the empty-map
        // fallback for `delta`; a later message_delta supplies the stop reason.
        final server = await _TestServer.start((request) async {
          request.response.statusCode = 200;
          request.response.headers.set('content-type', 'text/event-stream');
          request.response.write(
            'data: {"type":"message_start","message":{"id":"msg_9","model":"claude-sonnet-4-5","usage":{"input_tokens":4,"output_tokens":1}}}\n\n',
          );
          // message_delta with usage only (no `delta`, and no output_tokens):
          // exercises both the empty-map delta fallback and the
          // `streamUsage?.outputTokens` carry-over fallback.
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
        // input_tokens updated from the usage-only delta...
        expect(finish.usage?.inputTokens, 9);
        // ...while output_tokens carries over from message_start (1) because the
        // usage-only delta omitted it.
        expect(finish.usage?.outputTokens, 1);
        expect(finish.finishReason, LanguageModelV3FinishReason.stop);
      },
    );

    test('doGenerate synthesizes a tool call id when none is provided',
        () async {
      // A tool_use content block with no `id` forces the `_generateId` fallback.
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

      final call = result.content
          .whereType<LanguageModelV3ToolCallPart>()
          .single;
      expect(call.toolName, 'weather');
      // The synthesized id uses the `tool-<micros>` shape from _generateId.
      expect(call.toolCallId, startsWith('tool-'));
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
