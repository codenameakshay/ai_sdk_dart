import 'dart:convert';
import 'dart:typed_data';

/// Reads `data:` lines out of a Server-Sent Events byte stream.
///
/// Splits [bytes] into UTF-8 lines and yields the payload of every `data:`
/// line, skipping blank payloads and any other SSE fields (e.g. `event:`,
/// `id:`).
Stream<String> sseDataLines(Stream<Uint8List> bytes) async* {
  final lines = bytes
      .map<List<int>>((chunk) => chunk)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    if (!line.startsWith('data:')) continue;
    final payload = line.substring(5).trim();
    if (payload.isEmpty) continue;
    yield payload;
  }
}
