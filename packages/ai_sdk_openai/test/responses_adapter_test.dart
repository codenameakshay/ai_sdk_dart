import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Responses maps generic reasoning, JSON mode and file bytes faithfully',
    () async {
      Map<String, dynamic>? body;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          body = (request.data as Map).cast<String, dynamic>();
          return _reply(request, {
            'id': 'r',
            'status': 'completed',
            'output': [],
          });
        });
      final result = await OpenAIProvider(apiKey: 'key', client: dio)
          .responses('gpt-5')
          .doGenerate(
            LanguageModelV4CallOptions(
              prompt: LanguageModelV4Prompt(
                messages: [
                  LanguageModelV4Message(
                    role: LanguageModelV4Role.user,
                    content: [
                      LanguageModelV4FilePart(
                        data: DataContentBytes(Uint8List.fromList([1, 2, 3])),
                        mediaType: 'application/pdf',
                        filename: 'input.pdf',
                      ),
                    ],
                  ),
                ],
              ),
              reasoning: LanguageModelV4Reasoning.high,
              stopSequences: ['unsupported-stop'],
              responseFormat: const LanguageModelV4JsonResponseFormat(),
            ),
          );
      expect(body!['reasoning'], {'effort': 'high'});
      expect(body!['text'], {
        'format': {'type': 'json_object'},
      });
      expect(body!.containsKey('stop'), isFalse);
      expect(
        result.warnings.whereType<LanguageModelV4UnsupportedWarning>().map(
          (warning) => warning.feature,
        ),
        contains('stopSequences'),
      );
      final content =
          ((body!['input'] as List).single as Map)['content'] as List;
      expect(content.single, {
        'type': 'input_file',
        'file_data': 'data:application/pdf;base64,AQID',
        'filename': 'input.pdf',
      });
    },
  );

  test(
    'Responses serializes optional request controls and native overrides',
    () async {
      Map<String, dynamic>? body;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          body = (request.data as Map).cast<String, dynamic>();
          return _reply(request, {
            'id': 'resp_options',
            'status': 'completed',
            'output': [],
          });
        });

      await OpenAIProvider(apiKey: 'key', client: dio)
          .responses('gpt-5')
          .doGenerate(
            LanguageModelV4CallOptions(
              prompt: const LanguageModelV4Prompt(messages: []),
              maxOutputTokens: 128,
              temperature: 0.2,
              topP: 0.8,
              reasoning: LanguageModelV4Reasoning.high,
              toolChoice: const ToolChoiceSpecific(toolName: 'weather'),
              responseFormat: const LanguageModelV4JsonResponseFormat(
                name: 'weather',
                description: 'A weather response',
                schema: {'type': 'object'},
              ),
              providerOptions: const {
                'openai': {
                  'previous_response_id': 'resp_previous',
                  'reasoning_effort': 'medium',
                  'reasoning_summary': 'detailed',
                },
              },
            ),
          );

      expect(body!['max_output_tokens'], 128);
      expect(body!['temperature'], 0.2);
      expect(body!['top_p'], 0.8);
      expect(body!['tool_choice'], {'type': 'function', 'name': 'weather'});
      expect(body!['previous_response_id'], 'resp_previous');
      expect(body!['reasoning'], {'effort': 'medium', 'summary': 'detailed'});
      expect(body!['text'], {
        'format': {
          'type': 'json_schema',
          'name': 'weather',
          'description': 'A weather response',
          'schema': {'type': 'object'},
          'strict': true,
        },
      });
    },
  );

  test(
    'Responses places computer safety acknowledgements beside the output',
    () async {
      Map<String, dynamic>? body;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          body = (request.data as Map).cast<String, dynamic>();
          return _reply(request, {
            'id': 'resp-computer-output',
            'status': 'completed',
            'output': [],
          });
        });
      final prompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.assistant,
            content: [
              const LanguageModelV4ToolCallPart(
                toolCallId: 'call-computer',
                toolName: 'computer',
                input: {
                  'actions': [],
                  'pendingSafetyChecks': [],
                  'status': 'completed',
                },
              ),
              const LanguageModelV4ToolResultPart(
                toolCallId: 'call-computer',
                toolName: 'computer',
                output: ToolResultOutputJson({
                  'output': {
                    'type': 'computer_screenshot',
                    'fileId': 'file-screenshot',
                    'detail': 'high',
                  },
                  'acknowledgedSafetyChecks': [
                    {
                      'id': 'safety-1',
                      'code': 'external_side_effect',
                      'message': 'Reviewed by the user',
                    },
                  ],
                }),
              ),
            ],
          ),
        ],
      );
      await OpenAIProvider(apiKey: 'key', client: dio)
          .responses('gpt-5')
          .doGenerate(LanguageModelV4CallOptions(prompt: prompt));

      expect(
        (body!['input'] as List).singleWhere(
          (item) => item is Map && item['type'] == 'computer_call_output',
        ),
        {
          'type': 'computer_call_output',
          'call_id': 'call-computer',
          'output': {
            'type': 'computer_screenshot',
            'file_id': 'file-screenshot',
            'detail': 'high',
          },
          'acknowledged_safety_checks': [
            {
              'id': 'safety-1',
              'code': 'external_side_effect',
              'message': 'Reviewed by the user',
            },
          ],
        },
      );
    },
  );

  test(
    'Responses rejects malformed computer safety acknowledgements',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _reply(request, {
            'id': 'resp-computer-invalid',
            'status': 'completed',
            'output': [],
          }),
        );
      const prompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.assistant,
            content: [
              LanguageModelV4ToolResultPart(
                toolCallId: 'call-computer',
                toolName: 'computer',
                output: ToolResultOutputJson({
                  'output': {
                    'type': 'computer_screenshot',
                    'imageUrl': 'https://example.test/screenshot.png',
                  },
                  'acknowledgedSafetyChecks': [
                    {'code': 'missing-id'},
                  ],
                }),
              ),
            ],
          ),
        ],
      );

      await expectLater(
        OpenAIProvider(apiKey: 'key', client: dio)
            .responses('gpt-5')
            .doGenerate(const LanguageModelV4CallOptions(prompt: prompt)),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('Responses adapter sends items and maps output/tool calls', () async {
    Map<String, dynamic>? requestBody;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter((request) async {
        final raw = request.data;
        requestBody = raw is String
            ? jsonDecode(raw) as Map<String, dynamic>
            : (raw as Map).cast<String, dynamic>();
        return _reply(request, {
          'id': 'resp_1',
          'model': 'gpt-5',
          'output': [
            {
              'type': 'reasoning',
              'id': 'rs_1',
              'summary': [
                {'type': 'summary_text', 'text': 'brief'},
              ],
            },
            {
              'type': 'message',
              'id': 'msg_1',
              'role': 'assistant',
              'content': [
                {'type': 'output_text', 'text': 'hello'},
              ],
            },
            {
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_1',
              'name': 'weather',
              'arguments': '{"city":"Paris"}',
            },
          ],
          'status': 'completed',
          'usage': {
            'input_tokens': 4,
            'output_tokens': 3,
            'output_tokens_details': {'reasoning_tokens': 1},
          },
        });
      });

    final model = OpenAIProvider(
      apiKey: 'key',
      baseUrl: 'https://api.openai.test/v1',
      client: dio,
    ).responses('gpt-5');
    final result = await model.doGenerate(
      LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          messages: [
            const LanguageModelV4Message(
              role: LanguageModelV4Role.user,
              content: [LanguageModelV4TextPart(text: 'hi')],
            ),
          ],
        ),
        tools: [
          const LanguageModelV4FunctionTool(
            name: 'weather',
            inputSchema: {'type': 'object'},
          ),
        ],
        responseFormat: const LanguageModelV4JsonResponseFormat(
          schema: {'type': 'object'},
          name: 'answer',
        ),
      ),
    );

    expect(requestBody!['input'], isA<List>());
    expect(requestBody!['tools'], isA<List>());
    expect(requestBody!['text'], {
      'format': {
        'type': 'json_schema',
        'name': 'answer',
        'schema': {'type': 'object'},
        'strict': true,
      },
    });
    expect(
      result.content.whereType<LanguageModelV4TextPart>().single.text,
      'hello',
    );
    final call = result.content.whereType<LanguageModelV4ToolCallPart>().single;
    expect(call.toolCallId, 'call_1');
    expect(call.input, {'city': 'Paris'});
    expect(result.usage.inputTokens.total, 4);
    expect(result.response!.id, 'resp_1');
  });

  test(
    'Responses preserves encrypted-only reasoning in non-stream output',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          return _reply(request, {
            'id': 'resp_reasoning',
            'status': 'completed',
            'output': [
              {
                'type': 'reasoning',
                'id': 'rs_encrypted',
                'encrypted_content': 'sealed',
                'summary': [],
              },
            ],
          });
        });
      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doGenerate(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final reasoning = result.content
          .whereType<LanguageModelV4ReasoningPart>();
      expect(reasoning, hasLength(1));
      expect(reasoning.single.text, isEmpty);
      expect(reasoning.single.providerOptions?['raw'], {
        'type': 'reasoning',
        'id': 'rs_encrypted',
        'encrypted_content': 'sealed',
        'summary': [],
      });
    },
  );

  test('Responses preserves opaque reasoning without stream deltas', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter(
        (request) async => _streamReply(request, [
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'reasoning',
              'id': 'rs_encrypted',
              'encrypted_content': 'sealed',
              'summary': [],
            },
          },
          {
            'type': 'response.completed',
            'response': {'id': 'resp_reasoning', 'status': 'completed'},
          },
        ]),
      );
    final result =
        await OpenAIProvider(
              apiKey: 'key',
              baseUrl: 'https://api.openai.test/v1',
              client: dio,
            )
            .responses('gpt-5')
            .doStream(
              const LanguageModelV4CallOptions(
                prompt: LanguageModelV4Prompt(messages: []),
              ),
            );
    final parts = await result.stream.toList();
    expect(parts.whereType<StreamPartReasoningStart>(), hasLength(1));
    expect(parts.whereType<StreamPartReasoningEnd>(), hasLength(1));
    expect(
      parts.whereType<StreamPartReasoningEnd>().single.providerMetadata,
      isNotNull,
    );
  });

  test('Responses keeps continuation items in prompt order', () async {
    Map<String, dynamic>? body;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter((request) async {
        body = (request.data as Map).cast<String, dynamic>();
        return _reply(request, {
          'id': 'resp_order',
          'status': 'completed',
          'output': [],
        });
      });
    await OpenAIProvider(
          apiKey: 'key',
          baseUrl: 'https://api.openai.test/v1',
          client: dio,
        )
        .responses('gpt-5')
        .doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.assistant,
                  content: [
                    const LanguageModelV4TextPart(text: 'before'),
                    const LanguageModelV4ReasoningPart(
                      text: '',
                      providerOptions: {
                        'raw': {
                          'type': 'reasoning',
                          'id': 'rs_order',
                          'encrypted_content': 'sealed',
                          'summary': [],
                        },
                      },
                    ),
                    const LanguageModelV4ToolCallPart(
                      toolCallId: 'call_order',
                      toolName: 'weather',
                      input: {'city': 'Paris'},
                    ),
                    const LanguageModelV4ToolResultPart(
                      toolCallId: 'call_order',
                      toolName: 'weather',
                      output: ToolResultOutputText('sunny'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
    final input = (body!['input'] as List).cast<Map>();
    expect(input.map((item) => item['type']).toList(), [
      null,
      'reasoning',
      'function_call',
      'function_call_output',
    ]);
  });

  test(
    'Responses maps URL citations to source parts with provider metadata',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _reply(request, {
            'id': 'resp_source',
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'id': 'message_source',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'answer',
                    'annotations': [
                      {
                        'type': 'url_citation',
                        'id': 'cite_1',
                        'url': 'https://example.test',
                        'title': 'Example',
                      },
                    ],
                  },
                ],
              },
            ],
          }),
        );
      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doGenerate(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final source = result.content
          .whereType<LanguageModelV4SourcePart>()
          .single;
      expect(source.id, 'cite_1');
      expect(source.url, 'https://example.test');
      expect(source.title, 'Example');
      expect(source.providerMetadata?['openai'], isA<Map>());
    },
  );

  test('Responses stream emits semantic deltas and terminal finish', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter(
        (request) async => _streamReply(request, [
          {
            'type': 'response.created',
            'response': {'id': 'resp_s', 'model': 'gpt-5'},
          },
          {
            'type': 'response.output_text.delta',
            'item_id': 'msg_s',
            'delta': 'hi',
          },
          {
            'type': 'response.reasoning_summary_text.delta',
            'item_id': 'rs_s',
            'delta': 'think',
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'reasoning',
              'id': 'rs_s',
              'summary': [
                {'type': 'summary_text', 'text': 'think'},
              ],
            },
          },
          {
            'type': 'response.output_item.added',
            'item': {
              'type': 'function_call',
              'id': 'item_f',
              'call_id': 'call_f',
              'name': 'weather',
              'arguments': '',
            },
          },
          {
            'type': 'response.function_call_arguments.delta',
            'item_id': 'item_f',
            'delta': '{"city":"Paris"}',
          },
          {
            'type': 'response.function_call_arguments.done',
            'item_id': 'item_f',
            'arguments': '{"city":"Paris"}',
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'function_call',
              'id': 'item_f',
              'call_id': 'call_f',
              'name': 'weather',
              'arguments': '{"city":"Paris"}',
            },
          },
          {
            'type': 'response.completed',
            'response': {
              'id': 'resp_s',
              'model': 'gpt-5',
              'status': 'completed',
              'usage': {'input_tokens': 1, 'output_tokens': 1},
            },
          },
        ]),
      );
    final result =
        await OpenAIProvider(
              apiKey: 'key',
              baseUrl: 'https://api.openai.test/v1',
              client: dio,
            )
            .responses('gpt-5')
            .doStream(
              const LanguageModelV4CallOptions(
                prompt: LanguageModelV4Prompt(messages: []),
              ),
            );
    final parts = await result.stream.toList();
    expect(parts.whereType<StreamPartTextDelta>().single.delta, 'hi');
    expect(parts.whereType<StreamPartToolCall>(), hasLength(1));
    expect(parts.whereType<StreamPartToolInputStart>().map((part) => part.id), [
      'call_f',
    ]);
    expect(parts.whereType<StreamPartToolInputDelta>().map((part) => part.id), [
      'call_f',
    ]);
    expect(parts.whereType<StreamPartToolInputEnd>().map((part) => part.id), [
      'call_f',
    ]);
    expect(
      parts.whereType<StreamPartReasoningEnd>().single.providerMetadata,
      isNotNull,
    );
    expect(
      parts.whereType<StreamPartFinish>().single.finishReason,
      LanguageModelV4FinishReason.stop,
    );
  });

  test(
    'Responses rejects function calls with missing identity fields',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          return _reply(request, {
            'id': 'resp_bad_identity',
            'status': 'completed',
            'output': [
              {
                'type': 'function_call',
                'id': 'item_f',
                'name': 'weather',
                'arguments': '{}',
              },
            ],
          });
        });

      await expectLater(
        OpenAIProvider(
              apiKey: 'key',
              baseUrl: 'https://api.openai.test/v1',
              client: dio,
            )
            .responses('gpt-5')
            .doGenerate(
              const LanguageModelV4CallOptions(
                prompt: LanguageModelV4Prompt(messages: []),
              ),
            ),
        throwsA(
          isA<AiApiCallError>().having(
            (error) => error.cause,
            'cause',
            isA<FormatException>(),
          ),
        ),
      );
    },
  );

  test(
    'Responses rejects streamed identity changes and missing names',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.output_item.added',
              'item': {
                'type': 'function_call',
                'id': 'item_f',
                'call_id': 'call_f',
                'name': 'weather',
                'arguments': '',
              },
            },
            {
              'type': 'response.function_call_arguments.delta',
              'item_id': 'item_other',
              'delta': '{}',
            },
          ]),
        );

      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doStream(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartError>(), hasLength(1));
      expect(
        parts.whereType<StreamPartError>().single.error,
        isA<FormatException>(),
      );
    },
  );

  test('embedding cancellation closes a real HTTP connection', () async {
    final server = await _RawEmbeddingServer.start();
    addTearDown(server.close);
    final signal = _Signal();
    final provider = OpenAIProvider(
      apiKey: 'key',
      baseUrl: '${server.endpoint}/v1',
    );
    final pending = provider
        .embedding('embed')
        .doEmbed(
          EmbeddingModelV2CallOptions(
            values: const ['hello'],
            abortSignal: signal,
          ),
        );
    await server.requestReceived.future;
    signal.cancel();
    await expectLater(pending, throwsA(isA<Object>()));
    await server.peerClosed.future;
  });

  test(
    'streamText executes a Responses function call once across duplicate events',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.created',
              'response': {'id': 'resp_tool', 'model': 'gpt-5'},
            },
            {
              'type': 'response.output_item.added',
              'item': {
                'type': 'function_call',
                'id': 'item_t',
                'call_id': 'call_t',
                'name': 'count',
                'arguments': '',
              },
            },
            {
              'type': 'response.function_call_arguments.delta',
              'item_id': 'item_t',
              'delta': '{}',
            },
            {
              'type': 'response.function_call_arguments.done',
              'item_id': 'item_t',
              'arguments': '{}',
            },
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'function_call',
                'id': 'item_t',
                'call_id': 'call_t',
                'name': 'count',
                'arguments': '{}',
              },
            },
            {
              'type': 'response.completed',
              'response': {
                'id': 'resp_tool',
                'model': 'gpt-5',
                'status': 'completed',
                'usage': {'input_tokens': 1, 'output_tokens': 1},
              },
            },
          ]),
        );
      var executions = 0;
      final result = await streamText(
        model: OpenAIProvider(
          apiKey: 'key',
          baseUrl: 'https://api.openai.test/v1',
          client: dio,
        ).responses('gpt-5'),
        prompt: 'count',
        maxSteps: 1,
        tools: {
          'count': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async {
              executions++;
              return 'one';
            },
          ),
        },
      );
      await result.text;
      expect(executions, 1);
    },
  );

  test('truncated Responses stream emits a terminal error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter(
        (request) async => _streamReply(request, [
          {
            'type': 'response.created',
            'response': {'id': 'resp_truncated', 'model': 'gpt-5'},
          },
        ]),
      );
    final result =
        await OpenAIProvider(
              apiKey: 'key',
              baseUrl: 'https://api.openai.test/v1',
              client: dio,
            )
            .responses('gpt-5')
            .doStream(
              const LanguageModelV4CallOptions(
                prompt: LanguageModelV4Prompt(messages: []),
              ),
            );
    final parts = await result.stream.toList();
    expect(parts.whereType<StreamPartError>(), hasLength(1));
    expect(
      parts.whereType<StreamPartFinish>().single.finishReason,
      LanguageModelV4FinishReason.error,
    );
  });

  test(
    'failed and content-filter incomplete responses preserve terminal cause',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.failed',
              'response': {
                'id': 'failed',
                'status': 'failed',
                'error': 'provider failure',
              },
            },
          ]),
        );
      final failed =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doStream(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final failedParts = await failed.stream.toList();
      expect(failedParts.whereType<StreamPartError>(), hasLength(1));

      final filterDio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.incomplete',
              'response': {
                'id': 'incomplete',
                'status': 'incomplete',
                'incomplete_details': {'reason': 'content_filter'},
              },
            },
          ]),
        );
      final incomplete =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: filterDio,
              )
              .responses('gpt-5')
              .doStream(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      expect(
        (await incomplete.stream.toList())
            .whereType<StreamPartFinish>()
            .single
            .finishReason,
        LanguageModelV4FinishReason.contentFilter,
      );
    },
  );

  test('typed hosted tools serialize with Responses wire types', () async {
    Map<String, dynamic>? body;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter((request) async {
        body = (request.data as Map).cast<String, dynamic>();
        return _reply(request, {
          'id': 'resp_hosted',
          'model': 'gpt-5',
          'status': 'completed',
          'output': [],
        });
      });
    await OpenAIProvider(
          apiKey: 'key',
          baseUrl: 'https://api.openai.test/v1',
          client: dio,
        )
        .responses('gpt-5')
        .doGenerate(
          LanguageModelV4CallOptions(
            prompt: const LanguageModelV4Prompt(messages: []),
            tools: [
              OpenAIWebSearchTool(userLocation: 'Paris'),
              OpenAIFileSearchTool(vectorStoreIds: ['vs_1'], maxNumResults: 3),
              OpenAICodeInterpreterTool(container: {'type': 'auto'}),
              OpenAIImageGenerationTool(args: {'size': '1024x1024'}),
              OpenAIMCPTool(
                serverLabel: 'docs',
                serverUrl: 'https://mcp.test',
                allowedTools: ['lookup'],
                requireApproval: 'always',
                headers: {'X-Key': 'value'},
              ),
            ],
          ),
        );
    expect(
      body!['tools'],
      containsAll(<Object>[
        {
          'type': 'web_search_preview',
          'search_context_size': 'medium',
          'user_location': {'type': 'approximate', 'city': 'Paris'},
        },
        {
          'type': 'file_search',
          'vector_store_ids': ['vs_1'],
          'max_num_results': 3,
        },
        {
          'type': 'code_interpreter',
          'container': {'type': 'auto'},
        },
        {'type': 'image_generation', 'size': '1024x1024'},
        {
          'type': 'mcp',
          'server_label': 'docs',
          'server_url': 'https://mcp.test',
          'allowed_tools': ['lookup'],
          'require_approval': 'always',
          'headers': {'X-Key': 'value'},
        },
      ]),
    );
  });

  test(
    'Responses preserves provider executed hosted calls and results',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          return _reply(request, {
            'id': 'resp_hosted_result',
            'status': 'completed',
            'output': [
              {
                'type': 'web_search_call',
                'id': 'ws_1',
                'status': 'completed',
                'action': {
                  'type': 'search',
                  'query': 'weather Paris',
                  'sources': [
                    {
                      'type': 'url',
                      'url': 'https://weather.test',
                      'title': 'Weather',
                    },
                  ],
                },
              },
              {
                'type': 'code_interpreter_call',
                'id': 'ci_1',
                'status': 'completed',
                'code': 'print(1)',
                'container_id': 'cn_1',
                'outputs': [
                  {'type': 'logs', 'logs': '1'},
                ],
              },
              {
                'type': 'image_generation_call',
                'id': 'ig_1',
                'status': 'completed',
                'result': 'base64-image',
              },
              {
                'type': 'file_search_call',
                'id': 'fs_1',
                'status': 'completed',
                'queries': ['Paris'],
                'results': [
                  {
                    'file_id': 'file_1',
                    'filename': 'facts.txt',
                    'text': 'Paris',
                  },
                ],
              },
            ],
          });
        });

      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doGenerate(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );

      final calls = result.content.whereType<LanguageModelV4ToolCallPart>();
      final results = result.content.whereType<LanguageModelV4ToolResultPart>();
      expect(calls.map((call) => call.toolCallId), [
        'ws_1',
        'ci_1',
        'ig_1',
        'fs_1',
      ]);
      expect(results.map((result) => result.toolCallId), [
        'ws_1',
        'ci_1',
        'ig_1',
        'fs_1',
      ]);
      expect(
        calls.every((call) => call.providerOptions?['openai'] is Map),
        isTrue,
      );
      expect(
        calls.every(
          (call) =>
              (call.providerOptions!['openai'] as Map)['provider_executed'] ==
              true,
        ),
        isTrue,
      );
      expect(
        (results.first.output as ToolResultOutputText).text,
        contains('weather.test'),
      );
    },
  );

  test(
    'Responses retains unknown output items as replayable extensions',
    () async {
      Map<String, dynamic>? secondBody;
      var requestCount = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          requestCount++;
          if (requestCount == 2) {
            secondBody = (request.data as Map).cast<String, dynamic>();
          }
          return _reply(request, {
            'id': 'resp_unknown_$requestCount',
            'status': 'completed',
            'output': requestCount == 1
                ? [
                    {
                      'type': 'future_item',
                      'id': 'future_1',
                      'payload': {'value': 42},
                    },
                  ]
                : <Object>[],
          });
        });

      final first =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doGenerate(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final extension = first.content.single as LanguageModelV4OpaquePart;
      expect(extension.provider, 'openai');
      expect(extension.raw, {
        'type': 'future_item',
        'id': 'future_1',
        'payload': {'value': 42},
      });

      await OpenAIProvider(
            apiKey: 'key',
            baseUrl: 'https://api.openai.test/v1',
            client: dio,
          )
          .responses('gpt-5')
          .doGenerate(
            LanguageModelV4CallOptions(
              prompt: LanguageModelV4Prompt(
                messages: [
                  LanguageModelV4Message(
                    role: LanguageModelV4Role.assistant,
                    content: [extension],
                  ),
                ],
              ),
            ),
          );
      expect((secondBody!['input'] as List).single, {
        'type': 'future_item',
        'id': 'future_1',
        'payload': {'value': 42},
      });
    },
  );

  test(
    'Responses streams hosted lifecycle items without local execution',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'web_search_call',
                'id': 'ws_stream',
                'status': 'completed',
                'action': {'type': 'search', 'query': 'Dart'},
              },
            },
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'mcp_approval_request',
                'id': 'mcp_item',
                'approval_request_id': 'approval_1',
                'name': 'lookup',
                'arguments': '{"key":"value"}',
              },
            },
            {
              'type': 'response.completed',
              'response': {'id': 'resp_hosted_stream', 'status': 'completed'},
            },
          ]),
        );

      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doStream(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final parts = await result.stream.toList();
      final calls = parts.whereType<StreamPartToolCall>();
      expect(calls.map((part) => part.toolCall.toolCallId), [
        'ws_stream',
        'mcp_item',
      ]);
      expect(parts.whereType<StreamPartToolResult>(), hasLength(1));
      final approval = parts.whereType<StreamPartToolApprovalRequest>().single;
      expect(approval.approvalRequest.approvalId, 'approval_1');
      expect(approval.approvalRequest.toolCall.toolCallId, 'mcp_item');
      expect(
        calls.every(
          (part) =>
              (part.toolCall.providerOptions!['openai']
                  as Map)['provider_executed'] ==
              true,
        ),
        isTrue,
      );
    },
  );

  test(
    'Responses streams computer and MCP hosted items with annotations',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.created',
              'response': {'id': 'resp_hosted_variants', 'model': 'gpt-5'},
            },
            {
              'type': 'response.output_text.annotation.added',
              'annotation': {
                'type': 'url_citation',
                'id': 'source-1',
                'url': 'https://example.test/source',
                'title': 'Source',
              },
            },
            {
              'type': 'response.output_text.annotation.added',
              'annotation': {
                'type': 'file_citation',
                'file_id': 'file-1',
                'filename': 'report.pdf',
                'media_type': 'application/pdf',
              },
            },
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'computer_call',
                'id': 'computer-1',
                'status': 'completed',
                'action': {'type': 'click', 'x': 10, 'y': 20},
              },
            },
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'mcp_call',
                'id': 'mcp-1',
                'name': 'lookup',
                'server_label': 'docs',
                'arguments': '{"query":"Dart"}',
                'output': 'found',
                'status': 'completed',
              },
            },
            {
              'type': 'response.completed',
              'response': {
                'id': 'resp_hosted_variants',
                'model': 'gpt-5',
                'status': 'completed',
                'usage': {'input_tokens': 2, 'output_tokens': 3},
              },
            },
          ]),
        );
      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doStream(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                  includeRawChunks: true,
                ),
              );

      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartRaw>(), hasLength(6));
      expect(
        parts.whereType<StreamPartSource>().single.source.url,
        'https://example.test/source',
      );
      expect(
        parts.whereType<StreamPartDocumentSource>().single.source.filename,
        'report.pdf',
      );
      final calls = parts.whereType<StreamPartToolCall>().toList();
      expect(calls.map((part) => part.toolCall.toolCallId), [
        'computer-1',
        'mcp-1',
      ]);
      expect(calls.first.toolCall.toolName, 'computer_use');
      expect(calls.last.toolCall.input, '{"query":"Dart"}');
      expect(parts.whereType<StreamPartToolResult>(), hasLength(2));
      expect(
        parts.whereType<StreamPartFinish>().single.usage.inputTokens.total,
        2,
      );
    },
  );

  test(
    'core streamText response messages replay opaque Responses reasoning',
    () async {
      var calls = 0;
      Map<String, dynamic>? secondBody;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          calls++;
          if (calls == 2) {
            secondBody = (request.data as Map).cast<String, dynamic>();
          }
          return _streamReply(request, [
            {
              'type': 'response.created',
              'response': {'id': 'resp-$calls', 'model': 'gpt-5'},
            },
            if (calls == 1)
              {
                'type': 'response.reasoning_summary_text.delta',
                'item_id': 'rs_replay',
                'delta': 'opaque thought',
              },
            if (calls == 1)
              {
                'type': 'response.output_item.done',
                'item': {
                  'type': 'reasoning',
                  'id': 'rs_replay',
                  'summary': [
                    {'type': 'summary_text', 'text': 'opaque thought'},
                  ],
                  'encrypted_content': 'sealed',
                },
              },
            {
              'type': 'response.output_text.delta',
              'item_id': 'msg-$calls',
              'delta': calls == 1 ? 'first' : 'second',
            },
            {
              'type': 'response.completed',
              'response': {
                'id': 'resp-$calls',
                'model': 'gpt-5',
                'status': 'completed',
                'usage': {'input_tokens': 1, 'output_tokens': 1},
              },
            },
          ]);
        });
      final model = OpenAIProvider(
        apiKey: 'key',
        baseUrl: 'https://api.openai.test/v1',
        client: dio,
      ).responses('gpt-5');
      final first = await streamText(model: model, prompt: 'hello');
      final firstEvents = first.stream.toList();
      await first.text;
      final firstFinish = (await firstEvents)
          .whereType<StreamTextFinishEvent>()
          .single;
      final second = await streamText(
        model: model,
        messages: [
          for (final message in firstFinish.responseMessages)
            ModelMessage.parts(
              role: ModelMessageRole.assistant,
              parts: message.content,
            ),
        ],
      );
      await second.text;
      expect(
        (secondBody!['input'] as List).where(
          (item) =>
              item is Map &&
              item['type'] == 'reasoning' &&
              item['id'] == 'rs_replay',
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'core replays a citation alongside a client tool result across steps',
    () async {
      var calls = 0;
      Map<String, dynamic>? secondBody;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          calls++;
          if (calls == 2) {
            secondBody = (request.data as Map).cast<String, dynamic>();
          }
          return _streamReply(request, [
            {
              'type': 'response.created',
              'response': {'id': 'resp-$calls', 'model': 'gpt-5'},
            },
            if (calls == 1) ...[
              {
                'type': 'response.output_text.delta',
                'item_id': 'message-citation',
                'delta': 'According to the file,',
              },
              {
                'type': 'response.output_text.annotation.added',
                'item_id': 'message-citation',
                'annotation': {
                  'type': 'file_citation',
                  'file_id': 'file-1',
                  'filename': 'report.pdf',
                },
              },
              {
                'type': 'response.output_item.done',
                'item': {'type': 'message', 'id': 'message-citation'},
              },
              {
                'type': 'response.output_item.added',
                'item': {
                  'type': 'function_call',
                  'id': 'item-lookup',
                  'call_id': 'call-lookup',
                  'name': 'lookup',
                  'arguments': '',
                },
              },
              {
                'type': 'response.function_call_arguments.delta',
                'item_id': 'item-lookup',
                'delta': '{}',
              },
              {
                'type': 'response.function_call_arguments.done',
                'item_id': 'item-lookup',
                'arguments': '{}',
              },
            ] else ...[
              {
                'type': 'response.output_text.delta',
                'item_id': 'message-final',
                'delta': 'done',
              },
              {
                'type': 'response.output_item.done',
                'item': {'type': 'message', 'id': 'message-final'},
              },
            ],
            {
              'type': 'response.completed',
              'response': {
                'id': 'resp-$calls',
                'model': 'gpt-5',
                'status': 'completed',
                'usage': {'input_tokens': 1, 'output_tokens': 1},
              },
            },
          ]);
        });

      final result = await streamText(
        model: OpenAIProvider(
          apiKey: 'key',
          baseUrl: 'https://api.openai.test/v1',
          client: dio,
        ).responses('gpt-5'),
        prompt: 'lookup',
        maxSteps: 2,
        tools: {
          'lookup': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'result',
          ),
        },
      );

      expect(await result.text, 'done');
      expect((await result.documentSources).single.id, 'file-1');
      expect(calls, 2);
      expect(secondBody, isNotNull);
      expect(
        (secondBody!['input'] as List).where(
          (item) => item is Map && item['type'] == 'input_file',
        ),
        isEmpty,
      );
      expect(
        (secondBody!['input'] as List)
            .where((item) => item is Map && item['role'] == 'assistant')
            .single,
        {
          'role': 'assistant',
          'content': [
            {'type': 'input_text', 'text': 'According to the file,'},
          ],
        },
      );
    },
  );

  test(
    'core generateText replays a citation alongside a client tool result',
    () async {
      var calls = 0;
      Map<String, dynamic>? secondBody;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          calls++;
          if (calls == 2) {
            secondBody = (request.data as Map).cast<String, dynamic>();
          }
          return _reply(request, {
            'id': 'resp-$calls',
            'status': 'completed',
            'output': calls == 1
                ? [
                    {
                      'type': 'message',
                      'id': 'message-citation',
                      'content': [
                        {
                          'type': 'output_text',
                          'text': 'According to the file,',
                          'annotations': [
                            {
                              'type': 'file_citation',
                              'file_id': 'file-1',
                              'filename': 'report.pdf',
                            },
                          ],
                        },
                      ],
                    },
                    {
                      'type': 'function_call',
                      'id': 'item-lookup',
                      'call_id': 'call-lookup',
                      'name': 'lookup',
                      'arguments': '{}',
                    },
                  ]
                : [
                    {
                      'type': 'message',
                      'id': 'message-final',
                      'content': [
                        {
                          'type': 'output_text',
                          'text': 'done',
                          'annotations': [],
                        },
                      ],
                    },
                  ],
          });
        });

      final result = await generateText(
        model: OpenAIProvider(
          apiKey: 'key',
          baseUrl: 'https://api.openai.test/v1',
          client: dio,
        ).responses('gpt-5'),
        prompt: 'lookup',
        maxSteps: 2,
        tools: {
          'lookup': tool<Map<String, dynamic>, String>(
            inputSchema: Schema<Map<String, dynamic>>(
              jsonSchema: const {'type': 'object'},
              fromJson: (json) => json,
            ),
            execute: (_, _) async => 'result',
          ),
        },
      );

      expect(result.text, 'done');
      expect(result.documentSources.single.filename, 'report.pdf');
      expect(calls, 2);
      expect(secondBody, isNotNull);
      expect(
        (secondBody!['input'] as List).where(
          (item) => item is Map && item['type'] == 'input_file',
        ),
        isEmpty,
      );
      expect(
        (secondBody!['input'] as List)
            .where((item) => item is Map && item['role'] == 'assistant')
            .single,
        {
          'role': 'assistant',
          'content': [
            {'type': 'input_text', 'text': 'According to the file,'},
          ],
        },
      );
    },
  );

  test(
    'Responses replays MCP approval responses with their wire identity',
    () async {
      Map<String, dynamic>? body;
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter((request) async {
          body = (request.data as Map).cast<String, dynamic>();
          return _reply(request, {
            'id': 'resp_approval',
            'status': 'completed',
            'output': [],
          });
        });
      await OpenAIProvider(
            apiKey: 'key',
            baseUrl: 'https://api.openai.test/v1',
            client: dio,
          )
          .responses('gpt-5')
          .doGenerate(
            const LanguageModelV4CallOptions(
              prompt: LanguageModelV4Prompt(
                messages: [
                  LanguageModelV4Message(
                    role: LanguageModelV4Role.user,
                    content: [
                      LanguageModelV4ToolApprovalResponse(
                        approvalId: 'approval_1',
                        approved: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
      expect((body!['input'] as List).single, {
        'type': 'mcp_approval_response',
        'approval_request_id': 'approval_1',
        'approve': true,
      });
    },
  );

  test('core does not execute provider hosted tool calls locally', () async {
    var executions = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter(
        (request) async => _reply(request, {
          'id': 'resp_core_hosted',
          'status': 'completed',
          'output': [
            {
              'type': 'web_search_call',
              'id': 'ws_core',
              'status': 'completed',
              'action': {'type': 'search', 'query': 'Dart'},
            },
          ],
        }),
      );
    final result = await generateText(
      model: OpenAIProvider(
        apiKey: 'key',
        baseUrl: 'https://api.openai.test/v1',
        client: dio,
      ).responses('gpt-5'),
      prompt: 'search',
      tools: {
        'web_search_preview': tool<Map<String, dynamic>, String>(
          inputSchema: Schema<Map<String, dynamic>>(
            jsonSchema: const {'type': 'object'},
            fromJson: (json) => json,
          ),
          execute: (_, _) async {
            executions++;
            return 'local';
          },
        ),
      },
      providerDefinedTools: [OpenAIWebSearchTool()],
    );
    expect(executions, 0);
    expect(result.toolResults, hasLength(1));
  });

  test('Responses maps text boundaries to each output message item', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter(
        (request) async => _streamReply(request, [
          {
            'type': 'response.output_item.added',
            'item': {'type': 'message', 'id': 'message_empty'},
          },
          {
            'type': 'response.output_item.done',
            'item': {'type': 'message', 'id': 'message_empty'},
          },
          {
            'type': 'response.output_item.added',
            'item': {'type': 'message', 'id': 'message_text'},
          },
          {
            'type': 'response.output_text.delta',
            'item_id': 'message_text',
            'delta': 'hello',
          },
          {
            'type': 'response.output_item.done',
            'item': {'type': 'message', 'id': 'message_text'},
          },
          {
            'type': 'response.completed',
            'response': {'id': 'resp_text_items', 'status': 'completed'},
          },
        ]),
      );
    final result =
        await OpenAIProvider(
              apiKey: 'key',
              baseUrl: 'https://api.openai.test/v1',
              client: dio,
            )
            .responses('gpt-5')
            .doStream(
              const LanguageModelV4CallOptions(
                prompt: LanguageModelV4Prompt(messages: []),
              ),
            );
    final parts = await result.stream.toList();
    expect(parts.whereType<StreamPartTextStart>().map((part) => part.id), [
      'message_empty',
      'message_text',
    ]);
    expect(parts.whereType<StreamPartTextEnd>().map((part) => part.id), [
      'message_empty',
      'message_text',
    ]);
  });

  test(
    'Responses preserves unknown items as canonical opaque stream content',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'future_item',
                'id': 'future_stream',
                'payload': {'value': 7},
              },
            },
            {
              'type': 'response.completed',
              'response': {'id': 'resp_future', 'status': 'completed'},
            },
          ]),
        );
      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doStream(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final parts = await result.stream.toList();
      final opaque = parts.whereType<StreamPartOpaque>().single;
      expect(opaque.opaque.raw, {
        'type': 'future_item',
        'id': 'future_stream',
        'payload': {'value': 7},
      });
    },
  );

  test(
    'streamText retains unknown Responses items in content and fullStream',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'future_item',
                'id': 'future_core',
                'payload': {'value': 9},
              },
            },
            {
              'type': 'response.completed',
              'response': {'id': 'resp_future_core', 'status': 'completed'},
            },
          ]),
        );
      final result = await streamText(
        model: OpenAIProvider(
          apiKey: 'key',
          baseUrl: 'https://api.openai.test/v1',
          client: dio,
        ).responses('gpt-5'),
        prompt: 'hello',
      );
      final eventsFuture = result.stream.toList();
      final content = await result.content;
      expect(content.whereType<LanguageModelV4OpaquePart>(), hasLength(1));
      expect(
        (await eventsFuture).whereType<StreamTextOpaqueEvent>(),
        hasLength(1),
      );
    },
  );

  test('Responses rebinds MCP calls to approval IDs across turns', () async {
    Map<String, dynamic>? secondBody;
    var requestCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
      ..httpClientAdapter = _Adapter((request) async {
        requestCount++;
        if (requestCount == 2) {
          secondBody = (request.data as Map).cast<String, dynamic>();
        }
        return _reply(request, {
          'id': 'resp_$requestCount',
          'status': 'completed',
          'output': requestCount == 1
              ? [
                  {
                    'type': 'mcp_approval_request',
                    'id': 'mcp_approval_item',
                    'approval_request_id': 'approval_1',
                    'name': 'lookup',
                    'arguments': '{"key":"value"}',
                  },
                ]
              : [
                  {
                    'type': 'mcp_call',
                    'id': 'mcp_result_item',
                    'approval_request_id': 'approval_1',
                    'name': 'lookup',
                    'arguments': '{"key":"value"}',
                    'output': 'ok',
                    'status': 'completed',
                  },
                ],
        });
      });
    final model = OpenAIProvider(
      apiKey: 'key',
      baseUrl: 'https://api.openai.test/v1',
      client: dio,
    ).responses('gpt-5');
    final first = await model.doGenerate(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      ),
    );
    expect(
      first.content.whereType<LanguageModelV4ToolCallPart>().single.input,
      '{"key":"value"}',
    );
    final second = await model.doGenerate(
      LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.assistant,
              content: first.content,
            ),
            const LanguageModelV4Message(
              role: LanguageModelV4Role.user,
              content: [
                LanguageModelV4ToolApprovalResponse(
                  approvalId: 'approval_1',
                  approved: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(
      second.content.whereType<LanguageModelV4ToolCallPart>().single.toolCallId,
      'mcp_approval_item',
    );
    expect(
      (secondBody!['input'] as List).whereType<Map>().any(
        (item) => item['type'] == 'mcp_approval_response',
      ),
      isTrue,
    );
  });

  test(
    'Responses marks failed hosted results and preliminary hosted results',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'web_search_call',
                'id': 'search_failed',
                'status': 'failed',
                'action': {'type': 'search', 'query': 'Dart'},
              },
            },
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'web_search_call',
                'id': 'search_preliminary',
                'status': 'in_progress',
                'action': {'type': 'search', 'query': 'Dart'},
              },
            },
            {
              'type': 'response.completed',
              'response': {'id': 'resp_hosted_states', 'status': 'completed'},
            },
          ]),
        );
      final result =
          await OpenAIProvider(
                apiKey: 'key',
                baseUrl: 'https://api.openai.test/v1',
                client: dio,
              )
              .responses('gpt-5')
              .doStream(
                const LanguageModelV4CallOptions(
                  prompt: LanguageModelV4Prompt(messages: []),
                ),
              );
      final parts = await result.stream.toList();
      expect(
        parts.whereType<StreamPartToolResult>().first.toolResult.isError,
        isTrue,
      );
      expect(parts.whereType<StreamPartToolResult>().last.preliminary, isTrue);
    },
  );

  test(
    'streamText forwards provider hosted results through fullStream',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.openai.test/v1'))
        ..httpClientAdapter = _Adapter(
          (request) async => _streamReply(request, [
            {
              'type': 'response.output_item.done',
              'item': {
                'type': 'web_search_call',
                'id': 'search_full_stream',
                'status': 'completed',
                'action': {'type': 'search', 'query': 'Dart'},
              },
            },
            {
              'type': 'response.completed',
              'response': {'id': 'resp_full_stream', 'status': 'completed'},
            },
          ]),
        );
      final result = await streamText(
        model: OpenAIProvider(
          apiKey: 'key',
          baseUrl: 'https://api.openai.test/v1',
          client: dio,
        ).responses('gpt-5'),
        prompt: 'search',
        maxSteps: 1,
        providerDefinedTools: [OpenAIWebSearchTool()],
      );
      final eventsFuture = result.stream.toList();
      await result.text;
      expect(
        (await eventsFuture).whereType<StreamTextToolResultEvent>(),
        hasLength(1),
      );
    },
  );
}

