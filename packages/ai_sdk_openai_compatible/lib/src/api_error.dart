import 'package:ai_sdk_provider/ai_sdk_provider.dart';
import 'package:dio/dio.dart';

/// Maps a [DioException] from a non-2xx provider response to a typed
/// [AiApiCallError] carrying the provider's parsed message, status code, and
/// error `type`/`code`.
///
/// Handles JSON object bodies, raw byte bodies (`ResponseType.bytes`, e.g. the
/// speech endpoint), and streamed bodies (`ResponseType.stream`, e.g. chat
/// streaming) — the streamed body is drained before parsing. Non-response
/// failures (timeouts, connection errors) are wrapped with the Dio message so
/// the caller still receives an [AiApiCallError] rather than a bare
/// `DioException`.
Future<AiApiCallError> apiErrorFromDioException(
  DioException error, {
  required String provider,
}) async {
  final response = error.response;
  final body = await _materializeBody(response?.data) ?? error.message;
  return AiApiCallError.fromResponse(
    statusCode: response?.statusCode,
    url: error.requestOptions.uri.toString(),
    body: body,
    responseHeaders: _flattenHeaders(response?.headers),
    provider: provider,
    cause: error,
  );
}

Future<Object?> _materializeBody(Object? data) async {
  if (data == null) return null;
  if (data is ResponseBody) {
    // Streamed error body (ResponseType.stream): drain it to bytes.
    final bytes = <int>[];
    await for (final chunk in data.stream) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
  return data;
}

Map<String, String>? _flattenHeaders(Headers? headers) {
  if (headers == null) return null;
  final map = <String, String>{};
  headers.forEach((name, values) {
    map[name] = values.join(', ');
  });
  return map.isEmpty ? null : map;
}
