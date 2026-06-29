import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_groq/ai_sdk_groq.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('GroqProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = GroqProvider(apiKey: 'test-key');
      final model = provider('llama3-8b-8192');
      expect(model.provider, 'groq');
      expect(model.modelId, 'llama3-8b-8192');
      expect(model.specificationVersion, 'v3');
    });

    test('default groq constant is a GroqProvider', () {
      expect(groq, isA<GroqProvider>());
    });

    test('accepts custom baseUrl', () {
      final provider = GroqProvider(
        apiKey: 'key',
        baseUrl: 'https://custom.groq.example.com/openai/v1',
      );
      final model = provider('mixtral-8x7b-32768');
      expect(model.modelId, 'mixtral-8x7b-32768');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = GroqProvider(apiKey: 'key');
      final model = provider('llama3-70b-8192');
      expect(model, isA<LanguageModelV3>());
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

      final model = GroqProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'llama3-groq-70b-8192-tool-use-preview',
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('weather in Tokyo'),
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

      final model = GroqProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'llama-3.2-90b-vision-preview',
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

    test('uses max_tokens (not max_completion_tokens)', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        captured = await _captureBody(request);
        _writeOk(request);
      });
      addTearDown(server.close);

      final model = GroqProvider(apiKey: 'key', baseUrl: server.baseUrl)(
        'llama3-8b-8192',
      );
      await model.doGenerate(
        LanguageModelV3CallOptions(
          prompt: _userPrompt('hi'),
          maxOutputTokens: 256,
        ),
      );
      expect(captured['max_tokens'], 256);
      expect(captured.containsKey('max_completion_tokens'), isFalse);
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
