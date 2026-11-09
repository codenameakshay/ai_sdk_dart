import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> fetchImageBytes(Uri uri) async {
  final client = HttpClient();
  try {
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
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    client.close(force: true);
  }
}
