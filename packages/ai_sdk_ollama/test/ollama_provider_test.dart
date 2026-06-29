import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_ollama/ai_sdk_ollama.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('OllamaProvider', () {
    test('creates language model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider('llama3');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'llama3');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec/modelId', () {
      final provider = OllamaProvider();
      final model = provider.embedding('nomic-embed-text');
      expect(model.provider, 'ollama');
      expect(model.modelId, 'nomic-embed-text');
      expect(model.specificationVersion, 'v2');
    });

    test('default ollama constant is an OllamaProvider', () {
      expect(ollama, isA<OllamaProvider>());
    });

    test('accepts custom baseUrl', () {
      final provider = OllamaProvider(
        baseUrl: 'http://192.168.1.100:11434/api',
      );
      final model = provider('phi3');
      expect(model.modelId, 'phi3');
    });
  });

  group('LanguageModelV3 interface', () {
    test('language model implements LanguageModelV3', () {
      final provider = OllamaProvider();
      final model = provider('llama3');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('embedding model implements EmbeddingModelV2<String>', () {
      final provider = OllamaProvider();
      final model = provider.embedding('nomic-embed-text');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });

  group('Ollama doGenerate wire format', () {
    test(
      'serializes tools and image content; parses tool calls and real usage',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));
        late Map<String, dynamic> captured;

        final server = await _TestServer.start((request) async {
          expect(request.uri.path, '/api/chat');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {
                'role': 'assistant',
                'content': 'Let me check.',
                'tool_calls': [
                  {
                    'function': {
                      'name': 'weather',
                      'arguments': {'city': 'Paris'},
                    },
                  },
                ],
              },
              'prompt_eval_count': 18,
              'eval_count': 9,
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(
          baseUrl: server.baseUrl,
        ).call('llama3.2-vision');

        final result = await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.user,
                  content: [
                    LanguageModelV3TextPart(text: 'describe this'),
                    LanguageModelV3ImagePart(
                      image: DataContentBytes(
                        Uint8List.fromList(utf8.encode('img')),
                      ),
                      mediaType: 'image/png',
                    ),
                  ],
                ),
              ],
            ),
            tools: const [
              LanguageModelV3FunctionTool(
                name: 'weather',
                description: 'Get the weather',
                inputSchema: {'type': 'object'},
              ),
            ],
          ),
        );

        // Tools serialized into Ollama's OpenAI-style tools field.
        final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
        final fn = tools.single['function'] as Map<String, dynamic>;
        expect(tools.single['type'], 'function');
        expect(fn['name'], 'weather');
        expect(fn['description'], 'Get the weather');
        expect(fn['parameters'], {'type': 'object'});

        // Image content serialized into the message's images field (no prefix).
        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        final userMessage = messages.single;
        expect(userMessage['content'], 'describe this');
        expect((userMessage['images'] as List).single, imageB64);

        // Tool calls parsed; real usage tokens reported.
        expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
        final toolCall = result.content
            .whereType<LanguageModelV3ToolCallPart>()
            .single;
        expect(toolCall.toolName, 'weather');
        expect(toolCall.input, {'city': 'Paris'});
        expect(result.usage?.inputTokens, 18);
        expect(result.usage?.outputTokens, 9);
        expect(result.usage?.totalTokens, 27);
      },
    );

    test(
      'serializes tool-result messages back into the conversation',
      () async {
        late Map<String, dynamic> captured;
        final server = await _TestServer.start((request) async {
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();
          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'done': true,
              'done_reason': 'stop',
              'message': {'role': 'assistant', 'content': 'ok'},
              'prompt_eval_count': 5,
              'eval_count': 2,
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');

        await model.doGenerate(
          LanguageModelV3CallOptions(
            prompt: LanguageModelV3Prompt(
              messages: [
                LanguageModelV3Message(
                  role: LanguageModelV3Role.tool,
                  content: [
                    LanguageModelV3ToolResultPart(
                      toolCallId: 'call_1',
                      toolName: 'weather',
                      output: ToolResultOutputText('sunny'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        final toolMessage = messages.single;
        expect(toolMessage['role'], 'tool');
        expect(toolMessage['tool_name'], 'weather');
        expect(toolMessage['content'], 'sunny');
      },
    );

    test('parses tool calls and usage from the NDJSON stream', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '${jsonEncode({
            'message': {'role': 'assistant', 'content': 'thinking'},
            'done': false,
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'function': {
                    'name': 'weather',
                    'arguments': {'city': 'Paris'},
                  },
                },
              ],
            },
            'done': true,
            'done_reason': 'stop',
            'prompt_eval_count': 6,
            'eval_count': 3,
          })}\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = OllamaProvider(baseUrl: server.baseUrl).call('llama3');

      final streamResult = await model.doStream(
        LanguageModelV3CallOptions(
          prompt: LanguageModelV3Prompt(
            messages: [
              LanguageModelV3Message(
                role: LanguageModelV3Role.user,
                content: [LanguageModelV3TextPart(text: 'weather?')],
              ),
            ],
          ),
        ),
      );

      final parts = await streamResult.stream.toList();
      expect(
        parts.whereType<StreamPartTextDelta>().map((p) => p.delta).join(),
        'thinking',
      );
      final start = parts.whereType<StreamPartToolCallStart>().single;
      expect(start.toolName, 'weather');
      final end = parts.whereType<StreamPartToolCallEnd>().single;
      expect(end.input, {'city': 'Paris'});
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV3FinishReason.toolCalls);
      expect(finish.usage?.inputTokens, 6);
      expect(finish.usage?.outputTokens, 3);
    });
  });
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

  String get baseUrl => 'http://${_server.address.host}:${_server.port}/api';

  Future<void> close() => _server.close(force: true);
}
