import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  group('sseDataLines', () {
    test('yields only non-empty data payloads', () async {
      final bytes = Stream<Uint8List>.fromIterable([
        Uint8List.fromList(utf8.encode('event: ping\ndata: {"a":1}\n')),
        Uint8List.fromList(utf8.encode('data:\n\ndata: [DONE]\n')),
      ]);
      expect(await sseDataLines(bytes).toList(), ['{"a":1}', '[DONE]']);
    });
  });

  group('json helpers', () {
    test('intOrNull coerces int, num, and numeric strings', () {
      expect(intOrNull(3), 3);
      expect(intOrNull(3.9), 3);
      expect(intOrNull('12'), 12);
      expect(intOrNull('x'), isNull);
      expect(intOrNull(null), isNull);
    });

    test('safeParseJson returns the decoded value or the raw text', () {
      expect(safeParseJson('{"k":1}'), {'k': 1});
      expect(safeParseJson('not json'), 'not json');
    });

    test('prefixedId uses the prefix and stays unique', () {
      final a = prefixedId('tool');
      final b = prefixedId('tool');
      expect(a, startsWith('tool-'));
      expect(a, isNot(b));
    });
  });

  group('dataContentToBase64', () {
    test('encodes bytes, passes base64 through, and rejects urls', () {
      expect(
        dataContentToBase64(DataContentBytes(Uint8List.fromList([1, 2]))),
        base64Encode([1, 2]),
      );
      expect(dataContentToBase64(const DataContentBase64('AQI=')), 'AQI=');
      expect(
        dataContentToBase64(DataContentUrl(Uri.parse('https://x/y.png'))),
        isNull,
      );
    });
  });

  group('createProviderDio', () {
    test('trims a trailing slash and applies headers', () {
      final dio = createProviderDio(
        baseUrl: 'https://api.example.com/v1/',
        headers: {'x-a': 'b'},
      );
      expect(dio.options.baseUrl, 'https://api.example.com/v1');
      expect(dio.options.headers['x-a'], 'b');
      expect(dio.options.responseType, ResponseType.json);
    });
  });

  group('apiErrorFromDioException', () {
    final requestOptions = RequestOptions(path: 'https://api.example.com/x');

    test('maps cancellation to AiOperationCancelledError', () async {
      final error = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.cancel,
      );
      expect(
        await apiErrorFromDioException(error, provider: 'p'),
        isA<AiOperationCancelledError>(),
      );
    });

    test('carries status, parsed message, and flattened headers', () async {
      final error = DioException(
        requestOptions: requestOptions,
        response: Response<Object?>(
          requestOptions: requestOptions,
          statusCode: 429,
          data: {
            'error': {'message': 'slow down', 'type': 'rate_limit'},
          },
          headers: Headers.fromMap({
            'retry-after': ['7'],
            'x-multi': ['a', 'b'],
          }),
        ),
      );
      final mapped =
          await apiErrorFromDioException(error, provider: 'p')
              as AiApiCallError;
      expect(mapped.statusCode, 429);
      expect(mapped.message, 'slow down');
      expect(mapped.type, 'rate_limit');
      expect(mapped.responseHeaders, {'retry-after': '7', 'x-multi': 'a, b'});
      expect(mapped.url, 'https://api.example.com/x');
    });

    test('drains a streamed error body before parsing', () async {
      final body = utf8.encode('{"error":{"message":"streamed"}}');
      final error = DioException(
        requestOptions: requestOptions,
        response: Response<ResponseBody>(
          requestOptions: requestOptions,
          statusCode: 500,
          data: ResponseBody(
            Stream<Uint8List>.value(Uint8List.fromList(body)),
            500,
          ),
        ),
      );
      final mapped =
          await apiErrorFromDioException(error, provider: 'p')
              as AiApiCallError;
      expect(mapped.message, 'streamed');
      expect(mapped.responseHeaders, isNull);
    });

    test('falls back to the Dio message without a response', () async {
      final error = DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionError,
        message: 'refused',
      );
      final mapped =
          await apiErrorFromDioException(error, provider: 'p')
              as AiApiCallError;
      expect(mapped.statusCode, isNull);
      expect(mapped.message, contains('refused'));
    });
  });
}
