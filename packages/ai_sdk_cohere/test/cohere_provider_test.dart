import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_cohere/ai_sdk_cohere.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('CohereProvider', () {
    test('creates language model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider('command-r-plus');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'command-r-plus');
      expect(model.specificationVersion, 'v3');
    });

    test('creates embedding model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider.embedding('embed-english-v3.0');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'embed-english-v3.0');
      expect(model.specificationVersion, 'v2');
    });

    test('creates rerank model with correct provider/spec', () {
      final provider = CohereProvider(apiKey: 'test-key');
      final model = provider.rerank('rerank-english-v3.0');
      expect(model.provider, 'cohere');
      expect(model.modelId, 'rerank-english-v3.0');
      expect(model.specificationVersion, 'v1');
    });

    test('default cohere instance is a CohereProvider', () {
      expect(cohere, isA<CohereProvider>());
    });

    test('custom baseUrl is accepted', () {
      final provider = CohereProvider(
        apiKey: 'key',
        baseUrl: 'https://custom.cohere.example.com/v2',
      );
      // Just verify construction and model creation don't throw.
      final model = provider('command-r');
      expect(model.modelId, 'command-r');
    });
  });

  group('RerankModelV1 interface', () {
    test('implements RerankModelV1', () {
      final provider = CohereProvider(apiKey: 'key');
      final model = provider.rerank('rerank-english-v3.0');
      expect(model, isA<RerankModelV1>());
    });
  });

  group('EmbeddingModelV2 interface', () {
    test('implements EmbeddingModelV2<String>', () {
      final provider = CohereProvider(apiKey: 'key');
      final model = provider.embedding('embed-english-v3.0');
      expect(model, isA<EmbeddingModelV2<String>>());
    });
  });

  group('LanguageModelV3 interface', () {
    test('implements LanguageModelV3', () {
      final provider = CohereProvider(apiKey: 'key');
      final model = provider('command-r-plus');
      expect(model, isA<LanguageModelV3>());
    });
  });

  group('Cohere doGenerate wire format', () {
    test(
      'serializes tools, tool_choice, and image content; parses tool calls',
      () async {
        final imageB64 = base64Encode(utf8.encode('img'));
        late Map<String, dynamic> captured;

        final server = await _TestServer.start((request) async {
          expect(request.uri.path, '/chat');
          final body = await utf8.decoder.bind(request).join();
          captured = (jsonDecode(body) as Map).cast<String, dynamic>();

          request.response.statusCode = 200;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'finish_reason': 'TOOL_CALL',
              'message': {
                'content': [
                  {'type': 'text', 'text': 'Let me check.'},
                ],
                'tool_calls': [
                  {
                    'id': 'call_1',
                    'type': 'function',
                    'function': {
                      'name': 'weather',
                      'arguments': '{"city":"Paris"}',
                    },
                  },
                ],
              },
              'usage': {
                'tokens': {'input_tokens': 12, 'output_tokens': 7},
              },
            }),
          );
          await request.response.close();
        });
        addTearDown(server.close);

        final model = CohereProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('command-r-plus');

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
            toolChoice: const ToolChoiceRequired(),
          ),
        );

        // Tools serialized into the Cohere v2 tools field.
        final tools = (captured['tools'] as List).cast<Map<String, dynamic>>();
        final fn = tools.single['function'] as Map<String, dynamic>;
        expect(tools.single['type'], 'function');
        expect(fn['name'], 'weather');
        expect(fn['description'], 'Get the weather');
        expect(fn['parameters'], {'type': 'object'});
        expect(captured['tool_choice'], 'REQUIRED');

        // Image content serialized (not dropped) into a content array.
        final messages = (captured['messages'] as List)
            .cast<Map<String, dynamic>>();
        final userContent = (messages.first['content'] as List)
            .cast<Map<String, dynamic>>();
        expect(userContent[0]['type'], 'text');
        expect(userContent[1]['type'], 'image_url');
        expect(
          (userContent[1]['image_url'] as Map)['url'],
          'data:image/png;base64,$imageB64',
        );

        // Tool calls parsed out of the response.
        expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
        final toolCall = result.content
            .whereType<LanguageModelV3ToolCallPart>()
            .single;
        expect(toolCall.toolName, 'weather');
        expect(toolCall.input, {'city': 'Paris'});
        expect(result.usage?.inputTokens, 12);
        expect(result.usage?.outputTokens, 7);
      },
    );

    test('maps tool choice none and serializes tool-result messages', () async {
      late Map<String, dynamic> captured;
      final server = await _TestServer.start((request) async {
        final body = await utf8.decoder.bind(request).join();
        captured = (jsonDecode(body) as Map).cast<String, dynamic>();
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'finish_reason': 'COMPLETE',
            'message': {
              'content': [
                {'type': 'text', 'text': 'ok'},
              ],
            },
            'usage': {
              'tokens': {'input_tokens': 1, 'output_tokens': 1},
            },
          }),
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

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
          tools: const [
            LanguageModelV3FunctionTool(
              name: 'weather',
              inputSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoiceNone(),
        ),
      );

      expect(captured['tool_choice'], 'NONE');
      final messages = (captured['messages'] as List)
          .cast<Map<String, dynamic>>();
      final toolMessage = messages.single;
      expect(toolMessage['role'], 'tool');
      expect(toolMessage['tool_call_id'], 'call_1');
      expect(toolMessage['content'], 'sunny');
    });

    test('parses tool calls from the NDJSON stream', () async {
      final server = await _TestServer.start((request) async {
        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-start',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {'name': 'weather', 'arguments': ''},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'tool-call-delta',
            'index': 0,
            'delta': {
              'message': {
                'tool_calls': {
                  'function': {'arguments': '{"city":"Paris"}'},
                },
              },
            },
          })}\n',
        );
        request.response.write(
          '${jsonEncode({'type': 'tool-call-end', 'index': 0})}\n',
        );
        request.response.write(
          '${jsonEncode({
            'type': 'message-end',
            'delta': {
              'finish_reason': 'TOOL_CALL',
              'usage': {
                'tokens': {'input_tokens': 3, 'output_tokens': 4},
              },
            },
          })}\n',
        );
        await request.response.close();
      });
      addTearDown(server.close);

      final model = CohereProvider(
        apiKey: 'test',
        baseUrl: server.baseUrl,
      ).call('command-r-plus');

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
      final start = parts.whereType<StreamPartToolCallStart>().single;
      expect(start.toolName, 'weather');
      expect(start.toolCallId, 'call_1');
      final end = parts.whereType<StreamPartToolCallEnd>().single;
      expect(end.input, {'city': 'Paris'});
      final finish = parts.whereType<StreamPartFinish>().single;
      expect(finish.finishReason, LanguageModelV3FinishReason.toolCalls);
      expect(finish.usage?.inputTokens, 3);
      expect(finish.usage?.outputTokens, 4);
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

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  Future<void> close() => _server.close(force: true);
}
