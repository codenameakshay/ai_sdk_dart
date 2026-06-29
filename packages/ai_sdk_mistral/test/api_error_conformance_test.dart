import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_mistral/ai_sdk_mistral.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// Mistral's embeddings use a direct Dio client; a non-2xx response should
/// surface as a typed [AiApiCallError].
void main() {
  group('Mistral API error surfacing', () {
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
          request.response.statusCode = 422;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'object': 'error',
              'message': 'Invalid model',
              'type': 'invalid_request_error',
            }),
          );
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}/v1';
    }

    test('doEmbed surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = MistralProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).embedding('nope');
      await expectLater(
        model.doEmbed(const EmbeddingModelV2CallOptions(values: ['hi'])),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'Invalid model')
              .having((e) => e.statusCode, 'statusCode', 422),
        ),
      );
    });
  });
}
