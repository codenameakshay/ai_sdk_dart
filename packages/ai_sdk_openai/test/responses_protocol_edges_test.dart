import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generate maps mixed native output and malformed function arguments',
    () async {
      final adapter = _Adapter(
        (_) => {
          'id': 'r1',
          'status': 'completed',
          'output': [
            {
              'type': 'message',
              'id': 'msg1',
              'content': [
                {
                  'type': 'output_text',
                  'text': 'answer',
                  'annotations': [
                    {
                      'type': 'url_citation',
                      'url': 'https://example.test',
                      'title': 'Site',
                    },
                    {'type': 'file_citation', 'file_id': 'file1'},
                  ],
                },
                {'type': 'output_text', 'text': ''},
              ],
            },
            {
              'type': 'reasoning',
              'id': 'reason1',
              'summary': [
                {'text': 'think'},
              ],
            },
            {
              'type': 'function_call',
              'id': 'item1',
              'call_id': 'call1',
              'name': 'f',
              'arguments': '{bad',
            },
            {'type': 'future_item', 'id': 'opaque1'},
            null,
          ],
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final result = await _model(dio).doGenerate(_options());
      expect(
        result.content.whereType<LanguageModelV4TextPart>().single.text,
        'answer',
      );
      expect(
        result.content.whereType<LanguageModelV4SourcePart>().single.url,
        'https://example.test',
      );
      expect(
        result.content
            .whereType<LanguageModelV4DocumentSourcePart>()
            .single
            .mediaType,
        'application/octet-stream',
      );
      expect(
        result.content.whereType<LanguageModelV4ReasoningPart>().single.text,
        'think',
      );
      expect(
        result.content.whereType<LanguageModelV4ToolCallPart>().single.input,
        '{bad',
      );
      expect(
        (result.content.whereType<LanguageModelV4OpaquePart>().single.raw
            as Map)['type'],
        'future_item',
      );
    },
  );

  test(
    'stream maps item identity, reasoning, hosted annotations and terminal metadata',
    () async {
      final adapter = _Adapter(
        (_) => const {},
        stream: [
          {
            'type': 'response.output_item.added',
            'output_index': 0,
            'item': {'type': 'message', 'id': 'msg1'},
          },
          {
            'type': 'response.output_text.delta',
            'item_id': 'msg1',
            'delta': 'hello',
          },
          {
            'type': 'response.output_text.annotation.added',
            'annotation': {'type': 'file_citation', 'file_id': 'f1'},
          },
          {
            'type': 'response.reasoning_text.delta',
            'item_id': 'reason1',
            'delta': 'hmm',
          },
          {
            'type': 'response.output_item.added',
            'item': {
              'type': 'function_call',
              'id': 'fn1',
              'call_id': 'call1',
              'name': 'lookup',
            },
          },
          {
            'type': 'response.function_call_arguments.delta',
            'item_id': 'fn1',
            'delta': '{"q":1}',
          },
          {'type': 'response.function_call_arguments.done', 'item_id': 'fn1'},
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'reasoning',
              'id': 'reason1',
              'encrypted_content': 'opaque',
            },
          },
          {
            'type': 'response.output_item.done',
            'output_index': 0,
            'item': {'type': 'message', 'id': 'other'},
          },
          {
            'type': 'response.output_item.done',
            'item': {
              'type': 'web_search_call',
              'id': 'search1',
              'status': 'completed',
              'action': {
                'sources': [
                  {'url': 'https://source.test'},
                ],
              },
            },
          },
          {
            'type': 'response.completed',
            'response': {
              'id': 'r1',
              'model': 'm1',
              'status': 'completed',
              'usage': {'input_tokens': 2},
            },
          },
        ],
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final result = await _model(dio).doStream(_options());
      final parts = await result.stream.toList();
      expect(parts.whereType<StreamPartTextStart>().single.id, 'msg1');
      expect(parts.whereType<StreamPartDocumentSource>(), hasLength(1));
      expect(parts.whereType<StreamPartReasoningDelta>().single.delta, 'hmm');
      expect(
        parts.whereType<StreamPartToolCall>().map((p) => p.toolCall.toolCallId),
        containsAll(['call1', 'search1']),
      );
      expect(
        parts.whereType<StreamPartSource>().single.source.url,
        'https://source.test',
      );
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.stop,
      );
    },
  );

  test('stream reports truncated and malformed protocol events', () async {
    for (final stream in <List<Map<String, dynamic>>>[
      [
        {'type': 'response.output_text.delta', 'delta': 'missing id'},
      ],
      [
        {
          'type': 'response.function_call_arguments.delta',
          'item_id': 'unknown',
          'delta': '{}',
        },
      ],
      [
        {
          'type': 'response.output_item.added',
          'item': {
            'type': 'function_call',
            'id': 'x',
            'call_id': 'a',
            'name': 'f',
          },
        },
        {
          'type': 'response.output_item.added',
          'item': {
            'type': 'function_call',
            'id': 'x',
            'call_id': 'b',
            'name': 'f',
          },
        },
      ],
      [],
    ]) {
      final adapter = _Adapter((_) => const {}, stream: stream);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final parts = await (await _model(
        dio,
      ).doStream(_options())).stream.toList();
      expect(parts.whereType<StreamPartError>(), isNotEmpty);
    }
  });

  test(
    'replays image, raw extensions and tool result variants in wire format',
    () async {
      final adapter = _Adapter(
        (_) => {'id': 'r', 'status': 'completed', 'output': []},
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final prompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.user,
            content: [
              LanguageModelV4ImagePart(
                image: DataContentBytes(Uint8List.fromList([1, 2])),
                mediaType: 'image/jpeg',
              ),
              const LanguageModelV4TextPart(
                text: 'raw',
                providerOptions: {
                  'openai': {
                    'type': 'response_item_extension',
                    'raw': {'type': 'item', 'id': 'raw1'},
                  },
                },
              ),
            ],
          ),
          LanguageModelV4Message(
            role: LanguageModelV4Role.tool,
            content: [
              LanguageModelV4ToolResultPart(
                toolCallId: 'a',
                toolName: 'f',
                output: const ToolResultOutputExecutionDenied('no'),
              ),
              LanguageModelV4ToolResultPart(
                toolCallId: 'b',
                toolName: 'f',
                output: const ToolResultOutputJson({'ok': true}),
              ),
            ],
          ),
        ],
      );
      await _model(dio).doGenerate(LanguageModelV4CallOptions(prompt: prompt));
      final input = adapter.input as Map;
      final items = input['input'] as List;
      expect(
        items.whereType<Map>().any((item) => item['id'] == 'raw1'),
        isTrue,
      );
      expect(
        items
            .whereType<Map>()
            .firstWhere((item) => item['role'] == 'user')['content']
            .first['image_url'],
        'data:image/jpeg;base64,AQI=',
      );
      expect(
        items.whereType<Map>().map((item) => item['output']),
        contains('no'),
      );
      expect(
        items.whereType<Map>().map((item) => item['output']),
        contains('{"ok":true}'),
      );
    },
  );
  test(
    'replays provider raw items, approval responses and omits citations',
    () async {
      final adapter = _Adapter(
        (_) => {'id': 'r', 'status': 'completed', 'output': []},
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final prompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.assistant,
            content: [
              const LanguageModelV4ReasoningPart(
                text: 'hidden',
                providerOptions: {
                  'openai': {
                    'raw': {'type': 'reasoning', 'id': 'reason-raw'},
                  },
                },
              ),
              const LanguageModelV4ToolCallPart(
                toolCallId: 'call-raw',
                toolName: 'lookup',
                input: {},
                providerOptions: {
                  'openai': {
                    'raw': {'type': 'function_call', 'id': 'call-raw-item'},
                  },
                },
              ),
              const LanguageModelV4ToolResultPart(
                toolCallId: 'call-raw',
                toolName: 'lookup',
                output: ToolResultOutputText('ok'),
                providerOptions: {
                  'openai': {
                    'raw': {'type': 'function_call_output', 'id': 'output-raw'},
                  },
                },
              ),
              LanguageModelV4ReasoningFilePart(
                data: DataContentBytes(Uint8List(0)),
                mediaType: 'application/pdf',
                providerOptions: {
                  'openai': {
                    'raw': {'type': 'reasoning_file', 'id': 'reason-file'},
                  },
                },
              ),
              const LanguageModelV4SourcePart(
                id: 's',
                url: 'https://source.test',
              ),
              const LanguageModelV4DocumentSourcePart(
                id: 'd',
                mediaType: 'application/pdf',
                title: 'Doc',
              ),
              const LanguageModelV4ToolApprovalResponse(
                approvalId: 'approve-1',
                approved: false,
                reason: 'no',
              ),
              const LanguageModelV4OpaquePart(
                provider: 'openai',
                raw: {'type': 'opaque', 'id': 'opaque1'},
              ),
            ],
          ),
        ],
      );
      await _model(dio).doGenerate(LanguageModelV4CallOptions(prompt: prompt));
      final items = (adapter.input as Map)['input'] as List;
      expect(items.whereType<Map>().map((item) => item['type']), [
        'reasoning',
        'function_call',
        'function_call_output',
        'reasoning_file',
        'mcp_approval_response',
        'opaque',
      ]);
    },
  );

  test(
    'computer structured output preserves safety checks and rejects invalid screenshots',
    () async {
      final adapter = _Adapter(
        (_) => {'id': 'r', 'status': 'completed', 'output': []},
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      Future<void> send(Object value) => _model(dio).doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  LanguageModelV4ToolResultPart(
                    toolCallId: 'computer1',
                    toolName: 'computer',
                    output: ToolResultOutputJson(value),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await send({
        'output': {
          'type': 'computer_screenshot',
          'fileId': 'file1',
          'detail': 'high',
        },
        'acknowledgedSafetyChecks': [
          {'id': 'safe1', 'code': 'ok', 'message': 'checked'},
        ],
      });
      final item = ((adapter.input as Map)['input'] as List).single as Map;
      expect(item['output'], {
        'type': 'computer_screenshot',
        'file_id': 'file1',
        'detail': 'high',
      });
      expect(item['acknowledged_safety_checks'], [
        {'id': 'safe1', 'code': 'ok', 'message': 'checked'},
      ]);
      for (final invalid in [
        'not an object',
        <String, dynamic>{},
        {
          'output': {'type': 'other', 'imageUrl': 'x'},
        },
        {
          'output': {
            'type': 'computer_screenshot',
            'imageUrl': 'x',
            'detail': 1,
          },
        },
        {
          'output': {'type': 'computer_screenshot', 'imageUrl': 'x'},
          'acknowledgedSafetyChecks': 'bad',
        },
        {
          'output': {'type': 'computer_screenshot', 'imageUrl': 'x'},
          'acknowledgedSafetyChecks': [null],
        },
        {
          'output': {'type': 'computer_screenshot', 'imageUrl': 'x'},
          'acknowledgedSafetyChecks': [{}],
        },
      ]) {
        await expectLater(send(invalid), throwsA(isA<FormatException>()));
      }
    },
  );
  test(
    'response request warnings and unsupported replay values are explicit',
    () async {
      final adapter = _Adapter(
        (_) => {'id': 'r', 'status': 'mystery', 'output': []},
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final model = _model(dio);
      expect(model.provider, 'openai');
      expect(model.specificationVersion, 'v4');
      final result = await model.doGenerate(
        const LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
          stopSequences: ['stop'],
          topK: 2,
          presencePenalty: 0.2,
          frequencyPenalty: 0.3,
          seed: 7,
        ),
      );
      expect(result.warnings, hasLength(5));
      expect(result.finishReason, LanguageModelV4FinishReason.unknown);
      for (final unsupported in <LanguageModelV4ContentPart>[
        const LanguageModelV4OpaquePart(provider: 'openai', raw: 'not a map'),
        const LanguageModelV4ReasoningFilePart(
          data: DataContentBase64('AQ=='),
          mediaType: 'application/pdf',
        ),
      ]) {
        final prompt = LanguageModelV4Prompt(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.user,
              content: [unsupported],
            ),
          ],
        );
        await expectLater(
          model.doGenerate(LanguageModelV4CallOptions(prompt: prompt)),
          throwsA(isA<UnsupportedError>()),
        );
      }
    },
  );
  test('maps transport failures and rejects null response bodies', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (request) => throw DioException(requestOptions: request),
      );
    addTearDown(() => dio.close(force: true));
    await expectLater(
      _model(dio).doGenerate(_options()),
      throwsA(isA<AiApiCallError>()),
    );

    final nullDio = Dio()..httpClientAdapter = _Adapter((_) => null);
    addTearDown(() => nullDio.close(force: true));
    await expectLater(
      _model(nullDio).doGenerate(_options()),
      throwsA(isA<AiApiCallError>()),
    );

    final authDio = Dio()..httpClientAdapter = _Adapter((_) => {});
    addTearDown(() => authDio.close(force: true));
    final authModel = OpenAIProvider(
      client: authDio,
      credentialProvider: () async => throw StateError('credential failure'),
    ).responses('fixture');
    await expectLater(
      authModel.doGenerate(_options()),
      throwsA(isA<StateError>()),
    );
  });
}

LanguageModelV4 _model(Dio dio) =>
    OpenAIProvider(apiKey: 'fixture', client: dio).responses('fixture');

LanguageModelV4CallOptions _options() => const LanguageModelV4CallOptions(
  prompt: LanguageModelV4Prompt(messages: []),
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.response, {this.stream});
  final dynamic Function(RequestOptions request) response;
  final List<Map<String, dynamic>>? stream;
  dynamic input;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    input = options.data;
    final body = stream == null
        ? jsonEncode(response(options))
        : stream!.map((event) => 'data: ${jsonEncode(event)}\n\n').join();
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': [
          stream == null ? 'application/json' : 'text/event-stream',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
