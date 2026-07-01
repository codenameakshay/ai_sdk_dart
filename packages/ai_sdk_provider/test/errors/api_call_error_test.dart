import 'dart:convert';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:test/test.dart';

void main() {
  group('AiApiCallError', () {
    test('is part of the sealed AiSdkError hierarchy', () {
      const err = AiApiCallError('boom');
      expect(err, isA<AiSdkError>());
      expect(AiApiCallError.isInstance(err), isTrue);
    });

    test(
      'carries optional HTTP fields with backward-compatible message ctor',
      () {
        const err = AiApiCallError(
          'rate limited',
          statusCode: 429,
          url: 'https://api.example.com/v1/chat',
          code: 'rate_limit_exceeded',
          type: 'requests',
          isRetryable: true,
        );
        expect(err.message, 'rate limited');
        expect(err.statusCode, 429);
        expect(err.url, 'https://api.example.com/v1/chat');
        expect(err.code, 'rate_limit_exceeded');
        expect(err.type, 'requests');
        expect(err.isRetryable, isTrue);
      },
    );

    group('fromResponse', () {
      test('parses OpenAI / openai-compatible {error:{message,type,code}}', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 400,
          url: 'https://api.openai.com/v1/images/generations',
          provider: 'openai',
          body: {
            'error': {
              'message': "Unknown parameter: 'response_format'.",
              'type': 'invalid_request_error',
              'param': 'response_format',
              'code': 'unknown_parameter',
            },
          },
        );
        expect(err.message, "Unknown parameter: 'response_format'.");
        expect(err.statusCode, 400);
        expect(err.type, 'invalid_request_error');
        expect(err.code, 'unknown_parameter');
        expect(err.url, 'https://api.openai.com/v1/images/generations');
      });

      test('parses Anthropic {type:"error",error:{type,message}}', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 401,
          provider: 'anthropic',
          body: {
            'type': 'error',
            'error': {
              'type': 'authentication_error',
              'message': 'invalid x-api-key',
            },
          },
        );
        expect(err.message, 'invalid x-api-key');
        expect(err.statusCode, 401);
        expect(err.type, 'authentication_error');
      });

      test('parses Google {error:{code,message,status}}', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 400,
          provider: 'google',
          body: {
            'error': {
              'code': 400,
              'message': 'API key not valid. Please pass a valid API key.',
              'status': 'INVALID_ARGUMENT',
            },
          },
        );
        expect(err.message, 'API key not valid. Please pass a valid API key.');
        // The human-readable status string is preserved.
        expect(err.type, 'INVALID_ARGUMENT');
      });

      test('parses Cohere top-level {message}', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 400,
          provider: 'cohere',
          body: {'message': 'invalid request: model not found'},
        );
        expect(err.message, 'invalid request: model not found');
        expect(err.statusCode, 400);
      });

      test('parses Ollama {error:"..."} string shape', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 404,
          provider: 'ollama',
          body: {'error': 'model "llama99" not found, try pulling it first'},
        );
        expect(err.message, 'model "llama99" not found, try pulling it first');
        expect(err.statusCode, 404);
      });

      test('decodes a List<int> (bytes) body — the speech path', () {
        final bytes = utf8.encode(
          jsonEncode({
            'error': {'message': 'voice not supported', 'type': 'invalid'},
          }),
        );
        final err = AiApiCallError.fromResponse(
          statusCode: 400,
          provider: 'openai',
          body: bytes,
        );
        expect(err.message, 'voice not supported');
        expect(err.type, 'invalid');
      });

      test('parses a JSON String body', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 429,
          provider: 'groq',
          body: '{"error":{"message":"rate limit reached","code":"slow_down"}}',
        );
        expect(err.message, 'rate limit reached');
        expect(err.code, 'slow_down');
      });

      test('uses a non-JSON String body as the message and keeps raw body', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 502,
          provider: 'openai',
          body: 'Bad Gateway',
        );
        expect(err.message, contains('Bad Gateway'));
        expect(err.responseBody, 'Bad Gateway');
      });

      test('falls back to a synthetic message when body is null', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 500,
          provider: 'openai',
        );
        expect(err.message, contains('openai'));
        expect(err.message, contains('500'));
      });

      test('retains the raw response body for debugging', () {
        final err = AiApiCallError.fromResponse(
          statusCode: 400,
          provider: 'openai',
          body: {
            'error': {'message': 'nope'},
          },
        );
        expect(err.responseBody, contains('nope'));
      });

      test('marks 408/409/429/5xx retryable and 4xx (else) not', () {
        AiApiCallError at(int s) =>
            AiApiCallError.fromResponse(statusCode: s, provider: 'p');
        expect(at(408).isRetryable, isTrue);
        expect(at(409).isRetryable, isTrue);
        expect(at(429).isRetryable, isTrue);
        expect(at(500).isRetryable, isTrue);
        expect(at(503).isRetryable, isTrue);
        expect(at(400).isRetryable, isFalse);
        expect(at(404).isRetryable, isFalse);
      });
    });
  });
}
