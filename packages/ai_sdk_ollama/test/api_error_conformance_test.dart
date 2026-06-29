import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// A non-2xx Ollama response (`{error:"..."}` string shape) should surface as a
/// typed [AiApiCallError].
void main() {
  group('Ollama API error surfacing', () {
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
            jsonEncode({'error': 'model "llama99" not found, try pulling it'}),
          );
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}/api';
    }

    test('doGenerate surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = OllamaProvider(baseUrl: baseUrl).call('llama99');
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
                'model "llama99" not found, try pulling it',
              )
              .having((e) => e.statusCode, 'statusCode', 404),
        ),
      );
    });
  });
}
