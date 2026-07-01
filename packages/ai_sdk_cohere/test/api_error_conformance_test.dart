import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// A non-2xx Cohere response (top-level `{message}` shape) should surface as a
/// typed [AiApiCallError].
void main() {
  group('Cohere API error surfacing', () {
    HttpServer? server;

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    Future<String> startErrorServer({
      int statusCode = 404,
      String message = "model 'nope' not found",
    }) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server = s;
      unawaited(() async {
        await for (final request in s) {
          await request.drain<void>();
          request.response.statusCode = statusCode;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'message': message}));
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}';
    }

    test('doGenerate surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = CohereProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).call('command-r');
      await expectLater(
        model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
          ),
        ),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', "model 'nope' not found")
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });

    test('doEmbed surfaces the provider message', () async {
      final baseUrl = await startErrorServer(
        statusCode: 400,
        message: 'invalid embedding model',
      );
      final model = CohereProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).embedding('embed-english-v3.0');
      await expectLater(
        model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['hello']),
        ),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'invalid embedding model')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('doRerank surfaces the provider message', () async {
      final baseUrl = await startErrorServer(
        statusCode: 422,
        message: 'unknown rerank model',
      );
      final model = CohereProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).rerank('rerank-english-v3.0');
      await expectLater(
        model.doRerank(
          const RerankModelV1CallOptions(
            query: 'q',
            documents: ['a', 'b'],
          ),
        ),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'unknown rerank model')
              .having((e) => e.statusCode, 'statusCode', 422),
        ),
      );
    });

    test('doStream drains a streamed error body and surfaces the message',
        () async {
      // doStream issues the /chat request with ResponseType.stream, so a
      // non-2xx response arrives as a dio ResponseBody rather than decoded
      // JSON. _apiCallError must drain that byte stream to recover the
      // provider message (exercises the ResponseBody branch).
      final baseUrl = await startErrorServer(
        statusCode: 401,
        message: 'invalid api token',
      );
      final model = CohereProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).call('command-r-plus');
      await expectLater(
        model.doStream(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [LanguageModelV3TextPart(text: 'hi')],
                ),
              ],
            ),
          ),
        ),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'invalid api token')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });
}
