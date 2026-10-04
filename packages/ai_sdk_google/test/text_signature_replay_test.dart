import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      '${streaming ? 'streaming' : 'generation'} replays signed answer text',
      () async {
        final adapter = _Adapter();
        final client = Dio()..httpClientAdapter = adapter;
        addTearDown(() => client.close(force: true));
        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          client: client,
        ).call('gemini-3-flash');
        final content = streaming
            ? await (await streamText(model: model, prompt: 'hello')).content
            : (await generateText(model: model, prompt: 'hello')).content;
        expect(
          content
              .whereType<LanguageModelV4TextPart>()
              .single
              .providerOptions?['google']?['thoughtSignature'],
          'signature',
        );
        await model.doGenerate(
          LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(
              messages: [
                LanguageModelV4Message(
                  role: LanguageModelV4Role.assistant,
                  content: content,
                ),
              ],
            ),
          ),
        );
        final parts =
            ((adapter.lastBody['contents'] as List).single as Map)['parts']
                as List;
        expect((parts.single as Map)['thoughtSignature'], 'signature');
        expect((parts.single as Map)['text'], 'answer');
      },
    );
  }
  test(
    'streaming preserves an answer signature on an empty final text chunk',
    () async {
      final client = Dio()
        ..httpClientAdapter = _Adapter(separateSignature: true);
      addTearDown(() => client.close(force: true));
      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        client: client,
      ).call('gemini-3-flash');
      final result = await streamText(model: model, prompt: 'hello');
      final content = await result.content;
      expect(
        content
            .whereType<LanguageModelV4TextPart>()
            .single
            .providerOptions?['google']?['thoughtSignature'],
        'signature',
      );
    },
  );

  for (final scenario in [
    (
      name: 'late nonempty thought chunk',
      expectedText: 'private reasoning',
      events: [
        _thoughtChunk('private ', finish: false),
        _thoughtChunk('reasoning', signature: 'thought-signature'),
      ],
    ),
    (
      name: 'empty terminal thought chunk',
      expectedText: 'private reasoning',
      events: [
        _thoughtChunk('private reasoning', finish: false),
        _thoughtChunk('', signature: 'thought-signature'),
      ],
    ),
  ]) {
    test('streamed ${scenario.name} signature survives replay', () async {
      final streamAdapter = _ThoughtSignatureAdapter(scenario.events);
      final streamClient = Dio()..httpClientAdapter = streamAdapter;
      addTearDown(() => streamClient.close(force: true));
      final model = GoogleGenerativeAIProvider(
        apiKey: 'test',
        client: streamClient,
      ).call('gemini-3-flash');

      final streamedContent = await (await streamText(
        model: model,
        prompt: 'hello',
      )).content;
      final streamedReasoning = streamedContent
          .whereType<LanguageModelV4ReasoningPart>()
          .single;
      expect(streamedReasoning.text, scenario.expectedText);
      expect(
        streamedReasoning.providerOptions?['google']?['thoughtSignature'],
        'thought-signature',
      );

      await model.doGenerate(
        LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(
            messages: [
              LanguageModelV4Message(
                role: LanguageModelV4Role.assistant,
                content: streamedContent,
              ),
            ],
          ),
        ),
      );
      final replayedPart =
          ((streamAdapter.lastBody['contents'] as List).single as Map)['parts']
              as List;
      expect(
        (replayedPart.single as Map)['thoughtSignature'],
        'thought-signature',
      );
      expect((replayedPart.single as Map)['thought'], isTrue);

      final generateAdapter = _ThoughtSignatureAdapter(const []);
      final generateClient = Dio()..httpClientAdapter = generateAdapter;
      addTearDown(() => generateClient.close(force: true));
      final generated = await generateText(
        model: GoogleGenerativeAIProvider(
          apiKey: 'test',
          client: generateClient,
        ).call('gemini-3-flash'),
        prompt: 'hello',
      );
      final generatedReasoning = generated.content
          .whereType<LanguageModelV4ReasoningPart>()
          .single;
      expect(generatedReasoning.text, streamedReasoning.text);
      expect(
        generatedReasoning.providerOptions?['google']?['thoughtSignature'],
        streamedReasoning.providerOptions?['google']?['thoughtSignature'],
      );
    });
  }

  test('streamed late function-call signature survives replay', () async {
    final events = [
      {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'id': 'call-1',
                    'name': 'lookup',
                    'args': {'q': 'x'},
                  },
                },
              ],
            },
          },
        ],
      },
      {
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'functionCall': {
                    'id': 'call-1',
                    'name': 'lookup',
                    'args': {'q': 'x'},
                  },
                  'thoughtSignature': 'call-signature',
                },
              ],
            },
            'finishReason': 'STOP',
          },
        ],
      },
    ];
    final adapter = _ThoughtSignatureAdapter(events);
    final client = Dio()..httpClientAdapter = adapter;
    addTearDown(() => client.close(force: true));
    final model = GoogleGenerativeAIProvider(
      apiKey: 'test',
      client: client,
    ).call('gemini-3-flash');

    final result = await model.doStream(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      ),
    );
    final call = (await result.stream.toList())
        .whereType<StreamPartToolCall>()
        .single
        .toolCall;
    expect(call.toolCallId, 'call-1');
    expect(
      call.providerOptions?['google']?['thoughtSignature'],
      'call-signature',
    );

    await model.doGenerate(
      LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(
          messages: [
            LanguageModelV4Message(
              role: LanguageModelV4Role.assistant,
              content: [call],
            ),
          ],
        ),
      ),
    );
    final replayedPart =
        ((adapter.lastBody['contents'] as List).single as Map)['parts'] as List;
    expect((replayedPart.single as Map)['thoughtSignature'], 'call-signature');
    expect(
      ((replayedPart.single as Map)['functionCall'] as Map)['name'],
      'lookup',
    );
  });
}

