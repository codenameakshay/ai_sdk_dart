import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_groq/ai_sdk_groq.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// Groq delegates chat to the shared openai-compatible base, so a non-2xx
/// response should surface as a typed [AiApiCallError].
void main() {
  group('Groq API error surfacing', () {
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
          request.response.statusCode = 429;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'error': {
                'message': 'rate limit reached for requests',
                'type': 'rate_limit_exceeded',
                'code': 'rate_limit',
              },
            }),
          );
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}/openai/v1';
    }

    test('doGenerate surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = GroqProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).call('llama-3.1-8b-instant');
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
              .having((e) => e.message, 'message', contains('rate limit'))
              .having((e) => e.statusCode, 'statusCode', 429)
              .having((e) => e.isRetryable, 'isRetryable', isTrue),
        ),
      );
    });
  });
}
