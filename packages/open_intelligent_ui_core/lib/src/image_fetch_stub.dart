import 'dart:typed_data';

Future<Uint8List> fetchImageBytes(
  Uri uri, {
  required int maxBytes,
  required Duration timeout,
}) => Future<Uint8List>.error(UnsupportedError('Image loading is unavailable'));
