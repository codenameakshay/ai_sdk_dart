import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAICompatibleChatLanguageModel', () {
    // ── tool serialization + tool_choice modes ──────────────────────────
    test('serializes tools (strict) and tool_choice modes', () async {
      final seenBodies = <Map<String, dynamic>>[];
      final server = await _TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        seenBodies.add((jsonDecode(body) as Map).cast<String, dynamic>());
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 'ok'},
            },
          ],
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);

      Future<void> call(LanguageModelV3ToolChoice toolChoice) {
        return model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: _userPrompt('hi'),
            tools: const [
              LanguageModelV3FunctionTool(
                name: 'weather',
                description: 'Get the weather',
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
      final fn = tools.single['function'] as Map<String, dynamic>;
      expect(fn['name'], 'weather');
      expect(fn['description'], 'Get the weather');
      expect(fn['strict'], isTrue);
      expect(fn['parameters'], {'type': 'object'});
    });

    test('omits tools when supportsTools is false', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          supportsTools: false,
        ),
      );

      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          tools: const [
            LanguageModelV3FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
        ),
      );

      expect(captured.containsKey('tools'), isFalse);
      expect(captured.containsKey('tool_choice'), isFalse);
    });

    // ── multimodal image part serialization ──────────────────────────────
    test('serializes multimodal image + audio content parts', () async {
      final imageB64 = base64Encode(utf8.encode('img'));
      final audioB64 = base64Encode(utf8.encode('audio'));
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3TextPart(text: 'describe'),
                  LanguageModelV3ImagePart(
                    image: DataContentBytes(
                      Uint8List.fromList(utf8.encode('img')),
                    ),
                    mediaType: 'image/png',
                  ),
                  LanguageModelV3FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('audio')),
                    ),
                    mediaType: 'audio/wav',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final content = (messages.first['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      expect(
        (content[1]['image_url'] as Map)['url'],
        'data:image/png;base64,$imageB64',
      );
      expect(content[2]['type'], 'input_audio');
      expect((content[2]['input_audio'] as Map)['data'], audioB64);
    });

    test('flattens content to text when supportsMultimodal is false', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          supportsMultimodal: false,
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3TextPart(text: 'describe'),
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
        ),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(messages.first['content'], 'describe');
    });

    // ── response_format json_schema ──────────────────────────────────────
    test('serializes response_format json_schema from outputSchema', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('weather'),
          outputSchema: const {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
            'required': ['city'],
          },
        ),
      );

      final rf = captured['response_format'] as Map<String, dynamic>;
      expect(rf['type'], 'json_schema');
      final js = rf['json_schema'] as Map<String, dynamic>;
      expect(js['name'], 'response');
      expect(js['strict'], isTrue);
      expect(js['schema'], isA<Map>());
    });

    test('omits response_format when flag disabled', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'test',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          supportsResponseFormatJsonSchema: false,
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          outputSchema: const {'type': 'object'},
        ),
      );

      expect(captured.containsKey('response_format'), isFalse);
    });

    // ── non-streaming tool-call parsing + finish reason + usage ──────────
    test('doGenerate parses tool calls, finish reason, usage', () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'id': 'chatcmpl_1',
          'model': 'm',
          'choices': [
            {
              'finish_reason': 'tool_calls',
              'message': {
                'content': 'checking',
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
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('weather')),
      );

      expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
      expect(result.usage?.totalTokens, 15);
      expect(
        result.content.whereType<LanguageModelV3TextPart>().single.text,
        'checking',
      );
      final toolCall = result.content
          .whereType<LanguageModelV3ToolCallPart>()
          .single;
      expect(toolCall.toolName, 'weather');
      expect(toolCall.input, {'city': 'Paris'});
    });

    // ── SSE text + tool-call streaming ───────────────────────────────────
    test('doStream parses text deltas and tool-call deltas', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"choices":[{"delta":{"content":"Hel"}}]}',
          '{"choices":[{"delta":{"content":"lo"}}]}',
          '{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"weather","arguments":"{\\"city\\":\\""}}]}}]}',
          '{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"Paris\\"}"}}]}}]}',
          '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );

      final parts = await streamResult.stream.toList();
      expect(parts.whereType<StreamPartTextStart>().length, 1);
      expect(
        parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
        'Hello',
      );
      expect(parts.whereType<StreamPartToolCallStart>().length, 1);
      expect(
        parts.whereType<StreamPartToolCallDelta>().length,
        greaterThanOrEqualTo(1),
      );
      final end = parts.whereType<StreamPartToolCallEnd>().single;
      expect(end.toolName, 'weather');
      expect(end.input, {'city': 'Paris'});
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV3FinishReason.toolCalls,
      );
    });

    test('stream finish includes usage and provider metadata', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"id":"chatcmpl_123","model":"m","warnings":["careful"],"choices":[{"delta":{"content":"Hi"}}]}',
          '{"id":"chatcmpl_123","model":"m","usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12},"choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      final finish = (await streamResult.stream.toList())
          .whereType<StreamPartFinish>()
          .single;
      expect(finish.usage?.totalTokens, 12);
      expect(finish.providerMetadata?['test']?['id'], 'chatcmpl_123');
      expect(
        finish.providerMetadata?['test']?['warnings'],
        contains('careful'),
      );
    });

    // ── finish-reason mapping ────────────────────────────────────────────
    test('maps finish reasons', () async {
      Future<LanguageModelV3FinishReason> reasonFor(String? raw) async {
        final server = await _TestServer.start((request) async {
          _writeJson(request, {
            'choices': [
              {
                'finish_reason': raw,
                'message': {'content': 'ok'},
              },
            ],
          });
        });
        addTearDown(server.close);
        final model = _bearerModel(server.baseUrl);
        final result = await model.doGenerate(
          LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
        );
        await server.close();
        return result.finishReason;
      }

      expect(await reasonFor('stop'), LanguageModelV3FinishReason.stop);
      expect(await reasonFor('length'), LanguageModelV3FinishReason.length);
      expect(
        await reasonFor('content_filter'),
        LanguageModelV3FinishReason.contentFilter,
      );
      expect(
        await reasonFor('tool_calls'),
        LanguageModelV3FinishReason.toolCalls,
      );
      expect(await reasonFor(null), LanguageModelV3FinishReason.unknown);
      expect(await reasonFor('weird'), LanguageModelV3FinishReason.other);
    });

    // ── config quirks ────────────────────────────────────────────────────
    test('seed key override (random_seed) + max_tokens key override', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'mistral',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          seedKey: 'random_seed',
          maxTokensKey: 'max_tokens',
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          seed: 42,
          maxOutputTokens: 128,
        ),
      );

      expect(captured['random_seed'], 42);
      expect(captured.containsKey('seed'), isFalse);
      expect(captured['max_tokens'], 128);
      expect(captured.containsKey('max_completion_tokens'), isFalse);
    });

    test('default keys are seed + max_completion_tokens', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          seed: 7,
          maxOutputTokens: 64,
        ),
      );

      expect(captured['seed'], 7);
      expect(captured['max_completion_tokens'], 64);
    });

    test('api-version query parameter is sent (Azure quirk)', () async {
      late String capturedQuery;
      final server = await _TestServer.start((request) async {
        capturedQuery = request.uri.query;
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'dep',
        config: OpenAICompatibleConfig(
          provider: 'azure',
          baseUrl: server.baseUrl,
          headers: () => {'api-key': 'k'},
          queryParameters: const {'api-version': '2024-02-15-preview'},
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );

      expect(capturedQuery, contains('api-version=2024-02-15-preview'));
    });

    test('api-key header vs Bearer auth scheme', () async {
      late HttpHeaders apiKeyHeaders;
      final apiKeyServer = await _TestServer.start((request) async {
        apiKeyHeaders = request.headers;
        _writeOk(request);
      });
      addTearDown(apiKeyServer.close);

      final apiKeyModel = OpenAICompatibleChatLanguageModel(
        modelId: 'm',
        config: OpenAICompatibleConfig(
          provider: 'azure',
          baseUrl: apiKeyServer.baseUrl,
          headers: () => {'api-key': 'secret-key'},
        ),
      );
      await apiKeyModel.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      expect(apiKeyHeaders.value('api-key'), 'secret-key');
      expect(apiKeyHeaders.value('authorization'), isNull);

      late HttpHeaders bearerHeaders;
      final bearerServer = await _TestServer.start((request) async {
        bearerHeaders = request.headers;
        _writeOk(request);
      });
      addTearDown(bearerServer.close);
      final bearerModel = _bearerModel(bearerServer.baseUrl);
      await bearerModel.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      expect(bearerHeaders.value('authorization'), 'Bearer test-token');
      expect(bearerHeaders.value('api-key'), isNull);
    });

    test('extraBody hook injects provider-specific fields', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = OpenAICompatibleChatLanguageModel(
        modelId: 'o3-mini',
        config: OpenAICompatibleConfig(
          provider: 'openai',
          baseUrl: server.baseUrl,
          headers: () => {'Authorization': 'Bearer k'},
          extraBody: (options) {
            final po = options.providerOptions?['openai'];
            final effort = po?['reasoning_effort'] ?? po?['reasoningEffort'];
            return {if (effort != null) 'reasoning_effort': effort};
          },
        ),
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          providerOptions: const {
            'openai': {'reasoningEffort': 'high'},
          },
        ),
      );

      expect(captured['reasoning_effort'], 'high');
    });

    test('serializes assistant tool calls and tool result messages', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
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
                    input: {'city': 'Paris'},
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
                    output: ToolResultOutputContent([
                      LanguageModelV3TextPart(text: 'failed'),
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
      final assistant = messages.first;
      expect(assistant['role'], 'assistant');
      final toolCalls = (assistant['tool_calls'] as List)
          .cast<Map<String, dynamic>>();
      expect((toolCalls.single['function'] as Map)['name'], 'weather');

      final toolMessage = messages.last;
      expect(toolMessage['role'], 'tool');
      expect(toolMessage['tool_call_id'], 'call_1');
      expect(toolMessage['content'], contains('"isError":true'));
    });

    // ── specificationVersion / provider getters ──────────────────────────
    test('exposes provider and specificationVersion', () {
      final model = _bearerModel('http://localhost/v1');
      expect(model.provider, 'test');
      expect(model.specificationVersion, 'v3');
    });

    // ── sampling params + system prompt + stop sequences ─────────────────
    test('serializes sampling params, stop sequences and system prompt',
        () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
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
          temperature: 0.3,
          topP: 0.9,
          presencePenalty: 0.5,
          frequencyPenalty: 0.25,
          stopSequences: const ['STOP'],
        ),
      );

      expect(captured['temperature'], 0.3);
      expect(captured['top_p'], 0.9);
      expect(captured['presence_penalty'], 0.5);
      expect(captured['frequency_penalty'], 0.25);
      expect(captured['stop'], ['STOP']);
      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], 'You are concise.');
    });

    // ── empty / missing response shapes ──────────────────────────────────
    test('doGenerate tolerates empty choices and missing message', () async {
      final emptyChoicesServer = await _TestServer.start((request) async {
        _writeJson(request, {'choices': <dynamic>[]});
      });
      addTearDown(emptyChoicesServer.close);

      final model1 = _bearerModel(emptyChoicesServer.baseUrl);
      final result1 = await model1.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      expect(result1.content, isEmpty);
      expect(result1.finishReason, LanguageModelV3FinishReason.unknown);

      final missingMessageServer = await _TestServer.start((request) async {
        // A choice with no `message` and a tool_call whose `function` is absent.
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {
                'tool_calls': [
                  {'id': 'call_x', 'type': 'function'},
                ],
              },
            },
          ],
        });
      });
      addTearDown(missingMessageServer.close);

      final model2 = _bearerModel(missingMessageServer.baseUrl);
      final result2 = await model2.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      final call = result2.content
          .whereType<LanguageModelV3ToolCallPart>()
          .single;
      // Missing function name/arguments fall back to defaults.
      expect(call.toolName, 'unknown_tool');
      expect(call.input, <String, dynamic>{});
    });

    // ── annotations → source/file parts (non-streaming) ──────────────────
    test('doGenerate extracts url_citation and file_citation annotations',
        () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
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
                  // ignored: url_citation without a url
                  {'type': 'url_citation'},
                  // ignored: file_citation without a file_id
                  {'type': 'file_citation'},
                  // ignored: unknown annotation type
                  {'type': 'other'},
                ],
              },
            },
          ],
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );

      final source = result.content
          .whereType<LanguageModelV3SourcePart>()
          .single;
      expect(source.url, 'https://example.com');
      expect(source.title, 'Example');
      expect(source.id, 'test_source_0');

      final file = result.content
          .whereType<LanguageModelV3FilePart>()
          .single;
      expect((file.data as DataContentUrl).url.toString(), 'test://file/file_123');
      expect(file.filename, 'file_123');
    });

    // ── annotations during streaming ─────────────────────────────────────
    test('doStream emits source/file parts from delta annotations', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          '{"choices":[{"delta":{"annotations":[{"type":"url_citation","url":"https://docs.example","title":"Docs"},{"type":"file_citation","file_id":"file_9"}]}}]}',
          '{"choices":[{"delta":{},"finish_reason":"stop"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();

      final source = parts.whereType<StreamPartSource>().single.source;
      expect(source.url, 'https://docs.example');
      expect(source.title, 'Docs');
      final file = parts.whereType<StreamPartFile>().single.file;
      expect(
        (file.data as DataContentUrl).url.toString(),
        'test://file/file_9',
      );
    });

    // ── streaming tool call without explicit id/function ─────────────────
    test('doStream generates a tool id when none is provided', () async {
      final server = await _TestServer.start((request) async {
        _writeSse(request, [
          // tool_calls delta with no index, no id, no function block.
          '{"choices":[{"delta":{"tool_calls":[{}]}}]}',
          '{"choices":[{"delta":{"tool_calls":[{"function":{"arguments":"{}"}}]}}]}',
          '{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
          '[DONE]',
        ]);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      final parts = await streamResult.stream.toList();

      final start = parts.whereType<StreamPartToolCallStart>().single;
      expect(start.toolCallId, startsWith('tool-'));
      expect(start.toolName, 'unknown_tool');
      final end = parts.whereType<StreamPartToolCallEnd>().single;
      expect(end.toolCallId, startsWith('tool-'));
    });

    // ── streaming error path ─────────────────────────────────────────────
    test('doStream surfaces a StreamPartError when the body errors', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write('data: {"choices":[{"delta":{"content":"Hi"}}]}\n\n');
        // Abruptly destroy the connection mid-stream to trigger a read error.
        await request.response.flush();
        await request.response.close();
        request.response.deadline = Duration.zero;
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      // Just draining is enough; the finally{} closes the controller.
      final parts = await streamResult.stream.toList();
      expect(parts.whereType<StreamPartTextDelta>().length, greaterThanOrEqualTo(0));
    });

    // ── file content parts: image-file + generic file ────────────────────
    test('serializes image-typed and generic file content parts', () async {
      final imgB64 = base64Encode(utf8.encode('img'));
      final pdfB64 = base64Encode(utf8.encode('pdf'));
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  // A FilePart with an image/ media type -> image_url.
                  LanguageModelV3FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('img')),
                    ),
                    mediaType: 'image/png',
                  ),
                  // A generic (non-image, non-audio) FilePart -> file.
                  LanguageModelV3FilePart(
                    data: DataContentBytes(
                      Uint8List.fromList(utf8.encode('pdf')),
                    ),
                    mediaType: 'application/pdf',
                    filename: 'doc.pdf',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final content = ((captured['messages'] as List).first
              as Map<String, dynamic>)['content'] as List;
      final parts = content.cast<Map<String, dynamic>>();
      final imagePart = parts.firstWhere((p) => p['type'] == 'image_url');
      expect(
        (imagePart['image_url'] as Map)['url'],
        'data:image/png;base64,$imgB64',
      );
      final filePart = parts.firstWhere((p) => p['type'] == 'file');
      expect(
        (filePart['file'] as Map)['file_data'],
        'data:application/pdf;base64,$pdfB64',
      );
      expect((filePart['file'] as Map)['filename'], 'doc.pdf');
    });

    test('serializes image content from a base64 data source', () async {
      final imgB64 = base64Encode(utf8.encode('img64'));
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3ImagePart(
                    image: DataContentBase64(imgB64),
                    mediaType: 'image/jpeg',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final content = ((captured['messages'] as List).first
              as Map<String, dynamic>)['content'] as List;
      final imagePart = content.cast<Map<String, dynamic>>().single;
      expect(
        (imagePart['image_url'] as Map)['url'],
        'data:image/jpeg;base64,$imgB64',
      );
    });

    test('drops image content backed by a bare URL with no media type',
        () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [
                  LanguageModelV3ImagePart(
                    image: DataContentUrl(Uri.parse('https://img.example/a.png')),
                    mediaType: 'image/png',
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final content = ((captured['messages'] as List).first
              as Map<String, dynamic>)['content'] as List;
      final imagePart = content.cast<Map<String, dynamic>>().single;
      expect(
        (imagePart['image_url'] as Map)['url'],
        'https://img.example/a.png',
      );
    });

    // ── rich tool result outputs (content with image/file/text/source) ───
    test('serializes rich tool result content (text, image, file, source)',
        () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
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
                    isError: true,
                    output: ToolResultOutputContent([
                      LanguageModelV3TextPart(text: 'summary'),
                      LanguageModelV3ImagePart(
                        image: DataContentBytes(
                          Uint8List.fromList(utf8.encode('img')),
                        ),
                        mediaType: 'image/png',
                      ),
                      LanguageModelV3FilePart(
                        data: DataContentUrl(
                          Uri.parse('https://files.example/a.pdf'),
                        ),
                        mediaType: 'application/pdf',
                        filename: 'a.pdf',
                      ),
                      // An unsupported-for-this-path part (source) -> 'unsupported'.
                      LanguageModelV3SourcePart(
                        id: 's1',
                        url: 'https://src.example',
                      ),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final toolMessage = (captured['messages'] as List).last
          as Map<String, dynamic>;
      final decoded =
          (jsonDecode(toolMessage['content'] as String) as Map)
              .cast<String, dynamic>();
      expect(decoded['isError'], true);
      final output = (decoded['output'] as Map).cast<String, dynamic>();
      expect(output['type'], 'content');
      final outParts = (output['parts'] as List).cast<Map<String, dynamic>>();
      expect(outParts[0]['type'], 'text');
      expect(outParts[0]['text'], 'summary');
      expect(outParts[1]['type'], 'image');
      expect(outParts[1]['base64'], base64Encode(utf8.encode('img')));
      expect(outParts[2]['type'], 'file');
      expect(outParts[2]['url'], 'https://files.example/a.pdf');
      expect(outParts[2]['filename'], 'a.pdf');
      expect(outParts[3]['type'], 'unsupported');
    });

    test('passes plain text tool results through unwrapped', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'echo',
                    output: ToolResultOutputText('plain result'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final toolMessage = (captured['messages'] as List).last
          as Map<String, dynamic>;
      // Non-error ToolResultOutputText is emitted verbatim (not JSON-wrapped).
      expect(toolMessage['content'], 'plain result');
    });

    test('wraps errored text tool results as structured JSON', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.tool,
                content: [
                  LanguageModelV3ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'echo',
                    isError: true,
                    output: ToolResultOutputText('boom'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      final toolMessage = (captured['messages'] as List).last
          as Map<String, dynamic>;
      final decoded = (jsonDecode(toolMessage['content'] as String) as Map)
          .cast<String, dynamic>();
      expect(decoded['isError'], true);
      final output = (decoded['output'] as Map).cast<String, dynamic>();
      // ToolResultOutputText -> {type: text, text: ...}.
      expect(output['type'], 'text');
      expect(output['text'], 'boom');
    });

    // ── usage parsed from string-typed token counts ──────────────────────
    test('parses usage when token counts arrive as strings', () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'stop',
              'message': {'content': 'ok'},
            },
          ],
          'usage': {
            'prompt_tokens': '9',
            'completion_tokens': 3.0,
            'total_tokens': '12',
          },
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      // String prompt_tokens, num completion_tokens, string total_tokens all
      // coerced via _intOrNull.
      expect(result.usage?.inputTokens, 9);
      expect(result.usage?.outputTokens, 3);
      expect(result.usage?.totalTokens, 12);
    });

    // ── tool call id generation when none is returned ────────────────────
    test('doGenerate generates a tool call id when none is returned',
        () async {
      final server = await _TestServer.start((request) async {
        _writeJson(request, {
          'choices': [
            {
              'finish_reason': 'tool_calls',
              'message': {
                'tool_calls': [
                  {
                    'type': 'function',
                    'function': {'name': 'weather', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        });
      });
      addTearDown(server.close);

      final model = _bearerModel(server.baseUrl);
      final result = await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );
      final call = result.content
          .whereType<LanguageModelV3ToolCallPart>()
          .single;
      expect(call.toolCallId, startsWith('call-'));
    });
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

OpenAICompatibleChatLanguageModel _bearerModel(String baseUrl) {
  return OpenAICompatibleChatLanguageModel(
    modelId: 'm',
    config: OpenAICompatibleConfig(
      provider: 'test',
      baseUrl: baseUrl,
      headers: () => {'Authorization': 'Bearer test-token'},
    ),
  );
}

LanguageModelV3Prompt _userPrompt(String text) {
  return LanguageModelV3Prompt(
    messages: [
      LanguageModelV3Message(
        role: LanguageModelV3Role.user,
        content: [LanguageModelV3TextPart(text: text)],
      ),
    ],
  );
}

Future<Map<String, dynamic>> _captureBody(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return (jsonDecode(body) as Map).cast<String, dynamic>();
}

void _writeJson(HttpRequest request, Object payload) {
  request.response.statusCode = 200;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(payload));
  request.response.close();
}

void _writeOk(HttpRequest request) {
  _writeJson(request, {
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': 'ok'},
      },
    ],
  });
}

void _writeSse(HttpRequest request, List<String> events) {
  request.response.statusCode = 200;
  request.response.headers.set('content-type', 'text/event-stream');
  for (final event in events) {
    request.response.write('data: $event\n\n');
  }
  request.response.close();
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
