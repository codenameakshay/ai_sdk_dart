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
}

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
