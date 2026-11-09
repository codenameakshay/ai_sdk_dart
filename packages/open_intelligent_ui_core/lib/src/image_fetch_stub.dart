import 'dart:typed_data';

Future<Uint8List> fetchImageBytes(Uri uri) =>
    Future<Uint8List>.error(UnsupportedError('Image loading is unavailable'));
