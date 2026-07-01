import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_openai_compatible/ai_sdk_openai_compatible.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// A non-2xx provider response should surface as a typed [AiApiCallError] from
/// both the non-streaming and streaming chat paths.
void main() {
  group('openai-compatible API error surfacing', () {
    HttpServer? server;

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    Future<String> startErrorServer({
      int status = 400,
      Object body = const {
        'error': {
          'message': 'model not found',
          'type': 'invalid_request_error',
          'code': 'model_not_found',
        },
      },
    }) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server = s;
      unawaited(() async {
        await for (final request in s) {
          await request.drain<void>();
          request.response.statusCode = status;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}/v1';
    }

    OpenAICompatibleChatLanguageModel model(String baseUrl) =>
        OpenAICompatibleChatLanguageModel(
          modelId: 'm',
          config: OpenAICompatibleConfig(
            provider: 'test',
            baseUrl: baseUrl,
            headers: () => {'Authorization': 'Bearer test-token'},
          ),
        );

    LanguageModelV3Prompt userPrompt(String text) => LanguageModelV3Prompt(
      messages: [
        LanguageModelV3Message(
          role: LanguageModelV3Role.user,
          content: [LanguageModelV3TextPart(text: text)],
        ),
      ],
    );

    test('doGenerate surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      await expectLater(
        model(
          baseUrl,
        ).doGenerate(LanguageModelV3CallOptions(prompt: userPrompt('hi'))),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'model not found')
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'model_not_found'),
        ),
      );
    });

    test('doStream surfaces a connection-time provider error', () async {
      final baseUrl = await startErrorServer(
        status: 401,
        body: {
          'error': {'message': 'invalid api key', 'code': 'invalid_api_key'},
        },
      );
      await expectLater(
        model(
          baseUrl,
        ).doStream(LanguageModelV3CallOptions(prompt: userPrompt('hi'))),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'invalid api key')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });
}
