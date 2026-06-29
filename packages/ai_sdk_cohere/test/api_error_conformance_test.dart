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

    Future<String> startErrorServer() async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server = s;
      unawaited(() async {
        await for (final request in s) {
          await request.drain<void>();
          request.response.statusCode = 404;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'message': "model 'nope' not found"}),
          );
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
  });
}
