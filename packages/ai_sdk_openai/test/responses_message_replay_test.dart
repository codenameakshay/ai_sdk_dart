import 'dart:convert';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'support/fake_adapter.dart';

void main() {
  test('streamed assistant messages replay their text once', () async {
    final requests = <Map<String, dynamic>>[];
    final dio = Dio()
      ..httpClientAdapter = FakeHttpAdapter((request) async {
        requests.add(Map<String, dynamic>.from(request.data as Map));
        final events = [
          {
            'type': 'response.output_text.delta',
            'item_id': 'message-1',
            'delta': 'Hello',
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'message',
              'id': 'message-1',
              'role': 'assistant',
              'status': 'completed',
              'content': [
                {'type': 'output_text', 'text': 'Hello', 'annotations': []},
              ],
            },
          },
          {
            'type': 'response.completed',
            'response': {'id': 'response-1', 'status': 'completed'},
          },
        ];
        return ResponseBody.fromString(
          events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        );
      });
    addTearDown(() => dio.close(force: true));
    final model = OpenAIProvider(apiKey: 'fixture', client: dio).responses('m');
    final first = await streamText(model: model, prompt: 'hi');
    final firstEvents = first.stream.toList();
    expect(await first.text, 'Hello');
    final history = (await firstEvents)
        .whereType<StreamTextFinishEvent>()
        .single
        .responseMessages;
    final second = await streamText(
      model: model,
      messages: [
        for (final message in history)
          ModelMessage.parts(
            role: ModelMessageRole.assistant,
            parts: message.content,
          ),
      ],
    );
    await second.text;
    expect(requests.last['input'], [
      {
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': 'Hello'},
        ],
      },
    ]);
  });

  test(
    'reasoning without summary or encrypted content replays before its call',
    () async {
      final requests = <Map<String, dynamic>>[];
      final model = _model((request) {
        requests.add(Map<String, dynamic>.from(request.data as Map));
        return requests.length == 1
            ? {
                'id': 'resp_1',
                'status': 'completed',
                'output': [
                  {'type': 'reasoning', 'id': 'rs_1', 'summary': []},
                  {
                    'type': 'function_call',
                    'id': 'fc_1',
                    'call_id': 'call_1',
                    'name': 'lookup',
                    'arguments': '{}',
                  },
                ],
              }
            : {'id': 'resp_2', 'status': 'completed', 'output': []};
      });
      final first = await model.doGenerate(_emptyCall);
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: first.content,
              ),
            ],
          ),
        ),
      );
      expect(requests.last['input'], [
        {'type': 'reasoning', 'id': 'rs_1', 'summary': []},
        {
          'type': 'function_call',
          'id': 'fc_1',
          'call_id': 'call_1',
          'name': 'lookup',
          'arguments': '{}',
        },
      ]);
    },
  );

  test(
    'a completed response with a function call finishes with toolCalls',
    () async {
      final model = _model(
        (_) => {
          'id': 'resp_1',
          'status': 'completed',
          'output': [
            {
              'type': 'function_call',
              'id': 'fc_1',
              'call_id': 'call_1',
              'name': 'lookup',
              'arguments': '{}',
            },
          ],
        },
      );
      final result = await model.doGenerate(_emptyCall);
      expect(result.finishReason, LanguageModelV4FinishReason.toolCalls);
      final streamed = await model.doStream(_emptyCall);
      final finish = (await streamed.stream.toList())
          .whereType<StreamPartFinish>()
          .single;
      expect(finish.finishReason, LanguageModelV4FinishReason.toolCalls);
    },
  );

  test(
    'a function tool named computer replies with function_call_output',
    () async {
      final requests = <Map<String, dynamic>>[];
      final model = _model((request) {
        requests.add(Map<String, dynamic>.from(request.data as Map));
        return {'id': 'resp', 'status': 'completed', 'output': []};
      });
      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [
                  LanguageModelV4ToolCallPart(
                    toolCallId: 'call_1',
                    toolName: 'computer',
                    input: {'q': 1},
                  ),
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'call_1',
                    toolName: 'computer',
                    output: ToolResultOutputText('done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      expect(requests.single['input'], [
        {
          'type': 'function_call',
          'call_id': 'call_1',
          'name': 'computer',
          'arguments': '{"q":1}',
        },
        {'type': 'function_call_output', 'call_id': 'call_1', 'output': 'done'},
      ]);
    },
  );

  test('a computer-named function can return JSON', () async {
    final requests = <Map<String, dynamic>>[];
    final model = _model((request) {
      requests.add(Map<String, dynamic>.from(request.data as Map));
      return {'id': 'resp', 'status': 'completed', 'output': []};
    });
    await model.doGenerate(
      LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.assistant,
              content: [
                LanguageModelV4ToolCallPart(
                  toolCallId: 'call_1',
                  toolName: 'computer',
                  input: {'q': 1},
                  providerOptions: const {'item_id': 'fc_1'},
                ),
                LanguageModelV4ToolResultPart(
                  toolCallId: 'call_1',
                  toolName: 'computer',
                  output: const ToolResultOutputJson({'ok': true}),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    expect(requests.single['input'], [
      {
        'type': 'function_call',
        'id': 'fc_1',
        'call_id': 'call_1',
        'name': 'computer',
        'arguments': '{"q":1}',
      },
      {
        'type': 'function_call_output',
        'call_id': 'call_1',
        'output': '{"ok":true}',
      },
    ]);
  });

  test(
    'raw function_call provenance disambiguates computer result outputs',
    () async {
      final cases =
          <({LanguageModelV4ToolResultOutput output, Object expected})>[
            (output: const ToolResultOutputText('ok'), expected: 'ok'),
            (
              output: const ToolResultOutputErrorText('failed'),
              expected: 'failed',
            ),
            (
              output: const ToolResultOutputJson({'ok': true}),
              expected: '{"ok":true}',
            ),
            (
              output: const ToolResultOutputErrorJson({'error': true}),
              expected: '{"error":true}',
            ),
            (
              output: ToolResultOutputContent([
                LanguageModelV4TextPart(text: 'ok'),
              ]),
              expected: [
                {'type': 'input_text', 'text': 'ok'},
              ],
            ),
          ];
      for (final testCase in cases) {
        final requests = <Map<String, dynamic>>[];
        final model = _model((request) {
          requests.add(Map<String, dynamic>.from(request.data as Map));
          return {'id': 'resp', 'status': 'completed', 'output': []};
        });
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.assistant,
                  content: [
                    LanguageModelV4ToolCallPart(
                      toolCallId: 'call_1',
                      toolName: 'computer',
                      input: const {},
                      providerOptions: {
                        'openai': {
                          'raw': {
                            'type': 'function_call',
                            'id': 'fc_1',
                            'call_id': 'call_1',
                            'name': 'computer',
                            'arguments': '{}',
                          },
                        },
                      },
                    ),
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'call_1',
                      toolName: 'computer',
                      output: testCase.output,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        expect(requests.single['input'], [
          {
            'type': 'function_call',
            'id': 'fc_1',
            'call_id': 'call_1',
            'name': 'computer',
            'arguments': '{}',
          },
          {
            'type': 'function_call_output',
            'call_id': 'call_1',
            'output': testCase.expected,
          },
        ]);
      }
    },
  );

  test('azure responses replay hosted and computer items from raw', () async {
    final requests = <Map<String, dynamic>>[];
    final model = _model((request) {
      requests.add(Map<String, dynamic>.from(request.data as Map));
      return requests.length == 1
          ? {
              'id': 'resp_1',
              'status': 'completed',
              'output': [
                {
                  'type': 'web_search_call',
                  'id': 'ws_1',
                  'status': 'completed',
                  'action': {'type': 'search', 'query': 'Dart'},
                },
                {
                  'type': 'computer_call',
                  'id': 'cu_1',
                  'call_id': 'call_c',
                  'status': 'completed',
                  'action': {'type': 'screenshot'},
                },
              ],
            }
          : {'id': 'resp_2', 'status': 'completed', 'output': []};
    }, providerName: 'azure');
    final first = await model.doGenerate(_emptyCall);
    await model.doGenerate(
      LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.assistant,
              content: first.content,
            ),
          ],
        ),
      ),
    );
    expect(requests.last['input'], [
      {
        'type': 'web_search_call',
        'id': 'ws_1',
        'status': 'completed',
        'action': {'type': 'search', 'query': 'Dart'},
      },
      {
        'type': 'computer_call',
        'id': 'cu_1',
        'call_id': 'call_c',
        'status': 'completed',
        'action': {'type': 'screenshot'},
      },
    ]);
  });
}

const _emptyCall = LanguageModelV4CallOptions(
  prompt: LanguageModelV4Prompt(messages: []),
);

LanguageModelV4 _model(
  Map<String, dynamic> Function(RequestOptions) respond, {
  String providerName = 'openai',
}) {
  final dio = Dio()
    ..httpClientAdapter = FakeHttpAdapter((request) async {
      final body = respond(request);
      final wantsStream = (request.data as Map)['stream'] == true;
      if (wantsStream) {
        final output = body['output'] as List;
        final events = [
          for (final item in output)
            {'type': 'response.output_item.done', 'item': item},
          {'type': 'response.completed', 'response': body},
        ];
        return ResponseBody.fromString(
          events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
          200,
          headers: {
            'content-type': ['text/event-stream'],
          },
        );
      }
      return ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
  addTearDown(() => dio.close(force: true));
  return OpenAIResponsesLanguageModel(
    modelId: 'fixture',
    client: dio,
    headers: () async => const {},
    baseUrl: 'https://api.openai.test/v1',
    providerName: providerName,
  );
}
