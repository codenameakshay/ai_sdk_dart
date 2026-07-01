import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_azure/ai_sdk_azure.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// Azure's embeddings use a direct Dio client; a non-2xx response should
/// surface as a typed [AiApiCallError].
void main() {
  group('Azure API error surfacing', () {
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
          request.response.statusCode = 401;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'error': {
                'code': '401',
                'message': 'Access denied due to invalid subscription key.',
              },
            }),
          );
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}';
    }

    test('doEmbed surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = AzureOpenAIProvider(
        endpoint: baseUrl,
        apiKey: 'bad',
      ).embedding('text-embedding-ada-002');
      await expectLater(
        model.doEmbed(const EmbeddingModelV2CallOptions(values: ['hi'])),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', contains('Access denied'))
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.code, 'code', '401'),
        ),
      );
    });
  });
}
