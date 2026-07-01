import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_anthropic/ai_sdk_anthropic.dart';
import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

/// A non-2xx Anthropic response should surface as a typed [AiApiCallError]
/// carrying the parsed `error.message` — for both the non-streaming and
/// streaming paths.
void main() {
  group('Anthropic API error surfacing', () {
    HttpServer? server;

    tearDown(() async {
      await server?.close(force: true);
      server = null;
    });

    Future<String> startErrorServer({
      int status = 401,
      Object body = const {
        'type': 'error',
        'error': {
          'type': 'authentication_error',
          'message': 'invalid x-api-key',
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
      return 'http://${s.address.host}:${s.port}';
    }

    LanguageModelV3CallOptions opts() => LanguageModelV3CallOptions(
      prompt: LanguageModelV3Prompt(
        messages: [
          LanguageModelV3Message(
            role: LanguageModelV3Role.user,
            content: [LanguageModelV3TextPart(text: 'hi')],
          ),
        ],
      ),
    );

    test('doGenerate surfaces the provider message', () async {
      final baseUrl = await startErrorServer();
      final model = AnthropicProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).call('claude-3');
      await expectLater(
        model.doGenerate(opts()),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'invalid x-api-key')
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.type, 'type', 'authentication_error'),
        ),
      );
    });

    test('doStream surfaces a connection-time provider error', () async {
      final baseUrl = await startErrorServer(
        status: 400,
        body: {
          'type': 'error',
          'error': {'type': 'invalid_request_error', 'message': 'bad model'},
        },
      );
      final model = AnthropicProvider(
        apiKey: 'bad',
        baseUrl: baseUrl,
      ).call('claude-3');
      await expectLater(
        model.doStream(opts()),
        throwsA(
          isA<AiApiCallError>()
              .having((e) => e.message, 'message', 'bad model')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test(
      'doGenerate falls back to the Dio message when there is no response body',
      () async {
        // A connection abruptly closed before any HTTP response yields a
        // DioException with no `response` — so `_apiCallError` has no body and
        // falls back to `error.message` for the AiApiCallError body.
        final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server = s;
        unawaited(() async {
          await for (final request in s) {
            // Tear down the socket without writing any HTTP response at all.
            final socket = await request.response.detachSocket(
              writeHeaders: false,
            );
            socket.destroy();
          }
        }());
        final baseUrl = 'http://${s.address.host}:${s.port}';

        final model = AnthropicProvider(
          apiKey: 'bad',
          baseUrl: baseUrl,
        ).call('claude-3');

        await expectLater(
          model.doGenerate(opts()),
          throwsA(
            isA<AiApiCallError>()
                // No response body → message comes from the Dio error itself,
                // and is therefore non-empty.
                .having((e) => e.message, 'message', isNotEmpty)
                // No HTTP response was ever received.
                .having((e) => e.statusCode, 'statusCode', isNull),
          ),
        );
      },
    );
  });
}
