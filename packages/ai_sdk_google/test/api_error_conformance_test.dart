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
  });
}
