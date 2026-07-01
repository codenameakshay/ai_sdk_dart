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

    // doStream uses ResponseType.stream, so a non-2xx error body arrives as a
    // dio ResponseBody. This exercises both the doStream catch arm and the
    // streamed-body draining inside _apiCallError.
    test('doStream surfaces the provider message from a streamed body', () async {
      final baseUrl = await startErrorServer();
      final model = OllamaProvider(baseUrl: baseUrl).call('llama99');
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
                'model "llama99" not found, try pulling it',
              )
              .having((e) => e.statusCode, 'statusCode', 404)
              // The streamed error body was drained and preserved verbatim.
              .having(
                (e) => e.responseBody,
                'responseBody',
                contains('not found'),
              ),
        ),
      );
    });

    test('doEmbed surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = OllamaProvider(baseUrl: baseUrl).embedding('embed99');
      await expectLater(
        model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['hello']),
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

    // A transport-level failure (connection refused) yields a DioException with
    // no response, so _apiCallError has no body to drain and falls back to
    // error.message for the surfaced message.
    test('falls back to the transport error message when no response body',
        () async {
      // Bind and immediately release a port so nothing is listening on it.
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = probe.port;
      await probe.close(force: true);

      final model = OllamaProvider(
        baseUrl: 'http://${InternetAddress.loopbackIPv4.host}:$deadPort/api',
      ).call('llama3');

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
  });
}
