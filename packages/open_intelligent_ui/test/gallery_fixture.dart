import 'dart:convert';
import 'dart:io';

/// The reference gallery program with [id], from the engine package's fixtures.
/// Works from the repository root and from this package.
String galleryProgram(String id) {
  const relative = 'ai_sdk_openui/test/fixtures/gallery_programs.json';
  final file = [
    File('packages/$relative'),
    File('../$relative'),
  ].firstWhere((f) => f.existsSync());
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  for (final group in json.values) {
    for (final p in (group as List).cast<Map<String, Object?>>()) {
      if (p['id'] == id) return p['code'] as String;
    }
  }
  throw StateError('no gallery program "$id"');
}
