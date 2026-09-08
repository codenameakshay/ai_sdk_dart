import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_dart/ai_sdk_dart.dart';
import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_google/ai_sdk_google.dart';
import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:test/test.dart';

import '../../ai_sdk_provider/test/support/test_server.dart';

void main() {
  group('result envelope provider conformance', () {
    test(
      'openai generateText/streamText expose request/response bodies',
      () async {
        final server = await TestServer.start((request) async {
          if (request.uri.path != '/v1/chat/completions') {
            request.response.statusCode = 404;
            await request.response.close();
            return;
          }

          final bodyText = await utf8.decoder.bind(request).join();
          final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
          final isStream = body['stream'] == true;

          request.response.statusCode = 200;
          if (!isStream) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'id': 'chatcmpl-1',
                'model': 'gpt-4.1-mini',
                'choices': [
                  {
                    'finish_reason': 'stop',
                    'message': {'content': 'hello'},
                  },
                ],
              }),
            );
          } else {
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.write(
              'data: ${jsonEncode({
                'id': 'chatcmpl-2',
                'model': 'gpt-4.1-mini',
                'choices': [
                  {
                    'delta': {'content': 'stream'},
                    'finish_reason': null,
                  },
                ],
              })}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode({
                'id': 'chatcmpl-2',
                'model': 'gpt-4.1-mini',
                'choices': [
                  {'delta': {}, 'finish_reason': 'stop'},
                ],
              })}\n\n',
            );
            request.response.write('data: [DONE]\n\n');
          }
          await request.response.close();
        }, pathSuffix: '/v1');
        addTearDown(server.close);

        final model = OpenAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gpt-4.1-mini');
        final generated = await generateText<String>(
          model: model,
          prompt: 'hi',
        );
        expect(generated.request.body, isA<Map<String, dynamic>>());
        expect(generated.responseInfo.body, isA<Map<String, dynamic>>());

        final streamed = await streamText<String>(model: model, prompt: 'hi');
        await streamed.output;
        expect((await streamed.request).body, isA<Map<String, dynamic>>());
        expect((await streamed.response).body, isA<Map<String, dynamic>>());
      },
    );

    test(
      'anthropic generateText/streamText expose request/response bodies',
      () async {
        final server = await TestServer.start((request) async {
          if (request.uri.path != '/v1/messages') {
            request.response.statusCode = 404;
            await request.response.close();
            return;
          }

          final bodyText = await utf8.decoder.bind(request).join();
          final body = (jsonDecode(bodyText) as Map).cast<String, dynamic>();
          final isStream = body['stream'] == true;

          request.response.statusCode = 200;
          if (!isStream) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'id': 'msg_1',
                'model': 'claude-sonnet-4-5',
                'stop_reason': 'end_turn',
                'content': [
                  {'type': 'text', 'text': 'hello'},
                ],
              }),
            );
          } else {
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.write(
              'data: ${jsonEncode({
                'type': 'message_start',
                'message': {'id': 'msg_2', 'model': 'claude-sonnet-4-5'},
              })}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode({
                'type': 'content_block_start',
                'index': 0,
                'content_block': {'type': 'text'},
              })}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode({
                'type': 'content_block_delta',
                'index': 0,
                'delta': {'type': 'text_delta', 'text': 'stream'},
              })}\n\n',
            );
            request.response.write(
              'data: ${jsonEncode({
                'type': 'message_delta',
                'delta': {'stop_reason': 'end_turn'},
              })}\n\n',
            );
          }
          await request.response.close();
        }, pathSuffix: '/v1');
        addTearDown(server.close);

        final model = AnthropicProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('claude-sonnet-4-5');
        final generated = await generateText<String>(
          model: model,
          prompt: 'hi',
        );
        expect(generated.request.body, isA<Map<String, dynamic>>());
        expect(generated.responseInfo.body, isA<Map<String, dynamic>>());

        final streamed = await streamText<String>(model: model, prompt: 'hi');
        await streamed.output;
        expect((await streamed.request).body, isA<Map<String, dynamic>>());
        expect((await streamed.response).body, isA<Map<String, dynamic>>());
      },
    );

    test(
      'google generateText/streamText expose request/response bodies',
      () async {
        final server = await TestServer.start((request) async {
          final path = request.uri.path;
          if (path.endsWith(':generateContent')) {
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
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
            await request.response.close();
            return;
          }

          if (path.endsWith(':streamGenerateContent')) {
            request.response.statusCode = 200;
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.write(
              'data: ${jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'stream'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
              })}\n\n',
            );
            await request.response.close();
            return;
          }

          request.response.statusCode = 404;
          await request.response.close();
        }, pathSuffix: '/v1');
        addTearDown(server.close);

        final model = GoogleGenerativeAIProvider(
          apiKey: 'test',
          baseUrl: server.baseUrl,
        ).call('gemini-2.0-flash');
        final generated = await generateText<String>(
          model: model,
          prompt: 'hi',
        );
        expect(generated.request.body, isA<Map<String, dynamic>>());
        expect(generated.responseInfo.body, isA<Map<String, dynamic>>());

        final streamed = await streamText<String>(model: model, prompt: 'hi');
        await streamed.output;
        expect((await streamed.request).body, isA<Map<String, dynamic>>());
        expect((await streamed.response).body, isA<Map<String, dynamic>>());
      },
    );
  });
}