class _Signal implements AbortSignal {
  final _done = Completer<void>();
  bool _cancelled = false;
  @override
  bool get isCancelled => _cancelled;
  @override
  Future<void> get onCancelled => _done.future;
  void cancel() {
    _cancelled = true;
    _done.complete();
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _reply(RequestOptions _, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
ResponseBody _streamReply(
  RequestOptions _,
  List<Map<String, dynamic>> events,
) => ResponseBody.fromString(
  events.map((e) => 'data: ${jsonEncode(e)}\n\n').join(),
  200,
  headers: {
    'content-type': ['text/event-stream'],
  },
);

class _RawEmbeddingServer {
  _RawEmbeddingServer(this._server);

  final ServerSocket _server;
  final requestReceived = Completer<void>();
  final peerClosed = Completer<void>();
  final _sockets = <Socket>[];

  Uri get endpoint =>
      Uri.parse('http://${_server.address.host}:${_server.port}');

  static Future<_RawEmbeddingServer> start() async {
    final server = _RawEmbeddingServer(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen(server._handleSocket);
    return server;
  }

  void _handleSocket(Socket socket) {
    _sockets.add(socket);
    unawaited(socket.done.then<void>((_) {}, onError: (_) {}));
    var announced = false;
    socket.listen(
      (_) {
        if (announced) return;
        announced = true;
        requestReceived.complete();
        socket.add(
          utf8.encode(
            'HTTP/1.1 200 OK\r\n'
            'Content-Type: application/json\r\n'
            'Content-Length: 1000000\r\n'
            'Connection: keep-alive\r\n\r\n'
            '{"data":[',
          ),
        );
      },
      onDone: () {
        if (!peerClosed.isCompleted) peerClosed.complete();
      },
      onError: (_) {
        if (!peerClosed.isCompleted) peerClosed.complete();
      },
    );
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}
