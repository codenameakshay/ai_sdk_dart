import 'dart:io';
import 'dart:typed_data';

/// Fetches [uri] without redirects. Fails with an [HttpException] past
/// [maxBytes], and with a TimeoutException when the whole fetch takes longer
/// than [timeout].
Future<Uint8List> fetchImageBytes(
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await _fetch(client, uri, maxBytes).timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _fetch(HttpClient client, Uri uri, int maxBytes) async {
  final request = await client.getUrl(uri);
  request.followRedirects = false;
  final response = await request.close();
  if (response.statusCode >= HttpStatus.movedPermanently &&
      response.statusCode < HttpStatus.badRequest) {
    await response.drain<void>();
    throw HttpException('Image redirects are not allowed', uri: uri);
  }
  if (response.statusCode < HttpStatus.ok ||
      response.statusCode >= HttpStatus.multipleChoices) {
    await response.drain<void>();
    throw HttpException(
      'Image request failed with status ${response.statusCode}',
      uri: uri,
    );
  }
  final tooLarge = HttpException(
    'Image is larger than $maxBytes bytes',
    uri: uri,
  );
  if (response.contentLength > maxBytes) throw tooLarge;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in response) {
    bytes.add(chunk);
    if (bytes.length > maxBytes) throw tooLarge;
  }
  return bytes.takeBytes();
}
