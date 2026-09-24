import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generate maps thoughts, signed calls, files, and grounding sources',
    () async {
      final adapter = _Adapter(
        (_) => {
          'candidates': [
            {
              'finishReason': 'STOP',
              'content': {
                'parts': [
                  {
                    'text': 'reason',
                    'thought': true,
                    'thoughtSignature': 'sig',
                  },
                  {
                    'functionCall': {
                      'id': 'call1',
                      'name': 'lookup',
                      'args': {'q': 1},
                    },
                    'thoughtSignature': 'sig-call',
                  },
                  {
                    'fileData': {
                      'fileUri': 'https://files.test/a',
                      'mimeType': 'text/plain',
                    },
                  },
                  {
                    'inlineData': {'mimeType': 'image/png', 'data': 'AQI='},
                  },
                ],
              },
              'groundingMetadata': {
                'groundingChunks': [
                  {
                    'web': {'uri': 'https://source.test', 'title': 'Source'},
                  },
                  {
                    'web': {'uri': ''},
                  },
                  {'other': {}},
                ],
              },
            },
          ],
        },
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final result = await _model(dio).doGenerate(_options());
      expect(
        result.content
            .whereType<LanguageModelV4ReasoningPart>()
            .single
            .providerOptions?['google']?['thoughtSignature'],
        'sig',
      );
      expect(
        result.content
            .whereType<LanguageModelV4ToolCallPart>()
            .single
            .toolCallId,
        'call1',
      );
      expect(result.content.whereType<LanguageModelV4FilePart>(), hasLength(2));
      expect(
        result.content.whereType<LanguageModelV4SourcePart>().single.url,
        'https://source.test',
      );
    },
  );

  test(
    'tool result variants serialize and unsupported media fails before dispatch',
    () async {
      final adapter = _Adapter((_) => {'candidates': []});
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final outputs = <LanguageModelV4ToolResultOutput>[
        const ToolResultOutputErrorText('bad'),
        const ToolResultOutputErrorJson({'bad': true}),
        const ToolResultOutputExecutionDenied('denied', 'approval1'),
        ToolResultOutputContent([
          const LanguageModelV4TextPart(text: 'text'),
          LanguageModelV4ImagePart(
            image: DataContentBytes(Uint8List.fromList([1])),
            mediaType: 'image/png',
          ),
          LanguageModelV4FilePart(
            data: DataContentBytes(Uint8List.fromList([2])),
            mediaType: 'application/pdf',
            filename: 'a.pdf',
          ),
        ]),
      ];
      final prompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.tool,
            content: [
              for (var i = 0; i < outputs.length; i++)
                LanguageModelV4ToolResultPart(
                  toolCallId: 'call$i',
                  toolName: 'tool',
                  output: outputs[i],
                ),
            ],
          ),
        ],
      );
      await _model(dio).doGenerate(LanguageModelV4CallOptions(prompt: prompt));
      final parts =
          ((adapter.input['contents'] as List).single as Map)['parts'] as List;
      expect(
        parts.map(
          (part) =>
              ((part as Map)['functionResponse']
                  as Map)['response']['output']['type'],
        ),
        ['error-text', 'error-json', 'execution-denied', 'content'],
      );
      final content =
          ((((parts.last as Map)['functionResponse']
                  as Map)['response']['output']['parts'])
              as List);
      expect(content.map((part) => (part as Map)['type']), [
        'text',
        'image',
        'file',
      ]);
      final badPrompt = LanguageModelV4Prompt(
        messages: [
          LanguageModelV4Message(
            role: LanguageModelV4Role.tool,
            content: [
              LanguageModelV4ToolResultPart(
                toolCallId: 'x',
                toolName: 'tool',
                output: const ToolResultOutputContent([
                  LanguageModelV4ReasoningPart(text: 'not serializable'),
                ]),
              ),
            ],
          ),
        ],
      );
      await expectLater(
        _model(dio).doGenerate(LanguageModelV4CallOptions(prompt: badPrompt)),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );

  test(
    'stream maps thought lifecycle, media, sources, and omitted finish reason',
    () async {
      final adapter = _Adapter(
        (_) => const {},
        stream: [
          {
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': 'thinking',
                      'thought': true,
                      'thoughtSignature': 'sig',
                    },
                    {'text': 'answer'},
                    {
                      'functionCall': {
                        'name': 'lookup',
                        'args': {'q': 1},
                      },
                    },
                    {
                      'fileData': {'fileUri': 'https://files.test/a'},
                    },
                    {
                      'inlineData': {'data': 'AQI='},
                    },
                  ],
                },
                'groundingMetadata': {
                  'groundingChunks': [
                    {
                      'web': {'uri': 'https://source.test'},
                    },
                    {
                      'web': {'uri': ''},
                    },
                    {'other': {}},
                  ],
                },
              },
            ],
          },
          {
            'candidates': [
              {'finishReason': 'MAX_TOKENS'},
            ],
            'usageMetadata': {'promptTokenCount': 3},
          },
        ],
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final parts = await (await _model(
        dio,
      ).doStream(_options())).stream.toList();
      expect(parts.whereType<StreamPartReasoningStart>(), hasLength(1));
      expect(
        parts.whereType<StreamPartReasoningDelta>().single.delta,
        'thinking',
      );
      expect(
        parts.whereType<StreamPartToolCall>().single.toolCall.toolName,
        'lookup',
      );
      expect(parts.whereType<StreamPartFile>(), hasLength(2));
      expect(parts.whereType<StreamPartSource>(), hasLength(1));
      expect(
        parts.whereType<StreamPartFinish>().single.finishReason,
        LanguageModelV4FinishReason.length,
      );
    },
  );
  test('portable reasoning maps across Gemini model families', () async {
    final adapter = _Adapter((_) => {'candidates': []});
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    const levels = [
      LanguageModelV4Reasoning.none,
      LanguageModelV4Reasoning.minimal,
      LanguageModelV4Reasoning.low,
      LanguageModelV4Reasoning.medium,
      LanguageModelV4Reasoning.high,
      LanguageModelV4Reasoning.xhigh,
    ];
    for (final reasoning in levels) {
      await _model(
        dio,
      ).doGenerate(_options(reasoning: reasoning, maxOutputTokens: 10));
      expect(
        (adapter.input['generationConfig'] as Map)['thinkingConfig'],
        isA<Map>(),
      );
    }
    for (final modelId in ['gemini-3-flash', 'gemini-3-pro']) {
      for (final reasoning in levels) {
        await _model(
          dio,
          modelId: modelId,
        ).doGenerate(_options(reasoning: reasoning));
      }
    }
    expect((adapter.input['generationConfig'] as Map)['thinkingConfig'], {
      'thinkingLevel': 'high',
    });
  });

  test('rejects unsupported prompt files and media in tool results', () async {
    final adapter = _Adapter((_) => {'candidates': []});
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    for (final part in <LanguageModelV4ContentPart>[
      const LanguageModelV4ReasoningFilePart(
        data: DataContentBase64('AQ=='),
        mediaType: 'application/pdf',
      ),
      const LanguageModelV4DocumentSourcePart(
        id: 'doc',
        mediaType: 'application/pdf',
        title: 'Doc',
      ),
    ]) {
      await expectLater(
        _model(dio).doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.user,
                  content: [part],
                ),
              ],
            ),
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    }
    for (final part in <LanguageModelV4ContentPart>[
      const LanguageModelV4ImagePart(
        image: DataContentProviderReference(namespace: 'google', id: 'image1'),
        mediaType: 'image/png',
      ),
      const LanguageModelV4FilePart(
        data: DataContentProviderReference(namespace: 'google', id: 'file1'),
        mediaType: 'application/pdf',
      ),
    ]) {
      await expectLater(
        _model(dio).doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.tool,
                  content: [
                    LanguageModelV4ToolResultPart(
                      toolCallId: 'call1',
                      toolName: 'tool',
                      output: ToolResultOutputContent([part]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    }
  });
  test(
    'replays Gemini thought signatures on reasoning and function parts',
    () async {
      final adapter = _Adapter((_) => {'candidates': []});
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      expect(google, isA<GoogleGenerativeAIProvider>());
      await _model(dio).doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: [
                  const LanguageModelV4ReasoningPart(
                    text: 'thinking',
                    providerOptions: {
                      'google': {'thoughtSignature': 'sig-thought'},
                    },
                  ),
                  const LanguageModelV4ToolCallPart(
                    toolCallId: 'call1',
                    toolName: 'lookup',
                    input: {'q': 1},
                    providerOptions: {
                      'google': {'thoughtSignature': 'sig-call'},
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      final parts =
          (((adapter.input['contents'] as List).single as Map)['parts']
              as List);
      expect((parts[0] as Map)['thoughtSignature'], 'sig-thought');
      expect((parts[1] as Map)['thoughtSignature'], 'sig-call');
    },
  );

  test(
    'serializes empty tool output and JSON schema response format',
    () async {
      final adapter = _Adapter((_) => {'candidates': []});
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      await _model(dio).doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.tool,
                content: [
                  const LanguageModelV4ToolResultPart(
                    toolCallId: 'call1',
                    toolName: 'lookup',
                    output: ToolResultOutputContent([]),
                  ),
                ],
              ),
            ],
          ),
          responseFormat: const LanguageModelV4JsonResponseFormat(
            schema: {'type': 'object'},
          ),
          reasoning: LanguageModelV4Reasoning.xhigh,
        ),
      );
      final generationConfig = adapter.input['generationConfig'] as Map;
      expect(generationConfig['responseMimeType'], 'application/json');
      expect(generationConfig['responseJsonSchema'], {'type': 'object'});
      expect(
        (((adapter.input['contents'] as List).single as Map)['parts'] as List)
            .single,
        {
          'functionResponse': {
            'id': 'call1',
            'name': 'lookup',
            'response': {
              'isError': false,
              'output': {'type': 'content', 'parts': []},
            },
          },
        },
      );
    },
  );
  test('streams with a JSON schema and cancels an active stream', () async {
    final adapter = _Adapter(
      (_) => {},
      stream: [
        {'candidates': []},
      ],
    );
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final result = await _model(dio, modelId: 'gemini-3-pro').doStream(
      LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
        responseFormat: const LanguageModelV4JsonResponseFormat(
          schema: {'type': 'object'},
        ),
        reasoning: LanguageModelV4Reasoning.xhigh,
      ),
    );
    final config = adapter.input['generationConfig'] as Map;
    expect(config['responseMimeType'], 'application/json');
    expect(config['responseJsonSchema'], {'type': 'object'});
    expect(config['thinkingConfig'], {'thinkingLevel': 'high'});
    await result.stream.listen((_) {}).cancel();
  });
}

LanguageModelV4 _model(Dio dio, {String modelId = 'gemini-test'}) =>
    GoogleGenerativeAIProvider(apiKey: 'fixture', client: dio).call(modelId);

LanguageModelV4CallOptions _options({
  LanguageModelV4Reasoning reasoning = LanguageModelV4Reasoning.providerDefault,
  int? maxOutputTokens,
}) => LanguageModelV4CallOptions(
  reasoning: reasoning,
  maxOutputTokens: maxOutputTokens,
  prompt: LanguageModelV4Prompt(messages: []),
);

class _Adapter implements HttpClientAdapter {
  _Adapter(this.response, {this.stream});
  final Map<String, dynamic> Function(RequestOptions request) response;
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
