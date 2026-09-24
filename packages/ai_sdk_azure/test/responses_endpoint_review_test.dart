import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_azure/ai_sdk_azure.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/test_server.dart';

void main() {
  for (final streaming in [false, true]) {
    test('Azure Responses uses the v1 endpoint (stream=$streaming)', () async {
      late Uri uri;
      late Map<String, dynamic> body;
      String? apiKey;
      final server = await TestServer.start((request) async {
        uri = request.uri;
        apiKey = request.headers.value('api-key');
        body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        if (streaming) {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: {"type":"response.completed","response":{"id":"response-1","status":"completed","output":[]}}\n\n',
          );
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'response-1',
              'status': 'completed',
              'output': [],
            }),
          );
        }
        await request.response.close();
      });
      addTearDown(server.close);
      final provider = AzureOpenAIProvider(
        endpoint: server.baseUrl,
        apiKey: 'fixture-key',
        apiVersion: '2024-05-01-preview',
      );
      addTearDown(provider.dispose);
      final model = provider.responses('my-deployment');
      const options = LanguageModelV4CallOptions(
        prompt: LanguageModelV4Prompt(messages: []),
      );
      if (streaming) {
        final result = await model.doStream(options);
        await result.stream.toList();
      } else {
        await model.doGenerate(options);
      }
      expect(uri.path, '/openai/v1/responses');
      expect(uri.queryParameters, isEmpty);
      expect(body['model'], 'my-deployment');
      expect(body['stream'], streaming ? isTrue : anyOf(isFalse, isNull));
      expect(apiKey, 'fixture-key');
    });
  }
}
