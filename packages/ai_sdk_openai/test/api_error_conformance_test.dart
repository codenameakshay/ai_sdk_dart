import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_sdk_openai/ai_sdk_openai.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// A non-2xx provider response should surface as a typed [AiApiCallError]
/// carrying the provider's message/status/code — not a bare DioException.
void main() {
  group('OpenAI API error surfacing', () {
    HttpServer? server;

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    Future<String> startErrorServer({
      int status = 400,
      Object body = const {
        'error': {
          'message': "Unknown parameter: 'response_format'.",
          'type': 'invalid_request_error',
          'code': 'unknown_parameter',
        },
      },
    }) async {
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server = s;
      unawaited(() async {
        await for (final request in s) {
          await request.drain<void>();
          request.response.statusCode = status;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
          await request.response.close();
        }
      }());
      return 'http://${s.address.host}:${s.port}/v1';
    }

    test('image generation surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final provider = OpenAIProvider(apiKey: 'test', baseUrl: baseUrl);
      await expectLater(
        provider
            .image('gpt-image-1')
            .doGenerate(const ImageModelV3CallOptions(prompt: 'a cat')),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', contains('response_format'))
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'unknown_parameter'),
        ),
      );
    });

    test('embeddings surface the provider message', () async {
      final baseUrl = await startErrorServer(
        status: 401,
        body: {
          'error': {'message': 'invalid api key', 'code': 'invalid_api_key'},
        },
      );
      final provider = OpenAIProvider(apiKey: 'bad', baseUrl: baseUrl);
      await expectLater(
        provider
            .embedding('text-embedding-3-small')
            .doEmbed(const EmbeddingModelV2CallOptions(values: ['hi'])),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'invalid api key')
              .having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test(
      'speech (bytes response type) surfaces the provider message',
      () async {
        final baseUrl = await startErrorServer(
          status: 400,
          body: {
            'error': {
              'message': 'voice not supported',
              'type': 'invalid_request_error',
            },
          },
        );
        final provider = OpenAIProvider(apiKey: 'test', baseUrl: baseUrl);
        await expectLater(
          provider
              .speech('tts-1')
              .doGenerate(const SpeechModelV1CallOptions(text: 'hello')),
          throwsA(
            isA<AiApiCallError>().having(
              (e) => e.message,
              'message',
              contains('voice not supported'),
            ),
          ),
        );
      },
    );

    test('transcription surfaces the provider message', () async {
      final baseUrl = await startErrorServer(
        status: 400,
        body: {
          'error': {
            'message': 'invalid audio',
            'type': 'invalid_request_error',
          },
        },
      );
      final provider = OpenAIProvider(apiKey: 'test', baseUrl: baseUrl);
      await expectLater(
        provider
            .transcription('whisper-1')
            .doGenerate(
              TranscriptionModelV1CallOptions(
                audio: Uint8List.fromList([1, 2, 3]),
                audioMediaType: 'audio/mpeg',
              ),
            ),
        throwsA(
          isA<AiApiCallError>().having(
            (e) => e.message,
            'message',
            contains('invalid audio'),
          ),
        ),
      );
    });
  });
}
