import 'dart:convert';
import 'dart:typed_data';

/// Reads completed `data:` events out of a Server-Sent Events byte stream.
///
/// Splits [bytes] into UTF-8 lines, joins multiple `data:` fields with a
/// newline, and yields each event when its blank-line terminator arrives.
Stream<String> sseDataLines(Stream<Uint8List> bytes) async* {
  final lines = bytes
      .map<List<int>>((chunk) => chunk)
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  var dataLines = <String>[];

  await for (final line in lines) {
    if (line.isEmpty) {
      if (dataLines.isEmpty) continue;
      final payload = dataLines.join('\n');
      dataLines = <String>[];
      if (payload.isNotEmpty) yield payload;
      continue;
    }

    final separator = line.indexOf(':');
    final field = separator == -1 ? line : line.substring(0, separator);
    if (field != 'data') continue;

    var value = separator == -1 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    dataLines.add(value);
  }
}
