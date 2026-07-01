import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// A non-2xx Google response should surface as a typed [AiApiCallError]
/// carrying the parsed `error.message` (and `status` preserved as `type`).
void main() {
  group('Google API error surfacing', () {
    HttpServer? server;

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    Future<String> startErrorServer() async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server = s;
      unawaited(() async {
        await for (final request in s) {
          await request.drain<void>();
          request.response.statusCode = 400;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'error': {
                'code': 400,
                'message': 'API key not valid. Please pass a valid API key.',
                'status': 'INVALID_ARGUMENT',
              },
            }),
          );
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}';
    }

    test('doGenerate surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = GoogleGenerativeAIProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).call('gemini-2.0-flash');
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
              .having(
                (e) => e.message,
                'message',
                contains('API key not valid'),
              )
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.type, 'type', 'INVALID_ARGUMENT'),
        ),
      );
    });

    test('doStream surfaces the provider message from a streamed body',
        () async {
      // The streaming endpoint uses ResponseType.stream, so the non-2xx error
      // body arrives as a Dio ResponseBody. The error mapper must drain that
      // stream to recover the message/status/code, then throw AiApiCallError.
      final baseUrl = await startErrorServer();
      final model = GoogleGenerativeAIProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).call('gemini-2.0-flash');
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
              .having(
                (e) => e.message,
                'message',
                contains('API key not valid'),
              )
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.type, 'type', 'INVALID_ARGUMENT'),
        ),
      );
    });

    test('connection error (no HTTP response) falls back to error.message',
        () async {
      // A transport-level failure (connection refused) yields a DioException
      // whose response is null, so there is no body to parse. The mapper must
      // fall back to error.message. Bind then immediately close a server to
      // obtain a definitely-free port to connect to.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close(force: true);
      final model = GoogleGenerativeAIProvider(
        apiKey: 'bad',
        baseUrl: 'http://${InternetAddress.loopbackIPv4.host}:$deadPort',
      ).call('gemini-2.0-flash');
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
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having((e) => e.message, 'message', isNotEmpty),
        ),
      );
    });

    test('doEmbed surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = GoogleGenerativeAIProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).embedding('text-embedding-004');
      await expectLater(
        model.doEmbed(
          const EmbeddingModelV2CallOptions(values: ['hi']),
        ),
        throwsA(
          isA<AiApiCallError>()
              .having(
                (e) => e.message,
                'message',
                contains('API key not valid'),
              )
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.type, 'type', 'INVALID_ARGUMENT'),
        ),
      );
    });
  });
}
