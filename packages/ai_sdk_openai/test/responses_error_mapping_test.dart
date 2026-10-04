import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  test(
    'failed Responses object raises its structured provider error',
    () async {
      final dio = Dio()..httpClientAdapter = _FailedResponseAdapter();
      addTearDown(() => dio.close(force: true));
      final model = OpenAIProvider(
        apiKey: 'fixture',
        client: dio,
      ).responses('fixture');
      await expectLater(
        model.doGenerate(
          const LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(messages: []),
          ),
        ),
        throwsA(
          isA<AiApiCallError>()
              .having((error) => error.code, 'code', 'server_error')
              .having((error) => error.statusCode, 'wire status', 200)
              .having((error) => error.isRetryable, 'replay policy', false)
              .having(
                (error) => error.message,
                'message',
                contains('Provider failed'),
              ),
        ),
      );
    },
  );

  test('failed Responses event preserves the provider error code', () async {
    final dio = Dio()..httpClientAdapter = _FailedResponseAdapter();
    addTearDown(() => dio.close(force: true));
    final model = OpenAIProvider(
      apiKey: 'fixture',
      client: dio,
    ).responses('fixture');
    final result = await model.doStream(
      const LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      ),
    );
    final events = await result.stream.toList();
    final error = events.whereType<StreamPartError>().single.error;
    expect(
      error,
      isA<AiApiCallError>()
          .having((error) => error.code, 'code', 'server_error')
          .having((error) => error.statusCode, 'wire status', 200)
          .having((error) => error.isRetryable, 'replay policy', false),
    );
  });
  test('top-level Responses error preserves its string code', () async {
    final dio = Dio()
      ..httpClientAdapter = _FailedResponseAdapter(topLevel: true);
    addTearDown(() => dio.close(force: true));
    final result = await OpenAIProvider(apiKey: 'fixture', client: dio)
        .responses('fixture')
        .doStream(
          const LanguageModelV4CallOptions(
            prompt: LanguageModelV4Prompt(messages: []),
          ),
        );
    final events = await result.stream.toList();
    expect(
      events.whereType<StreamPartError>().single.error,
      isA<AiApiCallError>().having(
        (error) => error.code,
        'code',
        'rate_limit_exceeded',
      ),
    );
  });
}

class _FailedResponseAdapter implements HttpClientAdapter {
  _FailedResponseAdapter({this.topLevel = false});
  final bool topLevel;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = {
      'id': 'resp-failed',
      'status': 'failed',
      'output': [],
      'error': {'code': 'server_error', 'message': 'Provider failed'},
    };
    final streaming = (options.data as Map)['stream'] == true;
    return ResponseBody.fromString(
      streaming
          ? 'data: ${jsonEncode(topLevel ? {'type': 'error', 'code': 'rate_limit_exceeded', 'message': 'Rate limited'} : {'type': 'response.failed', 'response': response})}\n\n'
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
