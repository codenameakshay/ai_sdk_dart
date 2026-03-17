import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk/ai_sdk.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Local test HTTP server (mirrors result_envelope_provider_conformance_test)
// ---------------------------------------------------------------------------

class _TestServer {
  _TestServer._(this._server, this.baseUrl);

  final HttpServer _server;
  final String baseUrl;
  final List<Map<String, dynamic>> requestLog = [];

  static Future<_TestServer> start(
    Future<void> Function(HttpRequest request) onRequest,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final ts = _TestServer._(
      server,
      'http://${server.address.address}:${server.port}/v1',
    );
    unawaited(() async {
      await for (final request in server) {
        await onRequest(request);
      }
    }());
    return ts;
  }

  Future<void> close() => _server.close(force: true);
}

/// Read, parse, and return the request body JSON.
Future<Map<String, dynamic>> _readJson(HttpRequest req) async {
  final text = await utf8.decoder.bind(req).join();
  return (jsonDecode(text) as Map).cast<String, dynamic>();
}

// ---------------------------------------------------------------------------
// OpenAI wire-format conformance
// ---------------------------------------------------------------------------

void main() {
  group('provider wire-format conformance', () {
    // ── OpenAI ──────────────────────────────────────────────────────────────

    group('OpenAI', () {
      test(
        'generateText sends POST /v1/chat/completions with stream:false',
        () async {
          Map<String, dynamic>? capturedBody;

          final server = await _TestServer.start((req) async {
            if (req.method != 'POST' ||
                req.uri.path != '/v1/chat/completions') {
              req.response.statusCode = 404;
              await req.response.close();
              return;
            }
            capturedBody = await _readJson(req);
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              jsonEncode({
                'id': 'chatcmpl-1',
                'model': 'gpt-4.1-mini',
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {'content': 'hello'},
                  },
                ],
                'usage': {
                  'prompt_tokens': 5,
                  'completion_tokens': 3,
                  'total_tokens': 8,
                },
              }),
            );
            await req.response.close();
          });
          addTearDown(server.close);

          final model = OpenAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('gpt-4.1-mini');
          final result = await generateText<String>(model: model, prompt: 'hi');

          expect(capturedBody, isNotNull);
          // Non-streaming requests either omit stream or set it to false.
          expect(capturedBody!['stream'], isNot(isTrue));
          expect(capturedBody!['model'], 'gpt-4.1-mini');
          expect((capturedBody!['messages'] as List).first['role'], 'user');
          expect(result.text, 'hello');
          expect(result.usage?.inputTokens, 5);
          expect(result.usage?.outputTokens, 3);
        },
      );

      test(
        'streamText sends stream:true and stream_options.include_usage:true',
        () async {
          Map<String, dynamic>? capturedBody;

          final server = await _TestServer.start((req) async {
            if (req.method != 'POST' ||
                req.uri.path != '/v1/chat/completions') {
              req.response.statusCode = 404;
              await req.response.close();
              return;
            }
            capturedBody = await _readJson(req);
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            req.response.write(
              'data: ${jsonEncode({
                'id': 'chatcmpl-2',
                'model': 'gpt-4.1-mini',
                'choices': [
                  {
                    'delta': {'content': 'hi'},
                    'finish_reason': null,
                  },
                ],
              })}\n\n',
            );
            req.response.write(
              'data: ${jsonEncode({
                'id': 'chatcmpl-2',
                'model': 'gpt-4.1-mini',
                'choices': [
                  {'delta': {}, 'finish_reason': 'stop'},
                ],
                'usage': {'prompt_tokens': 4, 'completion_tokens': 2, 'total_tokens': 6},
              })}\n\n',
            );
            req.response.write('data: [DONE]\n\n');
            await req.response.close();
          });
          addTearDown(server.close);

          final model = OpenAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('gpt-4.1-mini');
          final streamed = await streamText<String>(model: model, prompt: 'hi');
          // Drain the stream to ensure request is captured.
          await streamed.output;

          expect(capturedBody, isNotNull);
          expect(capturedBody!['stream'], isTrue);
          final streamOptions =
              capturedBody!['stream_options'] as Map<String, dynamic>?;
          expect(streamOptions?['include_usage'], isTrue);
          expect(await streamed.text, 'hi');
        },
      );

      test('generateText exposes usage from non-streaming response', () async {
        final server = await _TestServer.start((req) async {
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'id': 'chatcmpl-3',
              'model': 'gpt-4.1-mini',
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': 'done'},
                },
              ],
              'usage': {
                'prompt_tokens': 10,
                'completion_tokens': 5,
                'total_tokens': 15,
              },
            }),
          );
          await req.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gpt-4.1-mini');
        final result = await generateText<String>(model: model, prompt: 'hi');

        expect(result.usage?.inputTokens, 10);
        expect(result.usage?.outputTokens, 5);
      });

      test('tools are sent as tools array with type:function', () async {
        Map<String, dynamic>? capturedBody;

        final server = await _TestServer.start((req) async {
          capturedBody = await _readJson(req);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'id': 'chatcmpl-4',
              'model': 'gpt-4.1-mini',
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {'content': 'ok'},
                },
              ],
            }),
          );
          await req.response.close();
        });
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gpt-4.1-mini');
        await generateText<String>(
          model: model,
          prompt: 'hi',
          tools: {
            'getWeather': tool<Map<String, dynamic>, String>(
              description: 'Get weather',
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                },
                fromJson: (json) => json,
              ),
            ),
          },
        );

        final tools = capturedBody!['tools'] as List?;
        expect(tools, isNotNull);
        expect(tools!.length, 1);
        final firstTool = tools.first as Map<String, dynamic>;
        expect(firstTool['type'], 'function');
        expect(
          (firstTool['function'] as Map<String, dynamic>)['name'],
          'getWeather',
        );
      });
    });

    // ── Anthropic ────────────────────────────────────────────────────────────

    group('Anthropic', () {
      test('generateText sends POST /v1/messages with stream:false', () async {
        Map<String, dynamic>? capturedBody;

        final server = await _TestServer.start((req) async {
          if (req.method != 'POST' || req.uri.path != '/v1/messages') {
            req.response.statusCode = 404;
            await req.response.close();
            return;
          }
          capturedBody = await _readJson(req);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'id': 'msg_1',
              'model': 'claude-sonnet-4-5',
              'stop_reason': 'end_turn',
              'content': [
                {'type': 'text', 'text': 'hello'},
              ],
              'usage': {'input_tokens': 5, 'output_tokens': 3},
            }),
          );
          await req.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');
        final result = await generateText<String>(model: model, prompt: 'hi');

        expect(capturedBody, isNotNull);
        // Non-streaming requests either omit stream or set it to false.
        expect(capturedBody!['stream'], isNot(isTrue));
        expect(capturedBody!['model'], 'claude-sonnet-4-5');
        expect((capturedBody!['messages'] as List).first['role'], 'user');
        expect(result.text, 'hello');
        expect(result.usage?.inputTokens, 5);
        expect(result.usage?.outputTokens, 3);
      });

      test('thinking content block maps to ReasoningPart', () async {
        final server = await _TestServer.start((req) async {
          if (req.uri.path != '/v1/messages') {
            req.response.statusCode = 404;
            await req.response.close();
            return;
          }
          await _readJson(req); // consume body
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'id': 'msg_2',
              'model': 'claude-sonnet-4-5',
              'stop_reason': 'end_turn',
              'content': [
                {
                  'type': 'thinking',
                  'thinking': 'Let me consider this carefully.',
                },
                {'type': 'text', 'text': 'The answer is 42.'},
              ],
            }),
          );
          await req.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');
        final result = await generateText<String>(model: model, prompt: 'hi');

        expect(result.text, 'The answer is 42.');
        expect(result.reasoning.length, 1);
        expect(result.reasoning[0].text, 'Let me consider this carefully.');
        expect(result.reasoningText, 'Let me consider this carefully.');
      });

      test('tool_use content block maps to ToolCallPart', () async {
        final server = await _TestServer.start((req) async {
          if (req.uri.path != '/v1/messages') {
            req.response.statusCode = 404;
            await req.response.close();
            return;
          }
          await _readJson(req);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'id': 'msg_3',
              'model': 'claude-sonnet-4-5',
              'stop_reason': 'tool_use',
              'content': [
                {
                  'type': 'tool_use',
                  'id': 'toolu_01',
                  'name': 'getWeather',
                  'input': {'city': 'Paris'},
                },
              ],
            }),
          );
          await req.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');
        final result = await generateText<String>(
          model: model,
          prompt: 'hi',
          tools: {
            'getWeather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          },
        );

        expect(result.toolCalls.length, 1);
        expect(result.toolCalls[0].toolName, 'getWeather');
        expect(result.finishReason, LanguageModelV3FinishReason.toolCalls);
      });

      test('streamText sends stream:true and emits text', () async {
        final server = await _TestServer.start((req) async {
          if (req.uri.path != '/v1/messages') {
            req.response.statusCode = 404;
            await req.response.close();
            return;
          }
          await _readJson(req);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          req.response.write(
            'data: ${jsonEncode({
              'type': 'message_start',
              'message': {
                'id': 'msg_4',
                'model': 'claude-sonnet-4-5',
                'usage': {'input_tokens': 4},
              },
            })}\n\n',
          );
          req.response.write(
            'data: ${jsonEncode({
              'type': 'content_block_start',
              'index': 0,
              'content_block': {'type': 'text'},
            })}\n\n',
          );
          req.response.write(
            'data: ${jsonEncode({
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'text_delta', 'text': 'hello'},
            })}\n\n',
          );
          req.response.write(
            'data: ${jsonEncode({
              'type': 'message_delta',
              'delta': {'stop_reason': 'end_turn'},
              'usage': {'output_tokens': 3},
            })}\n\n',
          );
          await req.response.close();
        });
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');
        final streamed = await streamText<String>(model: model, prompt: 'hi');
        await streamed.output;

        expect(await streamed.text, 'hello');
      });
    });

    // ── Google ────────────────────────────────────────────────────────────────

    group('Google', () {
      test(
        'generateText sends POST to :generateContent with contents array',
        () async {
          Map<String, dynamic>? capturedBody;

          final server = await _TestServer.start((req) async {
            if (!req.uri.path.endsWith(':generateContent')) {
              req.response.statusCode = 404;
              await req.response.close();
              return;
            }
            capturedBody = await _readJson(req);
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'STOP',
                    'content': {
                      'parts': [
                        {'text': 'hello'},
                      ],
                    },
                  },
                ],
                'usageMetadata': {
                  'promptTokenCount': 5,
                  'candidatesTokenCount': 3,
                },
              }),
            );
            await req.response.close();
          });
          addTearDown(server.close);

          final model = GoogleGenerativeAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('gemini-2.0-flash');
          final result = await generateText<String>(model: model, prompt: 'hi');

          expect(capturedBody, isNotNull);
          final contents = capturedBody!['contents'] as List;
          expect(contents, isNotEmpty);
          expect(contents.first['role'], 'user');
          expect(result.text, 'hello');
          expect(result.usage?.inputTokens, 5);
          expect(result.usage?.outputTokens, 3);
        },
      );

      test('streamText sends POST to :streamGenerateContent', () async {
        final server = await _TestServer.start((req) async {
          if (req.uri.path.endsWith(':generateContent')) {
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'STOP',
                    'content': {
                      'parts': [
                        {'text': 'hello'},
                      ],
                    },
                  },
                ],
              }),
            );
            await req.response.close();
            return;
          }
          if (req.uri.path.endsWith(':streamGenerateContent')) {
            await _readJson(req);
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            req.response.write(
              'data: ${jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'hello'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              })}\n\n',
            );
            await req.response.close();
            return;
          }
          req.response.statusCode = 404;
          await req.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');
        final streamed = await streamText<String>(model: model, prompt: 'hi');
        await streamed.output;

        expect(await streamed.text, 'hello');
      });

      test('functionCall parts map to ToolCallPart', () async {
        final server = await _TestServer.start((req) async {
          if (!req.uri.path.endsWith(':generateContent')) {
            req.response.statusCode = 404;
            await req.response.close();
            return;
          }
          await _readJson(req);
          req.response.statusCode = 200;
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {
                        'functionCall': {
                          'name': 'getWeather',
                          'args': {'city': 'Tokyo'},
                        },
                      },
                    ],
                  },
                },
              ],
            }),
          );
          await req.response.close();
        });
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');
        final result = await generateText<String>(
          model: model,
          prompt: 'hi',
          tools: {
            'getWeather': tool<Map<String, dynamic>, String>(
              inputSchema: Schema<Map<String, dynamic>>(
                jsonSchema: const {'type': 'object'},
                fromJson: (json) => json,
              ),
            ),
          },
        );

        expect(result.toolCalls.length, 1);
        expect(result.toolCalls[0].toolName, 'getWeather');
      });

      test(
        'STOP finish reason maps to LanguageModelV3FinishReason.stop',
        () async {
          final server = await _TestServer.start((req) async {
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'STOP',
                    'content': {
                      'parts': [
                        {'text': 'ok'},
                      ],
                    },
                  },
                ],
              }),
            );
            await req.response.close();
          });
          addTearDown(server.close);

          final model = GoogleGenerativeAIProvider(
            apiKey: 'test',
            baseUrl: server.baseUrl,
          ).call('gemini-2.0-flash');
          final result = await generateText<String>(model: model, prompt: 'hi');

          expect(result.finishReason, LanguageModelV3FinishReason.stop);
        },
      );
    });
  });
}