Map<String, dynamic> _thoughtChunk(
  String text, {
  String? signature,
  bool finish = true,
}) => {
  'candidates': [
    {
      'content': {
        'parts': [
          {'text': text, 'thought': true, 'thoughtSignature': ?signature},
        ],
      },
      if (finish) 'finishReason': 'STOP',
    },
  ],
};

class _Adapter implements HttpClientAdapter {
  _Adapter({this.separateSignature = false});

  final bool separateSignature;
  late Map<String, dynamic> lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastBody = (options.data as Map).cast<String, dynamic>();
    Map<String, dynamic> chunk(
      Map<String, dynamic> part, {
      bool finish = false,
    }) => {
      'candidates': [
        {
          'content': {
            'parts': [part],
          },
          if (finish) 'finishReason': 'STOP',
        },
      ],
    };
    final response = chunk({
      'text': 'answer',
      'thoughtSignature': 'signature',
    }, finish: true);
    final streaming = options.responseType == ResponseType.stream;
    final events = separateSignature
        ? [
            chunk({'text': 'answer'}),
            chunk({'text': '', 'thoughtSignature': 'signature'}, finish: true),
          ]
        : [response];
    return ResponseBody.fromString(
      streaming
          ? events.map((event) => 'data: ${jsonEncode(event)}\n\n').join()
          : jsonEncode(response),
      200,
      headers: {
        'content-type': [streaming ? 'text/event-stream' : 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThoughtSignatureAdapter implements HttpClientAdapter {
  _ThoughtSignatureAdapter(this.events);

  final List<Map<String, dynamic>> events;
  late Map<String, dynamic> lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastBody = (options.data as Map).cast<String, dynamic>();
    final streaming = options.responseType == ResponseType.stream;
    final responseEvents = streaming
        ? events
        : [_thoughtChunk('private reasoning', signature: 'thought-signature')];
    final body = streaming
        ? responseEvents.map((event) => 'data: ${jsonEncode(event)}\n\n').join()
        : jsonEncode(responseEvents.single);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': [streaming ? 'text/event-stream' : 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
