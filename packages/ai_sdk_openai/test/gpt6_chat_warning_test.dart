import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

const _warningDetails =
    'GPT-6 models are not qualified on Chat Completions. '
    'Use openai.responses(modelId) instead.';

void main() {
  group('GPT-6 Chat Completions warning', () {
    test(
      'generateText exposes warning without changing chat request',
      () async {
        final server = await _startServer((request) async {
          final body = await _readJsonBody(request);
          expect(request.uri.path, '/v1/chat/completions');
          expect(body['model'], 'gpt-6-luna');
          _expectUserPrompt(body, 'Say hello');
          expect(body, isNot(contains('warnings')));
          await _writeGenerateResponse(request, 'hello');
        });
        addTearDown(server.close);

        final result = await generateText(
          model: OpenAIProvider(apiKey: 'test', baseUrl: _baseUrl(server))(
            'gpt-6-luna',
          ),
          prompt: 'Say hello',
        );

        _expectCompatibilityWarning(result.warnings);
      },
    );

    test('streamText exposes warning without changing chat request', () async {
      final server = await _startServer((request) async {
        final body = await _readJsonBody(request);
        expect(request.uri.path, '/v1/chat/completions');
        expect(body['model'], 'gpt-6-sol');
        _expectUserPrompt(body, 'Say hello');
        expect(body, isNot(contains('warnings')));
        request.response.statusCode = 200;
        request.response.headers.set('content-type', 'text/event-stream');
        request.response.write(
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'hello'},
              },
            ],
          })}\n\n',
        );
        request.response.write(
          'data: ${jsonEncode({
            'choices': [
              {'delta': {}, 'finish_reason': 'stop'},
            ],
          })}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      addTearDown(server.close);

      final result = await streamText(
        model: OpenAIProvider(
          apiKey: 'test',
          baseUrl: _baseUrl(server),
        ).chat('gpt-6-sol'),
        prompt: 'Say hello',
      );

      await result.text;
      _expectCompatibilityWarning(await result.warnings);
    });

    test('generateObject preserves warning in wrapped response', () async {
      final server = await _startServer((request) async {
        final body = await _readJsonBody(request);
        expect(request.uri.path, '/v1/chat/completions');
        expect(body['model'], 'gpt-6-astra');
        _expectUserPrompt(body, 'Return a name');
        expect(body, isNot(contains('warnings')));
        await _writeGenerateResponse(request, '{"name":"Ada"}');
      });
      addTearDown(server.close);

      final result = await generateObject<Map<String, String>>(
        model: OpenAIProvider(
          apiKey: 'test',
          baseUrl: _baseUrl(server),
        ).call('gpt-6-astra'),
        schema: const Schema<Map<String, String>>(
          jsonSchema: {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
            },
            'required': ['name'],
          },
          fromJson: _decodeName,
        ),
        prompt: 'Return a name',
      );

      expect(result.object, {'name': 'Ada'});
      _expectCompatibilityWarning(result.response.warnings);
    });

    test('Responses and embeddings do not receive the chat warning', () async {
      final paths = <String>[];
      final server = await _startServer((request) async {
        paths.add(request.uri.path);
        if (request.uri.path.endsWith('/responses')) {
          final body = await _readJsonBody(request);
          expect(body['model'], 'gpt-6-luna');
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'resp_1',
              'model': 'gpt-6-luna',
              'status': 'completed',
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {'type': 'output_text', 'text': 'ok'},
                  ],
                },
              ],
            }),
          );
        } else {
          final body = await _readJsonBody(request);
          expect(body['model'], 'text-embedding-3-small');
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {
                  'index': 0,
                  'embedding': [0.1, 0.2],
                },
              ],
              'model': 'text-embedding-3-small',
              'usage': {'prompt_tokens': 1, 'total_tokens': 1},
            }),
          );
        }
        await request.response.close();
      });
      addTearDown(server.close);

      final provider = OpenAIProvider(
        apiKey: 'test',
        baseUrl: _baseUrl(server),
      );
      final responseResult = await provider
          .responses('gpt-6-luna')
          .doGenerate(_prompt('hi'));
      final embeddingResult = await embed(
        model: provider.embedding('text-embedding-3-small'),
        value: 'hi',
      );

      expect(responseResult.warnings, isEmpty);
      expect(embeddingResult.embedding, [0.1, 0.2]);
      expect(paths, ['/v1/responses', '/v1/embeddings']);
    });
  });
}

Map<String, String> _decodeName(Map<String, dynamic> json) => {
  'name': json['name'] as String,
};

void _expectUserPrompt(Map<String, dynamic> body, String prompt) {
  final messages = body['messages'] as List<dynamic>;
  final message = messages.cast<Map<String, dynamic>>().singleWhere(
    (message) => message['role'] == 'user',
  );
  expect(message['role'], 'user');
  expect(message['content'], [
    {'type': 'text', 'text': prompt},
  ]);
}

void _expectCompatibilityWarning(List<LanguageModelV4Warning> warnings) {
  expect(warnings, hasLength(1));
  expect(
    warnings.single,
    isA<LanguageModelV4CompatibilityWarning>()
        .having((warning) => warning.feature, 'feature', 'chat-completions')
        .having((warning) => warning.details, 'details', _warningDetails),
  );
}

LanguageModelV4CallOptions _prompt(String text) => LanguageModelV4CallOptions(
  prompt: LanguageModelV4Prompt(
    messages: [
      LanguageModelV4Message(
        role: LanguageModelV4Role.user,
        content: [LanguageModelV4TextPart(text: text)],
      ),
    ],
  ),
);

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async =>
    jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;

Future<void> _writeGenerateResponse(HttpRequest request, String text) async {
  request.response.statusCode = 200;
  request.response.headers.contentType = ContentType.json;
  request.response.write(
    jsonEncode({
      'id': 'chatcmpl_1',
      'model': 'gpt-6-luna',
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {'content': text},
        },
      ],
    }),
  );
  await request.response.close();
}

Future<HttpServer> _startServer(
  Future<void> Function(HttpRequest) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(() async {
    await for (final request in server) {
      await handler(request);
    }
  }());
  return server;
}

String _baseUrl(HttpServer server) =>
    'http://${server.address.host}:${server.port}/v1';
