import 'dart:typed_data';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  for (final streaming in [false, true]) {
    test(
      'JSON mode without a schema sends json_object (stream=$streaming)',
      () async {
        final adapter = _CaptureAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(() => dio.close(force: true));
        final model = OpenAICompatibleChatLanguageModel(
          modelId: 'm',
          config: OpenAICompatibleConfig(
            provider: 'test',
            baseUrl: 'http://chat.test',
            client: dio,
            headers: () => const {},
          ),
        );
        const options = LanguageModelV4CallOptions(
          prompt: LanguageModelV4Prompt(messages: []),
          responseFormat: LanguageModelV4JsonResponseFormat(),
        );
        if (streaming) {
          await (await model.doStream(options)).stream.drain<void>();
        } else {
          await model.doGenerate(options);
        }
        expect(adapter.body['response_format'], {'type': 'json_object'});
      },
    );
  }
}

class _CaptureAdapter implements HttpClientAdapter {
  late Map<dynamic, dynamic> body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    body = options.data as Map;
    final streaming = body['stream'] == true;
    return ResponseBody.fromString(
      streaming
          ? 'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n'
          : '{"choices":[{"message":{"content":"{}"},"finish_reason":"stop"}]}',
      200,
      headers: {
        'content-type': [streaming ? 'text/event-stream' : 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
