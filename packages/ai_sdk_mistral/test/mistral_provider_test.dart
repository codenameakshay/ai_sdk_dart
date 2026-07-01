import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_mistral/ai_sdk_mistral.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('MistralProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = MistralProvider(apiKey: 'test-key');
      final model = provider('mistral-large-latest');
      expect(model.provider, 'mistral');
      expect(model.modelId, 'mistral-large-latest');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = MistralProvider(apiKey: 'test-key');
      final model = provider.embedding('mistral-embed');
      expect(model.provider, 'mistral');
      expect(model.modelId, 'mistral-embed');
      expect(model.specificationVersion, 'v2');
    });

    test('default mistral constant is a MistralProvider', () {
      expect(mistral, isA<MistralProvider>());
    });

    test('accepts custom baseUrl', () {
      final provider = MistralProvider(
        apiKey: 'key',
        baseUrl: 'https://custom.mistral.example.com/v1',
      );
      final model = provider('mistral-small');
      expect(model.modelId, 'mistral-small');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = MistralProvider(apiKey: 'key');
      final model = provider('mistral-medium');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('embedding model implements EmbeddingModelV2<String>', () {
      final provider = MistralProvider(apiKey: 'key');
      final model = provider.embedding('mistral-embed');
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

      final model = MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'mistral-large-latest',
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('weather'),
          tools: const [
            LanguageModelV3FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceAuto(),
        ),
      );

      final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
      expect((tools.single['function'] as Map)['name'], 'weather');
      expect(captured['tool_choice'], 'auto');
    });

    test('serializes multimodal image content part', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'pixtral-large-latest',
      );
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

    test('uses random_seed and max_tokens quirks', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = MistralProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'mistral-small',
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          seed: 99,
          maxOutputTokens: 200,
        ),
      );
      expect(captured['random_seed'], 99);
      expect(captured.containsKey('seed'), isFalse);
      expect(captured['max_tokens'], 200);
    });
  });

  group('Mistral embedding doEmbed wire format', () {
    test(
      'posts to /embeddings with bearer auth, parses embeddings in order',
      () async {
        late Map<String, dynamic> captured;
        String? path;
        String? authHeader;
        final server = await _TestServer.start((request) async {
          path = request.uri.path;
          authHeader = request.headers.value('authorization');
          captured = await _captureBody(request);

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'index': 0,
                  'embedding': [0.1, 0.2],
                },
                {
                  'index': 1,
                  'embedding': [0.3, 0.4],
                },
              ],
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = MistralProvider(
          apiKey: 'secret-key',
          baseUrl: server.baseUrl,
        ).embedding('mistral-embed');

        final result = await model.doEmbed(
          const EmbeddingModelV2CallOptions<String>(values: ['a', 'b']),
        );

        expect(path, '/v1/embeddings');
        expect(authHeader, 'Bearer secret-key');
        expect(captured['model'], 'mistral-embed');
        expect(captured['input'], ['a', 'b']);
        expect(result.embeddings, hasLength(2));
        expect(result.embeddings[0].value, 'a');
        expect(result.embeddings[0].embedding, [0.1, 0.2]);
        expect(result.embeddings[1].value, 'b');
        expect(result.embeddings[1].embedding, [0.3, 0.4]);
      },
    );

    test('tolerates a response with no data list', () async {
      final server = await _TestServer.start((request) async {
        await _captureBody(request);
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'object': 'list'}));
        await request.response.close();
      });
      addTearDown(server.close);

      final model = MistralProvider(
        apiKey: 'key',
        baseUrl: server.baseUrl,
      ).embedding('mistral-embed');

      final result = await model.doEmbed(
        const EmbeddingModelV2CallOptions<String>(values: ['only']),
      );
      expect(result.embeddings, isEmpty);
    });
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

  String get baseUrl => 'http://${_server.address.host}:${_server.port}/v1';

  Future<void> close() => _server.close(force: true);
}
