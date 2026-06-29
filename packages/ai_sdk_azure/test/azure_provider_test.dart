import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_azure/ai_sdk_azure.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('AzureOpenAIProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'test-key',
      );
      final model = provider('my-gpt4-deployment');
      expect(model.provider, 'azure');
      expect(model.modelId, 'my-gpt4-deployment');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'test-key',
      );
      final model = provider.embedding('my-ada-deployment');
      expect(model.provider, 'azure');
      expect(model.modelId, 'my-ada-deployment');
      expect(model.specificationVersion, 'v2');
    });

    test('default azureOpenAI constant is an AzureOpenAIProvider', () {
      expect(azureOpenAI, isA<AzureOpenAIProvider>());
    });

    test('uses default api version', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
      );
      expect(provider.apiVersion, '2024-02-15-preview');
    });

    test('accepts custom api version', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
        apiVersion: '2024-05-01-preview',
      );
      expect(provider.apiVersion, '2024-05-01-preview');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
      );
      final model = provider('gpt-4');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('embedding model implements EmbeddingModelV2<String>', () {
      final provider = AzureOpenAIProvider(
        endpoint: 'https://my-resource.openai.azure.com',
        apiKey: 'key',
      );
      final model = provider.embedding('text-embedding-ada-002');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });

  group('OpenAI-compatible capabilities (via shared base)', () {
    test('serializes tools and tool_choice', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.endpoint,
        apiKey: 'key',
      )('gpt-4-deployment');
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('weather'),
          tools: const [
            LanguageModelV3FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceRequired(),
        ),
      );

      final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
      expect((tools.single['function'] as Map)['name'], 'weather');
      expect(captured['tool_choice'], 'required');
    });

    test('serializes multimodal image content part', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.endpoint,
        apiKey: 'key',
      )('gpt-4o-deployment');
      await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _imagePrompt()),
      );

      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final content = (messages.first['content'] as List)
          .cast<Map<String, dynamic>>();
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
    });

    test('sends api-key header and api-version query param', () async {
      String? authHeader;
      String? apiKeyHeader;
      String? query;
      final server = await _TestServer.start((request) async {
        authHeader = request.headers.value('authorization');
        apiKeyHeader = request.headers.value('api-key');
        query = request.uri.query;
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = AzureOpenAIProvider(
        endpoint: server.endpoint,
        apiKey: 'secret-key',
        apiVersion: '2024-05-01-preview',
      )('gpt-4-deployment');
      await model.doGenerate(
        LanguageModelV3CallOptions(prompt: _userPrompt('hi')),
      );

      expect(apiKeyHeader, 'secret-key');
      expect(authHeader, isNull);
      expect(query, contains('api-version=2024-05-01-preview'));
    });

    test(
      'response_format json_schema is serialized from outputSchema',
      () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          captured = await _captureBody(request);
          _writeOk(request);
        });
        addTearDown(server.close);

        final model = AzureOpenAIProvider(
          endpoint: server.endpoint,
          apiKey: 'key',
        )('gpt-4o-deployment');
        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: _userPrompt('weather'),
            outputSchema: const {'type': 'object'},
          ),
        );

        final rf = captured['response_format'] as Map<String, dynamic>;
        expect(rf['type'], 'json_schema');
      },
    );
  });
}

LanguageModelV3Prompt _userPrompt(String text) => LanguageModelV3Prompt(
  messages: [
    LanguageModelV3Message(
      role: LanguageModelV3Role.user,
      content: [LanguageModelV3TextPart(text: text)],
    ),
  ],
);

LanguageModelV3Prompt _imagePrompt() => LanguageModelV3Prompt(
  messages: [
    LanguageModelV3Message(
      role: LanguageModelV3Role.user,
      content: [
        LanguageModelV3TextPart(text: 'describe'),
        LanguageModelV3ImagePart(
          image: DataContentBytes(Uint8List.fromList(utf8.encode('img'))),
          mediaType: 'image/png',
        ),
      ],
    ),
  ],
);

Future<Map<String, dynamic>> _captureBody(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  return (jsonDecode(body) as Map).cast<String, dynamic>();
}

void _writeOk(HttpRequest request) {
  request.response.statusCode = 200;
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {'content': 'ok'},
        },
      ],
    }),
  );
  request.response.close();
}

class _TestServer {
  _TestServer._(this._server);

  final HttpServer _server;

  static Future<_TestServer> start(
    FutureOr<void> Function(HttpRequest request) handler,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(() async {
      await for (final request in server) {
        await handler(request);
      }
    }());
    return _TestServer._(server);
  }

  /// Used as the Azure `endpoint`; the base URL becomes
  /// `<endpoint>/openai/deployments/<deployment>` which all resolves to this
  /// loopback server.
  String get endpoint => 'http://${_server.address.host}:${_server.port}';

  Future<void> close() => _server.close(force: true);
}
