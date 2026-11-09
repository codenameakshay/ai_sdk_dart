// Reads the conformance vectors and the spec with dart:io, which the web platforms lack.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ai_sdk_openui/src/lang/parser.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The vectors that tool/conformance/run.mjs checks against @openuidev/lang-core.
File _vectorsFile() =>
    [
      File('conformance/vectors.json'),
      File('packages/ai_sdk_openui/conformance/vectors.json'),
    ].firstWhere(
      (f) => f.existsSync(),
      orElse: () => File('conformance/vectors.json'),
    );

/// lang-core's `ParseResult`, projected as the runner projects it.
Map<String, Object?> _project(ParseResult r) {
  final j = r.toJson();
  return {
    'hasRoot': j['root'] != null || j.containsKey('rootExpression'),
    'meta': j['meta'],
    'stateDeclarations': j['stateDeclarations'],
  };
}

void main() {
  final file =
      jsonDecode(_vectorsFile().readAsStringSync()) as Map<String, Object?>;
  final spec = jsonDecode(fixture('spec.json')) as Map<String, Object?>;
  final schema = CompiledSchema.fromJsonSchema(
    spec['schema']! as Map<String, Object?>,
  );
  final root = spec['root'] as String?;

  for (final v in (file['vectors']! as List).cast<Map<String, Object?>>()) {
    final id = v['id']! as String;
    test('$id matches lang-core', () {
      final result = parseProgram(
        v['program']! as String,
        schema,
        rootName: root,
      );
      expect(_project(result), v['expect']);
    }, skip: v['knownDifference'] as String?);
  }
}
